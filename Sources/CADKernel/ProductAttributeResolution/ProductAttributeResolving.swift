import CADCore
import CADGeometry
import CADIR

public protocol ProductAttributeResolving: Sendable {
    func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits) throws -> ResolvedProductAttributes
    func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits, using execution: inout OriginalQueryExecution) throws -> ResolvedProductAttributes
    func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument) throws -> StableSubshapeReference
}

public extension ProductAttributeResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Composed product queries require an injected
    // resolver's actual direct traversal. An ordinary-only provider must refuse until
    // its source, geometry and property stages share this execution.
    func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits,
        using execution: inout OriginalQueryExecution) throws -> ResolvedProductAttributes {
        throw ProductAttributeError.invalidSource("Product resolver lacks original execution support.")
    }
}
