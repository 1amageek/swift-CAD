/// Borrows one caller ledger for the complete existing numeric invocation.
enum ExactScalarNumericAccess {
    static func withAdmission<A: ExactScalarAdmission & ~Copyable, R>(
        _ admission: inout A, original: ExactScalarDepth = .zero,
        inherited: ExactScalarDepth = .zero,
        maximum: ExactScalarDepth = .init(uncheckedValue: Int.max, coefficient: Int.max),
        _ body: (inout ExactScalarRationalAdmission<A>) throws -> R
    ) throws(ExactScalarFailure) -> (value: R, depth: ExactScalarDepth) {
        try admission.checkpoint()
        guard inherited.value <= maximum.value else { throw .resourceLimit(.valueDepth) }
        guard inherited.coefficient <= maximum.coefficient else { throw .resourceLimit(.coefficientDepth) }
        try admission.admitDepth(value: inherited.value, coefficient: inherited.coefficient)
        var reached = inherited
        do {
            let value = try withUnsafeMutablePointer(to: &admission) { ledger in
                try withUnsafeMutablePointer(to: &reached) { depth in
                    var numeric = ExactScalarRationalAdmission(ledger: ledger, reached: depth,
                        original: original, inherited: inherited, maximum: maximum)
                    try numeric.consumeExactWork(1)
                    return try body(&numeric)
                }
            }
            try admission.checkpoint()
            return (value, reached)
        } catch let failure as ExactScalarFailure { throw failure }
        catch is CancellationError { throw .cancelled }
        catch { throw .admissionRejected(error) }
    }
}
