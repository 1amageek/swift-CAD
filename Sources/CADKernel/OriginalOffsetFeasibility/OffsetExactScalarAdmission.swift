import CADCore
import CADGeometry

/// Borrows one result invocation and preserves independent exact depth limits.
struct OffsetExactScalarAdmission: ~Copyable, ExactScalarAdmission {
    let invocation: OffsetFeasibilityInvocation
    let maximumDepth: Int
    mutating func checkpoint() throws(ExactScalarFailure) {
        do { try CurrentTaskCancellationChecker().checkCancellation() }
        catch { throw .cancelled }
    }
    mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
        guard count >= 0 else { throw .countOverflow }
        try checkpoint()
        do { for _ in 0..<count { try invocation.consume(depth:0) } }
        catch let error as ExactScalarFailure { throw error }
        catch is CancellationError { throw .cancelled }
        catch { throw .admissionRejected(error) }
        try checkpoint()
    }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint()
        do { try invocation.retain(bytes) }
        catch let error as ExactScalarFailure { throw error }
        catch is CancellationError { throw .cancelled }
        catch { throw .admissionRejected(error) }
        try checkpoint()
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard value >= 0,coefficient >= 0 else { throw .countOverflow }
        guard value <= maximumDepth else { throw .resourceLimit(.valueDepth) }
        guard coefficient <= maximumDepth else { throw .resourceLimit(.coefficientDepth) }
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try admitDepth(value:axis == .value ? depth:0,coefficient:axis == .coefficient ? depth:0)
        try consumeWork(1)
    }
}
