import CADCore
import Synchronization

/// One cumulative caller owner shared by exclusive query executions.
public final class OriginalQueryBudget: Sendable {
    private struct Contribution: Sendable {
        let workLimit: Int?
        let storageByteLimit: Int?
        let sourceTextByteLimit: Int?
        let cellLimit: Int?
        let recordLimit: Int?
        let storageByteQuantum: Int
        var work = 0
        var storageBytes = 0
        var sourceTextBytes = 0
        var cells = 0
        var records = 0
    }
    private struct State: Sendable {
        var sourceTextBytes = 0
        var work = 0
        var storageBytes = 0
        var cells = 0
        var records = 0
        var contributions: [Contribution] = []
    }
    private struct Rejection {
        let axis: OriginalQueryResourceAxis
        let used: Int
        let limit: Int?
        let requested: Int
        let overflow: Bool
    }
    public let workLimit: Int?
    public let storageByteLimit: Int?
    public let sourceTextByteLimit: Int?
    public let cellLimit: Int?
    public let recordLimit: Int?
    public let cellVisitWorkUnits: Int
    public let cellVisitRecords: Int
    public let allocationPolicy: OriginalQueryAllocationPolicy
    private let state = Mutex(State())
    private let workCallback: (@Sendable (Int) throws -> Void)?
    private let storageCallback: (@Sendable (Int) throws -> Void)?
    private let callerCheckpoint: (@Sendable () throws -> Void)?

