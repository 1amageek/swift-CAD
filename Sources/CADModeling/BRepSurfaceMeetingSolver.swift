#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADTopology

/// Solves where faces' surfaces meet, near where the topology says they do: the branch of two
/// surfaces' intersection nearest a point, the point where several surfaces cross nearest a
/// seed, and the parameters of a curve between two of its points in a given sense. The local
/// face operations (`FaceSurfaceReplacementRebuilder`) and the healing of removed faces
/// (`FaceRemovalHealer`) re-solve their edges and vertices with it.
package struct BRepSurfaceMeetingSolver: Sendable {
    /// The least angle, in radians, at which surfaces meeting at a vertex are solved from their
    /// tangent planes; nearer tangency the vertex is found along a curve instead, where the
    /// tangent planes no longer fix it well.
    private static let transversality = 1e-4

    package let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func nearestBranch(of first: Surface3D, and second: Surface3D, near point: Point3D) throws -> (curve: Curve3D?, coincide: Bool) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try nearestBranch(of: first, and: second, near: point, using: &execution)
    }
    package func nearestIntersection(of first: Surface3D, and second: Surface3D, near point: Point3D) throws -> (branch: SurfaceSurfaceIntersectionCurve?, coincide: Bool) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try nearestIntersection(of: first, and: second, near: point, using: &execution)
    }
    package func crossingPoint(of surfaces: [Surface3D], near seed: Point3D) throws -> Point3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try crossingPoint(of: surfaces, near: seed, using: &execution)
    }
    package func crossingPoint(on curve: Curve3D, with others: [Surface3D], near seed: Point3D) throws -> Point3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try crossingPoint(on: curve, with: others, near: seed, using: &execution)
    }
    package func lies(_ point: Point3D, onAll surfaces: [Surface3D]) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try lies(point, onAll: surfaces, using: &execution)
    }
    package func trim(_ curve: Curve3D, from start: Point3D, to end: Point3D, isClosed: Bool,
        sense: Vector3D, near: Point3D? = nil) throws -> CurveTrim? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trim(curve, from: start, to: end, isClosed: isClosed, sense: sense, near: near, using: &execution)
    }

    /// The branch of `first` ∩ `second` nearest `point`; nil when they do not meet in a curve.
    /// `coincide` reports surfaces lying on each other.
    package func nearestBranch(of first: Surface3D, and second: Surface3D, near point: Point3D, using execution: inout OriginalQueryExecution) throws -> (curve: Curve3D?, coincide: Bool) {
        let nearest = try nearestIntersection(of: first, and: second, near: point, using: &execution)
        return (nearest.branch?.curve, nearest.coincide)
    }

    /// `nearestBranch` with the certified intersection itself, which carries the branch's
    /// parameter curves on both surfaces.
    package func nearestIntersection(of first: Surface3D, and second: Surface3D, near point: Point3D, using execution: inout OriginalQueryExecution) throws
        -> (branch: SurfaceSurfaceIntersectionCurve?, coincide: Bool) {
        if first == second { return (nil, true) }
        var nearest: (branch: SurfaceSurfaceIntersectionCurve, distance: Double)?
        var coincide = false
        for component in try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, options: .init(), tolerance: tolerance, using: &execution) {
            switch component {
            case let .curve(branch):
                let distance = (try closest(to: point, on: branch.curve, using: &execution).point - point).length
                if nearest.map({ distance < $0.distance }) ?? true { nearest = (branch, distance) }
            case .coincident:
                coincide = true
            case .point:
                continue
            // FIXME(INCOMPLETE_IMPLEMENTATION): Production local face/healing
            // callers require a selected curve with full transferable pcurves.
            // Retained symbolic relations cannot be reduced to absence or
            // coincidence until that original branch transfer is implemented.
            case .originalCoaxial, .originalBoundedSphereCone, .originalFullSphereCone,
                 .originalFullConeCone, .originalApexSphereCone, .originalCommonApexCone,
                 .originalCoincidentCone:
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Surface meeting requires a transferable original branch and pcurve certificate.")
            }
        }
        return (nearest?.branch, coincide && nearest == nil)
    }

    /// The point nearest `seed` lying on every surface where they cross: three or more surfaces
    /// fix it; two fix it along their intersection, where it stays nearest the seed; one is the
    /// seed's foot on it. Nil when surfaces touch tangentially there, so their tangent planes
    /// cannot fix it.
    package func crossingPoint(of surfaces: [Surface3D], near seed: Point3D, using execution: inout OriginalQueryExecution) throws -> Point3D? {
        guard let only = surfaces.first else { return nil }
        if surfaces.count == 1 { return try foot(of: seed, on: only, using: &execution).point }
        var point = seed
        for _ in 0..<64 {
            try execution.consumeWork(1)
            var rows: [(normal: Vector3D, value: Double)] = []
            let capacity = surfaces.count.addingReportingOverflow(1)
            guard !capacity.overflow else { throw ExactScalarFailure.countOverflow }
            try execution.retainStorage(count: capacity.partialValue, stride: MemoryLayout<(normal: Vector3D, value: Double)>.stride)
            rows.reserveCapacity(capacity.partialValue)
            for surface in surfaces {
                let foot = try foot(of: point, on: surface, using: &execution)
                rows.append((foot.normal, foot.normal.dot(foot.point - .origin)))
            }
            if surfaces.count == 2 {
                let along = rows[0].normal.cross(rows[1].normal)
                guard along.length > Self.transversality else { return nil }
                let unit = try along.normalized(tolerance: tolerance.distance)
                rows.append((unit, unit.dot(seed - .origin)))
            }
            guard let next = try leastSquaresPoint(rows, using: &execution) else { return nil }
            let step = (next - point).length
            point = next
            if step <= tolerance.distance * 1e-3 { break }
        }
        return try lies(point, onAll: surfaces, using: &execution) ? point : nil
    }

    /// The point of `curve` nearest `seed` that lies on every one of `others`, found where the
    /// curve's signed distance to the first of them vanishes; nil when it does not converge there
    /// or misses the rest.
    package func crossingPoint(on curve: Curve3D, with others: [Surface3D], near seed: Point3D, using execution: inout OriginalQueryExecution) throws -> Point3D? {
        var parameter = try closest(to: seed, on: curve, using: &execution).parameter
        guard let target = others.first else { return try curve.point(at: parameter, tolerance: tolerance, using: &execution) }
        func signedDistance(_ t: Double, using execution: inout OriginalQueryExecution) throws -> Double {
            let point = try curve.point(at: t, tolerance: tolerance, using: &execution)
            let foot = try foot(of: point, on: target, using: &execution)
            return (point - foot.point).dot(foot.normal)
        }
        for _ in 0..<64 {
            let value = try signedDistance(parameter, using: &execution)
            if abs(value) <= tolerance.distance * 1e-3 { break }
            let step = max(1e-9, abs(parameter) * 1e-8)
            let slope = (try signedDistance(parameter + step, using: &execution) - (try signedDistance(parameter - step, using: &execution))) / (2 * step)
            guard abs(slope) > 1e-12 else { return nil }
            parameter -= value / slope
        }
        let point = try curve.point(at: parameter, tolerance: tolerance, using: &execution)
        return try lies(point, onAll: others, using: &execution) ? point : nil
    }

    /// Whether `point` lies on every surface within tolerance.
    package func lies(_ point: Point3D, onAll surfaces: [Surface3D], using execution: inout OriginalQueryExecution) throws -> Bool {
        for surface in surfaces where (try foot(of: point, on: surface, using: &execution).point - point).length > tolerance.distance {
            return false
        }
        return true
    }

    /// The nearest point of `surface` to `point` and the surface's unit normal there.
    package func foot(of point: Point3D, on surface: Surface3D) throws -> (point: Point3D, normal: Vector3D) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try foot(of: point, on: surface, using: &execution)
    }

    package func foot(of point: Point3D, on surface: Surface3D,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, normal: Vector3D) {
        do {
            let result = try SurfaceFootResolver().foot(of: point, on: surface,
                tolerance: tolerance, using: &execution)
            try execution.checkpoint()
            return result
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    /// The parameter and point of `curve` nearest `point`: exact on a line, and certified over the
    /// curve's finite or periodic domain otherwise.
    package func closest(to point: Point3D, on curve: Curve3D) throws -> (parameter: Double, point: Point3D) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try closest(to: point, on: curve, using: &execution)
    }

    package func closest(to point: Point3D, on curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> (parameter: Double, point: Point3D) {
        do {
            let result = try resolve(using: &execution)
            try execution.checkpoint()
            return result
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
        func resolve(using execution: inout OriginalQueryExecution) throws -> (parameter: Double, point: Point3D) {
        try execution.consumeWork(1)
        let line: (origin: Point3D, direction: Vector3D)?
        switch curve {
        case let .line(value): line = (value.origin, value.direction)
        case let .analytic(.line(origin, direction)): line = (origin, direction)
        default: line = nil
        }
        if let line {
            let parameter = (point - line.origin).dot(line.direction) / line.direction.dot(line.direction)
            return (parameter, try curve.point(at: parameter, tolerance: tolerance, using: &execution))
        }
        guard case .unbounded = curve.parameterDomain else {
            let projection = try curve.closestParameterProjection(of: point, options: CurveParameterProjectionOptions(), tolerance: tolerance, using: &execution)
            return (projection.parameter, projection.point)
        }
        // An unbounded curve (a cone's or cylinder's section by a plane at a slant: a hyperbola or
        // a parabola) is searched over windows of its parameter widening eightfold until the
        // nearest point lies inside one rather than at its bound.
        var width = 1.0
        while true {
            try execution.consumeWork(1)
            let range = try ScalarInterval(lower: -width, upper: width)
            let projection = try curve.closestParameterProjection(of: point, options: CurveParameterProjectionOptions(parameterRange: range),
                                                                  tolerance: tolerance, using: &execution)
            if abs(abs(projection.parameter) - width) > 1e-9 * width {
                return (projection.parameter, projection.point)
            }
            guard width < 1e6 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Unbounded nearest-point search exhausted its envelope at a window boundary.")
            }
            width *= 8
        }
            }
    }

    /// The parameters of `curve` from `start` to `end` running the way `sense` points at the
    /// start; a closed edge runs once around. Nil when the points are off the curve, or the span
    /// collapses or runs against the sense.
    /// `near`, a point the edge ran by before, settles the way round a periodic curve when its
    /// tangent at the start stands square to `sense` (a half circle leaving its end straight up).
    package func trim(_ curve: Curve3D, from start: Point3D, to end: Point3D, isClosed: Bool, sense: Vector3D, near: Point3D? = nil, using execution: inout OriginalQueryExecution) throws -> CurveTrim? {
        let startFoot = try closest(to: start, on: curve, using: &execution)
        let endFoot = try closest(to: end, on: curve, using: &execution)
        guard (startFoot.point - start).length <= tolerance.distance, (endFoot.point - end).length <= tolerance.distance else { return nil }
        let first = startFoot.parameter
        let last = endFoot.parameter
        let startTangent = try tangent(of: curve, at: first, using: &execution)
        var forward = startTangent.dot(sense) > 0
        if let near, case let .periodic(period) = curve.parameterDomain, isClosed == false,
           abs(startTangent.dot(sense)) <= 1e-3 * startTangent.length * sense.length {
            // Each way round to the end, the one whose middle passes nearer the old edge.
            var ahead = last
            while ahead <= first { ahead += period }
            while ahead - first > period { ahead -= period }
            let aheadMiddle = try curve.point(at: (first + ahead) / 2, tolerance: tolerance, using: &execution)
            let behindMiddle = try curve.point(at: (first + ahead - period) / 2, tolerance: tolerance, using: &execution)
            forward = (aheadMiddle - near).length <= (behindMiddle - near).length
        }
        var endParameter = last
        if case let .periodic(period) = curve.parameterDomain {
            // A periodic curve reaches the end once, the way the edge runs.
            let slack = isClosed ? tolerance.distance : 0
            while forward ? endParameter <= first + slack : endParameter >= first - slack {
                endParameter += forward ? period : -period
            }
            while forward ? endParameter - first > period + tolerance.distance : first - endParameter > period + tolerance.distance {
                endParameter -= forward ? period : -period
            }
        } else if isClosed {
            return nil
        }
        guard abs(endParameter - first) > tolerance.distance, (endParameter > first) == forward else { return nil }
        return CurveTrim(startParameter: first, endParameter: endParameter)
    }

    /// The direction a curve runs at a parameter, by a difference kept within its domain.
    package func tangent(of curve: Curve3D, at parameter: Double) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try tangent(of: curve, at: parameter, using: &execution)
    }

    package func tangent(of curve: Curve3D, at parameter: Double,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        let step = max(1e-6, abs(parameter) * 1e-9)
        var (before, after) = (parameter - step, parameter + step)
        if case let .closed(lower, upper) = curve.parameterDomain {
            (before, after) = (max(lower, before), min(upper, after))
        }
        return try curve.point(at: after, tolerance: tolerance, using: &execution) - curve.point(at: before, tolerance: tolerance, using: &execution)
    }

    /// The point best satisfying `normal · X = value` for every row; nil when the rows leave a
    /// direction free.
    private func leastSquaresPoint(_ rows: [(normal: Vector3D, value: Double)], using execution: inout OriginalQueryExecution) throws -> Point3D? {
        try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
        try execution.retainStorage(count: 12, stride: MemoryLayout<Double>.stride)
        var matrix = [[Double]](repeating: [0, 0, 0], count: 3)
        var right = [0.0, 0.0, 0.0]
        for row in rows {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
            let n = [row.normal.x, row.normal.y, row.normal.z]
            for i in 0..<3 {
                for j in 0..<3 { matrix[i][j] += n[i] * n[j] }
                right[i] += n[i] * row.value
            }
        }
        func determinant(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let det = determinant(matrix)
        guard abs(det) > Self.transversality * Self.transversality else { return nil }
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        var solution = [0.0, 0.0, 0.0]
        for column in 0..<3 {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
            try execution.retainStorage(count: 9, stride: MemoryLayout<Double>.stride)
            var replaced = matrix
            for i in 0..<3 { replaced[i][column] = right[i] }
            solution[column] = determinant(replaced) / det
        }
        return Point3D(x: solution[0], y: solution[1], z: solution[2])
    }
}
