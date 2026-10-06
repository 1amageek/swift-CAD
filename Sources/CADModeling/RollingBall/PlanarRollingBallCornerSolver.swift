import CADCore
import CADGeometry

package struct PlanarRollingBallCornerSolver: Sendable {
    package init() {}

    package func center(corner: Point3D, outwardNormals normals: [Vector3D], radius: Double,
                        tolerance: ModelingTolerance) throws -> Point3D {
        guard normals.count >= 3, normals.count <= 4_096, radius.isFinite, radius > tolerance.distance else {
            throw failure(.invalidInput, "A planar vertex ball requires at least three supports and a positive radius.", tolerance)
        }
        var selected: (Int, Int, Int)?
        var best = 0.0
        var visits = 0
        for first in 0..<(normals.count - 2) {
            for second in (first + 1)..<(normals.count - 1) {
                for third in (second + 1)..<normals.count {
                    try Task.checkCancellation()
                    visits += 1
                    guard visits <= 65_536 else {
                        throw failure(.resourceLimitExceeded, "Vertex ball support selection exceeded its work budget.", tolerance)
                    }
                    let magnitude = abs(normals[first].dot(normals[second].cross(normals[third])))
                    if magnitude > best { best = magnitude; selected = (first, second, third) }
                }
            }
        }
        guard let selected, best > tolerance.angle else {
            throw failure(.singularGeometry, "Vertex ball supports do not enclose one finite center.", tolerance)
        }
        typealias Interval = OutwardScalarInterval
        func fixed(_ vector: Vector3D) -> [Interval] { [.exact(vector.x), .exact(vector.y), .exact(vector.z)] }
        func cross(_ a: [Interval], _ b: [Interval]) -> [Interval] {
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        }
        func dot(_ a: [Interval], _ b: [Interval]) -> Interval {
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        }
        let a = fixed(normals[selected.0]), b = fixed(normals[selected.1]), c = fixed(normals[selected.2])
        let bc = cross(b, c), ca = cross(c, a), ab = cross(a, b)
        let determinant = dot(a, bc)
        var offset: [Interval] = []
        for index in 0..<3 {
            guard let value = ((bc[index] + ca[index] + ab[index]) * .exact(-radius)).divided(by: determinant) else {
                throw failure(.singularGeometry, "The original vertex support determinant does not certify a nonzero solve.", tolerance)
            }
            offset.append(value)
        }
        for normal in normals {
            let error = dot(fixed(normal), offset) + .exact(radius)
            // FIXME(INCOMPLETE_IMPLEMENTATION): the public planar round network can reach
            // a vertex whose supports admit no one equal-radius tangent sphere. Full F3
            // requires a general vertex surface for this domain and mixed sharp/radius
            // incidences, with original contact and whole finite patch admission.
            guard error.absoluteUpperBound <= tolerance.distance else {
                throw failure(.unsupportedCapability, "Original vertex supports require a general vertex blend rather than one tangent sphere.", tolerance)
            }
        }
        let origin = [corner.x, corner.y, corner.z]
        let coordinates = (0..<3).map { offset[$0] + .exact(origin[$0]) }
        guard coordinates.allSatisfy({ $0.width <= tolerance.distance * 0.25 }) else {
            throw failure(.resourceLimitExceeded, "Vertex ball center cannot retain the original support solve within its positional allowance.", tolerance)
        }
        let center = Point3D(x: coordinates[0].midpoint, y: coordinates[1].midpoint, z: coordinates[2].midpoint)
        let published = [Interval.exact(center.x) - .exact(corner.x),
                         Interval.exact(center.y) - .exact(corner.y),
                         Interval.exact(center.z) - .exact(corner.z)]
        for normal in normals {
            guard (dot(fixed(normal), published) + .exact(radius)).absoluteUpperBound <= tolerance.distance else {
                throw failure(.classificationFailure, "The published vertex center does not retain every original support certificate.", tolerance)
            }
        }
        return center
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
