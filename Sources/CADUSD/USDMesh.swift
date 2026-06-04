public struct USDMesh: Sendable, Hashable {
    public var name: String?
    public var points: [USDPoint3D]
    public var faceVertexCounts: [Int]
    public var faceVertexIndices: [Int]
    public var subdivisionScheme: String?

    public init(
        name: String? = nil,
        points: [USDPoint3D] = [],
        faceVertexCounts: [Int] = [],
        faceVertexIndices: [Int] = [],
        subdivisionScheme: String? = nil
    ) {
        self.name = name
        self.points = points
        self.faceVertexCounts = faceVertexCounts
        self.faceVertexIndices = faceVertexIndices
        self.subdivisionScheme = subdivisionScheme
    }
}
