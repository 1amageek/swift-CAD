#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed Rodrigues norm identities and exact line-on-axis incidence, not a full surface cover.
public struct OriginalRevolutionAxisSectionEvidence<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,L: OriginalLinearSourceReading>: Sendable where F.Source == F.Value {
    public let law: OriginalRevolutionLawReceipt<S,C,F>
    public let line: OriginalWholeLinearLawReceipt<L,F>
    public let axisOrigin: [F.Value]
    public let axisDirection: [F.Value]
    public let axisNormSquared: F.Value
    public let lineNormSquared: F.Value
    public let lineAxisResiduals: [F.Value]
    /// Whole-polynomial identities establishing the intrinsic rotated radial norm.
    public let identityResiduals: [ExactPolynomial<F>]
    public let proofDepth: ExactScalarDepth

    init(law: OriginalRevolutionLawReceipt<S,C,F>,line: OriginalWholeLinearLawReceipt<L,F>,
        axisOrigin: [F.Value],axisDirection: [F.Value],axisNormSquared: F.Value,lineNormSquared: F.Value,
        lineAxisResiduals: [F.Value],identityResiduals: [ExactPolynomial<F>],proofDepth: ExactScalarDepth) {
        self.law=law;self.line=line;self.axisOrigin=axisOrigin;self.axisDirection=axisDirection
        self.axisNormSquared=axisNormSquared;self.lineNormSquared=lineNormSquared
        self.lineAxisResiduals=lineAxisResiduals;self.identityResiduals=identityResiduals;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try admission.checkpoint();try law.admitProof(limits:limits,using:&admission);try line.source.require(limits)
            try admission.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            let field=law.field
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:5,of:[F.Value].self))
            for values in [axisOrigin,axisDirection,line.origin,line.direction,lineAxisResiduals] {
                for value in values { try admission.consumeWork(1);_ = try field.sign(of:value,using:&admission) }
            }
            _ = try field.sign(of:axisNormSquared,using:&admission)
            _ = try field.sign(of:lineNormSquared,using:&admission)
            for residual in identityResiduals {
                try admission.consumeWork(1);_ = try law.polynomials.degree(of:residual,in:2,using:&admission)
            }
            try admission.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
