public enum USDCLayerFieldValue: Sendable, Equatable {
    case token(String)
    case tokenArray([String])
    case tokenVector([String])
    case string(String)
    case assetPath(String)
    case pathVector([String])
    case double(Double)
    case intArray([Int])
    case specifier(USDCPrimSpecifier)
}
