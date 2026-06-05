public struct USDCLayerSpec: Sendable, Equatable {
    public var path: String
    public var specType: USDCCrateSpecType
    public var specifier: USDCPrimSpecifier?
    public var typeName: String?
    public var fieldNames: [String]

    public init(
        path: String,
        specType: USDCCrateSpecType,
        specifier: USDCPrimSpecifier? = nil,
        typeName: String? = nil,
        fieldNames: [String] = []
    ) {
        self.path = path
        self.specType = specType
        self.specifier = specifier
        self.typeName = typeName
        self.fieldNames = fieldNames
    }
}
