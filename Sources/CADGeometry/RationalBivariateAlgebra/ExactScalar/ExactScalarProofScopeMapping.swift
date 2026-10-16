/// A numeric operation's causal depth mapping and optional value-axis routing.
public struct ExactScalarProofScopeMapping: Sendable {
    public let original: ExactScalarDepth?
    public let inherited: ExactScalarDepth
    public let maximum: ExactScalarDepth
    public let valueAxis: ExactScalarRootAxis

    public init(original: ExactScalarDepth? = nil, inherited: ExactScalarDepth,
        maximum: ExactScalarDepth, valueAxis: ExactScalarRootAxis = .value) {
        self.original=original; self.inherited=inherited; self.maximum=maximum; self.valueAxis=valueAxis
    }

    func applying(_ input: ExactScalarDepth) throws(ExactScalarFailure) -> ExactScalarDepth {
        var value=input.value, coefficient=input.coefficient
        if valueAxis == .coefficient { coefficient=max(coefficient,value); value=0 }
        if let original {
            let v=inherited.value.addingReportingOverflow(max(0,value-original.value))
            let c=inherited.coefficient.addingReportingOverflow(max(0,coefficient-original.coefficient))
            guard !v.overflow,!c.overflow else { throw .countOverflow }
            value=v.partialValue; coefficient=c.partialValue
        }
        guard value<=maximum.value else { throw .resourceLimit(.valueDepth) }
        guard coefficient<=maximum.coefficient else { throw .resourceLimit(.coefficientDepth) }
        return .init(uncheckedValue:value,coefficient:coefficient)
    }
}
