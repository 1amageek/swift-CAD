#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

enum ExactGeometryAccess {
    static func add(_ a: Int, _ b: Int) throws -> Int {
        let r = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !r.overflow else { throw ExactGeometricRelationFailure.countOverflow }
        return r.partialValue
    }
    static func multiply(_ a: Int, _ b: Int) throws -> Int {
        let r = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !r.overflow else { throw ExactGeometricRelationFailure.countOverflow }
        return r.partialValue
    }
    static func storage<T,A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type, _ a: inout A) throws {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }
}
