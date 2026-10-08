import L0

struct TerminalAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var checks = 0
    var cancelAt = Int.max
    var maxStorageRequest = 0
    init(valueDepth: Int = 12,coefficientDepth: Int = 12) throws { ledger = ExactScalarLedger(limits: try DomainFixtures.limits(valueDepth:valueDepth,coefficientDepth:coefficientDepth)) }
    mutating func checkpoint() throws(ExactScalarFailure) {
        checks += 1
        if checks == cancelAt { ledger.cancel() }
        try ledger.checkpoint()
    }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        maxStorageRequest = max(maxStorageRequest, bytes)
        try ledger.retainStorage(bytes: bytes)
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try ledger.admitDepth(value: value, coefficient: coefficient)
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try ledger.visitCell(axis: axis, depth: depth)
    }
}
