import CADCore

/// Exclusive query-local bridge to the original Geometry allowance.
/// Lower layers report already mapped depths and every actual cell visit.
struct NativeExactPublicAdmission<Usage: RationalAlgebraAdmitting>: ~Copyable, ExactScalarAdmission {
    var usage: Usage
    let maximumValueDepth: Int
    let maximumCoefficientDepth: Int

    init(usage: Usage, maximumDepth: Int) {
        self.usage = usage
        maximumValueDepth = maximumDepth; maximumCoefficientDepth = maximumDepth
    }
    init(usage: Usage, maximumValueDepth: Int, maximumCoefficientDepth: Int) {
        self.usage = usage
        self.maximumValueDepth = maximumValueDepth
        self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    mutating func checkpoint() throws(ExactScalarFailure) {
        do { try CurrentTaskCancellationChecker().checkCancellation() }
        catch { throw .cancelled }
    }

    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        try checkpoint()
        do { try usage.consumeExactWork(units) }
        catch { throw Self.preserving(error) }
        try checkpoint()
    }

    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard bytes >= 0 else { throw .countOverflow }
        let stride = MemoryLayout<UInt32>.stride
        let quotient = bytes / stride
        let rounded = quotient.addingReportingOverflow(bytes % stride == 0 ? 0 : 1)
        guard !rounded.overflow else { throw .countOverflow }
        do { try usage.retainExactStorage(rounded.partialValue) }
        catch { throw Self.preserving(error) }
        try checkpoint()
    }

    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard value >= 0, coefficient >= 0 else { throw .countOverflow }
        guard value <= maximumValueDepth else {
            throw .resourceLimit(.valueDepth)
        }
        guard coefficient <= maximumCoefficientDepth else { throw .resourceLimit(.coefficientDepth) }
    }

    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try checkpoint()
        guard depth >= 0 else { throw .countOverflow }
        guard depth <= (axis == .value ? maximumValueDepth : maximumCoefficientDepth) else {
            throw .resourceLimit(axis == .value ? .valueDepth : .coefficientDepth)
        }
        do {
            switch axis {
            case .value: try usage.visitExactCell(depth: depth)
            case .coefficient: try usage.visitCoefficientCell(depth: depth)
            }
        } catch { throw Self.preserving(error) }
        try checkpoint()
    }
    private static func preserving(_ error: any Error) -> ExactScalarFailure {
        if let error = error as? ExactScalarFailure { return error }
        if error is CancellationError { return .cancelled }
        return .admissionRejected(error)
    }
}
