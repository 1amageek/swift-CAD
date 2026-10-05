import CADCore

/// Immutable admission forwarded to every original query producer operation.
package struct CurveSurfaceQueryInvocation: Sendable {
    package let maximumSubdivisionDepth:Int
    package let maximumSpanCount:Int
    package let remainingSourceDepth:Int
    package let maximumAlgebraicDepth: Int?
    package let consumeStorage: (@Sendable (Int) throws -> Void)?
    private let consumeWork:@Sendable (Int)throws->Void
    package init(maximumSubdivisionDepth:Int,maximumSpanCount:Int,remainingSourceDepth:Int,
        consumeWork:@escaping @Sendable (Int)throws->Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
        guard (0...32).contains(maximumSubdivisionDepth),maximumSpanCount > 0,remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original curve-surface invocation requires caller depth, span and source admission.")
        }
        self.maximumSubdivisionDepth = maximumSubdivisionDepth;self.maximumSpanCount = maximumSpanCount
        self.remainingSourceDepth = remainingSourceDepth;self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage; self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }
    package func consume(depth:Int) throws {
        try Task.checkCancellation()
        guard depth >= 0,depth <= maximumSubdivisionDepth else {
            throw GeometryConversionError.resourceLimitExceeded("Original curve-surface invocation exhausted caller subdivision depth.")
        }
        try consumeWork(depth)
    }
    package func reserve(count: Int, stride: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride > 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original curve-surface storage byte admission overflows.")
        }
        try Task.checkCancellation(); try consumeStorage?(bytes.partialValue)
    }
    package func consumeFixedWork() throws { try consume(depth:0) }
}
