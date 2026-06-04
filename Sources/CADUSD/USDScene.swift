public struct USDScene: Sendable, Hashable {
    public var defaultPrim: String?
    public var metersPerUnit: Double
    public var upAxis: USDUpAxis
    public var meshes: [USDMesh]

    public init(
        defaultPrim: String? = nil,
        metersPerUnit: Double = 1,
        upAxis: USDUpAxis = .y,
        meshes: [USDMesh] = []
    ) {
        self.defaultPrim = defaultPrim
        self.metersPerUnit = metersPerUnit
        self.upAxis = upAxis
        self.meshes = meshes
    }
}
