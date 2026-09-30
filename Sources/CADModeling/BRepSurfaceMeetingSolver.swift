import Foundation
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

    /// The branch of `first` ∩ `second` nearest `point`; nil when they do not meet in a curve.
    /// `coincide` reports surfaces lying on each other.
    package func nearestBranch(of first: Surface3D, and second: Surface3D, near point: Point3D) throws -> (curve: Curve3D?, coincide: Bool) {
        if first == second { return (nil, true) }
        var nearest: (curve: Curve3D, distance: Double)?
        var coincide = false
        for component in try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: tolerance) {
            switch component {
            case let .curve(branch):
                let distance = (try closest(to: point, on: branch.curve).point - point).length
                if nearest.map({ distance < $0.distance }) ?? true { nearest = (branch.curve, distance) }
            case .coincident:
                coincide = true
            case .point:
                continue
            }
        }
        return (nearest?.curve, coincide && nearest == nil)
    }

    /// The point nearest `seed` lying on every surface where they cross: three or more surfaces
    /// fix it; two fix it along their intersection, where it stays nearest the seed; one is the
    /// seed's foot on it. Nil when surfaces touch tangentially there, so their tangent planes
    /// cannot fix it.
    package func crossingPoint(of surfaces: [Surface3D], near seed: Point3D) throws -> Point3D? {
        guard let only = surfaces.first else { return nil }
        if surfaces.count == 1 { return try foot(of: seed, on: only).point }
        var point = seed
        for _ in 0..<64 {
            var rows: [(normal: Vector3D, value: Double)] = []
            for surface in surfaces {
                let foot = try foot(of: point, on: surface)
                rows.append((foot.normal, foot.normal.dot(foot.point - .origin)))
            }
            if surfaces.count == 2 {
                let along = rows[0].normal.cross(rows[1].normal)
                guard along.length > Self.transversality else { return nil }
                let unit = try along.normalized(tolerance: tolerance.distance)
                rows.append((unit, unit.dot(seed - .origin)))
            }
            guard let next = leastSquaresPoint(rows) else { return nil }
            let step = (next - point).length
            point = next
            if step <= tolerance.distance * 1e-3 { break }
        }
        return try lies(point, onAll: surfaces) ? point : nil
    }

    /// The point of `curve` nearest `seed` that lies on every one of `others`, found where the
    /// curve's signed distance to the first of them vanishes; nil when it does not converge there
    /// or misses the rest.
    package func crossingPoint(on curve: Curve3D, with others: [Surface3D], near seed: Point3D) throws -> Point3D? {
        var parameter = try closest(to: seed, on: curve).parameter
        guard let target = others.first else { return try curve.point(at: parameter, tolerance: tolerance) }
        func signedDistance(_ t: Double) throws -> Double {
            let point = try curve.point(at: t, tolerance: tolerance)
            let foot = try foot(of: point, on: target)
            return (point - foot.point).dot(foot.normal)
        }
        for _ in 0..<64 {
            let value = try signedDistance(parameter)
            if abs(value) <= tolerance.distance * 1e-3 { break }
            let step = max(1e-9, abs(parameter) * 1e-8)
            let slope = (try signedDistance(parameter + step) - (try signedDistance(parameter - step))) / (2 * step)
            guard abs(slope) > 1e-12 else { return nil }
            parameter -= value / slope
        }
        let point = try curve.point(at: parameter, tolerance: tolerance)
        return try lies(point, onAll: others) ? point : nil
    }

    /// Whether `point` lies on every surface within tolerance.
    package func lies(_ point: Point3D, onAll surfaces: [Surface3D]) throws -> Bool {
        for surface in surfaces where (try foot(of: point, on: surface).point - point).length > tolerance.distance {
            return false
        }
        return true
    }

    /// The nearest point of `surface` to `point` and the surface's unit normal there.
    package func foot(of point: Point3D, on surface: Surface3D) throws -> (point: Point3D, normal: Vector3D) {
        try SurfaceFootResolver().foot(of: point, on: surface, tolerance: tolerance)
    }

    /// The parameter and point of `curve` nearest `point`: exact on a line, and certified over the
    /// curve's finite or periodic domain otherwise.
    package func closest(to point: Point3D, on curve: Curve3D) throws -> (parameter: Double, point: Point3D) {
        let line: (origin: Point3D, direction: Vector3D)?
        switch curve {
        case let .line(value): line = (value.origin, value.direction)
        case let .analytic(.line(origin, direction)): line = (origin, direction)
        default: line = nil
        }
        if let line {
            let parameter = (point - line.origin).dot(line.direction) / line.direction.dot(line.direction)
            return (parameter, try curve.point(at: parameter, tolerance: tolerance))
        }
        let projection = try curve.closestParameterProjection(of: point, options: CurveParameterProjectionOptions(), tolerance: tolerance)
        return (projection.parameter, projection.point)
    }

    /// The parameters of `curve` from `start` to `end` running the way `sense` points at the
    /// start; a closed edge runs once around. Nil when the points are off the curve, or the span
    /// collapses or runs against the sense.
    package func trim(_ curve: Curve3D, from start: Point3D, to end: Point3D, isClosed: Bool, sense: Vector3D) throws -> CurveTrim? {
        let startFoot = try closest(to: start, on: curve)
        let endFoot = try closest(to: end, on: curve)
        guard (startFoot.point - start).length <= tolerance.distance, (endFoot.point - end).length <= tolerance.distance else { return nil }
        let first = startFoot.parameter
        let last = endFoot.parameter
        let forward = try tangent(of: curve, at: first).dot(sense) > 0
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

    /// The direction a curve runs at a parameter, by a central difference.
    package func tangent(of curve: Curve3D, at parameter: Double) throws -> Vector3D {
        let step = max(1e-6, abs(parameter) * 1e-9)
        return try curve.point(at: parameter + step, tolerance: tolerance) - curve.point(at: parameter - step, tolerance: tolerance)
    }

    /// The point best satisfying `normal · X = value` for every row; nil when the rows leave a
    /// direction free.
    private func leastSquaresPoint(_ rows: [(normal: Vector3D, value: Double)]) -> Point3D? {
        var matrix = [[Double]](repeating: [0, 0, 0], count: 3)
        var right = [0.0, 0.0, 0.0]
        for row in rows {
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
        var solution = [0.0, 0.0, 0.0]
        for column in 0..<3 {
            var replaced = matrix
            for i in 0..<3 { replaced[i][column] = right[i] }
            solution[column] = determinant(replaced) / det
        }
        return Point3D(x: solution[0], y: solution[1], z: solution[2])
    }
}
