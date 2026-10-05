import CADCore
import CADTopology

/// Retains two original body sessions prepared from one immutable source receipt.
public struct PreparedSolidClassificationPair: Sendable {
    public let validatedModel: ValidatedBRepModel
    public let firstBodyID: BodyID
    public let secondBodyID: BodyID
    public let firstClassification: any SolidPointClassificationSession
    public let secondClassification: any SolidPointClassificationSession

    // FIXME(INCOMPLETE_IMPLEMENTATION): Q1/Q2 source-bound session reuse preserves
    // caller work/depth. The additive selected path forwards optional bytes to
    // original preparation/extent/winding/normal owners, while curve-surface and
    // model-space projection still need their real byte-admitted producers.
    // Neither path establishes complete bounded storage from outer slot charges.
    public init(firstBodyID: BodyID, secondBodyID: BodyID,
        validatedModel: ValidatedBRepModel,
        classifier: any SolidPointClassifying,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws {
        try Task.checkCancellation()
        try consumeWork(0)
        guard validatedModel.validationLevel != .modeling,
              validatedModel.model.bodies[firstBodyID]?.kind == .solid,
              validatedModel.model.bodies[secondBodyID]?.kind == .solid else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Original classification pairs require two source-owned exact solids.")
        }
        let first = try classifier.preparedClassificationSession(in: firstBodyID,
            validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork)
        let second: any SolidPointClassificationSession
        if firstBodyID == secondBodyID {
            second = first
        } else {
            second = try classifier.preparedClassificationSession(in: secondBodyID,
                validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork)
        }
        try Task.checkCancellation()
        self.validatedModel = validatedModel
        self.firstBodyID = firstBodyID
        self.secondBodyID = secondBodyID
        firstClassification = first
        secondClassification = second
    }

    public init(firstBodyID: BodyID, secondBodyID: BodyID,
        validatedModel: ValidatedBRepModel,
        classifier: any SolidPointClassifying,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws {
        try Task.checkCancellation()
        try consumeWork(0)
        guard validatedModel.validationLevel != .modeling,
              validatedModel.model.bodies[firstBodyID]?.kind == .solid,
              validatedModel.model.bodies[secondBodyID]?.kind == .solid else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Original classification pairs require two source-owned exact solids.")
        }
        let first = try classifier.preparedClassificationSession(in: firstBodyID,
            validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        let second: any SolidPointClassificationSession
        if firstBodyID == secondBodyID {
            second = first
        } else {
            second = try classifier.preparedClassificationSession(in: secondBodyID,
                validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        try Task.checkCancellation()
        self.validatedModel = validatedModel
        self.firstBodyID = firstBodyID
        self.secondBodyID = secondBodyID
        firstClassification = first
        secondClassification = second
    }
}
