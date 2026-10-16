import CADCore
import CADGeometry
import CADTopology

/// Admits contact of the complete exactly validated result body before publication.
public protocol OffsetResultValidating: Sendable {
    func validate(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws
    func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel) throws
    func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws
}

public extension OffsetResultValidating {
    func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel) throws {
        try validate(bodyID: bodyID, model: validatedModel.model, tolerance: validatedModel.tolerance)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Generated-sheet consumers require the
    // same original caller admission throughout every self/finite-face proof.
    // A legacy conformer cannot supply that witness through receipt replay.
    func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws {
        throw KernelError(phase: .validation, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "This result contact validator has no original caller-admitted composition.")
    }
}
