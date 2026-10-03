import CADIR
import CADKernel

public protocol STEPAttributesReading: Sendable {
    func read(entities: [Int: String], transfer: STEPAttributeReadTransfer,
              evaluated: EvaluatedDocument, limits: ExchangeResourceLimits) throws -> ProductAttributes
}
