import CADCore
import CADGeometry
import CADTopology

/// Retains two original body sessions prepared from one immutable source receipt.
public struct PreparedSolidClassificationPair: Sendable {
    public let validatedModel: ValidatedBRepModel
    public let firstBodyID: BodyID
    public let secondBodyID: BodyID
    public let firstClassification: any SolidPointClassificationSession
    public let secondClassification: any SolidPointClassificationSession

    // FIXME(INCOMPLETE_IMPLEMENTATION): Source-bound session reuse retains actual
    // preparation depth and the common cumulative owner. General lower original
    // family coverage must be verified before a whole-query completeness claim.
    public init(firstBodyID: BodyID, secondBodyID: BodyID,
        validatedModel: ValidatedBRepModel, classifier: any SolidPointClassifying,
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint(); try execution.consumeWork(1)
        guard validatedModel.validationLevel != .modeling,
            validatedModel.model.bodies[firstBodyID]?.kind == .solid,
            validatedModel.model.bodies[secondBodyID]?.kind == .solid else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "Original classification pairs require two source-owned exact solids.")
        }
        let first = try classifier.preparedClassificationSession(in: firstBodyID,
            validatedModel: validatedModel, using: &execution)
        let second: any SolidPointClassificationSession
        if firstBodyID == secondBodyID { second = first }
        else {
            second = try classifier.preparedClassificationSession(in: secondBodyID,
                validatedModel: validatedModel, using: &execution)
        }
        try execution.checkpoint()
        self.validatedModel = validatedModel
        self.firstBodyID = firstBodyID; self.secondBodyID = secondBodyID
        firstClassification = first; secondClassification = second
    }
}
