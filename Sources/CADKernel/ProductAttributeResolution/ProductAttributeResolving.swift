import CADCore
import CADIR

public protocol ProductAttributeResolving: Sendable {
    func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits) throws -> ResolvedProductAttributes
    func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument) throws -> StableSubshapeReference
}
