/// Query-local ownership prevents accidentally duplicating a budget snapshot.
public struct ExactScalarLedger: ~Copyable, ExactScalarAdmission, Sendable {
    public var proofScopes = ExactScalarProofScopes()
    public let limits: ExactScalarLimits
    public private(set) var work = 0
    public private(set) var storageBytes = 0
    public private(set) var valueDepth = 0
    public private(set) var coefficientDepth = 0
    private var cancelled = false

    public init(limits: ExactScalarLimits) { self.limits = limits }
    public mutating func cancel() { cancelled = true }
    public mutating func checkpoint() throws(ExactScalarFailure) {
        if cancelled || Task<Never, Never>.isCancelled { throw .cancelled }
    }
    public mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard units >= 0 else { throw .countOverflow }
        try proofScopes.checkWork(units)
        let next = work.addingReportingOverflow(units)
        guard !next.overflow else { throw .countOverflow }
        guard next.partialValue <= limits.work else { throw .resourceLimit(.work) }
        work = next.partialValue
        proofScopes.recordWork(units)
    }
    public mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard bytes >= 0 else { throw .countOverflow }
        let next = storageBytes.addingReportingOverflow(bytes)
        guard !next.overflow else { throw .countOverflow }
        guard next.partialValue <= limits.storageBytes else { throw .resourceLimit(.storage) }
        storageBytes = next.partialValue
    }
    public mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try admitDepth(value:axis == .value ? depth:0,coefficient:axis == .coefficient ? depth:0)
    }
    public mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let mapped=try proofScopes.mapped(value:value,coefficient:coefficient)
        guard mapped.value<=limits.valueDepth else { throw .resourceLimit(.valueDepth) }
        guard mapped.coefficient<=limits.coefficientDepth else { throw .resourceLimit(.coefficientDepth) }
        try proofScopes.record(value:value,coefficient:coefficient)
        valueDepth=max(valueDepth,mapped.value); coefficientDepth=max(coefficientDepth,mapped.coefficient)
    }
}
