#if NATIVE_FAMILY_FULL_VERIFICATION
import CADGeometry
#else
import L0
#endif
struct TerminalAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var storageCalls = 0
    let cancellingCall: Int?
    init(cancellingCall: Int? = nil) throws {
        self.cancellingCall = cancellingCall
        ledger = try FamilyFixtures.ledger()
    }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try ledger.retainStorage(bytes:bytes)
        storageCalls += 1
        if storageCalls == cancellingCall { ledger.cancel() }
    }
    mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
    mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
}
