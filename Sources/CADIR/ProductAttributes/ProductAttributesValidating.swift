import CADGeometry
public protocol ProductAttributesValidating: Sendable {
    func validate(_ attributes: ProductAttributes, in document: CADDocument, budget: inout ProductAttributeBudget) throws
    func validate(_ attributes: ProductAttributes, in document: CADDocument, budget: inout ProductAttributeBudget,
        using execution: inout OriginalQueryExecution) throws
}

public extension ProductAttributesValidating {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected validator without its actual
    // direct source traversal cannot enter a composing query through an ordinary
    // budget reset. Production direct validation must refuse until that core exists.
    func validate(_ attributes: ProductAttributes, in document: CADDocument, budget: inout ProductAttributeBudget,
        using execution: inout OriginalQueryExecution) throws {
        throw ProductAttributeError.invalidSource("Product validator lacks original execution support.")
    }
}
