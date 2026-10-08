import L0

struct TraceAdmission: ~Copyable, ExactScalarAdmission {
    var base: ExactScalarLedger
    var storageCalls = 0
    let cancelAtStorage: Int?
    let rejectDepth: ExactScalarRootAxis?
    var work: Int { base.work }
    var storageBytes: Int { base.storageBytes }

    init(work: Int = 20_000_000, storage: Int = 134_217_728,
        cancelAtStorage: Int? = nil, rejectDepth: ExactScalarRootAxis? = nil) throws {
        base = ExactScalarLedger(limits: try .init(work: work, storageBytes: storage,
            valueDepth: 32, coefficientDepth: 32))
        self.cancelAtStorage = cancelAtStorage; self.rejectDepth = rejectDepth
    }
    mutating func checkpoint() throws(ExactScalarFailure) { try base.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try base.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try base.retainStorage(bytes: bytes)
        let next = storageCalls.addingReportingOverflow(1)
        guard !next.overflow else { throw .countOverflow }
        storageCalls = next.partialValue
        if storageCalls == cancelAtStorage { base.cancel() }
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try base.visitCell(axis: axis, depth: depth)
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        if let rejectDepth {
            throw .resourceLimit(rejectDepth == .value ? .valueDepth : .coefficientDepth)
        }
        try base.admitDepth(value: value, coefficient: coefficient)
    }
}
