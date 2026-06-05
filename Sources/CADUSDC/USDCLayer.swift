import CADUSD

public struct USDCLayer: Sendable, Equatable {
    public var defaultPrim: String?
    public var metersPerUnit: Double?
    public var upAxis: USDUpAxis?
    public var specs: [USDCLayerSpec]

    public init(
        defaultPrim: String? = nil,
        metersPerUnit: Double? = nil,
        upAxis: USDUpAxis? = nil,
        specs: [USDCLayerSpec] = []
    ) {
        self.defaultPrim = defaultPrim
        self.metersPerUnit = metersPerUnit
        self.upAxis = upAxis
        self.specs = specs
    }

    public var prims: [USDCLayerSpec] {
        specs.filter { $0.specType == .prim }
    }

    public func spec(at path: String) -> USDCLayerSpec? {
        specs.first { $0.path == path }
    }
}
