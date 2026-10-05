import CADCore

public struct ProductViewMetadata: Equatable, Sendable {
    public var views: [ProductSavedView]
    public var validationProperties: [ProductValidationProperty]
    public init(views: [ProductSavedView] = [], validationProperties: [ProductValidationProperty] = []) {
        self.views = views; self.validationProperties = validationProperties
    }
    public var isEmpty: Bool { views.isEmpty && validationProperties.isEmpty }
    public var canonicalized: Self {
        Self(views: views.sorted { $0.id < $1.id }, validationProperties: validationProperties.sorted { $0.id < $1.id })
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case views, validationProperties }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.views, .validationProperties], in: decoder)
        views = try c.decode([ProductSavedView].self, forKey: .views)
        validationProperties = try c.decode([ProductValidationProperty].self, forKey: .validationProperties)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductViewMetadata: Codable {}
#endif
