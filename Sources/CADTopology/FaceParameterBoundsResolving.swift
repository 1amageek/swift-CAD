import CADCore
import CADGeometry

package protocol FaceParameterBoundsResolving: Sendable {
    func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox
    func bounds(for faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox
}

extension FaceParameterBoundsResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Original face queries require the actual
    // caller execution; ordinary provider dispatch cannot provide that evidence.
    func bounds(for faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
            message: "The face bounds provider has no direct original execution witness.")
    }
}
