import CADGeometry

struct OrderedConstructionAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var workCalls = 0
    let cancellingCall: Int?
    init(cancellingCall: Int? = nil) throws {
        ledger = try NativeExactFixtures.ledger()
        self.cancellingCall = cancellingCall
    }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try ledger.consumeWork(units)
        workCalls += 1
        if workCalls == cancellingCall { ledger.cancel() }
    }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try ledger.visitCell(axis: axis, depth: depth)
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try ledger.admitDepth(value: value, coefficient: coefficient)
    }
}
