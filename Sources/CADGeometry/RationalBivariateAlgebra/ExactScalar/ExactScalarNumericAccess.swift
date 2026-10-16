/// Runs existing numeric operations on the original caller admission directly.
enum ExactScalarNumericAccess {
    static func withAdmission<A:ExactScalarAdmission & ~Copyable,R>(
        _ admission:inout A,original:ExactScalarDepth = .zero,inherited:ExactScalarDepth = .zero,
        maximum:ExactScalarDepth = .init(uncheckedValue:Int.max,coefficient:Int.max),
        _ body:(inout A)throws->R) throws(ExactScalarFailure)->(value:R,depth:ExactScalarDepth) {
        do {
            return try admission.withProofScope(original:original,inherited:inherited,maximum:maximum) { a in
                try a.consumeWork(1)
                let value=try body(&a)
                return (value,try a.depth)
            }
        } catch let failure as ExactScalarFailure { throw failure }
        catch is CancellationError { throw .cancelled }
        catch { throw .admissionRejected(error) }
    }
}
