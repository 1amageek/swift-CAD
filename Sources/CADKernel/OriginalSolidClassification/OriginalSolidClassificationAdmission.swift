import CADCore

struct OriginalSolidClassificationAdmission: Sendable {
    let maximumSubdivisionDepth: Int
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: (@Sendable (Int) throws -> Void)?
    let remainingSourceDepth: Int?
    let maximumAlgebraicDepth: Int

    init(maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        tolerance: ModelingTolerance,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int = 32) throws {
        guard (0...32).contains(maximumSubdivisionDepth),
              remainingSourceDepth.map({ $0 >= 0 }) ?? true,
              (0...32).contains(maximumAlgebraicDepth) else {
            throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Original solid classification requires caller depth between zero and 32.")
        }
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    func consume(_ depth: Int = 0) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= maximumSubdivisionDepth else {
            throw KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original solid classification exhausted caller subdivision depth.")
        }
        try consumeWork(depth)
    }
}
