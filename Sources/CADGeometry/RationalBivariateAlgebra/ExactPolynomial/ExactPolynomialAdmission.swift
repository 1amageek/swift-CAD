#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// A nonescaping stack borrow observes depth without copying or resetting the caller ledger.
/// The caller owns initialized ledger storage; the enclosing query owns this pointer's
/// lifetime. There is no allocation/deallocation, binding, offset or Sendable transfer.
struct ExactPolynomialAdmission<A: ExactScalarAdmission & ~Copyable>: ~Copyable, ExactScalarAdmission {
    let caller: UnsafeMutablePointer<A>
    private(set) var valueDepth: Int
    private(set) var coefficientDepth: Int
    var depth: ExactScalarDepth { get throws(ExactScalarFailure) {
        try .init(value: valueDepth, coefficient: coefficientDepth)
    } }
    init(caller: UnsafeMutablePointer<A>, inherited: ExactScalarDepth) {
        self.caller = caller; valueDepth = inherited.value; coefficientDepth = inherited.coefficient
    }
    mutating func checkpoint() throws(ExactScalarFailure) { try caller.pointee.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try checkpoint(); try caller.pointee.consumeWork(units); try checkpoint()
    }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint(); try caller.pointee.retainStorage(bytes: bytes); try checkpoint()
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try checkpoint(); try caller.pointee.visitCell(axis: axis, depth: depth)
        if axis == .value { valueDepth = max(valueDepth, depth) }
        else { coefficientDepth = max(coefficientDepth, depth) }
        try checkpoint()
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint(); try caller.pointee.admitDepth(value: value, coefficient: coefficient)
        valueDepth = max(valueDepth, value); coefficientDepth = max(coefficientDepth, coefficient)
        try checkpoint()
    }
}
