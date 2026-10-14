import CADCore

/// Exact equal-authored primitive law; nonzero slant is injective modulo B.
public struct OriginalCoincidentConeSnapshot: Sendable {
    public typealias Field=OriginalPhysicalAngleScalarDomain
    public let original: OriginalCoincidentConeInput
    public let field: Field
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot,Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot,Field>
    public let sine: Field.Value
    public let cosine: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
    public func position<A: ExactScalarAdmission & ~Copyable>(intrinsicLabel: Field.Value, slant: Field.Value,
        using a: inout A) throws -> OriginalCoincidentConePosition {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            let label=try field.importing(intrinsicLabel,using:&a),v=try field.importing(slant,using:&a)
            let radial=try field.multiplying(sine,v,using:&a),axial=try field.multiplying(cosine,v,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoincidentConePosition.self))
            let result=OriginalCoincidentConePosition(source:self,intrinsicLabel:label,slant:v,radial:radial,axial:axial,proofDepth:try a.depth)
            try a.checkpoint();return result
        }
    }
}
