import CADCore
import CADGeometry
import CADIR
import Foundation

package struct ConstrainedSurfaceHeightFitter {
    let maximumMatrixElements: Int

    func fit(_ source: ConstrainedSurfaceFeature, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        try source.validate(tolerance: tolerance)
        guard maximumMatrixElements > 0, source.points.count <= maximumMatrixElements / 16 else {
            throw failure(.resourceLimitExceeded, "Constrained Surface exceeded its point storage budget.")
        }
        let origin = source.points[0].position
        let longest = source.points.dropFirst().map { $0.position - origin }.max { $0.length < $1.length }!
        let uAxis = try longest.normalized(tolerance: tolerance.distance)
        let cross = source.points.map { uAxis.cross($0.position - origin) }.max { $0.length < $1.length }!
        guard cross.length > tolerance.distance else {
            throw failure(.invalidInput, "Constrained Surface points must span a nondegenerate projection plane.")
        }
        let normal = try cross.normalized(tolerance: tolerance.distance)
        let vAxis = normal.cross(uAxis)
        let local = source.points.map { constraint -> Vector3D in
            let d = constraint.position - origin
            return Vector3D(x: d.dot(uAxis), y: d.dot(vAxis), z: d.dot(normal))
        }
        let minU = local.map(\.x).min()!, maxU = local.map(\.x).max()!
        let minV = local.map(\.y).min()!, maxV = local.map(\.y).max()!
        let width = maxU - minU, height = maxV - minV
        guard width.isFinite, height.isFinite, min(width, height) > tolerance.distance else {
            throw failure(.invalidInput, "Constrained Surface projection has invalid dimensions.")
        }
        let coordinates = local.map { Point2D(x: ($0.x - minU) / width, y: ($0.y - minV) / height) }
        var heightsByCoordinate: [Point2D: Double] = [:]
        for i in coordinates.indices {
            if let previous = heightsByCoordinate[coordinates[i]],
               abs(previous - local[i].z) > source.positionTolerance {
                throw failure(.conflictingConstraints, "Distinct heights share a constrained projection coordinate.")
            }
            heightsByCoordinate[coordinates[i]] = local[i].z
        }
        let equalityCount = source.points.count
        var count = max(4, Int(ceil(sqrt(Double(equalityCount)))))
        while true {
            let columns = count * count
            let fairnessCount = source.optimization == .smoothness
                ? 2 * count * (count - 2) + (count - 1) * (count - 1)
                : 2 * count * (count - 1)
            let rows = columns + fairnessCount
            // Bound all fitting matrices and right-hand sides before allocation.
            guard columns <= maximumMatrixElements / max(rows + equalityCount + 1, 1),
                  rows + equalityCount <= maximumMatrixElements - columns * (rows + equalityCount + 1) else {
                throw failure(.resourceLimitExceeded, "Constrained Surface exhausted its bounded basis refinement budget.")
            }
            let knots = Self.knots(count: count)
            var objective = Array(repeating: 0.0, count: rows * columns)
            for i in 0..<columns { objective[i * columns + i] = 1 }
            var row = columns
            if source.optimization == .smoothness {
                for v in 0..<count {
                    for u in 0..<(count - 2) {
                        let i = v * count + u
                        objective[row * columns + i] = 1
                        objective[row * columns + i + 1] = -2
                        objective[row * columns + i + 2] = 1
                        row += 1
                    }
                }
                for v in 0..<(count - 2) {
                    for u in 0..<count {
                        let i = v * count + u
                        objective[row * columns + i] = 1
                        objective[row * columns + i + count] = -2
                        objective[row * columns + i + 2 * count] = 1
                        row += 1
                    }
                }
                for v in 0..<(count - 1) { for u in 0..<(count - 1) {
                    let i = v * count + u
                    objective[row * columns + i] = 1
                    objective[row * columns + i + 1] = -1
                    objective[row * columns + i + count] = -1
                    objective[row * columns + i + count + 1] = 1
                    row += 1
                } }
            } else {
                for v in 0..<count { for u in 0..<count {
                    let i = v * count + u
                    if u + 1 < count {
                        objective[row * columns + i] = -1
                        objective[row * columns + i + 1] = 1
                        row += 1
                    }
                    if v + 1 < count {
                        objective[row * columns + i] = -1
                        objective[row * columns + i + count] = 1
                        row += 1
                    }
                } }
            }
            var constraints = Array(repeating: 0.0, count: equalityCount * columns)
            var values = Array(repeating: 0.0, count: equalityCount)
            row = 0
            for i in source.points.indices {
                let uv = coordinates[i]
                let ub = BSplineBasis.values(parameter: uv.x, degree: 3, knots: knots, count: count)
                let vb = BSplineBasis.values(parameter: uv.y, degree: 3, knots: knots, count: count)
                for v in 0..<count { for u in 0..<count {
                    constraints[row * columns + v * count + u] = ub[u] * vb[v]
                } }
                values[row] = local[i].z
                row += 1
            }
            let heights: [Double]
            do {
                let tight = try SurfaceFittingLeastSquares.solve(
                    objective: Array(objective.prefix(columns * columns)),
                    target: Array(repeating: 0, count: columns), constraints: constraints, values: values,
                    columns: columns, relativeRankTolerance: 1e-12,
                    constraintTolerance: source.positionTolerance,
                    maximumElements: maximumMatrixElements)
                let relaxed = try SurfaceFittingLeastSquares.solve(objective: objective,
                    target: Array(repeating: 0, count: rows), constraints: constraints, values: values,
                    columns: columns, relativeRankTolerance: 1e-12,
                    constraintTolerance: source.positionTolerance,
                    maximumElements: maximumMatrixElements)
                heights = try Self.angularlyBoundedRelaxation(tight: tight, relaxed: relaxed,
                    count: count, knots: knots, width: width, height: height,
                    angularTolerance: source.angularTolerance)
            } catch let error as KernelError where error.code == .conflictingConstraints || error.code == .singularSystem {
                // Refinement is the construction algorithm, bounded by the same matrix allowance.
                count += 1
                continue
            }
            var net: [[Point3D]] = []
            for v in 0..<count {
                let y = minV + height * (knots[v + 1] + knots[v + 2] + knots[v + 3]) / 3
                var points: [Point3D] = []
                for u in 0..<count {
                    let x = minU + width * (knots[u + 1] + knots[u + 2] + knots[u + 3]) / 3
                    points.append(origin + uAxis * x + vAxis * y + normal * heights[v * count + u])
                }
                net.append(points)
            }
            let surface = BSplineSurface3D(uDegree: 3, vDegree: 3, uKnots: knots, vKnots: knots, controlPoints: net)
            try surface.validate(tolerance: tolerance)
            for i in source.points.indices {
                let evaluated = try surface.differentialGeometry(u: coordinates[i].x, v: coordinates[i].y, tolerance: tolerance)
                guard (evaluated.position - source.points[i].position).length <= source.positionTolerance else {
                    throw failure(.conflictingConstraints, "Constrained Surface failed independent positional verification.")
                }
            }
            return surface
        }
    }

    /// For a height graph, normal geodesic distance is bounded by gradient distance.
    /// The derivative B-spline control hull bounds each gradient component everywhere.
    package static func angularlyBoundedRelaxation(
        tight: [Double], relaxed: [Double], count: Int, knots: [Double],
        width: Double, height: Double, angularTolerance: Double
    ) throws -> [Double] {
        let bound = try normalChangeBound(from: tight, to: relaxed,
            count: count, knots: knots, width: width, height: height)
        let fraction = bound == 0 ? 1 : min(1, angularTolerance / bound) * (1 - 32 * Double.ulpOfOne)
        let candidate = zip(tight, relaxed).map { $0 + fraction * ($1 - $0) }
        let verified = try normalChangeBound(from: tight, to: candidate,
            count: count, knots: knots, width: width, height: height)
        guard verified <= angularTolerance else {
            throw KernelError(phase: .geometry, code: .conflictingConstraints, tolerance: nil,
                message: "Constrained Surface failed its whole-patch normal-change bound.")
        }
        return candidate
    }

    private static func normalChangeBound(
        from reference: [Double], to candidate: [Double], count: Int,
        knots: [Double], width: Double, height: Double
    ) throws -> Double {
        let delta = zip(candidate, reference).map { OutwardScalarInterval.exact($0) - .exact($1) }
        var maxU = 0.0, maxV = 0.0
        func derivative(_ a: Int, _ b: Int, _ span: Int, _ scale: Double) throws -> Double {
            let numerator = OutwardScalarInterval.exact(3) * (delta[b] - delta[a])
            let denominator = (OutwardScalarInterval.exact(knots[span + 4]) - .exact(knots[span + 1])) * .exact(scale)
            guard let result = numerator.divided(by: denominator), result.isFinite else {
                throw KernelError(phase: .geometry, code: .conflictingConstraints, tolerance: nil,
                    message: "Constrained Surface has an invalid derivative interval.")
            }
            return result.absoluteUpperBound
        }
        for v in 0..<count { for u in 0..<count {
            let i = v * count + u
            if u + 1 < count { maxU = max(maxU, try derivative(i, i + 1, u, width)) }
            if v + 1 < count { maxV = max(maxV, try derivative(i, i + count, v, height)) }
        } }
        let squared = OutwardScalarInterval.exact(maxU) * .exact(maxU)
            + OutwardScalarInterval.exact(maxV) * .exact(maxV)
        let bound = sqrt(squared.upper).nextUp
        guard bound.isFinite else {
            throw KernelError(phase: .geometry, code: .conflictingConstraints, tolerance: nil,
                message: "Constrained Surface has a nonfinite normal-change bound.")
        }
        return bound
    }

    private static func knots(count: Int) -> [Double] {
        Array(repeating: 0, count: 4) + (1..<(count - 3)).map { Double($0) / Double(count - 3) }
            + Array(repeating: 1, count: 4)
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}
