import CADCore
import CADGeometry
import CADTopology

package struct PlanarOffsetJointResolver: Sendable {
    package init() {}

    package func trims(curves: [BSplineCurve3D], originalCorners: [Point3D],
                       normal: Vector3D, tolerance: ModelingTolerance,
                       originalSources: [PlanarOffsetCurveSource]? = nil) throws -> [BSplineCurve3D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trims(curves: curves, originalCorners: originalCorners, normal: normal,
            tolerance: tolerance, originalSources: originalSources, using: &execution)
    }

    package func trims(curves: [BSplineCurve3D], originalCorners: [Point3D],
        normal: Vector3D, tolerance: ModelingTolerance,
        originalSources: [PlanarOffsetCurveSource]? = nil,
        using execution: inout OriginalQueryExecution) throws -> [BSplineCurve3D] {
        try execution.consumeWork(1)
        guard curves.count == originalCorners.count, curves.count >= 2 else {
            throw failure(.invalidInput, "Offset joints require one original corner per retained curve.", tolerance)
        }
        guard originalSources == nil || originalSources?.count == curves.count else {
            throw failure(.invalidInput, "Every offset candidate requires its retained original law.", tolerance)
        }
        let n = try normal.normalized(tolerance: tolerance.distance)
        let seed = abs(n.x) < 0.6 ? Vector3D.unitX : Vector3D.unitY
        let u = try n.cross(seed).normalized(tolerance: tolerance.distance)
        let v = n.cross(u)
        let origin = originalCorners[0]
        func projected(_ curve: BSplineCurve3D, using execution: inout OriginalQueryExecution) throws -> BSplineCurve2D {
            let points = try OriginalParameterQueryStorage.map(curve.controlPoints, using: &execution) { point, execution in
                    let d = point - origin
                    return Point2D(x: d.dot(u), y: d.dot(v))
                }
            return BSplineCurve2D(degree: curve.degree, knots: curve.knots, controlPoints: points, weights: curve.weights)
        }
        var starts: [Double] = []
        var ends: [Double] = []
        for curve in curves {
            guard case let .closed(a, b) = curve.domain else {
                throw failure(.invalidInput, "An offset joint lost its finite source support.", tolerance)
            }
            try OriginalParameterQueryStorage.append(a, to: &starts, using: &execution)
            try OriginalParameterQueryStorage.append(b, to: &ends, using: &execution)
        }
        let originalStarts = starts, originalEnds = ends
        let encloser = DefaultCurveDifferentialEncloser()
        for index in curves.indices {
            try execution.consumeWork(1)
            let next = (index + 1) % curves.count
            let first = curves[index], second = curves[next]
            let corner = originalCorners[index]
            let firstEnd = try first.point(at: ends[index], tolerance: tolerance, using: &execution)
            let secondStart = try second.point(at: starts[next], tolerance: tolerance, using: &execution)
            if (firstEnd - secondStart).length <= tolerance.distance { continue }
            func originalPositions(_ root: RationalBSplineCurveIntersection2D, using execution: inout OriginalQueryExecution) throws -> (CoordinateEnclosure3D, CoordinateEnclosure3D) {
                let a = try ScalarInterval(lower: max(originalStarts[index], root.firstParameterEnclosure.lower),
                    upper: min(originalEnds[index], root.firstParameterEnclosure.upper))
                let b = try ScalarInterval(lower: max(originalStarts[next], root.secondParameterEnclosure.lower),
                    upper: min(originalEnds[next], root.secondParameterEnclosure.upper))
                if let originalSources {
                    let firstRange = try ScalarInterval(lower: a.lower.nextDown, upper: a.upper.nextUp)
                    let secondRange = try ScalarInterval(lower: b.lower.nextDown, upper: b.upper.nextUp)
                    return (try originalSources[index].enclosure(over: firstRange, tolerance: tolerance, using: &execution).position,
                        try originalSources[next].enclosure(over: secondRange, tolerance: tolerance, using: &execution).position)
                }
                return (try encloser.enclosure(of: .bSpline(first), over: a, tolerance: tolerance, using: &execution).position,
                        try encloser.enclosure(of: .bSpline(second), over: b, tolerance: tolerance, using: &execution).position)
            }
            let allowed = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
            let projectedFirst = try projected(first, using: &execution)
            let projectedSecond = try projected(second, using: &execution)
            let roots = try RationalBSplineCurveIntersector2D().intersections(first: projectedFirst, second: projectedSecond,
                maximumSubdivisionDepth: 32, maximumSubdivisionCells: 65_536, accepting: { root, execution in
                    let positions = try originalPositions(root, using: &execution)
                    func difference(_ a: ScalarInterval, _ b: ScalarInterval) -> OutwardScalarInterval {
                        let d = OutwardScalarInterval(lower: a.lower, upper: a.upper)
                            - OutwardScalarInterval(lower: b.lower, upper: b.upper)
                        let upper = d.absoluteUpperBound
                        return OutwardScalarInterval(lower: 0, upper: (upper * upper).nextUp)
                    }
                    let residual = difference(positions.0.x, positions.1.x)
                        + difference(positions.0.y, positions.1.y) + difference(positions.0.z, positions.1.z)
                    return residual.upper <= allowed.lower
                }, tolerance: tolerance, using: &execution)
            // FIXME(INCOMPLETE_IMPLEMENTATION): original finite offset supports do not yet
            // continue their native laws beyond an authored sharp corner. Thin/extrude callers
            // reach this branch; all required concave/exterior corners need original-law
            // continuation and a certified nearest intersection before full S3 completion.
            guard !roots.isEmpty else {
                throw failure(.intersectionFailure, "Offset walls have no certified intersection on their retained supports.", tolerance)
            }
            let distances = try OriginalParameterQueryStorage.map(roots, using: &execution) { root, execution -> OutwardScalarInterval in
                let positions = try originalPositions(root, using: &execution)
                func square(_ first: ScalarInterval, _ second: ScalarInterval, _ value: Double) -> OutwardScalarInterval {
                    let difference = OutwardScalarInterval(lower: min(first.lower, second.lower), upper: max(first.upper, second.upper)) - .exact(value)
                    let lower = difference.absoluteLowerBound, upper = difference.absoluteUpperBound
                    return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
                }
                return square(positions.0.x, positions.1.x, corner.x)
                    + square(positions.0.y, positions.1.y, corner.y) + square(positions.0.z, positions.1.z, corner.z)
            }
            guard let selected = try OriginalParameterQueryStorage.first(roots.indices, using: &execution, predicate: { candidate, execution in
                try OriginalParameterQueryStorage.allSatisfy(roots.indices, using: &execution) { other, execution in
                    other == candidate || distances[candidate].upper < distances[other].lower
                }
            }) else {
                throw failure(.ambiguousSelection, "Offset corner roots do not certify one nearest original joint.", tolerance)
            }
            ends[index] = roots[selected].firstParameterEnclosure.midpoint
            starts[next] = roots[selected].secondParameterEnclosure.midpoint
        }
        return try OriginalParameterQueryStorage.map(curves.indices, using: &execution) { index, execution in
            guard starts[index] < ends[index] else {
                throw failure(.singularGeometry, "Offset intersections remove or reverse a complete boundary segment.", tolerance)
            }
            return try curves[index].trimmed(from: starts[index], to: ends[index], tolerance: tolerance, using: &execution)
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
