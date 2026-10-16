import CADCore

/// Direct admission with a shared cumulative owner and exclusive proof/policy state.
public struct OriginalQueryExecution: ~Copyable, ExactScalarAdmission, NumericWorkAdmission, Sendable {
    private struct ConversionScope: Sendable {
        let ordinal: Int
        let maximumWork: Int
        let maximumScalars: Int
        let maximumBoxes: Int
        var work = 0
        var scalars = 0
        var boxes = 0
    }
    private struct AllocationScope: Sendable {
        let ordinal: Int
        let policy: OriginalQueryAllocationPolicy
        let maximumWork: Int?
        let maximumRecords: Int?
        let maximumBytes: Int?
        let sourceTextByteLimit: Int?
        let maxCombinedUnits: Int?
        let cellVisitWorkUnits: Int?
        let cellVisitRecords: Int?
        var work = 0
        var records = 0
        var bytes = 0
        var sourceTextBytes = 0
        var combinedUnits = 0
    }
    private struct PreparationScope: Sendable {
        let ordinal: Int
        let scalar: ExactScalarProofScopeToken
        let sourceOrigin: Int
        var sourceDepth = 0
        var geometricDepth = 0
        var transportDepth = 0
    }
    public let budget: OriginalQueryBudget
    public let limits: OriginalQueryExecutionLimits
    public var context: OriginalQueryFailureContext
    public var proofScopes = ExactScalarProofScopes()
    public private(set) var localWork = 0
    public private(set) var localStorageBytes = 0
    public private(set) var localRecords = 0
    public private(set) var localSourceTextBytes = 0
    public private(set) var scalarSlots = 0
    public private(set) var visitedCells = 0
    public private(set) var valueDepth = 0
    public private(set) var coefficientDepth = 0
    public private(set) var geometricDepth = 0
    public private(set) var sourceDepth = 0
    public private(set) var transportDepth = 0
    private var geometricDepthOffset = 0
    private var sourceDepthOffset = 0
    private var conversionScopes: [ConversionScope] = []
    private var conversionIssuer: OriginalQueryScopeIssuer?
    private var nextConversionOrdinal = 0
    private var allocationScopes: [AllocationScope] = []
    private var allocationIssuer: OriginalQueryScopeIssuer?
    private var nextAllocationOrdinal = 0
    private var preparationScopes: [PreparationScope] = []
    private var preparationIssuer: OriginalQueryScopeIssuer?
    private var nextPreparationOrdinal = 0
    private var activeContributions: [OriginalQueryContributionHandle] = []
    private var admittedPreparations: [any AnyObject & Sendable] = []

