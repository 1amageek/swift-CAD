public protocol ProductAttributesValidating: Sendable {
    func validate(_ attributes: ProductAttributes, in document: CADDocument, budget: inout ProductAttributeBudget) throws
}
