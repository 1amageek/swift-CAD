import CADIR
import CADKernel

public protocol STEPAttributesWriting: Sendable {
    func geometryNames(for evaluated: EvaluatedDocument, resolved: ResolvedProductAttributes,
                       limits: ExchangeResourceLimits) throws -> STEPGeometryAttributeNames
    func records(for evaluated: EvaluatedDocument, resolved: ResolvedProductAttributes,
                 transfer: STEPAttributeWriteTransfer, startingAt: Int, limits: ExchangeResourceLimits) throws -> [String]
}
