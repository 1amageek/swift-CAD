import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// The solid that faces of a solid which do not close bound with the surfaces around them
/// (Plasticity's Alternative Duplicate): a pocket's plug, a boss's block.
///
/// The body is healed over the chosen faces (`FaceRemovalPlanner`, the faces around grown over
/// them until they meet) in a staged copy, and the opening — the edges where the chosen faces meet
/// the others — is imprinted on that copy (`BRepFaceImprinter`). The copy's faces off the source's
/// boundary are the caps closing the opening; the chosen faces and the caps are sewn as one solid,
/// the chosen faces turned inside out where they bound a void of the source (a pocket) and the caps
/// where they run through its material (a boss). The source stays as it is.
// FIXME(INCOMPLETE_IMPLEMENTATION): caps both inside and outside the source (faces that are partly
// pocket, partly boss) are refused, and so are faces the healing cannot grow the faces around over.
// Production path: ExtractFeatureEvaluator for `.solidFaces` that do not close, and
// ExtractFaceClosure.makesSolid, which answers a sheet for them. Complete only when such faces make
// the solid they bound, verified by a face set crossing the source's boundary making its two parts.
struct ExtractFacePlugBuilder {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    func plug(faces chosen: Set<FaceID>, of bodyID: BodyID, featureID: FeatureID,
        context: EvaluationContext) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try plug(faces: chosen, of: bodyID, featureID: featureID,
            context: context, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Extract Plug requires the ordinary-only healing producer.
    // Production ExtractFeatureEvaluator and ExtractFaceClosure cannot publish a plug until
    // FaceRemovalPlanner provides original source coverage and the same execution through healing.
    func plug(faces chosen: Set<FaceID>, of bodyID: BodyID, featureID: FeatureID,
        context: EvaluationContext, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        guard context.brep.bodies[bodyID] != nil else {
            throw TopologyError.missingReference("The extracted body is missing.")
        }
        throw KernelError(phase: .evaluation, code: .unsupportedCapability,
            featureID: featureID, tolerance: tolerance,
            message: "Extract Plug healing has no direct original execution witness.")
    }
}
