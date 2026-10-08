/// Query-local ownership prevents accidentally duplicating a budget snapshot.
public struct ExactScalarLedger: ~Copyable, ExactScalarAdmission, Sendable {
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
        let next = work.addingReportingOverflow(units)
        guard !next.overflow else { throw .countOverflow }
        guard next.partialValue <= limits.work else { throw .resourceLimit(.work) }
        work = next.partialValue
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
        try admitDepth(value: axis == .value ? depth : valueDepth,
            coefficient: axis == .coefficient ? depth : coefficientDepth)
    }
    public mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard value >= 0, coefficient >= 0 else { throw .countOverflow }
        guard value <= limits.valueDepth else { throw .resourceLimit(.valueDepth) }
        guard coefficient <= limits.coefficientDepth else { throw .resourceLimit(.coefficientDepth) }
        valueDepth = max(valueDepth, value); coefficientDepth = max(coefficientDepth, coefficient)
    }
}
