import CADCore

public struct BoundingBox3D: Codable, Equatable, Hashable, Sendable {
    public let minimum: Point3D
    public let maximum: Point3D

    public init(minimum: Point3D, maximum: Point3D) throws {
        try minimum.validate()
        try maximum.validate()
        guard minimum.x <= maximum.x,
              minimum.y <= maximum.y,
              minimum.z <= maximum.z else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Bounding box minimum must not exceed maximum."
            )
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(points: some Sequence<Point3D>) throws {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "A bounding box requires at least one point."
            )
        }
        var minimum = first
        var maximum = first
        while let point = iterator.next() {
            try point.validate()
            minimum = Point3D(
                x: Swift.min(minimum.x, point.x),
                y: Swift.min(minimum.y, point.y),
                z: Swift.min(minimum.z, point.z)
            )
            maximum = Point3D(
                x: Swift.max(maximum.x, point.x),
                y: Swift.max(maximum.y, point.y),
                z: Swift.max(maximum.z, point.z)
            )
        }
        try self.init(minimum: minimum, maximum: maximum)
    }

    public var center: Point3D {
        Point3D(
            x: minimum.x + (maximum.x - minimum.x) * 0.5,
            y: minimum.y + (maximum.y - minimum.y) * 0.5,
            z: minimum.z + (maximum.z - minimum.z) * 0.5
        )
    }

    public var size: Vector3D {
        maximum - minimum
    }

    public func contains(_ point: Point3D, tolerance: Double) -> Bool {
        minimum.x - tolerance <= point.x && point.x <= maximum.x + tolerance
            && minimum.y - tolerance <= point.y && point.y <= maximum.y + tolerance
            && minimum.z - tolerance <= point.z && point.z <= maximum.z + tolerance
    }

    public func intersects(_ other: BoundingBox3D, tolerance: Double) -> Bool {
        minimum.x - tolerance <= other.maximum.x && other.minimum.x - tolerance <= maximum.x
            && minimum.y - tolerance <= other.maximum.y && other.minimum.y - tolerance <= maximum.y
            && minimum.z - tolerance <= other.maximum.z && other.minimum.z - tolerance <= maximum.z
    }

    public func union(_ other: BoundingBox3D) throws -> BoundingBox3D {
        try BoundingBox3D(
            minimum: Point3D(
                x: Swift.min(minimum.x, other.minimum.x),
                y: Swift.min(minimum.y, other.minimum.y),
                z: Swift.min(minimum.z, other.minimum.z)
            ),
            maximum: Point3D(
                x: Swift.max(maximum.x, other.maximum.x),
                y: Swift.max(maximum.y, other.maximum.y),
                z: Swift.max(maximum.z, other.maximum.z)
            )
        )
    }

    public func expanded(by amount: Double) throws -> BoundingBox3D {
        guard amount.isFinite, amount >= 0.0 else {
            throw GeometryError.invalidDistance(amount)
        }
        return try BoundingBox3D(
            minimum: Point3D(
                x: minimum.x - amount,
                y: minimum.y - amount,
                z: minimum.z - amount
            ),
            maximum: Point3D(
                x: maximum.x + amount,
                y: maximum.y + amount,
                z: maximum.z + amount
            )
        )
    }
}
