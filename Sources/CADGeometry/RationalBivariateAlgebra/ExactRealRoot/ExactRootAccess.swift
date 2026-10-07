#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

enum ExactRootAccess {
    static func run<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        inherited: ExactScalarDepth? = nil, _ body: (inout ExactRootBorrowedAdmission) throws -> R
    ) throws(ExactRealRootFailure) -> R {
        do {
            try admission.checkpoint()
            let depth = try inherited ?? ExactScalarDepth(value: 0, coefficient: 0)
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            // Class payload/header plus four scoped closure contexts, each retaining one pointer.
            let closure = MemoryLayout<() throws -> Void>.stride
            let pointer = MemoryLayout<UnsafeRawPointer>.stride
            let bytes = try add(add(multiply(4, closure), MemoryLayout<ExactScalarDepth>.stride),
                add(multiply(2, pointer), multiply(4, multiply(3, pointer))))
            try admission.retainStorage(bytes: bytes)
            let result = try withUnsafeMutablePointer(to: &admission) { pointer in
                var usage = ExactRootBorrowedAdmission(owner: ExactRootInvocationOwner(caller: pointer, depth: depth))
                try usage.consumeWork(1)
                let result = try body(&usage)
                try usage.checkpoint()
                return result
            }
            try admission.checkpoint()
            return result
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
    static func storage<T>(_ count: Int, _ type: T.Type, _ a: inout ExactRootBorrowedAdmission) throws {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }
    static func owner<T>(_ payload: T.Type, _ a: inout ExactRootBorrowedAdmission) throws {
        try a.retainStorage(bytes: add(MemoryLayout<T>.stride, multiply(2, MemoryLayout<UnsafeRawPointer>.stride)))
    }
    static func admit(_ depth: ExactScalarDepth, _ a: inout ExactRootBorrowedAdmission) throws {
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
    }
    static func step(_ depth: ExactScalarDepth, axis: ExactScalarRootAxis,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactScalarDepth {
        let next = try ExactScalarDepth(value: axis == .value ? add(depth.value, 1) : depth.value,
            coefficient: axis == .coefficient ? add(depth.coefficient, 1) : depth.coefficient)
        try admit(next, &a); return next
    }
}