    public init(budget: OriginalQueryBudget, limits: OriginalQueryExecutionLimits,
        context: OriginalQueryFailureContext = .unspecified) {
        self.budget = budget; self.limits = limits; self.context = context
    }
    public init(budget: OriginalQueryBudget, limits: OriginalQueryExecutionLimits,
        context: OriginalQueryFailureContext = .unspecified, contribution: OriginalQueryContributionHandle)
        throws(ExactScalarFailure) {
        self.init(budget: budget, limits: limits, context: context)
        try checkpoint()
        guard contribution.budget === budget else { throw .invalidEvidence }
        try retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalQueryContributionHandle.self))
        activeContributions.reserveCapacity(1)
        activeContributions.append(contribution)
    }
    public init(contribution: OriginalQueryContributionHandle, limits: OriginalQueryExecutionLimits,
        context: OriginalQueryFailureContext = .unspecified) throws(ExactScalarFailure) {
        try self.init(budget: contribution.budget, limits: limits, context: context, contribution: contribution)
    }
    public init(budget: OriginalQueryBudget, limits: OriginalQueryExecutionLimits,
        context: OriginalQueryFailureContext = .unspecified, contributions: [OriginalQueryContributionHandle])
        throws(ExactScalarFailure) {
        self.init(budget: budget, limits: limits, context: context)
        try checkpoint()
        for handle in contributions { guard handle.budget === budget else { throw .invalidEvidence } }
        try retainStorage(bytes: exactScalarPayloadBytes(count: contributions.count, of: OriginalQueryContributionHandle.self))
        activeContributions.reserveCapacity(contributions.count)
        for handle in contributions { activeContributions.append(handle) }
    }
    public var availableWork: Int {
        var remaining = budget.availableWork
        for handle in activeContributions { remaining = min(remaining, handle.remainingWorkUnits) }
        return remaining
    }
    public mutating func makeContributionHandle(workLimit: Int? = nil, storageByteLimit: Int? = nil,
        sourceTextByteLimit: Int? = nil, cellLimit: Int? = nil, recordLimit: Int? = nil, storageByteQuantum: Int = 1,
        allocationPolicy: OriginalQueryAllocationPolicy = .none,
        executionLimits: OriginalQueryExecutionLimits? = nil) throws(ExactScalarFailure) -> OriginalQueryContributionHandle {
        try checkpoint()
        let owner = budget, currentContext = context
        let parents = activeContributions
        let metadataPolicy = effectiveAllocationPolicy
        var combined = 0
        return try owner.issuingContributionHandle(workLimit: workLimit, storageByteLimit: storageByteLimit,
            sourceTextByteLimit: sourceTextByteLimit, cellLimit: cellLimit, recordLimit: recordLimit, storageByteQuantum: storageByteQuantum, allocationPolicy: allocationPolicy,
            executionLimits: executionLimits, metadataPolicy: metadataPolicy, contributions: parents,
            context: currentContext, preflight: { work, bytes, records in
                do throws(ExactScalarFailure) {
                    combined = try checkCombined(allocationBytes: bytes)
                    try checkWork(work); try checkAllocation(bytes: bytes, records: records); return nil
                }
                catch { return error }
            }, admitted: { work, bytes, records in
                recordWork(work); recordAllocation(bytes: bytes, records: records); recordCombined(combined)
            })
    }
    public var effectiveAllocationPolicy: OriginalQueryAllocationPolicy {
        allocationScopes.last?.policy ?? activeContributions.last?.allocationPolicy ?? budget.allocationPolicy
    }
    /// Accepted historical combined contribution of the current selected scope.
    public var allocationScopeCombinedUnits: Int? {
        guard let scope = allocationScopes.last, scope.maxCombinedUnits != nil else { return nil }
        return scope.combinedUnits
    }
    public var activeContributionCount: Int { activeContributions.count }
    /// The innermost authority; distinct outer authorities are retained separately.
    public var activeContributionHandle: OriginalQueryContributionHandle? { activeContributions.last }
    public var effectiveLimits: OriginalQueryExecutionLimits {
        var result = limits
        for handle in activeContributions {
            if let selected = handle.executionLimits { result = result.intersecting(selected) }
        }
        return result
    }
    public mutating func withContributionScope<Result>(_ handle: OriginalQueryContributionHandle,
        _ body: (inout Self) throws -> Result) throws -> Result {
        try checkpoint()
        guard handle.budget === budget else { throw ExactScalarFailure.invalidEvidence }
        if activeContributions.last?.id == handle.id { return try body(&self) }
        let previous = activeContributions.count
        if activeContributions.count == activeContributions.capacity {
            let doubled = activeContributions.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
            let capacity = max(1, doubled.partialValue)
            try retainStorage(bytes: exactScalarPayloadBytes(count: capacity, of: OriginalQueryContributionHandle.self))
            activeContributions.reserveCapacity(capacity)
        }
        activeContributions.append(handle)
        defer { activeContributions.removeLast(activeContributions.count - previous) }
        return try body(&self)
    }
    public mutating func withContributionScopes<Result>(_ handles: [OriginalQueryContributionHandle],
        _ body: (inout Self) throws -> Result) throws -> Result {
        try checkpoint()
        for handle in handles { guard handle.budget === budget else { throw ExactScalarFailure.invalidEvidence } }
        if handles.isEmpty { return try body(&self) }
        if handles.last?.id == activeContributions.last?.id,
           handles.allSatisfy({ selected in activeContributions.contains(where: { $0.id == selected.id }) }) {
            return try body(&self)
        }
        let previous = activeContributions.count
        defer { activeContributions.removeLast(activeContributions.count - previous) }
        for handle in handles {
            if activeContributions.count == activeContributions.capacity {
                let doubled = activeContributions.capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
                let capacity = max(1, doubled.partialValue)
                try retainStorage(bytes: exactScalarPayloadBytes(count: capacity, of: OriginalQueryContributionHandle.self))
                activeContributions.reserveCapacity(capacity)
            }
            activeContributions.append(handle)
        }
        return try body(&self)
    }
    public mutating func retainActiveContributionHandles() throws(ExactScalarFailure) -> [OriginalQueryContributionHandle] {
        try retainStorage(bytes: exactScalarPayloadBytes(count: activeContributions.count, of: OriginalQueryContributionHandle.self))
        var result: [OriginalQueryContributionHandle] = []; result.reserveCapacity(activeContributions.count)
        for index in activeContributions.indices {
            try consumeWork(1)
            let handle = activeContributions[index]
            result.append(handle)
        }
        return result
    }
    public mutating func checkpoint() throws(ExactScalarFailure) { try budget.checkpoint(context: context) }
    private mutating func checkWork(_ units: Int) throws(ExactScalarFailure) {
        do { try proofScopes.checkWork(units) }
        catch {
            guard let rejected = proofScopes.lastWorkRejection else { throw error }
            throw .admissionRejected(OriginalQueryFailure.published(error,
                context: context.recording(resource: .init(axis: .work, used: .known(rejected.used),
                    limit: .known(rejected.limit), requested: .known(rejected.requested))), tolerance: nil))
        }
        let next = localWork.addingReportingOverflow(units)
        guard units >= 0, !next.overflow else { throw .countOverflow }
        for scope in conversionScopes {
            try require(axis: .work, used: scope.work, requested: units, limit: scope.maximumWork)
        }
        for scope in allocationScopes {
            if let maximum = scope.maximumWork { try require(axis: .work, used: scope.work, requested: units, limit: maximum) }
        }
    }
    private mutating func recordWork(_ units: Int) {
        proofScopes.recordWork(units)
        localWork += units
        for index in conversionScopes.indices { conversionScopes[index].work += units }
        for index in allocationScopes.indices { allocationScopes[index].work += units }
    }
    private func checkCombined(explicitWork: Int = 0, allocationBytes: Int = 0,
        cells: Int = 0) throws(ExactScalarFailure) -> Int {
        guard explicitWork >= 0, allocationBytes >= 0, cells >= 0 else { throw .countOverflow }
        guard allocationScopes.contains(where: { $0.maxCombinedUnits != nil }) else { return 0 }
        let words = allocationBytes / 4 + (allocationBytes % 4 == 0 ? 0 : 1)
        let workAndWords = explicitWork.addingReportingOverflow(words)
        let aggregate = workAndWords.partialValue.addingReportingOverflow(cells)
        guard !workAndWords.overflow, !aggregate.overflow else { throw .countOverflow }
        for scope in allocationScopes {
            if let maximum = scope.maxCombinedUnits {
                try require(axis: .combinedUnits, used: scope.combinedUnits,
                    requested: aggregate.partialValue, limit: maximum)
            }
        }
        return aggregate.partialValue
    }
    private mutating func recordCombined(_ units: Int) {
        for index in allocationScopes.indices where allocationScopes[index].maxCombinedUnits != nil {
            allocationScopes[index].combinedUnits += units
        }
    }
    private func checkAllocation(bytes: Int, records: Int) throws(ExactScalarFailure) {
        let nextBytes = localStorageBytes.addingReportingOverflow(bytes)
        let nextRecords = localRecords.addingReportingOverflow(records)
        guard bytes >= 0, records >= 0, !nextBytes.overflow, !nextRecords.overflow else { throw .countOverflow }
        for scope in allocationScopes {
            if let maximum = scope.maximumBytes { try require(axis: .storageBytes, used: scope.bytes, requested: bytes, limit: maximum) }
            if let maximum = scope.maximumRecords { try require(axis: .sourceRecords, used: scope.records, requested: records, limit: maximum) }
        }
    }
    private mutating func recordAllocation(bytes: Int, records: Int) {
        localStorageBytes += bytes; localRecords += records
        for index in allocationScopes.indices {
            allocationScopes[index].bytes += bytes; allocationScopes[index].records += records
        }
    }
    public mutating func chargeSource(records: Int = 0, work: Int = 0, storageBytes: Int = 0)
        throws(ExactScalarFailure) {
        try checkpoint()
        let combined = try checkCombined(explicitWork: work)
        try checkWork(work); try checkAllocation(bytes: storageBytes, records: records)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: work, bytes: storageBytes, cells: 0, records: records, contributions: contributions, context: currentContext) {
            recordWork(work); recordAllocation(bytes: storageBytes, records: records); recordCombined(combined)
        }
    }
    public mutating func chargeSourceText(records: Int = 0, work: Int = 0, storageBytes: Int)
        throws(ExactScalarFailure) {
        try checkpoint()
        let next = localSourceTextBytes.addingReportingOverflow(storageBytes)
        guard storageBytes >= 0, !next.overflow else { throw .countOverflow }
        for scope in allocationScopes {
            if let maximum = scope.sourceTextByteLimit {
                try require(axis: .sourceTextBytes, used: scope.sourceTextBytes, requested: storageBytes, limit: maximum)
            }
        }
        let combined = try checkCombined(explicitWork: work)
        try checkWork(work); try checkAllocation(bytes: storageBytes, records: records)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: work, bytes: storageBytes, cells: 0, records: records,
            sourceTextBytes: storageBytes, contributions: contributions, context: currentContext) {
            recordWork(work); recordAllocation(bytes: storageBytes, records: records); recordCombined(combined)
            localSourceTextBytes += storageBytes
            for index in allocationScopes.indices { allocationScopes[index].sourceTextBytes += storageBytes }
        }
    }
    public mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let combined = try checkCombined(explicitWork: units)
        try checkWork(units)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: units, bytes: 0, cells: 0, records: 0, contributions: contributions, context: currentContext) { recordWork(units); recordCombined(combined) }
    }
    public mutating func retainStorage(count: Int, stride: Int) throws(ExactScalarFailure) {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !bytes.overflow else { throw .countOverflow }
        try retainStorage(bytes: bytes.partialValue)
    }
    public mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let policy = effectiveAllocationPolicy
        let work = try budget.allocationWorkUnits(bytes: bytes, policy: policy)
        let records: Int
        switch policy { case .uint32Words: records = work; case .none, .bytes, .uint32WordWork: records = 0 }
        let combined = try checkCombined(allocationBytes: bytes)
        try checkWork(work); try checkAllocation(bytes: bytes, records: records)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: work, bytes: bytes, cells: 0, records: records, contributions: contributions, context: currentContext) {
            recordWork(work); recordAllocation(bytes: bytes, records: records); recordCombined(combined)
        }
    }
    public mutating func retainSourceStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint(); try checkAllocation(bytes: bytes, records: 0)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: 0, bytes: bytes, cells: 0, records: 0, contributions: contributions, context: currentContext) { recordAllocation(bytes: bytes, records: 0) }
    }
    public mutating func consumeRecords(_ count: Int) throws(ExactScalarFailure) {
        try checkpoint(); try checkAllocation(bytes: 0, records: count)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: 0, bytes: 0, cells: 0, records: count, contributions: contributions, context: currentContext) { recordAllocation(bytes: 0, records: count) }
    }
    public mutating func consumeCells(_ count: Int = 1) throws(ExactScalarFailure) {
        try admitCells(count, certification: false)
    }
    private mutating func admitCells(_ count: Int, certification: Bool) throws(ExactScalarFailure) {
        try checkpoint()
        if certification {
            for scope in conversionScopes {
                try require(axis: .cells, used: scope.boxes, requested: count, limit: scope.maximumBoxes)
            }
        }
        try require(axis: .cells, used: visitedCells, requested: count, limit: limits.maximumCells)
        let cellWork = allocationScopes.reversed().first(where: { $0.cellVisitWorkUnits != nil })?.cellVisitWorkUnits
            ?? budget.cellVisitWorkUnits
        let cellRecords = allocationScopes.reversed().first(where: { $0.cellVisitRecords != nil })?.cellVisitRecords
            ?? budget.cellVisitRecords
        let work = try exactScalarCount(count, cellWork, multiply: true)
        let records = try exactScalarCount(count, cellRecords, multiply: true)
        let combined = try checkCombined(cells: count)
        try checkWork(work); try checkAllocation(bytes: 0, records: records)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: work, bytes: 0, cells: count, records: records, contributions: contributions, context: currentContext) {
            recordWork(work); recordAllocation(bytes: 0, records: records); visitedCells += count
            recordCombined(combined)
            if certification { for index in conversionScopes.indices { conversionScopes[index].boxes += count } }
        }
    }
    public mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let mapped = try proofScopes.mapped(value: value, coefficient: coefficient)
        try require(axis: .valueDepth, used: valueDepth, requested: mapped.value, limit: effectiveLimits.maximumValueDepth, additive: false)
        try require(axis: .coefficientDepth, used: coefficientDepth, requested: mapped.coefficient, limit: effectiveLimits.maximumCoefficientDepth, additive: false)
        try proofScopes.record(value: value, coefficient: coefficient)
        valueDepth = max(valueDepth, mapped.value); coefficientDepth = max(coefficientDepth, mapped.coefficient)
    }
    public mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let value = axis == .value ? depth : 0, coefficient = axis == .coefficient ? depth : 0
        let mapped = try proofScopes.mapped(value: value, coefficient: coefficient)
        try require(axis: .valueDepth, used: valueDepth, requested: mapped.value, limit: effectiveLimits.maximumValueDepth, additive: false)
        try require(axis: .coefficientDepth, used: coefficientDepth, requested: mapped.coefficient, limit: effectiveLimits.maximumCoefficientDepth, additive: false)
        try consumeCells(1)
        try proofScopes.record(value: value, coefficient: coefficient)
        valueDepth = max(valueDepth, mapped.value); coefficientDepth = max(coefficientDepth, mapped.coefficient)
    }
    public mutating func withGeometricDepthOffset<Result>(_ offset: Int,
        body: (inout Self) throws -> Result) throws -> Result {
        guard offset >= 0 else { throw ExactScalarFailure.countOverflow }
        let mapped = geometricDepthOffset.addingReportingOverflow(offset)
        guard !mapped.overflow else { throw ExactScalarFailure.countOverflow }
        let previous = geometricDepthOffset
        geometricDepthOffset = mapped.partialValue
        defer { geometricDepthOffset = previous }
        return try body(&self)
    }
    public mutating func admitGeometricDepth(_ depth: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let mapped = geometricDepthOffset.addingReportingOverflow(depth)
        guard depth >= 0, !mapped.overflow else { throw .countOverflow }
        try require(axis: .geometricDepth, used: geometricDepth, requested: mapped.partialValue,
            limit: effectiveLimits.maximumSubdivisionDepth, additive: false)
        geometricDepth = max(geometricDepth, mapped.partialValue)
        for index in preparationScopes.indices {
            preparationScopes[index].geometricDepth = max(preparationScopes[index].geometricDepth, mapped.partialValue)
        }
    }
    public mutating func withSourceDepthOffset<Result>(_ offset: Int,
        body: (inout Self) throws -> Result) throws -> Result {
        guard offset >= 0 else { throw ExactScalarFailure.countOverflow }
        let mapped = sourceDepthOffset.addingReportingOverflow(offset)
        guard !mapped.overflow else { throw ExactScalarFailure.countOverflow }
        let previous = sourceDepthOffset
        sourceDepthOffset = mapped.partialValue
        defer { sourceDepthOffset = previous }
        return try body(&self)
    }
    public mutating func admitSourceDepth(_ depth: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let mapped = sourceDepthOffset.addingReportingOverflow(depth)
        guard depth >= 0, !mapped.overflow else { throw .countOverflow }
        try require(axis: .sourceDepth, used: sourceDepth, requested: mapped.partialValue,
            limit: effectiveLimits.remainingSourceDepth, additive: false)
        for scope in preparationScopes {
            guard mapped.partialValue >= scope.sourceOrigin else { throw .invalidEvidence }
        }
        sourceDepth = max(sourceDepth, mapped.partialValue)
        for index in preparationScopes.indices {
            preparationScopes[index].sourceDepth = max(preparationScopes[index].sourceDepth,
                mapped.partialValue - preparationScopes[index].sourceOrigin)
        }
    }
    public mutating func admitTransportDepth(_ depth: Int) throws(ExactScalarFailure) {
        try checkpoint()
        try require(axis: .transportDepth, used: transportDepth, requested: depth, limit: effectiveLimits.maximumTransportDepth, additive: false)
        transportDepth = max(transportDepth, depth)
        for index in preparationScopes.indices { preparationScopes[index].transportDepth = max(preparationScopes[index].transportDepth, depth) }
    }
    public mutating func visitGeometricCell(depth: Int) throws(ExactScalarFailure) {
        try admitGeometricDepth(depth)
        try consumeCells(1)
    }
    public mutating func charge(scalars: Int = 0, work: Int = 0, storageBytes: Int = 0) throws(ExactScalarFailure) {
        try checkpoint()
        try require(axis: .scalarSlots, used: scalarSlots, requested: scalars, limit: limits.maximumScalarSlots)
        for scope in conversionScopes {
            try require(axis: .scalarSlots, used: scope.scalars, requested: scalars, limit: scope.maximumScalars)
        }
        let combined = try checkCombined(explicitWork: work, allocationBytes: storageBytes)
        let policy = effectiveAllocationPolicy
        let allocationWork = try budget.allocationWorkUnits(bytes: storageBytes, policy: policy)
        let totalWork = try exactScalarCount(work, allocationWork, multiply: false)
        let records: Int
        switch policy { case .uint32Words: records = allocationWork; case .none, .bytes, .uint32WordWork: records = 0 }
        try checkWork(totalWork); try checkAllocation(bytes: storageBytes, records: records)
        let owner = budget, currentContext = context
        let contributions = activeContributions
        try owner.admitting(work: totalWork, bytes: storageBytes, cells: 0, records: records,
            contributions: contributions, context: currentContext) {
            recordWork(totalWork); recordAllocation(bytes: storageBytes, records: records); recordCombined(combined)
            scalarSlots += scalars
            for index in conversionScopes.indices { conversionScopes[index].scalars += scalars }
        }
    }
    public mutating func openAllocationScope(policy: OriginalQueryAllocationPolicy,
        recordLimit: Int? = nil, storageByteLimit: Int? = nil, sourceTextByteLimit: Int? = nil, workLimit: Int? = nil,
        maxCombinedUnits: Int? = nil, cellVisitWorkUnits: Int? = nil, cellVisitRecords: Int? = nil)
        throws(ExactScalarFailure) -> OriginalQueryAllocationScopeToken {
        try checkpoint()
        guard recordLimit.map({ $0 >= 0 }) ?? true, storageByteLimit.map({ $0 >= 0 }) ?? true,
            workLimit.map({ $0 >= 0 }) ?? true, sourceTextByteLimit.map({ $0 >= 0 }) ?? true,
            maxCombinedUnits.map({ $0 >= 0 }) ?? true,
            cellVisitWorkUnits.map({ $0 >= 0 }) ?? true,
            cellVisitRecords.map({ $0 >= 0 }) ?? true else { throw .invalidSource }
        let next = nextAllocationOrdinal.addingReportingOverflow(1)
        guard !next.overflow else { throw .countOverflow }
        let oldPolicy = effectiveAllocationPolicy
        let capacity: Int?
        let stackBytes: Int
        if allocationScopes.count == allocationScopes.capacity {
            let doubled = allocationScopes.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw .countOverflow }
            let count = max(1, doubled.partialValue)
            capacity = count
            stackBytes = try exactScalarPayloadBytes(count: count, of: AllocationScope.self)
        } else { capacity = nil; stackBytes = 0 }
        let issuerBytes = allocationIssuer == nil
            ? MemoryLayout<OriginalQueryScopeIssuer>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride : 0
        let setupBytes = try exactScalarCount(stackBytes, issuerBytes, multiply: false)
        let setupWork = try exactScalarCount(budget.allocationWorkUnits(bytes: stackBytes, policy: oldPolicy),
            budget.allocationWorkUnits(bytes: issuerBytes, policy: oldPolicy), multiply: false)
        let setupRecords: Int
        switch oldPolicy { case .uint32Words: setupRecords = setupWork; case .none, .bytes, .uint32WordWork: setupRecords = 0 }
        if let maximum = workLimit { try require(axis: .work, used: 0, requested: setupWork, limit: maximum) }
        if let maximum = recordLimit { try require(axis: .sourceRecords, used: 0, requested: setupRecords, limit: maximum) }
        if let maximum = storageByteLimit { try require(axis: .storageBytes, used: 0, requested: setupBytes, limit: maximum) }
        if let capacity {
            try retainStorage(bytes: stackBytes)
            allocationScopes.reserveCapacity(capacity)
        }
        if allocationIssuer == nil {
            try retainStorage(bytes: issuerBytes)
            allocationIssuer = OriginalQueryScopeIssuer()
        }
        guard let issuer = allocationIssuer else { throw .invalidEvidence }
        allocationScopes.append(.init(ordinal: nextAllocationOrdinal, policy: policy,
            maximumWork: workLimit, maximumRecords: recordLimit, maximumBytes: storageByteLimit,
            sourceTextByteLimit: sourceTextByteLimit,
            maxCombinedUnits: maxCombinedUnits,
            cellVisitWorkUnits: cellVisitWorkUnits, cellVisitRecords: cellVisitRecords,
            work: setupWork, records: setupRecords, bytes: setupBytes))
        let token = OriginalQueryAllocationScopeToken(issuer: issuer, ordinal: nextAllocationOrdinal)
        nextAllocationOrdinal = next.partialValue
        return token
    }
    public func allocationScopeSnapshot(_ token: OriginalQueryAllocationScopeToken)
        throws(ExactScalarFailure) -> OriginalQueryAllocationScopeSnapshot {
        guard token.issuer === allocationIssuer, let scope = allocationScopes.last,
            scope.ordinal == token.ordinal else { throw .invalidEvidence }
        return .init(work: scope.work, storageBytes: scope.bytes, records: scope.records, sourceTextBytes: scope.sourceTextBytes,
            combinedUnits: scope.maxCombinedUnits == nil ? nil : scope.combinedUnits)
    }
    @discardableResult
    public mutating func closeAllocationScope(_ token: OriginalQueryAllocationScopeToken)
        throws(ExactScalarFailure) -> OriginalQueryAllocationScopeSnapshot {
        let snapshot = try allocationScopeSnapshot(token)
        allocationScopes.removeLast()
        return snapshot
    }
    public mutating func withAllocationScope<Result>(policy: OriginalQueryAllocationPolicy,
        recordLimit: Int? = nil, storageByteLimit: Int? = nil, sourceTextByteLimit: Int? = nil, workLimit: Int? = nil,
        maxCombinedUnits: Int? = nil, cellVisitWorkUnits: Int? = nil, cellVisitRecords: Int? = nil,
        _ body: (inout Self) throws -> Result) throws -> Result {
        let token = try openAllocationScope(policy: policy, recordLimit: recordLimit,
            storageByteLimit: storageByteLimit, sourceTextByteLimit: sourceTextByteLimit, workLimit: workLimit, maxCombinedUnits: maxCombinedUnits,
            cellVisitWorkUnits: cellVisitWorkUnits, cellVisitRecords: cellVisitRecords)
        do {
            let result = try body(&self)
            try closeAllocationScope(token)
            try checkpoint(); return result
        } catch {
            let original = error
            if token.issuer === allocationIssuer,
                let index = allocationScopes.lastIndex(where: { $0.ordinal == token.ordinal }) {
                allocationScopes.removeLast(allocationScopes.count - index)
            }
            throw original
        }
    }
    public mutating func openPreparationScope() throws(ExactScalarFailure) -> OriginalQueryPreparationScopeToken {
        try checkpoint()
        let next = nextPreparationOrdinal.addingReportingOverflow(1)
        guard !next.overflow else { throw .countOverflow }
        if preparationScopes.count == preparationScopes.capacity {
            let doubled = preparationScopes.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw .countOverflow }
            let capacity = max(1, doubled.partialValue)
            try retainStorage(bytes: exactScalarPayloadBytes(count: capacity, of: PreparationScope.self))
            preparationScopes.reserveCapacity(capacity)
        }
        if preparationIssuer == nil {
            try retainStorage(bytes: MemoryLayout<OriginalQueryScopeIssuer>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
            preparationIssuer = OriginalQueryScopeIssuer()
        }
        guard let issuer = preparationIssuer else { throw .invalidEvidence }
        let scalar = try openProofScope()
        preparationScopes.append(.init(ordinal: nextPreparationOrdinal, scalar: scalar, sourceOrigin: sourceDepthOffset))
        let token = OriginalQueryPreparationScopeToken(issuer: issuer, ordinal: nextPreparationOrdinal)
        nextPreparationOrdinal = next.partialValue
        return token
    }
    public mutating func closePreparationScope(_ token: OriginalQueryPreparationScopeToken) throws(ExactScalarFailure) -> OriginalQueryPreparationDepth {
        guard token.issuer === preparationIssuer, let scope = preparationScopes.last,
            scope.ordinal == token.ordinal else { throw .invalidEvidence }
        let scalar = try closeProofScope(scope.scalar)
        preparationScopes.removeLast()
        return .init(scalar: scalar, sourceDepth: scope.sourceDepth,
            geometricDepth: scope.geometricDepth, transportDepth: scope.transportDepth)
    }
    public mutating func withPreparationScope<Result>(_ body: (inout Self) throws -> Result)
        throws -> (result: Result, depth: OriginalQueryPreparationDepth) {
        let token = try openPreparationScope()
        let result: Result
        do { result = try body(&self) }
        catch {
            let original = error
            do {
                guard token.issuer === preparationIssuer,
                    let index = preparationScopes.lastIndex(where: { $0.ordinal == token.ordinal }) else { throw ExactScalarFailure.invalidEvidence }
                try proofScopes.unwind(preparationScopes[index].scalar)
                preparationScopes.removeLast(preparationScopes.count - index)
            } catch { throw original }
            throw original
        }
        let depth = try closePreparationScope(token)
        try checkpoint(); return (result, depth)
    }
    /// Accounts for source-validated immutable preparation once per query.
    /// This identity cache grants no geometry or source proof authority.
    public mutating func admitRetainedPreparation(owner: any AnyObject & Sendable, budget originalBudget: OriginalQueryBudget,
        work: Int, storageBytes: Int, depth: ExactScalarDepth,
        sourceDepth: Int, geometricDepth: Int, transportDepth: Int) throws(ExactScalarFailure) -> Bool {
        try checkpoint()
        try admitDepth(value: depth.value, coefficient: depth.coefficient)
        try admitSourceDepth(sourceDepth); try admitGeometricDepth(geometricDepth)
        try admitTransportDepth(transportDepth)
        for admitted in admittedPreparations {
            try consumeWork(1)
            if admitted === owner { return false }
        }
        guard work >= 0, storageBytes >= 0 else { throw .countOverflow }
        if budget !== originalBudget {
            try consumeWork(work); try retainStorage(bytes: storageBytes)
        }
        if admittedPreparations.count == admittedPreparations.capacity {
            let doubled = admittedPreparations.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw .countOverflow }
            let capacity = max(1, doubled.partialValue)
            try retainStorage(bytes: exactScalarPayloadBytes(count: capacity, of: (any AnyObject & Sendable).self))
            admittedPreparations.reserveCapacity(capacity)
        }
        admittedPreparations.append(owner)
        try checkpoint(); return true
    }
    public mutating func openConversionScope(maximumWorkUnits: Int, maximumScalarCount: Int,
        maximumCertificationBoxes: Int) throws(ExactScalarFailure) -> OriginalQueryConversionScopeToken {
        try checkpoint()
        guard maximumWorkUnits >= 0, maximumScalarCount >= 0, maximumCertificationBoxes >= 0 else { throw .invalidSource }
        let next = nextConversionOrdinal.addingReportingOverflow(1)
        guard !next.overflow else { throw .countOverflow }
        let capacity: Int?
        let stackBytes: Int
        if conversionScopes.count == conversionScopes.capacity {
            let doubled = conversionScopes.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw .countOverflow }
            let count = max(1, doubled.partialValue)
            capacity = count
            stackBytes = try exactScalarPayloadBytes(count: count, of: ConversionScope.self)
        } else { capacity = nil; stackBytes = 0 }
        let issuerBytes = conversionIssuer == nil
            ? MemoryLayout<OriginalQueryScopeIssuer>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride : 0
        let policy = effectiveAllocationPolicy
        let setupWork = try exactScalarCount(budget.allocationWorkUnits(bytes: stackBytes, policy: policy),
            budget.allocationWorkUnits(bytes: issuerBytes, policy: policy), multiply: false)
        try require(axis: .work, used: 0, requested: setupWork, limit: maximumWorkUnits)
        if let capacity {
            try retainStorage(bytes: stackBytes)
            conversionScopes.reserveCapacity(capacity)
        }
        if conversionIssuer == nil {
            try retainStorage(bytes: issuerBytes)
            conversionIssuer = OriginalQueryScopeIssuer()
        }
        guard let issuer = conversionIssuer else { throw .invalidEvidence }
        conversionScopes.append(.init(ordinal: nextConversionOrdinal, maximumWork: maximumWorkUnits,
            maximumScalars: maximumScalarCount, maximumBoxes: maximumCertificationBoxes, work: setupWork))
        let token = OriginalQueryConversionScopeToken(issuer: issuer, ordinal: nextConversionOrdinal)
        nextConversionOrdinal = next.partialValue
        return token
    }
    public mutating func closeConversionScope(_ token: OriginalQueryConversionScopeToken) throws(ExactScalarFailure) {
        guard token.issuer === conversionIssuer, conversionScopes.last?.ordinal == token.ordinal else { throw .invalidEvidence }
        conversionScopes.removeLast()
    }
    public mutating func withConversionScope<Result>(maximumWorkUnits: Int, maximumScalarCount: Int,
        maximumCertificationBoxes: Int, _ body: (inout Self) throws -> Result) throws -> Result {
        let token = try openConversionScope(maximumWorkUnits: maximumWorkUnits,
            maximumScalarCount: maximumScalarCount, maximumCertificationBoxes: maximumCertificationBoxes)
        do {
            let result = try body(&self)
            try closeConversionScope(token)
            return result
        } catch {
            let original = error
            if token.issuer === conversionIssuer,
                let index = conversionScopes.lastIndex(where: { $0.ordinal == token.ordinal }) {
                conversionScopes.removeLast(conversionScopes.count - index)
            }
            throw original
        }
    }
    public var conversionScopeSnapshot: OriginalQueryConversionScopeSnapshot? {
        guard let scope = conversionScopes.last else { return nil }
        return .init(work: scope.work, scalarSlots: scope.scalars, certificationBoxes: scope.boxes)
    }
    public mutating func visitCertificationCell(depth: Int) throws(ExactScalarFailure) {
        try admitGeometricDepth(depth)
        try admitCells(1, certification: true)
    }
    public mutating func visitConversionCell(depth: Int) throws(ExactScalarFailure) {
        try visitCertificationCell(depth: depth)
        try charge(scalars: 512, work: 4_096)
    }
    private func require(axis: OriginalQueryResourceAxis, used: Int, requested: Int, limit: Int,
        additive: Bool = true) throws(ExactScalarFailure) {
        let next = additive ? used.addingReportingOverflow(requested) : (partialValue: requested, overflow: false)
        guard used >= 0, requested >= 0, !next.overflow else { throw .countOverflow }
        guard next.partialValue <= limit else {
            let scalar: any Error
            switch axis {
            case .valueDepth: scalar = ExactScalarFailure.resourceLimit(.valueDepth)
            case .coefficientDepth: scalar = ExactScalarFailure.resourceLimit(.coefficientDepth)
            case .work: scalar = ExactScalarFailure.resourceLimit(.work)
            case .storageBytes: scalar = ExactScalarFailure.resourceLimit(.storage)
            default: scalar = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original query exceeded its independent local resource ceiling.")
            }
            throw .admissionRejected(OriginalQueryFailure.published(scalar,
                context: context.recording(resource: .init(axis: axis, used: .known(used),
                    limit: .known(limit), requested: .known(requested))), tolerance: nil))
        }
    }
}
