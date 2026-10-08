#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

enum OriginalDomainAccess {
    static func run<A: ExactScalarAdmission & ~Copyable, R>(_ a: inout A,
        _ body: (inout A) throws -> R) throws(OriginalDomainIdentityFailure) -> R {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            let value = try body(&a)
            try a.checkpoint(); return value
        } catch { throw .init(preserving: error) }
    }
    static func storage<T, A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type,
        _ a: inout A) throws { try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type)) }
    static func add(_ a: Int, _ b: Int) throws(OriginalDomainIdentityFailure) -> Int {
        let sum = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !sum.overflow else { throw .countOverflow }; return sum.partialValue
    }
    static func multiplied(_ a: Int, _ b: Int) throws(OriginalDomainIdentityFailure) -> Int {
        let value = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !value.overflow else { throw .countOverflow }; return value.partialValue
    }
    static func owner<T, A: ExactScalarAdmission & ~Copyable>(_ type: T.Type, _ a: inout A) throws {
        let bytes = try exactScalarPayloadBytes(count: 1, of: type)
        let header = try exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self)
        try a.retainStorage(bytes: add(bytes, header))
    }
}
