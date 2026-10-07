/// A stack-borrowed handle; copies share the invocation's ledger and depth state.
/// Pointers never escape ExactScalarNumericAccess.withAdmission, cross a Sendable
/// boundary, allocate memory, change binding, or use unchecked offsets.
struct ExactScalarRationalAdmission<A: ExactScalarAdmission & ~Copyable>: RationalAlgebraAdmitting {
    let ledger: UnsafeMutablePointer<A>
    let reached: UnsafeMutablePointer<ExactScalarDepth>
    let original: ExactScalarDepth
    let inherited: ExactScalarDepth
    let maximum: ExactScalarDepth

    mutating func consumeExactWork(_ count: Int) throws {
        try ledger.pointee.checkpoint()
        try ledger.pointee.consumeWork(count)
        try ledger.pointee.checkpoint()
    }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = try exactScalarCount(count, MemoryLayout<UInt32>.stride, multiply: true)
        try ledger.pointee.checkpoint()
        try ledger.pointee.retainStorage(bytes: bytes)
        try ledger.pointee.checkpoint()
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0 else { throw ExactScalarFailure.countOverflow }
        let mapped = try exactScalarCount(inherited.value, max(0, depth - original.value))
        guard mapped <= maximum.value else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        try ledger.pointee.admitDepth(value: mapped, coefficient: reached.pointee.coefficient)
        reached.pointee = .init(uncheckedValue: max(reached.pointee.value, mapped), coefficient: reached.pointee.coefficient)
        try ledger.pointee.checkpoint()
    }
    mutating func visitCoefficientCell(depth: Int) throws {
        guard depth >= 0 else { throw ExactScalarFailure.countOverflow }
        let mapped = try exactScalarCount(inherited.coefficient, max(0, depth - original.coefficient))
        guard mapped <= maximum.coefficient else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        try ledger.pointee.admitDepth(value: reached.pointee.value, coefficient: mapped)
        reached.pointee = .init(uncheckedValue: reached.pointee.value, coefficient: max(reached.pointee.coefficient, mapped))
        try ledger.pointee.checkpoint()
    }
}
