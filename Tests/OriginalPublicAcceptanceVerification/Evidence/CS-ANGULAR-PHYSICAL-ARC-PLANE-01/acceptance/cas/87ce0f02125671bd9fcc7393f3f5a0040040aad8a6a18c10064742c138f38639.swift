#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Scoped forwarding borrow of the caller's exclusive ledger, without a new allowance.
/// The stack pointer exists only inside withUnsafeMutablePointer and never escapes.
/// Its pointee is initialized A with matching alignment; no allocation, rebinding,
/// deallocation, Sendable crossing or concurrent access is performed.
struct OriginalSourceProofAdmission<A: ExactScalarAdmission & ~Copyable>: ~Copyable, ExactScalarAdmission {
    private let ledger: UnsafeMutablePointer<A>
    private(set) var valueDepth = 0
    private(set) var coefficientDepth = 0
    private init(_ ledger: UnsafeMutablePointer<A>) { self.ledger = ledger }
    static func withBorrow<Result>(_ admission: inout A,
        _ body: (inout Self) throws -> Result
    ) throws -> Result {
        try withUnsafeMutablePointer(to: &admission) { pointer in
            var usage = Self(pointer)
            return try body(&usage)
        }
    }
    var depth: ExactScalarDepth { get throws {
        try .init(value: valueDepth, coefficient: coefficientDepth)
    } }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.pointee.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.pointee.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.pointee.retainStorage(bytes: bytes) }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try ledger.pointee.admitDepth(value: value, coefficient: coefficient)
        valueDepth = max(valueDepth, value); coefficientDepth = max(coefficientDepth, coefficient)
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try ledger.pointee.visitCell(axis: axis, depth: depth)
        if axis == .value { valueDepth = max(valueDepth, depth) }
        else { coefficientDepth = max(coefficientDepth, depth) }
    }
}
