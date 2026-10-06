public struct Matrix4x4: Hashable, Sendable {
    public var values: [Double]

    public init(values: [Double]) throws {
        try Self.validate(values: values)
        self.values = values
    }

    public func validate() throws {
        try Self.validate(values: values)
    }

    private static func validate(values: [Double]) throws {
        guard values.count == 16 else {
            throw GeometryError.invalidMatrixElementCount(values.count)
        }
        for value in values where !value.isFinite {
            throw GeometryError.invalidCoordinate(value)
        }
    }

    private init(uncheckedValues values: [Double]) {
        self.values = values
    }

    public static let identity = Matrix4x4(uncheckedValues: [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    ])
}

#if !hasFeature(Embedded)
extension Matrix4x4: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([Double].self)
        try self.init(values: values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
#endif
