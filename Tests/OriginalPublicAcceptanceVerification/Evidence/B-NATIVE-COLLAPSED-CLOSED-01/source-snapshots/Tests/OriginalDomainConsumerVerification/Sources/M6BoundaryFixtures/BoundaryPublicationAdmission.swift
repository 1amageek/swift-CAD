#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
#else
import CADGeometry
#endif

/// Invocation-owned admission that cancels at the measured final publication allocation.
struct BoundaryPublicationAdmission: ~Copyable, ExactScalarAdmission {
    private var ledger: ExactScalarLedger
    private(set) var storageCalls = 0
    let cancellingCall: Int?
    init(cancellingCall: Int? = nil) throws {
        self.cancellingCall = cancellingCall
        ledger = try M6ExactBoundaryFixtures.ledger()
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
