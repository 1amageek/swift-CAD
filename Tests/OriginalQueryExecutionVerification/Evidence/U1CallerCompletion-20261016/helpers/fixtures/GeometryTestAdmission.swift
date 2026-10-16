import CADCore
import Testing
@testable import CADGeometry

/// Shared canonical mechanics; each instrumented test owns its counters and visit policy.
protocol GeometryScalarTestAdmission: ExactScalarAdmission, ~Copyable {
    var maximumTestValueDepth: Int { get }
    var maximumTestCoefficientDepth: Int { get }
}

extension GeometryScalarTestAdmission where Self: ~Copyable {
    var maximumTestValueDepth: Int { Int.max }
    var maximumTestCoefficientDepth: Int { Int.max }

    mutating func checkpoint() throws(ExactScalarFailure) {
        if Task<Never, Never>.isCancelled { throw .cancelled }
    }

    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let mapped = try proofScopes.mapped(value: value, coefficient: coefficient)
        guard mapped.value <= maximumTestValueDepth else { throw .resourceLimit(.valueDepth) }
        guard mapped.coefficient <= maximumTestCoefficientDepth else { throw .resourceLimit(.coefficientDepth) }
        try proofScopes.record(value: value, coefficient: coefficient)
    }
}

/// Preserves historical rounded-word observations at the canonical byte boundary.
func geometryTestStorageWords(_ bytes: Int) throws(ExactScalarFailure) -> Int {
    guard bytes >= 0 else { throw .countOverflow }
    let rounded = bytes.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
    guard !rounded.overflow else { throw .countOverflow }
    return rounded.partialValue / MemoryLayout<UInt32>.stride
}

/// Reads the retained cause without converting refusal into success.
func geometryTestOriginalFailure(_ error: any Error) -> any Error {
    if let retained = error as? OriginalQueryFailure {
        return geometryTestOriginalFailure(retained.originalError)
    }
    if let scalar = error as? ExactScalarFailure, case .admissionRejected(let original) = scalar {
        return geometryTestOriginalFailure(original)
    }
    return error
}

func geometryTestIsCancelled(_ error: any Error) -> Bool {
    let original = geometryTestOriginalFailure(error)
    if original is CancellationError { return true }
    if let scalar = original as? ExactScalarFailure, case .cancelled = scalar { return true }
    return false
}

/// Test-selected public query policy is carried by the real execution owner.
func geometryTestWithQuery<Result>(maximumSpanCount: Int = 262_144,
    maximumSubdivisionDepth: Int = 32, remainingSourceDepth: Int = 16,
    maximumAlgebraicDepth: Int = 32,
    consumeWorkUnits: (@Sendable (Int) throws -> Void)? = nil,
    consumeStorageBytes: (@Sendable (Int) throws -> Void)? = nil,
    _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
    var execution = OriginalQueryExecution(
        budget: try OriginalQueryBudget(consumeWorkUnits: consumeWorkUnits,
            consumeStorageBytes: consumeStorageBytes),
        limits: try OriginalQueryExecutionLimits(maximumValueDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSpans: maximumSpanCount,
            maximumNativeSpans: maximumSpanCount))
    return try body(&execution)
}

/// A test instrument owns its proof scopes; observers can reject the actual debit.
struct GeometryTestScalarRecorder: ~Copyable, GeometryScalarTestAdmission {
    var proofScopes = ExactScalarProofScopes()
    private(set) var work = 0
    private(set) var storageBytes = 0
    private(set) var valueVisits = 0
    private(set) var coefficientVisits = 0
    var maximumTestValueDepth = Int.max
    var maximumTestCoefficientDepth = Int.max
    private let observeWork: (Int) throws -> Void
    private let observeStorageWords: (Int) throws -> Void
    private let observeValueCell: (Int) throws -> Void
    private let observeCoefficientCell: (Int) throws -> Void

    init(maximumValueDepth: Int = Int.max, maximumCoefficientDepth: Int = Int.max,
        observeWork: @escaping (Int) throws -> Void = { _ in },
        observeStorageWords: @escaping (Int) throws -> Void = { _ in },
        observeValueCell: @escaping (Int) throws -> Void = { _ in },
        observeCoefficientCell: @escaping (Int) throws -> Void = { _ in }) {
        self.maximumTestValueDepth = maximumValueDepth
        self.maximumTestCoefficientDepth = maximumCoefficientDepth
        self.observeWork = observeWork
        self.observeStorageWords = observeStorageWords
        self.observeValueCell = observeValueCell
        self.observeCoefficientCell = observeCoefficientCell
    }

    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try checkpoint()
        try proofScopes.checkWork(units)
        let next = work.addingReportingOverflow(units)
        guard units >= 0, !next.overflow else { throw .countOverflow }
        do { try observeWork(units) }
        catch { throw .admissionRejected(error) }
        work = next.partialValue
        proofScopes.recordWork(units)
        try checkpoint()
    }

    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint()
        let words = try geometryTestStorageWords(bytes)
        let next = storageBytes.addingReportingOverflow(bytes)
        guard !next.overflow else { throw .countOverflow }
        do { try observeStorageWords(words) }
        catch { throw .admissionRejected(error) }
        storageBytes = next.partialValue
        try checkpoint()
    }

    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
        let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0,
            coefficient: axis == .coefficient ? depth : 0)
        do {
            if axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth {
                try observeCoefficientCell(mapped.coefficient)
                guard coefficientVisits < Int.max else { throw ExactScalarFailure.countOverflow }
                coefficientVisits += 1
            } else {
                try observeValueCell(mapped.value)
                guard valueVisits < Int.max else { throw ExactScalarFailure.countOverflow }
                valueVisits += 1
            }
        } catch let scalar as ExactScalarFailure { throw scalar }
        catch { throw .admissionRejected(error) }
        try checkpoint()
    }
}

/// Public classification remains separate from the retained original typed cause.
func geometryTestKernelFailure(_ error: any Error) -> KernelError? {
    let published = OriginalQueryFailure.published(error, context: .unspecified, tolerance: nil)
    return OriginalQueryFailure.classification(of: published)
}

func geometryTestQueryFailure(_ error: any Error) -> OriginalQueryFailure? {
    if let retained = error as? OriginalQueryFailure { return retained }
    if let scalar = error as? ExactScalarFailure, case .admissionRejected(let original) = scalar {
        return geometryTestQueryFailure(original)
    }
    return nil
}

/// Evaluate an exclusive producer call before Testing's Copyable optional checker.
func geometryTestRequire<Value>(_ value: Value?, sourceLocation: SourceLocation = #_sourceLocation) throws -> Value {
    try #require(value, sourceLocation: sourceLocation)
}

/// Match the retained failure explicitly without Testing's removed matcher spelling.
func geometryTestExpectFailure<Result>(_ matches: (any Error) -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Result) {
    do {
        _ = try operation()
        Issue.record("Expected the selected typed failure.", sourceLocation: sourceLocation)
    } catch {
        let matched = matches(error)
        #expect(matched, sourceLocation: sourceLocation)
    }
}

func geometryTestExpectFailure<Result>(_ matches: (any Error) -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () async throws -> Result) async {
    do {
        _ = try await operation()
        Issue.record("Expected the selected typed failure.", sourceLocation: sourceLocation)
    } catch {
        let matched = matches(error)
        #expect(matched, sourceLocation: sourceLocation)
    }
}
