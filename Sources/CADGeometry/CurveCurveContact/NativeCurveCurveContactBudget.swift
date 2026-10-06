import CADCore

struct NativeCurveCurveContactBudget: Sendable, RationalAlgebraAdmitting {
    private var remainingWork: Int
    private var remainingCells: Int
    private var inheritedExactDepth = 0
    private var originalWordAlgebra = false
    private let admission: OriginalCurveContactAdmission?
    let maximumSubdivisionDepth: Int
    let maximumAlgebraicDepth: Int
    let remainingSourceDepth: Int
    var maximumDepth: Int { originalWordAlgebra ? maximumAlgebraicDepth : maximumSubdivisionDepth }
    let tolerance: ModelingTolerance
    var availableWork: Int { remainingWork }

    init(maximumDepth: Int, maximumCells: Int, maximumWork: Int, tolerance: ModelingTolerance,
        admission: OriginalCurveContactAdmission? = nil, maximumAlgebraicDepth: Int = 32,
        remainingSourceDepth: Int = 32) throws {
        guard maximumDepth >= 0, maximumDepth <= 32, maximumCells > 0, maximumWork > 0,
            (0...32).contains(maximumAlgebraicDepth), (0...32).contains(remainingSourceDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original curve contact limits are outside the retained resource envelope.")
        }
        maximumSubdivisionDepth = maximumDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.remainingSourceDepth = remainingSourceDepth
        remainingCells = maximumCells
        remainingWork = maximumWork
        self.tolerance = tolerance
        self.admission = admission
    }

    mutating func work(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count >= 0, count <= remainingWork else { throw exhausted() }
        remainingWork -= count
        try admission?.chargeWork(count)
    }

    mutating func retainBytes(_ bytes: Int) throws {
        guard bytes >= 0 else { throw exhausted() }
        let stride = MemoryLayout<UInt32>.stride
        let rounded = bytes.addingReportingOverflow(stride - 1)
        guard !rounded.overflow else { throw exhausted() }
        try retainExactStorage(rounded.partialValue / stride)
    }

    mutating func consumeExactWork(_ count: Int) throws { try work(count) }
    mutating func retainExactStorage(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, count <= remainingWork, !bytes.overflow else { throw exhausted() }
        remainingWork -= count
        try admission?.chargeStorage(bytes: bytes.partialValue)
    }
    mutating func visitCoefficientCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumAlgebraicDepth else { throw exhausted() }
        try cell()
    }

    mutating func visitExactCell(depth: Int) throws {
        let actual = depth.addingReportingOverflow(inheritedExactDepth)
        let ceiling = originalWordAlgebra ? maximumAlgebraicDepth : maximumSubdivisionDepth
        guard depth >= 0, !actual.overflow, actual.partialValue <= ceiling else { throw exhausted() }
        try cell()
    }

    struct ExactContext: Sendable {
        let algebra: Bool
        let inheritedDepth: Int
    }

    /// Exact event and original placement algebra is separate from pair subdivision.
    mutating func enterExactAlgebra() -> ExactContext {
        let previous = ExactContext(algebra: originalWordAlgebra, inheritedDepth: inheritedExactDepth)
        if !originalWordAlgebra { inheritedExactDepth = 0 }
        originalWordAlgebra = true
        return previous
    }

    mutating func restoreExactAlgebra(_ previous: ExactContext) {
        originalWordAlgebra = previous.algebra
        inheritedExactDepth = previous.inheritedDepth
    }

    mutating func enterOriginalWordAlgebra() -> ExactContext { enterExactAlgebra() }
    mutating func restoreOriginalWordAlgebra(_ previous: ExactContext) { restoreExactAlgebra(previous) }

    /// Only context is restored; all work, cells and storage remain consumed.
    mutating func enterExactDepth(_ parent: Int) throws -> Int {
        let actual = inheritedExactDepth.addingReportingOverflow(parent)
        guard parent >= 0, !actual.overflow, actual.partialValue <= maximumDepth else { throw exhausted() }
        let previous = inheritedExactDepth
        inheritedExactDepth = actual.partialValue
        return previous
    }

    mutating func restoreExactDepth(_ previous: Int) {
        inheritedExactDepth = previous
    }

    mutating func cell() throws {
        try work(1)
        guard remainingCells > 0 else { throw exhausted() }
        remainingCells -= 1
    }

    func exhausted() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original curve-pair contact exhausted its cumulative source, storage or subdivision allowance.")
    }
}
