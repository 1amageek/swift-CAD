import CADCore
import CADGeometry

/// One source operation's cumulative traversal and retained-output allowance.
struct IndependentShapeSourceBudget: RationalAlgebraAdmitting {
    let limits: IndependentShapeSourceLimits
    private var records = 0
    private var work = 0
    private var textBytes = 0
    init(limits: IndependentShapeSourceLimits) throws { try limits.validate(); self.limits = limits }
    mutating func charge(records: Int = 0, work: Int = 0, textBytes: Int = 0) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard records >= 0, work >= 0, textBytes >= 0,
              records <= limits.maximumRecords - self.records,
              work <= limits.maximumWork - self.work,
              textBytes <= limits.maximumTextBytes - self.textBytes else { throw IndependentShapeSourceError.resourceLimitExceeded("Source translation cumulative budget.") }
        self.records += records; self.work += work; self.textBytes += textBytes
    }
    var remaining: IndependentShapeSourceLimits {
        .init(maximumRecords: limits.maximumRecords - records, maximumTextBytes: limits.maximumTextBytes - textBytes,
              maximumDepth: limits.maximumDepth, maximumWork: limits.maximumWork - work, maximumCurveSubdivisionDepth: limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= limits.maximumAlgebraicDepth else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Source translation exact algebraic depth.")
        }
        try charge(records: 1, work: 1)
    }
    mutating func consumeExactWork(_ count: Int) throws { try charge(work: count) }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Source translation exact storage overflow.")
        }
        try charge(records: count, work: count, textBytes: bytes.partialValue)
    }
}
