import L0
import L1
import SourceIssuer

/// Focused execution of the same guide fixtures without unrelated WMO work.
public enum SourceFixtures {
    enum Failure:Error { case incorrectEvidence }
    typealias Field=ExactRationalScalarDomain
    typealias Receipt=OriginalRationalChartReceipt<NativeSnapshot,OriginalBSplineChartSelection,Field>
    static func require(_ condition:Bool) throws {
        guard condition else { throw Failure.incorrectEvidence }
    }
}
