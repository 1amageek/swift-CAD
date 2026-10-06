/// Every copy borrows the same composing admission owners; no private quota exists.
public struct OriginalRelationUsage: RationalAlgebraAdmitting, Sendable {
    private let work: @Sendable (Int) throws -> Void
    private let storage: @Sendable (Int) throws -> Void
    private let cell: @Sendable (Int) throws -> Void
    private let coefficientCell: @Sendable (Int) throws -> Void

    /// Storage counts are canonical UInt32 words, independently admitted from work.
    public init(consumeWork: @escaping @Sendable (Int) throws -> Void,
        retainStorage: @escaping @Sendable (Int) throws -> Void,
        visitCell: @escaping @Sendable (Int) throws -> Void,
        visitCoefficientCell: @escaping @Sendable (Int) throws -> Void) {
        work = consumeWork; storage = retainStorage; cell = visitCell; coefficientCell = visitCoefficientCell
    }
    public mutating func consumeExactWork(_ count: Int) throws {
        try validate(count); try work(count)
    }
    public mutating func retainExactStorage(_ count: Int) throws {
        try validate(count); try storage(count)
    }
    public mutating func visitExactCell(depth: Int) throws {
        try validate(depth); try cell(depth)
    }
    public mutating func visitCoefficientCell(depth: Int) throws {
        try validate(depth); try coefficientCell(depth)
    }
    private func validate(_ count: Int) throws {
        try Task.checkCancellation()
        guard count >= 0 else { throw rationalAlgebraFailure("Original relation admission cannot receive a negative count.") }
    }
}
