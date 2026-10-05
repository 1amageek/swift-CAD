public struct Transform3D: Hashable, Sendable {
    public var matrix: Matrix4x4

    public init(matrix: Matrix4x4 = .identity) {
        self.matrix = matrix
    }

    public func validate() throws {
        try matrix.validate()
    }

    public static let identity = Transform3D()
}

#if !hasFeature(Embedded)
extension Transform3D: Codable {}
#endif
