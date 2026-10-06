import CADCore

/// Immutable callbacks borrowed from one complete conversion invocation.
public struct GeometryConversionAdmission: Sendable {
    private final class InvocationIdentity: Sendable {}
    private let invocationIdentity: InvocationIdentity
    public let maximumSpanCount: Int
    public let maximumSubdivisionDepth: Int
    public let remainingSourceDepth: Int
    public let maximumAlgebraicDepth: Int?
    private let consumeWorkUnits: @Sendable (Int) throws -> Void
    private let consumeBytes: @Sendable (Int) throws -> Void

    public init(maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void,
        maximumAlgebraicDepth: Int? = nil) throws {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Conversion admission requires positive spans and nonnegative original depths.")
        }
        invocationIdentity = InvocationIdentity()
        self.maximumSpanCount = maximumSpanCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        consumeWorkUnits = consumeWork; consumeBytes = consumeStorage
    }

    /// Copies borrow the same invocation; independently created admissions do not.
    public func belongsToSameInvocation(as other: Self) -> Bool {
        invocationIdentity === other.invocationIdentity
    }

    public func chargeWork(_ units: Int = 1) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard units >= 0 else {
            throw GeometryConversionError.invalidInput("Conversion work units must be nonnegative.")
        }
        try consumeWorkUnits(units)
    }

    public func chargeStorage(bytes: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard bytes >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Conversion byte accounting overflowed.")
        }
        try consumeBytes(bytes)
    }

    public func visit(depth: Int) throws {
        guard depth >= 0, depth <= maximumSubdivisionDepth else {
            throw GeometryConversionError.resourceLimitExceeded("Conversion exhausted the caller subdivision depth.")
        }
        try chargeWork()
    }
}
