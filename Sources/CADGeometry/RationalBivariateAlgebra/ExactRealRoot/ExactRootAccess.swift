#if L2_ISOLATED_VERIFICATION
import L0
import L1
import DI0
#endif

enum ExactRootAccess {
    static func parameterDomain<R>(_ body: () throws(ExactParameterDomainFailure) -> R)
        throws(ExactRealRootFailure) -> R {
        do { return try body() }
        catch {
            switch error {
            case .invalidDomain, .invalidArity: throw .invalidDomain
            case .foreignOwner: throw .incompatibleDomain
            case .countOverflow: throw .countOverflow
            case .scalar(let cause): throw .scalar(cause)
            case .operationRejected(let cause): throw .operationRejected(cause)
            }
        }
    }
    static func run<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        inherited: ExactScalarDepth? = nil, _ body: (inout A) throws -> R
    ) throws(ExactRealRootFailure) -> R {
        do {
            return try admission.withProofScope(inherited:inherited) { a in
                try a.consumeWork(1)
                return try body(&a)
            }
        } catch let failure as ExactRealRootFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch let failure as ExactPolynomialFailure { throw .polynomial(failure) }
        catch { throw .operationRejected(error) }
    }
    static func add(_ a: Int, _ b: Int) throws(ExactRealRootFailure) -> Int {
        let r = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !r.overflow else { throw .countOverflow }; return r.partialValue
    }
    static func multiply(_ a: Int, _ b: Int) throws(ExactRealRootFailure) -> Int {
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
    static func visit<A: ExactScalarAdmission & ~Copyable>(_ interval: ExactScalarDepth, axis: ExactScalarRootAxis,
        _ a: inout A) throws {
        let causal = axis == .value ? max(interval.value, (try a.depth).value) : max(interval.coefficient, (try a.depth).coefficient)
        try a.visitCell(axis: axis, depth: causal)
    }
    static func step<A: ExactScalarAdmission & ~Copyable>(_ depth: ExactScalarDepth, axis: ExactScalarRootAxis,
        _ a: inout A) throws -> ExactScalarDepth {
        let next = try ExactScalarDepth(value: axis == .value ? add(depth.value, 1) : depth.value,
            coefficient: axis == .coefficient ? add(depth.coefficient, 1) : depth.coefficient)
        try admit(next, &a); return next
    }
}
