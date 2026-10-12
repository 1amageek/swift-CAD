#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Source-law and complete-domain handoff, preserving original Native lifts.
/// This receipt certifies one selected chart law, not a CS/SSI solution set.
public struct OriginalDomainBoundRationalChart<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let law: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>
    public let occurrence: OriginalBSplineChartOccurrence<S,F>
    public let localSelection: OriginalParameterSelection<S,F>
    public let inverse: OriginalParameterTransport<S,F>
    init(law: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,occurrence: OriginalBSplineChartOccurrence<S,F>,
        localSelection: OriginalParameterSelection<S,F>,inverse: OriginalParameterTransport<S,F>) {
        self.law = law; self.occurrence = occurrence; self.localSelection = localSelection; self.inverse = inverse
    }
    public func position<A: ExactScalarAdmission & ~Copyable>(at originalTuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [F.Value] {
        let originalTuple = copy originalTuple
        return try OriginalDomainAccess.run(&admission) { a in
            let local = try DefaultOriginalParameterTransporter<S,F>().forward(originalTuple,through:inverse,limits:limits,using:&a)
            let ring = law.polynomials,f = law.field
            let w = try ring.evaluated(law.denominator,at:local,using:&a).value
            guard try f.sign(of:w,using:&a) != .zero else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            try OriginalDomainAccess.storage(3,F.Value.self,&a)
            var result: [F.Value] = []; result.reserveCapacity(3)
            for axis in 0..<3 {
                try a.consumeWork(1)
                result.append(try f.dividing(ring.evaluated(law.homogeneous[axis],at:local,using:&a).value,w,using:&a))
            }
            return result
        }
    }
}
