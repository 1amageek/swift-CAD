#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Checked partition of local parameter and auxiliary solver coordinates.
public struct OriginalParametricVariableLayout: Sendable {
    public let variableCount: Int
    public let parameters: [Int]
    public let auxiliaries: [Int]
    public static func checked<A: ExactScalarAdmission & ~Copyable>(variableCount: Int,
        parameters: [Int], auxiliaries: [Int], using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> Self {
        do {
            try a.checkpoint()
            let total=parameters.count.addingReportingOverflow(auxiliaries.count)
            guard variableCount>=0,!total.overflow,total.partialValue==variableCount else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:variableCount,of:Bool.self))
            var seen=[Bool](repeating:false,count:variableCount)
            for ordinal in 0..<variableCount {
                    let index = ordinal < parameters.count ? parameters[ordinal] : auxiliaries[ordinal-parameters.count]
                    try a.consumeWork(1)
                    guard index>=0,index<variableCount,!seen[index] else { throw OriginalSourceIssuanceFailure.invalidChart }
                    seen[index]=true
            }
            let result=Self(variableCount:variableCount,parameters:parameters,auxiliaries:auxiliaries)
            try a.checkpoint();return result
        } catch { throw .init(preserving:error) }
    }
    private init(variableCount:Int,parameters:[Int],auxiliaries:[Int]) {
        self.variableCount=variableCount;self.parameters=parameters;self.auxiliaries=auxiliaries
    }
}
