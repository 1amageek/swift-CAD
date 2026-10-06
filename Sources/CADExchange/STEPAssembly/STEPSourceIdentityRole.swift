enum STEPSourceIdentityRole: String, Sendable {
    case product, formation, definition, material, representationCarrier, documentCarrier
    var entityNames: [String] {
        switch self {
        case .product: return ["PRODUCT"]
        case .formation: return ["PRODUCT_DEFINITION_FORMATION", "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE"]
        case .documentCarrier, .definition: return ["PRODUCT_DEFINITION"]
        case .representationCarrier: return ["SHAPE_REPRESENTATION"]
        case .material: return ["MATERIAL_DESIGNATION"]
        }
    }
    static let namespace = "urn:swiftcad:assembly-source-id"
}