    public init(workLimit: Int? = nil, storageByteLimit: Int? = nil,
        sourceTextByteLimit: Int? = nil,
        cellLimit: Int? = nil, recordLimit: Int? = nil,
        cellVisitWorkUnits: Int = 1, cellVisitRecords: Int = 0,
        allocationPolicy: OriginalQueryAllocationPolicy = .none,
        consumeWorkUnits: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorageBytes: (@Sendable (Int) throws -> Void)? = nil,
        checkpoint: (@Sendable () throws -> Void)? = nil) throws(ExactScalarFailure) {
        guard workLimit.map({ $0 >= 0 }) ?? true,
            storageByteLimit.map({ $0 >= 0 }) ?? true,
            sourceTextByteLimit.map({ $0 >= 0 }) ?? true,
            cellLimit.map({ $0 >= 0 }) ?? true,
            recordLimit.map({ $0 >= 0 }) ?? true,
            cellVisitWorkUnits >= 0, cellVisitRecords >= 0 else { throw .invalidSource }
        self.workLimit = workLimit; self.storageByteLimit = storageByteLimit
        self.sourceTextByteLimit = sourceTextByteLimit
        self.cellLimit = cellLimit; self.recordLimit = recordLimit
        self.cellVisitWorkUnits = cellVisitWorkUnits; self.cellVisitRecords = cellVisitRecords
        self.allocationPolicy = allocationPolicy
        workCallback = consumeWorkUnits; storageCallback = consumeStorageBytes
        callerCheckpoint = checkpoint
    }
    public var availableWork: Int { max(0, (workLimit ?? Int.max) - snapshot.work) }
    public var snapshot: OriginalQueryBudgetSnapshot {
        state.withLock { .init(work: $0.work, storageBytes: $0.storageBytes, cellVisits: $0.cells, records: $0.records, sourceTextBytes: $0.sourceTextBytes) }
    }
    public func checkpoint(context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        guard !Task<Never, Never>.isCancelled else { throw .cancelled }
        do { try callerCheckpoint?() }
        catch { throw rejection(error, context: context) }
        guard !Task<Never, Never>.isCancelled else { throw .cancelled }
    }
    public func chargeSource(records: Int = 0, work: Int = 0, storageBytes: Int = 0,
        contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: work, bytes: storageBytes, cells: 0, records: records, contribution: contribution, context: context)
    }
    public func chargeSource(records: Int = 0, work: Int = 0, storageBytes: Int = 0,
        contributions: borrowing [OriginalQueryContributionHandle],
        context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: work, bytes: storageBytes, cells: 0, records: records,
            contributions: contributions, context: context)
    }
    /// Retained UTF-8 wire bytes, independently bounded from numeric allocation metadata.
    public func chargeSourceText(records: Int = 0, work: Int = 0, storageBytes: Int,
        contribution: OriginalQueryContributionHandle? = nil,
        context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: work, bytes: storageBytes, cells: 0, records: records, sourceTextBytes: storageBytes,
            contribution: contribution, context: context)
    }
    public func chargeSourceText(records: Int = 0, work: Int = 0, storageBytes: Int,
        contributions: borrowing [OriginalQueryContributionHandle],
        context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: work, bytes: storageBytes, cells: 0, records: records, sourceTextBytes: storageBytes,
            contributions: contributions, context: context)
    }
    public func consumeWork(_ units: Int, contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: units, bytes: 0, cells: 0, records: 0, contribution: contribution, context: context)
    }
    public func consumeRecords(_ count: Int, contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: 0, bytes: 0, cells: 0, records: count, contribution: contribution, context: context)
    }
    public func consumeCells(_ count: Int = 1, contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try checkpoint(context: context)
        let work = try exactScalarCount(count, cellVisitWorkUnits, multiply: true)
        let records = try exactScalarCount(count, cellVisitRecords, multiply: true)
        try debit(work: work, bytes: 0, cells: count, records: records, contribution: contribution, context: context)
    }
    public func allocationWorkUnits(bytes: Int, policy: OriginalQueryAllocationPolicy? = nil) throws(ExactScalarFailure) -> Int {
        guard bytes >= 0 else { throw .countOverflow }
        switch policy ?? allocationPolicy {
        case .none: return 0
        case .uint32Words, .uint32WordWork: return try wordCount(bytes: bytes)
        case .bytes: return bytes
        }
    }
    public func retainStorage(bytes: Int, policy: OriginalQueryAllocationPolicy? = nil, contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try checkpoint(context: context)
        let selectedPolicy = policy ?? contribution?.allocationPolicy ?? allocationPolicy
        let work = try allocationWorkUnits(bytes: bytes, policy: selectedPolicy)
        let records: Int
        switch selectedPolicy {
        case .uint32Words: records = work
        case .none, .bytes, .uint32WordWork: records = 0
        }
        try debit(work: work, bytes: bytes, cells: 0, records: records, contribution: contribution, context: context)
    }
    /// Source-owned text/authoring bytes are not numeric allocation events.
    public func retainSourceStorage(bytes: Int, contribution: OriginalQueryContributionHandle? = nil, context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try debit(work: 0, bytes: bytes, cells: 0, records: 0, contribution: contribution, context: context)
    }
    func admitting(work: Int, bytes: Int, cells: Int, records: Int, sourceTextBytes: Int = 0,
        contributions: borrowing [OriginalQueryContributionHandle] = [],
        context: OriginalQueryFailureContext, _ admitted: () -> Void) throws(ExactScalarFailure) {
        try debit(work: work, bytes: bytes, cells: cells, records: records, sourceTextBytes: sourceTextBytes, contributions: contributions, context: context, admitted: admitted)
    }
    private func wordCount(bytes: Int) throws(ExactScalarFailure) -> Int {
        let stride = MemoryLayout<UInt32>.stride
        let rounded = (bytes / stride).addingReportingOverflow(bytes % stride == 0 ? 0 : 1)
        guard !rounded.overflow else { throw .countOverflow }
        return rounded.partialValue
    }
    private func debit(work: Int, bytes: Int, cells: Int, records: Int, sourceTextBytes: Int = 0,
        contribution: OriginalQueryContributionHandle? = nil,
        contributions: borrowing [OriginalQueryContributionHandle] = [],
        context: OriginalQueryFailureContext, admitted: () -> Void = {}) throws(ExactScalarFailure) {
        try checkpoint(context: context)
        guard work >= 0, bytes >= 0, cells >= 0, records >= 0, sourceTextBytes >= 0, sourceTextBytes <= bytes else { throw .countOverflow }
        if let contribution { guard contribution.budget === self else { throw .invalidEvidence } }
        for index in contributions.indices { guard contributions[index].budget === self else { throw .invalidEvidence } }
        let denied = state.withLock { state -> Rejection? in
            if let failure = checked(axis: .sourceTextBytes, used: state.sourceTextBytes, requested: sourceTextBytes, limit: sourceTextByteLimit) { return failure }
            if let failure = checked(axis: .work, used: state.work, requested: work, limit: workLimit) { return failure }
            if let failure = checked(axis: .storageBytes, used: state.storageBytes, requested: bytes, limit: storageByteLimit) { return failure }
            if let failure = checked(axis: .cells, used: state.cells, requested: cells, limit: cellLimit) { return failure }
            if let failure = checked(axis: .sourceRecords, used: state.records, requested: records, limit: recordLimit) { return failure }
            if let contribution, let failure = checkedContribution(state.contributions[contribution.id],
                work: work, bytes: bytes, cells: cells, records: records, sourceTextBytes: sourceTextBytes) { return failure }
            for index in contributions.indices {
                let handle = contributions[index]
                if contribution?.id == handle.id || duplicate(handle, before: index, in: contributions) { continue }
                if let failure = checkedContribution(state.contributions[handle.id],
                    work: work, bytes: bytes, cells: cells, records: records, sourceTextBytes: sourceTextBytes) { return failure }
            }
            state.work += work; state.storageBytes += bytes; state.cells += cells; state.records += records
            state.sourceTextBytes += sourceTextBytes
            if let contribution {
                state.contributions[contribution.id].work += work
                let attributed = attributedBytes(bytes, quantum: state.contributions[contribution.id].storageByteQuantum).partialValue
                state.contributions[contribution.id].storageBytes += attributed
                state.contributions[contribution.id].cells += cells
                state.contributions[contribution.id].records += records
                state.contributions[contribution.id].sourceTextBytes += sourceTextBytes
            }
            for index in contributions.indices {
                let handle = contributions[index]
                if contribution?.id == handle.id || duplicate(handle, before: index, in: contributions) { continue }
                state.contributions[handle.id].work += work
                let attributed = attributedBytes(bytes, quantum: state.contributions[handle.id].storageByteQuantum).partialValue
                state.contributions[handle.id].storageBytes += attributed
                state.contributions[handle.id].cells += cells
                state.contributions[handle.id].records += records
                state.contributions[handle.id].sourceTextBytes += sourceTextBytes
            }
            return nil
        }
        if let denied { throw reject(denied, context: context) }
        admitted()
        if work > 0 {
            do { try workCallback?(work) }
            catch { throw opaque(error, axis: .work, requested: work, context: context) }
        }
        if bytes > 0 {
            do { try storageCallback?(bytes) }
            catch { throw opaque(error, axis: .storageBytes, requested: bytes, context: context) }
        }
        try checkpoint(context: context)
    }
    private func duplicate(_ handle: OriginalQueryContributionHandle, before index: Int,
        in handles: borrowing [OriginalQueryContributionHandle]) -> Bool {
        for prior in 0..<index where handles[prior].id == handle.id { return true }
        return false
    }
    private func attributedBytes(_ bytes: Int, quantum: Int) -> (partialValue: Int, overflow: Bool) {
        let units = bytes / quantum + (bytes % quantum == 0 ? 0 : 1)
        return units.multipliedReportingOverflow(by: quantum)
    }
    private func checkedContribution(_ group: Contribution, work: Int, bytes: Int, cells: Int,
        records: Int, sourceTextBytes: Int = 0) -> Rejection? {
        let rounded = attributedBytes(bytes, quantum: group.storageByteQuantum)
        if rounded.overflow {
            return .init(axis: .countOverflow, used: group.storageBytes, limit: group.storageByteLimit, requested: bytes, overflow: true)
        }
        return checked(axis: .sourceTextBytes, used: group.sourceTextBytes,
                requested: sourceTextBytes, limit: group.sourceTextByteLimit)
            ?? checked(axis: .work, used: group.work, requested: work, limit: group.workLimit)
            ?? checked(axis: .storageBytes, used: group.storageBytes, requested: rounded.partialValue, limit: group.storageByteLimit)
            ?? checked(axis: .cells, used: group.cells, requested: cells, limit: group.cellLimit)
            ?? checked(axis: .sourceRecords, used: group.records, requested: records, limit: group.recordLimit)
    }
    func contributionSnapshot(_ handle: OriginalQueryContributionHandle) -> OriginalQueryBudgetSnapshot {
        state.withLock { state in
            let group = state.contributions[handle.id]
            return .init(work: group.work, storageBytes: group.storageBytes, cellVisits: group.cells,
                records: group.records, sourceTextBytes: group.sourceTextBytes)
        }
    }
    public func makeContributionHandle(workLimit: Int? = nil, storageByteLimit: Int? = nil,
        sourceTextByteLimit: Int? = nil, cellLimit: Int? = nil, recordLimit: Int? = nil, storageByteQuantum: Int = 1,
        allocationPolicy policy: OriginalQueryAllocationPolicy = .none,
        executionLimits: OriginalQueryExecutionLimits? = nil,
        context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) -> OriginalQueryContributionHandle {
        try issuingContributionHandle(workLimit: workLimit, storageByteLimit: storageByteLimit,
            sourceTextByteLimit: sourceTextByteLimit, cellLimit: cellLimit, recordLimit: recordLimit, storageByteQuantum: storageByteQuantum, allocationPolicy: policy,
            executionLimits: executionLimits, metadataPolicy: allocationPolicy, contributions: [],
            context: context, preflight: { _, _, _ in nil }, admitted: { _, _, _ in })
    }
    func issuingContributionHandle(workLimit: Int?, storageByteLimit: Int?, sourceTextByteLimit: Int?,
        cellLimit: Int?, recordLimit: Int?,
        storageByteQuantum: Int, allocationPolicy policy: OriginalQueryAllocationPolicy, executionLimits: OriginalQueryExecutionLimits?,
        metadataPolicy: OriginalQueryAllocationPolicy, contributions: borrowing [OriginalQueryContributionHandle],
        context: OriginalQueryFailureContext, preflight: (Int, Int, Int) -> ExactScalarFailure?,
        admitted: (Int, Int, Int) -> Void) throws(ExactScalarFailure) -> OriginalQueryContributionHandle {
        try checkpoint(context: context)
        guard workLimit.map({ $0 >= 0 }) ?? true, storageByteLimit.map({ $0 >= 0 }) ?? true,
            cellLimit.map({ $0 >= 0 }) ?? true, recordLimit.map({ $0 >= 0 }) ?? true,
            sourceTextByteLimit.map({ $0 >= 0 }) ?? true, storageByteQuantum > 0 else { throw .invalidSource }
        for index in contributions.indices { guard contributions[index].budget === self else { throw .invalidEvidence } }
        enum Creation {
            case created(Int, Int, Int, Int)
            case rejected(Rejection)
            case localFailure(ExactScalarFailure)
            case overflow
        }
        let creation = state.withLock { state -> Creation in
            var bytes = 0, capacity = state.contributions.capacity
            if state.contributions.count == capacity {
                let doubled = capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { return .overflow }
                capacity = max(1, doubled.partialValue)
                let payload = capacity.multipliedReportingOverflow(by: MemoryLayout<Contribution>.stride)
                guard !payload.overflow else { return .overflow }
                bytes = payload.partialValue
            }
            let work: Int
            switch metadataPolicy {
            case .none: work = 0
            case .bytes: work = bytes
            case .uint32Words, .uint32WordWork: work = bytes / 4 + (bytes % 4 == 0 ? 0 : 1)
            }
            let records: Int
            switch metadataPolicy { case .uint32Words: records = work; case .none, .bytes, .uint32WordWork: records = 0 }
            if let failure = checked(axis: .work, used: state.work, requested: work, limit: self.workLimit) { return .rejected(failure) }
            if let failure = checked(axis: .storageBytes, used: state.storageBytes, requested: bytes, limit: self.storageByteLimit) { return .rejected(failure) }
            if let failure = checked(axis: .sourceRecords, used: state.records, requested: records, limit: self.recordLimit) { return .rejected(failure) }
            guard state.contributions.count < Int.max else { return .overflow }
            for index in contributions.indices {
                let handle = contributions[index]
                if duplicate(handle, before: index, in: contributions) { continue }
                if let failure = checkedContribution(state.contributions[handle.id],
                    work: work, bytes: bytes, cells: 0, records: records) { return .rejected(failure) }
            }
            if let failure = preflight(work, bytes, records) { return .localFailure(failure) }
            state.work += work; state.storageBytes += bytes; state.records += records
            for index in contributions.indices {
                let handle = contributions[index]
                if duplicate(handle, before: index, in: contributions) { continue }
                state.contributions[handle.id].work += work
                let attributed = attributedBytes(bytes, quantum: state.contributions[handle.id].storageByteQuantum).partialValue
                state.contributions[handle.id].storageBytes += attributed
                state.contributions[handle.id].records += records
            }
            if bytes > 0 { state.contributions.reserveCapacity(capacity) }
            let id = state.contributions.count
            state.contributions.append(.init(workLimit: workLimit, storageByteLimit: storageByteLimit,
                sourceTextByteLimit: sourceTextByteLimit, cellLimit: cellLimit, recordLimit: recordLimit, storageByteQuantum: storageByteQuantum))
            return .created(id, work, bytes, records)
        }
        switch creation {
        case .overflow: throw .countOverflow
        case .rejected(let denied): throw reject(denied, context: context)
        case .localFailure(let failure): throw failure
        case .created(let id, let work, let bytes, let records):
            admitted(work, bytes, records)
            if work > 0 {
                do { try workCallback?(work) } catch { throw opaque(error, axis: .work, requested: work, context: context) }
            }
            if bytes > 0 {
                do { try storageCallback?(bytes) } catch { throw opaque(error, axis: .storageBytes, requested: bytes, context: context) }
            }
            try checkpoint(context: context)
            return .init(budget: self, id: id, storageByteQuantum: storageByteQuantum, workLimit: workLimit,
                sourceTextByteLimit: sourceTextByteLimit, allocationPolicy: policy, executionLimits: executionLimits)
        }
    }
    private func checked(axis: OriginalQueryResourceAxis, used: Int, requested: Int, limit: Int?) -> Rejection? {
        let next = used.addingReportingOverflow(requested)
        if next.overflow { return .init(axis: axis, used: used, limit: limit, requested: requested, overflow: true) }
        if let limit, next.partialValue > limit { return .init(axis: axis, used: used, limit: limit, requested: requested, overflow: false) }
        return nil
    }
    private func reject(_ denied: Rejection, context: OriginalQueryFailureContext) -> ExactScalarFailure {
        let cause: any Error
        if denied.overflow { cause = ExactScalarFailure.countOverflow }
        else if denied.axis == .work { cause = ExactScalarFailure.resourceLimit(.work) }
        else if denied.axis == .storageBytes { cause = ExactScalarFailure.resourceLimit(.storage) }
        else {
            cause = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original query exhausted its cumulative source admission.")
        }
        return rejection(cause, context: context.recording(resource: .init(axis: denied.axis,
            used: .known(denied.used), limit: denied.limit.map { .known($0) } ?? .unlimited,
            requested: .known(denied.requested))))
    }
    private func opaque(_ error: any Error, axis: OriginalQueryResourceAxis, requested: Int,
        context: OriginalQueryFailureContext) -> ExactScalarFailure {
        rejection(error, context: context.recording(resource: .init(axis: axis,
            used: .unknown(.opaqueCallback), limit: .unknown(.opaqueCallback), requested: .known(requested))))
    }
    private func rejection(_ error: any Error, context: OriginalQueryFailureContext) -> ExactScalarFailure {
        if error is CancellationError { return .cancelled }
        if let scalar = error as? ExactScalarFailure, case .cancelled = scalar { return .cancelled }
        return .admissionRejected(OriginalQueryFailure.published(error, context: context, tolerance: nil))
    }
}
