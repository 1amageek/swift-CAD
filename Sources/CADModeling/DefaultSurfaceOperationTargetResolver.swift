import CADCore
import CADIR
import CADTopology

package struct DefaultSurfaceOperationTargetResolver:
    SurfaceOperationTargetResolving
{
    private let subshapeResolver: any StableSubshapeResolving

    package init(
        subshapeResolver: any StableSubshapeResolving =
            StableSubshapeResolver()
    ) {
        self.subshapeResolver = subshapeResolver
    }

    package func resolve(
        _ target: SurfaceOperationTargetReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> ResolvedSurfaceOperationTarget {
        let bodyID = try context.bodyID(generatedBy: target.featureID)
        let topologyReference = try subshapeResolver.topologyReference(
            for: target.face,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = topologyReference else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                featureID: featureID,
                subshapeID: target.face.subshapeID,
                tolerance: context.tolerance,
                message: "Surface operation target did not resolve to a face."
            )
        }
        guard let body = context.brep.bodies[bodyID] else {
            throw TopologyError.missingReference(
                "Surface operation target body is missing."
            )
        }
        guard body.kind == .sheet else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: featureID,
                subshapeID: target.face.subshapeID,
                tolerance: context.tolerance,
                message: "Exact surface operations require a sheet body."
            )
        }
        var owningShell: Shell?
        for shellID in body.shellIDs {
            guard let shell = context.brep.shells[shellID] else {
                throw TopologyError.missingReference(
                    "Surface operation target shell is missing."
                )
            }
            if shell.faceIDs.contains(faceID) {
                guard owningShell == nil else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        featureID: featureID,
                        subshapeID: target.face.subshapeID,
                        tolerance: context.tolerance,
                        message: "Surface operation face has multiple owners in one body."
                    )
                }
                owningShell = shell
            }
        }
        guard let shell = owningShell,
              let face = context.brep.faces[faceID],
              let surface = context.brep.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                featureID: featureID,
                subshapeID: target.face.subshapeID,
                tolerance: context.tolerance,
                message: "Surface operation face does not belong to the referenced sheet body."
            )
        }
        return ResolvedSurfaceOperationTarget(
            bodyID: bodyID,
            shellID: shell.id,
            faceID: faceID,
            body: body,
            shell: shell,
            face: face,
            surface: surface
        )
    }
}
