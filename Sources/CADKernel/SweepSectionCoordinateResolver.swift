import CADCore
import CADIR

struct SweepSectionCoordinates: Sendable {
    var coordinates: [Point2D]
    var isClosed: Bool
    var plane: SketchPlane
}

struct SweepSectionCoordinateResolver: Sendable {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    func coordinates(for profile: Profile) throws -> SweepSectionCoordinates {
        try tolerance.validate()
        let result = try localCoordinates(
            for: profile.vertices,
            plane: profile.plane
        )
        let coordinates = result.coordinates
        guard coordinates.count >= 3 else {
            throw SketchError.openProfile
        }
        return SweepSectionCoordinates(
            coordinates: coordinates,
            isClosed: true,
            plane: profile.plane
        )
    }

    func coordinates(for curve: EvaluatedCurve) throws -> SweepSectionCoordinates {
        try tolerance.validate()
        guard let plane = curve.plane else {
            throw SketchError.unsupportedEntity(
                "Curve-section sweep requires source curve plane metadata."
            )
        }
        let result = try localCoordinates(
            for: curve.points,
            plane: plane
        )
        let coordinates = result.coordinates
        guard coordinates.count >= 2 else {
            throw SketchError.unsupportedEntity("Curve-section sweep requires at least two distinct curve points.")
        }
        return SweepSectionCoordinates(
            coordinates: coordinates,
            isClosed: curve.isClosed || result.closedByEndpoint,
            plane: plane
        )
    }

    func basis(for plane: SketchPlane) throws -> (u: Vector3D, v: Vector3D) {
        try tolerance.validate()
        switch plane {
        case .xy:
            return (.unitX, .unitY)
        case .yz:
            return (.unitY, .unitZ)
        case .zx:
            return (.unitZ, .unitX)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return (u, v)
        }
    }

    func origin(for plane: SketchPlane) -> Point3D {
        switch plane {
        case .xy, .yz, .zx:
            return .origin
        case let .plane(plane):
            return plane.origin
        }
    }

    private func localCoordinates(
        for points: [Point3D],
        plane: SketchPlane
    ) throws -> (coordinates: [Point2D], closedByEndpoint: Bool) {
        let basis = try basis(for: plane)
        let origin = origin(for: plane)
        var coordinates: [Point2D] = []
        coordinates.reserveCapacity(points.count)
        for point in points {
            let offset = point - origin
            let coordinate = Point2D(
                x: offset.dot(basis.u),
                y: offset.dot(basis.v)
            )
            if let previous = coordinates.last,
               isClose(previous, coordinate) {
                continue
            }
            coordinates.append(coordinate)
        }
        let closedByEndpoint = closes(coordinates)
        if closedByEndpoint {
            coordinates.removeLast()
        }
        return (coordinates: coordinates, closedByEndpoint: closedByEndpoint)
    }

    private func closes(_ coordinates: [Point2D]) -> Bool {
        guard let first = coordinates.first,
              let last = coordinates.last else {
            return false
        }
        return isClose(first, last)
    }

    private func isClose(_ first: Point2D, _ second: Point2D) -> Bool {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return (deltaX * deltaX + deltaY * deltaY) <= tolerance.distance * tolerance.distance
    }
}
