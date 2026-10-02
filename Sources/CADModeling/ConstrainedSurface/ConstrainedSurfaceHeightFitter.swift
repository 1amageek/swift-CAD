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
        let (origin, uAxis, vAxis, normal) = try frame(of: source.points.map(\.position), tolerance: tolerance)
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
        var fraction = bound == 0 ? 1 : min(1, angularTolerance / bound) * (1 - 32 * Double.ulpOfOne)
        // The candidate's own rounding is outside the bound's intervals, so a candidate the bound
        // does not verify relaxes half as far, down to the tight solution itself.
        for _ in 0..<64 {
            let candidate = zip(tight, relaxed).map { $0 + fraction * ($1 - $0) }
            let verified = try normalChangeBound(from: tight, to: candidate,
                count: count, knots: knots, width: width, height: height)
            if verified <= angularTolerance { return candidate }
            fraction *= 0.5
        }
        return tight
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

    /// The sheet's frame from the points alone, not their order: the least-squares plane's normal
    /// (the covariance's least eigenvector, turned to face as the first three points turn), and in
    /// it the axes of the points' smallest enclosing rectangle, one side along an edge of their
    /// convex hull — so four points of a square sit at its corners and three of a triangle put two
    /// at adjacent corners.
    private func frame(of points: [Point3D], tolerance: ModelingTolerance) throws
        -> (origin: Point3D, u: Vector3D, v: Vector3D, normal: Vector3D) {
        let count = Double(points.count)
        let centroid = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / count)
        var covariance = [[Double]](repeating: [0, 0, 0], count: 3)
        for point in points {
            let d = point - centroid
            let c = [d.x, d.y, d.z]
            for i in 0..<3 { for j in 0..<3 { covariance[i][j] += c[i] * c[j] } }
        }
        let (values, vectors) = Self.symmetricEigen(covariance)
        let order = values.indices.sorted { values[$0] < values[$1] }
        guard max(values[order[1]], 0).squareRoot() > tolerance.distance else {
            throw failure(.invalidInput, "Constrained Surface points must span a nondegenerate projection plane.")
        }
        var normal = try Vector3D(x: vectors[0][order[0]], y: vectors[1][order[0]], z: vectors[2][order[0]])
            .normalized(tolerance: tolerance.distance)
        let turning = (points[1] - points[0]).cross(points[2] - points[0])
        if turning.dot(normal) < 0 { normal = normal * -1 }
        let seed = abs(normal.x) < 0.9 ? Vector3D(x: 1, y: 0, z: 0) : Vector3D(x: 0, y: 1, z: 0)
        let e1 = try (seed - normal * seed.dot(normal)).normalized(tolerance: 1e-12)
        let e2 = normal.cross(e1)
        let flat = points.map { (($0 - centroid).dot(e1), ($0 - centroid).dot(e2)) }
        // The convex hull (monotone chain), then the hull edge whose direction gives the least area.
        let sorted = flat.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        func turn(_ o: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        var lower: [(Double, Double)] = [], upper: [(Double, Double)] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        let hull = Array(lower.dropLast() + upper.dropLast())
        var best: (area: Double, angle: Double)?
        for (a, b) in zip(hull, hull.dropFirst() + hull.prefix(1)) {
            let length = hypot(b.0 - a.0, b.1 - a.1)
            guard length > tolerance.distance else { continue }
            let (c, s) = ((b.0 - a.0) / length, (b.1 - a.1) / length)
            let us = flat.map { $0.0 * c + $0.1 * s }, vs = flat.map { -$0.0 * s + $0.1 * c }
            guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max() else { continue }
            let area = (u1 - u0) * (v1 - v0)
            if best.map({ area < $0.area * (1 - 1e-9) }) ?? true { best = (area, atan2(s, c)) }
        }
        guard let best else {
            throw failure(.invalidInput, "Constrained Surface points must span a nondegenerate projection plane.")
        }
        let u = e1 * cos(best.angle) + e2 * sin(best.angle)
        return (centroid, u, normal.cross(u), normal)
    }

    /// The eigenvalues and eigenvectors (as columns) of a symmetric 3 × 3 matrix, by Jacobi
    /// rotations.
    private static func symmetricEigen(_ matrix: [[Double]]) -> ([Double], [[Double]]) {
        var a = matrix
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<64 {
            var (p, q, largest) = (0, 1, 0.0)
            for i in 0..<3 { for j in (i + 1)..<3 where abs(a[i][j]) > largest { (p, q, largest) = (i, j, abs(a[i][j])) } }
            if largest <= 1e-300 { break }
            let theta = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p])
            let (c, s) = (cos(theta), sin(theta))
            for k in 0..<3 {
                let (akp, akq) = (a[k][p], a[k][q])
                a[k][p] = c * akp - s * akq
                a[k][q] = s * akp + c * akq
            }
            for k in 0..<3 {
                let (apk, aqk) = (a[p][k], a[q][k])
                a[p][k] = c * apk - s * aqk
                a[q][k] = s * apk + c * aqk
            }
            for k in 0..<3 {
                let (vkp, vkq) = (v[k][p], v[k][q])
                v[k][p] = c * vkp - s * vkq
                v[k][q] = s * vkp + c * vkq
            }
        }
        return ([a[0][0], a[1][1], a[2][2]], v)
    }

}
