/// Sealed whole-support exclusion retaining the original source and actual plane owners.
public struct OriginalCertifiedSphereConeApexPlaneSeparationReceipt: Sendable {
    public typealias Field = OriginalPhysicalAngleScalarDomain
    public enum CoefficientSemantics: Sendable {
        case canonicalPhysicalAndExactBinaryConfiguration
    }
    public let source: OriginalSourceBinding<OriginalCertifiedSphereConeApexSnapshot>
    public let plane: OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, Field>
    public let field: Field
    public let support: OriginalSourceParameterInterval<Field.Value>
    public let signedDistanceLower: Field.Value
    public let signedDistanceUpper: Field.Value
    public let heightUpperBound: Field.Value
    public let clearance: Field.Value
    public let coefficientSemantics: CoefficientSemantics
    /// Exact imports of every original configuration, basis and angle-label coefficient.
    public let binaryCoefficients: [Field.Value]
    /// Mathematical sine, cosine, tangent and quadratic coefficient of the authored angle.
    public let physicalCoefficients: [Field.Value]
    /// Common coefficient, denominator, inverse and whole-phase height bounds.
    public let commonEnvelope: [Field.Value]
    public let proofDepth: ExactScalarDepth

    init(source: OriginalSourceBinding<OriginalCertifiedSphereConeApexSnapshot>,
        plane: OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, Field>, field: Field,
        support: OriginalSourceParameterInterval<Field.Value>, signedDistanceLower: Field.Value,
        signedDistanceUpper: Field.Value, heightUpperBound: Field.Value, clearance: Field.Value,
        binaryCoefficients: [Field.Value], physicalCoefficients: [Field.Value],
        commonEnvelope: [Field.Value], proofDepth: ExactScalarDepth) {
        self.source = source; self.plane = plane; self.field = field; self.support = support
        self.signedDistanceLower = signedDistanceLower; self.signedDistanceUpper = signedDistanceUpper
        self.heightUpperBound = heightUpperBound; self.clearance = clearance
        coefficientSemantics = .canonicalPhysicalAndExactBinaryConfiguration
        self.binaryCoefficients = binaryCoefficients; self.physicalCoefficients = physicalCoefficients
        self.commonEnvelope = commonEnvelope; self.proofDepth = proofDepth
    }

    /// Readmits every retained coefficient and attained depth without regenerating the source.
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) {
        do {
            try admission.checkpoint(); try source.require(limits); try plane.source.require(limits)
            try admission.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            let sourceZero = try source.original.field.integer(0, using: &admission)
            _ = try field.importing(sourceZero, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Field.Value.self))
            for value in [support.lower, support.upper, signedDistanceLower, signedDistanceUpper,
                heightUpperBound, clearance] {
                try admission.consumeWork(1); _ = try field.importing(value, using: &admission)
            }
            // These immutable values belong to an already sealed theorem. Importing
            // checks each owner and full retained scalar/coefficient depth; a new sign
            // refinement would prove the same physical theorem again.
            for value in binaryCoefficients { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in physicalCoefficients { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in commonEnvelope { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in plane.origin { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in plane.normal { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in plane.u { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            for value in plane.v { try admission.consumeWork(1); _ = try field.importing(value, using: &admission) }
            try admission.checkpoint()
        } catch { throw .init(preserving: error) }
    }
}
