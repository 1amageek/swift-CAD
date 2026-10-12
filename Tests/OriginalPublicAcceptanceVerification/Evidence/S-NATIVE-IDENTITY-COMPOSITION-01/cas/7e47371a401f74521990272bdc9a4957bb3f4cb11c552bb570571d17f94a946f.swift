import CADCore
import CADGeometry

public protocol BRepVolumeMomentMeasuring: Sendable {
    func moments(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions) throws -> BRepVolumeMoments
    func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
        tolerance: ModelingTolerance) throws -> BRepVolumeMoments
}

public extension BRepVolumeMomentMeasuring {
    func moments(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions) throws -> BRepVolumeMoments {
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "This moment provider does not consume original immutable validation receipts.")
    }
}
