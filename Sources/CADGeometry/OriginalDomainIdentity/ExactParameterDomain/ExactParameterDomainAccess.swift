#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

enum ExactParameterDomainAccess {
    static func run<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        depth: ExactScalarDepth, _ body: (inout A) throws -> R
    ) throws(ExactParameterDomainFailure) -> R {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try admission.consumeWork(1)
            let result = try body(&admission)
            try admission.checkpoint()
            return result
        } catch let failure as ExactParameterDomainFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .operationRejected(error) }
    }
    static func storage<T, A: ExactScalarAdmission & ~Copyable>(_ count: Int,
        _ type: T.Type, _ admission: inout A) throws {
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }
    static func add(_ lhs: Int, _ rhs: Int) throws(ExactParameterDomainFailure) -> Int {
        let sum = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !sum.overflow else { throw .countOverflow }
        return sum.partialValue
    }
    static func joined(_ lhs: ExactScalarDepth, _ rhs: ExactScalarDepth) throws(ExactScalarFailure) -> ExactScalarDepth {
        try .init(value: max(lhs.value, rhs.value), coefficient: max(lhs.coefficient, rhs.coefficient))
    }
    static func compare<F: ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        _ lhs: ExactParameterBound<F.Value>, _ rhs: ExactParameterBound<F.Value>,
        field: F, using admission: inout A) throws -> ExactOrder {
        try admission.consumeWork(1)
        switch (lhs, rhs) {
        case (.negativeInfinity, .negativeInfinity), (.positiveInfinity, .positiveInfinity): return .equal
        case (.negativeInfinity, _), (_, .positiveInfinity): return .less
        case (.positiveInfinity, _), (_, .negativeInfinity): return .greater
        case (.finite(let l), .finite(let r)): return try field.compare(l, r, using: &admission)
        }
    }
}
