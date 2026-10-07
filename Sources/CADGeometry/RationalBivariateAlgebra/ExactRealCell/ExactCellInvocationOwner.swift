#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// These closures retain only the scope's exclusive admission pointer.
/// Neither the owner nor a closure escapes ExactCellAccess.run or crosses isolation.
final class ExactCellInvocationOwner: ExactCellInvocation {
    private let check: () throws -> Void
    private let work: (Int) throws -> Void
    private let storage: (Int) throws -> Void
    private let depths: (Int, Int) throws -> Void
    private(set) var depth: ExactScalarDepth
    init<A: ExactScalarAdmission & ~Copyable>(caller: UnsafeMutablePointer<A>, depth: ExactScalarDepth) {
        self.depth = depth
        check = { () throws in try caller.pointee.checkpoint() }
        work = { (n: Int) throws in try caller.pointee.consumeWork(n) }
        storage = { (n: Int) throws in try caller.pointee.retainStorage(bytes: n) }
        depths = { (v: Int, c: Int) throws in try caller.pointee.admitDepth(value: v, coefficient: c) }
    }
    func forwarding(_ body: () throws -> Void) throws(ExactScalarFailure) {
        do { try body() }
        catch let failure as ExactScalarFailure { throw failure }
        catch { throw .admissionRejected(error) }
    }
    func checkpoint() throws(ExactScalarFailure) { try forwarding(check) }
    func consumeWork(_ units: Int) throws(ExactScalarFailure) { try forwarding { try work(units) }; try checkpoint() }
    func retainStorage(bytes: Int) throws(ExactScalarFailure) { try forwarding { try storage(bytes) }; try checkpoint() }
    func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try forwarding { try depths(value, coefficient) }
        depth = try .init(value: max(value, depth.value), coefficient: max(coefficient, depth.coefficient))
        try checkpoint()
    }
}
