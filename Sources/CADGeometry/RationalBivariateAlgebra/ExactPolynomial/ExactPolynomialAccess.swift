#if L1_ISOLATED_VERIFICATION
import L0
#endif

enum ExactPolynomialAccess {
    static func zeroDepth() throws(ExactPolynomialFailure) -> ExactScalarDepth {
        do { return try .init(value: 0, coefficient: 0) }
        catch { throw .scalar(error) }
    }
    static func query<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        inherited: ExactScalarDepth, _ body: (inout ExactPolynomialAdmission<A>) throws -> R
    ) throws(ExactPolynomialFailure) -> R {
        do {
            try admission.checkpoint()
            let result = try withUnsafeMutablePointer(to: &admission) { caller in
                var usage = ExactPolynomialAdmission(caller: caller, inherited: inherited)
                try usage.admitDepth(value: inherited.value, coefficient: inherited.coefficient)
                try usage.consumeWork(1)
                let result = try body(&usage)
                try usage.checkpoint()
                return result
            }
            try admission.checkpoint()
            return result
        } catch let failure as ExactPolynomialFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .operationRejected(error) }
    }
    static func count(_ a: Int, _ b: Int, multiply: Bool = false) throws(ExactPolynomialFailure) -> Int {
        let value = multiply ? a.multipliedReportingOverflow(by: b) : a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !value.overflow else { throw .countOverflow }
        return value.partialValue
    }
    static func exponent(_ a: Int, _ b: Int) throws(ExactPolynomialFailure) -> Int {
        let value = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !value.overflow else { throw .exponentOverflow }
        return value.partialValue
    }
    static func storage<A: ExactScalarAdmission & ~Copyable, T>(_ count: Int, _ type: T.Type,
        _ usage: inout ExactPolynomialAdmission<A>) throws {
        let bytes: Int
        do { bytes = try exactScalarPayloadBytes(count: count, of: type) }
        catch {
            if case .countOverflow = error { throw ExactPolynomialFailure.countOverflow }
            throw ExactPolynomialFailure.scalar(error)
        }
        try usage.retainStorage(bytes: bytes)
    }
    static func order<A: ExactScalarAdmission & ~Copyable>(_ a: [Int], _ b: [Int],
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Int {
        try usage.consumeWork(try count(a.count, 1))
        guard a.count == b.count else { throw ExactPolynomialFailure.invalidCertificate }
        for i in a.indices { if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 } }
        return 0
    }
    static func merged(_ a: ExactScalarDepth, _ b: ExactScalarDepth) throws(ExactScalarFailure) -> ExactScalarDepth {
        try .init(value: max(a.value, b.value), coefficient: max(a.coefficient, b.coefficient))
    }
}
