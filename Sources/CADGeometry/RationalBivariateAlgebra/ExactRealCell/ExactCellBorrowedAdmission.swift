#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// A fixed kernel type prevents recursive generic admission specialization.
struct ExactCellBorrowedAdmission: ExactScalarAdmission {
    let owner: any ExactCellInvocation
    var depth: ExactScalarDepth { owner.depth }
    mutating func checkpoint() throws(ExactScalarFailure) { try owner.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try owner.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try owner.retainStorage(bytes: bytes) }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try owner.visitCell(axis: axis, depth: depth)
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try owner.admitDepth(value: value, coefficient: coefficient)
    }
}
