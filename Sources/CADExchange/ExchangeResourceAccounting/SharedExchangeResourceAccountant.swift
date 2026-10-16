import CADCore
import CADGeometry

/// The format root and all original executions share one cumulative owner.
final class SharedExchangeResourceAccountant: Sendable {
    let limits: ExchangeResourceLimits
    let format: ExchangeFileFormat
    let budget: ExchangeProcessingBudget
    let originalBudget: OriginalQueryBudget
    private let template: ExchangeResourceAccountant
    private let wireContribution: OriginalQueryContributionHandle?
    private let wireContributions: [OriginalQueryContributionHandle]

    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat,
        processingBudget: ExchangeProcessingBudget? = nil, cellVisitRecords: Int = 1,
        nativeDecodingStorage: Bool = false) throws {
        let original = try ExchangeResourceAccountant(limits: limits, format: format, processingBudget: processingBudget)
        self.limits = original.limits; self.format = original.format
        budget = original.budget; template = original
        let processing = original.budget
        originalBudget = try OriginalQueryBudget(workLimit: limits.maximumIterations,
            storageByteLimit: format == .swiftCAD && !nativeDecodingStorage ? nil : limits.maximumBytes,
            sourceTextByteLimit: format == .swiftCAD ? limits.maximumBytes : nil, recordLimit: limits.maximumEntities,
            cellVisitRecords: cellVisitRecords, checkpoint: { try processing.check(format: format) })
        wireContribution = format == .swiftCAD
            ? try originalBudget.makeContributionHandle(storageByteLimit: limits.maximumBytes, allocationPolicy: .none) : nil
        if let wireContribution {
            try originalBudget.retainStorage(bytes: MemoryLayout<OriginalQueryContributionHandle>.stride)
            wireContributions = [wireContribution]
        } else { wireContributions = [] }
    }
    var entityCount: Int { originalBudget.snapshot.records }
    var iterationCount: Int { originalBudget.snapshot.work }
    var byteCount: Int { wireContribution?.snapshot.storageBytes ?? originalBudget.snapshot.storageBytes }
    func snapshot() -> ExchangeResourceAccountant { .init(snapshot: originalBudget.snapshot, template: template, byteCount: byteCount) }
    func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try checkTime()
        guard entities >= 0 else { throw exchangeResourceLimitError(format: format, detail: "entity accounting received a negative value.") }
        guard work >= 0 else { throw exchangeResourceLimitError(format: format, detail: "iteration accounting received a negative value.") }
        guard bytes >= 0 else { throw exchangeResourceLimitError(format: format, detail: "byte accounting received a negative value.") }
        do { try originalBudget.chargeSource(records: entities, work: work, storageBytes: bytes, contributions: wireContributions) }
        catch { throw failure(error) }
    }
    func recordEntities(_ count: Int = 1) throws { try charge(entities: count) }
    func recordIterations(_ count: Int = 1) throws { try charge(work: count) }
    func recordBytes(_ count: Int, label: String = "processed") throws {
        try checkTime()
        guard count >= 0 else { throw exchangeResourceLimitError(format: format, detail: "byte accounting received a negative value.") }
        do { try originalBudget.chargeSource(storageBytes: count, contributions: wireContributions) }
        catch { throw failure(error, byteLabel: label) }
    }
    func validateInputByteCount(_ count: Int) throws {
        try checkTime()
        guard count >= 0, count <= limits.maximumBytes else {
            throw exchangeResourceLimitError(format: format, detail: "input exceeds the configured byte limit.")
        }
    }
    func validateNestingDepth(_ depth: Int) throws {
        guard depth >= 0, depth <= limits.maximumNesting else {
            throw exchangeResourceLimitError(format: format, detail: "input exceeds the configured nesting limit.")
        }
    }
    func checkTime() throws { try budget.check(format: format) }
    func failure(_ error: any Error, byteLabel: String = "processed") -> any Error {
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .cancelled: return CancellationError()
            case .admissionRejected(let cause): return failure(cause, byteLabel: byteLabel)
            default: return error
            }
        }
        guard let original = error as? OriginalQueryFailure else { return error }
        if let resource = original.context.resource, case .known(let used) = resource.used,
            case .known(let requested) = resource.requested {
            let overflow = used.addingReportingOverflow(requested).overflow
            let label: String
            let detail: String
            switch resource.axis {
            case .sourceRecords: label = "entity"; detail = "processing exceeds the configured entity limit."
            case .work: label = "iteration"; detail = "processing exceeds the configured iteration limit."
            case .storageBytes: label = "byte"; detail = "\(byteLabel) bytes exceed the configured byte limit."
            default: return error
            }
            return exchangeResourceLimitError(format: format,
                detail: overflow ? "\(label) accounting exceeds the platform integer range." : detail)
        }
        return failure(original.originalError, byteLabel: byteLabel)
    }
}
