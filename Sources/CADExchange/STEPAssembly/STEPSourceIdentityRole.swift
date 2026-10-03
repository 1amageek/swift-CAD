enum STEPSourceIdentityRole: String, Sendable {
    case product, formation, definition
    var entityNames: [String] {
        switch self {
        case .product: return ["PRODUCT"]
        case .formation: return ["PRODUCT_DEFINITION_FORMATION", "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE"]
        case .definition: return ["PRODUCT_DEFINITION"]
        }
    }
    static let namespace = "urn:swiftcad:assembly-source-id"
}
