#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

enum ExactCellAccess {
    static func run<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        inherited: ExactScalarDepth? = nil, _ body: (inout A) throws -> R
    ) throws(ExactRealCellFailure) -> R {
        do {
            return try admission.withProofScope(inherited:inherited) { a in
                try a.consumeWork(1)
                return try body(&a)
            }
        } catch let failure as ExactRealCellFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch let failure as ExactPolynomialFailure { throw .polynomial(failure) }
        catch let failure as ExactRealRootFailure { throw .root(failure) }
        catch { throw .operationRejected(error) }
    }
    static func add(_ a: Int, _ b: Int) throws(ExactRealCellFailure) -> Int {
        let r = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !r.overflow else { throw .countOverflow }; return r.partialValue
    }
    static func multiply(_ a: Int, _ b: Int) throws(ExactRealCellFailure) -> Int {
        let r = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !r.overflow else { throw .countOverflow }; return r.partialValue
    }
    static func storage<T, A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type, _ a: inout A) throws {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }
    static func owner<T, A: ExactScalarAdmission & ~Copyable>(_ payload: T.Type, _ a: inout A) throws {
        try a.retainStorage(bytes: add(MemoryLayout<T>.stride, multiply(2, MemoryLayout<UnsafeRawPointer>.stride)))
    }
    static func admit<A: ExactScalarAdmission & ~Copyable>(_ depth: ExactScalarDepth, _ a: inout A) throws {
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
    }
}
