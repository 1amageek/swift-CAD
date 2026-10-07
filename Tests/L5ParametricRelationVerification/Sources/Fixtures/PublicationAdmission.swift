import L0

struct PublicationAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    let storageStop: Int
    let workStop: Int
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try ledger.consumeWork(units)
        if ledger.work >= workStop { ledger.cancel() }
    }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try ledger.retainStorage(bytes: bytes)
        if ledger.storageBytes >= storageStop { ledger.cancel() }
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try ledger.admitDepth(value: value, coefficient: coefficient)
    }
}
