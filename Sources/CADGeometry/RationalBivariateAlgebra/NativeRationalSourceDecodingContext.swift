#if !hasFeature(Embedded)
import Foundation

/// Decoder root policy and common cumulative budget shared by every nested source.
public final class NativeRationalSourceDecodingContext: Sendable {
    public static let key = CodingUserInfoKey(rawValue: "swift-cad.original-rational-source-allowance")!
    public let budget: OriginalQueryBudget
    public let contribution: OriginalQueryContributionHandle
    private let rootLimits: OriginalQueryExecutionLimits
    private let sourceContributions: [OriginalQueryContributionHandle]
    private let decodingContributions: [OriginalQueryContributionHandle]
    public let limits: OriginalQueryExecutionLimits
    public let maximumWork: Int
    public let maximumCells: Int
    /// The decoder entry preserves its canonical UInt32-word storage limit.
    public let maximumStorage: Int
    public let maximumDepth: Int

    public convenience init(maximumWork: Int, maximumCells: Int, maximumStorage: Int, maximumDepth: Int,
        operationCheck: @escaping @Sendable () throws -> Void,
        budget originalBudget: OriginalQueryBudget? = nil) throws {
        guard maximumWork >= 0, maximumCells >= 0, maximumStorage >= 0, maximumDepth >= 0 else {
            throw ExactScalarFailure.invalidSource
        }
        let bytes = try exactScalarPayloadBytes(count: maximumStorage, of: UInt32.self)
        let budget = try originalBudget ?? OriginalQueryBudget(workLimit: maximumWork, storageByteLimit: bytes,
            cellLimit: maximumCells, cellVisitWorkUnits: 0, cellVisitRecords: 0,
            allocationPolicy: .none, checkpoint: operationCheck)
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumDepth, maximumCoefficientDepth: maximumDepth,
                maximumCells: maximumCells))
        try self.init(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth, using: &execution)
    }

    public init(maximumWork: Int, maximumCells: Int, maximumStorage: Int, maximumDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
        guard maximumWork >= 0, maximumCells >= 0, maximumStorage >= 0, maximumDepth >= 0 else {
            throw ExactScalarFailure.invalidSource
        }
        let bytes = try exactScalarPayloadBytes(count: maximumStorage, of: UInt32.self)
        budget = execution.budget
        rootLimits = execution.effectiveLimits
        limits = try .init(maximumValueDepth: maximumDepth, maximumCoefficientDepth: maximumDepth,
            maximumCells: maximumCells)
        sourceContributions = try execution.retainActiveContributionHandles()
        contribution = try execution.makeContributionHandle(workLimit: maximumWork, storageByteLimit: bytes,
            cellLimit: maximumCells, storageByteQuantum: 4, allocationPolicy: .none, executionLimits: limits)
        decodingContributions = try execution.withContributionScope(contribution) { execution in
            try execution.retainActiveContributionHandles()
        }
        self.maximumWork = maximumWork; self.maximumCells = maximumCells
        self.maximumStorage = maximumStorage; self.maximumDepth = maximumDepth
    }

    public func execution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: budget, limits: rootLimits, contributions: decodingContributions)
    }
    /// Source continuation retains all original caller groups outside the decoder word scope.
    public func sourceExecution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: budget, limits: rootLimits, contributions: sourceContributions)
    }

    /// Ordinary validating codecs may be used outside a bounded Native package.
    public static func validationExecution(from decoder: any Decoder) throws -> OriginalQueryExecution {
        guard decoder.userInfo[key] != nil else {
            return try OriginalQueryExecution.independentGeometry()
        }
        return try execution(from: decoder)
    }

    public static func execution(from decoder: any Decoder) throws -> OriginalQueryExecution {
        guard let installed = decoder.userInfo[key] else {
            throw NativeRationalSourceDecodingError.missingCallerAllowance
        }
        guard let context = installed as? NativeRationalSourceDecodingContext else {
            throw NativeRationalSourceDecodingError.invalidCallerContext
        }
        try context.budget.checkpoint()
        return try context.execution()
    }

    public func snapshot() throws -> NativeRationalSourceDecodingSnapshot {
        try budget.checkpoint()
        let observed = contribution.snapshot
        let stride = MemoryLayout<UInt32>.stride
        let quotient = observed.storageBytes / stride
        let words = quotient.addingReportingOverflow(observed.storageBytes % stride == 0 ? 0 : 1)
        guard !words.overflow else { throw ExactScalarFailure.countOverflow }
        return NativeRationalSourceDecodingSnapshot(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth, work: observed.work,
            cells: observed.cellVisits, storage: words.partialValue)
    }
}
#endif
