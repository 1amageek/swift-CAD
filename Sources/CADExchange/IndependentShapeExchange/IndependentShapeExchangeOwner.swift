import CADCore
import CADGeometry
import CADIR

/// The original exchange invocation owns cumulative source, work and byte admission.
public final class IndependentShapeExchangeOwner: Sendable {
    public let format: ExchangeFileFormat
    public let limits: ExchangeResourceLimits
    public let originalBudget: OriginalQueryBudget
    private let processing: ExchangeProcessingBudget
    public var consumedEntities: Int { originalBudget.snapshot.records }
    public var consumedWork: Int { originalBudget.snapshot.work }
    public var consumedBytes: Int { originalBudget.snapshot.storageBytes }
    public var consumedSourceTextBytes: Int { originalBudget.snapshot.sourceTextBytes }

    public convenience init(limits: ExchangeResourceLimits, format: ExchangeFileFormat = .step,
        consumedEntities: Int = 0, consumedWork: Int = 0, consumedBytes: Int = 0) throws {
        try self.init(limits: limits, format: format,
            processing: ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration),
            consumedEntities: consumedEntities, consumedWork: consumedWork, consumedBytes: consumedBytes)
    }
    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat = .step,
        processing: ExchangeProcessingBudget, consumedEntities: Int, consumedWork: Int, consumedBytes: Int) throws {
        try limits.validate()
        guard consumedEntities >= 0, consumedEntities <= limits.maximumEntities,
            consumedWork >= 0, consumedWork <= limits.maximumIterations,
            consumedBytes >= 0, consumedBytes <= limits.maximumBytes else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Invalid parent-paid exchange prefix.")
        }
        self.format = format; self.limits = limits; self.processing = processing
        originalBudget = try OriginalQueryBudget(workLimit: limits.maximumIterations,
            storageByteLimit: limits.maximumBytes, sourceTextByteLimit: limits.maximumBytes, recordLimit: limits.maximumEntities,
            cellVisitRecords: 1, checkpoint: { try processing.check(format: format) })
        try charge(entities: consumedEntities, work: consumedWork, bytes: consumedBytes)
    }
    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat,
        processing: ExchangeProcessingBudget, originalBudget: OriginalQueryBudget) throws {
        try limits.validate()
        self.format = format; self.limits = limits; self.processing = processing
        self.originalBudget = originalBudget
    }
    /// Seeds already-paid root input before an execution exists. Processing uses the direct overload.
    public func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try check()
        do {
            try originalBudget.chargeSource(records: entities, work: work, storageBytes: bytes)
        } catch { throw Self.failure(error) }
    }
    public func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0,
        using execution: inout OriginalQueryExecution) throws {
        try requireExecution(execution)
        try check()
        do {
            try execution.chargeSource(records: entities, work: work, storageBytes: bytes)
        } catch { throw Self.failure(error) }
    }
    public func check() throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try processing.check(format: format)
    }
    public func execution() throws -> OriginalQueryExecution {
        try check()
        return try OriginalQueryExecution(budget: originalBudget,
            limits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumNesting,
                maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
                maximumSpans: limits.maximumEntities))
    }
    func requireExecution(_ execution: borrowing OriginalQueryExecution) throws {
        guard execution.budget === originalBudget else {
            throw IndependentShapeExchangeError.invalidAssociation(
                "Independent graph processing requires its actual exchange owner.")
        }
    }
    /// Validation consumes this invocation directly, including its scoped source policy.
    func validateDocument(_ document: CADDocument, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        guard execution.budget === originalBudget else {
            throw IndependentShapeExchangeError.invalidAssociation("Document validation requires its actual exchange owner.")
        }
        let records = limits.maximumEntities - consumedEntities
        let work = limits.maximumIterations - consumedWork
        guard records > 0, work > 0 else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("No document source-validation allowance.")
        }
        do {
            _ = try document.validate(tolerance: tolerance,
                independentShapeLimits: .init(maximumRecords: records,
                    maximumTextBytes: limits.maximumBytes - consumedSourceTextBytes,
                    maximumDepth: limits.maximumNesting, maximumWork: work,
                    maximumCurveSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth), using: &execution)
        } catch { throw Self.failure(error) }
    }
    static func failure(_ error: any Error) -> any Error {
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .cancelled: return CancellationError()
            case .admissionRejected(let cause): return failure(cause)
            case .countOverflow:
                return IndependentShapeExchangeError.resourceLimitExceeded("Independent exchange count overflow.")
            default: return error
            }
        }
        guard let original = error as? OriginalQueryFailure else { return error }
        if let resource = original.context.resource, case .known = resource.used {
            switch resource.axis {
            case .work, .storageBytes, .sourceRecords, .cells:
                return IndependentShapeExchangeError.resourceLimitExceeded("Independent exchange cumulative caller ceiling.")
            default: break
            }
        }
        return failure(original.originalError)
    }
}
