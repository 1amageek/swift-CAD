#if ORIGINAL_QUADRATIC_BOUNDARY_ISOLATED_VERIFICATION
import L0
import L1
@testable import SourceIssuer
#endif

/// Sealed complete arc/preimage authority in the first two original coordinates.
/// The cap has nonnegative barycentrics and
/// 4*w1*w1*lambda0*lambda2-w0*w2*lambda1*lambda1 > 0.
/// Its oriented contribution relative to the forward chord is sign(determinant).
public struct OriginalRationalQuadraticBoundaryReceipt<S: OriginalBSplineSourceReading,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let law: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>
    public let first: [F.Value]
    public let last: [F.Value]
    /// Three affine rows in coefficient order U, V, constant.
    public let barycentricRows: [[F.Value]]
    public let weights: [F.Value]
    public let determinant: F.Value
    /// The three barycentric Bernstein identities and their denominator sum.
    public let identityResiduals: [ExactPolynomial<F>]
    public let proofDepth: ExactScalarDepth

    init(law: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,first:[F.Value],last:[F.Value],
        barycentricRows:[[F.Value]],weights:[F.Value],determinant:F.Value,
        identityResiduals:[ExactPolynomial<F>],proofDepth:ExactScalarDepth) {
        self.law=law;self.first=first;self.last=last;self.barycentricRows=barycentricRows
        self.weights=weights;self.determinant=determinant;self.identityResiduals=identityResiduals;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try admission.checkpoint()
            guard law.source.sourceDepth >= 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
            guard law.source.sourceDepth <= limits.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try law.admitProof(using:&admission)
            try admission.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            func values(_ input:[F.Value],_ a:inout A) throws {
                for value in input { try a.consumeWork(1);_ = try law.field.sign(of:value,using:&a) }
            }
            try values(first,&admission);try values(last,&admission);try values(weights,&admission)
            for row in barycentricRows { try values(row,&admission) }
            _ = try law.field.sign(of:determinant,using:&admission)
            for interval in law.support { _ = try law.field.compare(interval.lower,interval.upper,using:&admission) }
            for polynomial in law.homogeneous { _ = try law.polynomials.degree(of:polynomial,in:0,using:&admission) }
            for polynomial in law.parameterTransport.numerators { _ = try law.polynomials.degree(of:polynomial,in:0,using:&admission) }
            for polynomial in law.parameterTransport.denominators { _ = try law.polynomials.degree(of:polynomial,in:0,using:&admission) }
            for residual in identityResiduals { _ = try law.polynomials.degree(of:residual,in:0,using:&admission) }
            try admission.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
