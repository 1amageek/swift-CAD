import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct ExactIntersectionFacePatchMaterializer {
    func materialize(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        var hasOpenComponent = false
        var hasClosedComponent = false
        var requiresPeriodicArrangement = false
        var hasCoincidentComponent = false
        var hasBoundaryContact = false
        for split in uvSplitGraph.splits {
            for component in split.components {
                switch component.geometry {
                case .transverseSegment, .trimmedCurve:
                    hasOpenComponent = true
                case let .closedCurve(closedIntersection):
                    hasClosedComponent = true
                    if try isNonContractible(
                        closedIntersection,
                        facePair: split.facePair,
                        model: model,
                        tolerance: tolerance
                    ) {
                        requiresPeriodicArrangement = true
                    }
                case .tangent:
                    hasBoundaryContact = true
                case .coincident:
                    hasCoincidentComponent = true
                    hasBoundaryContact = true
                }
            }
        }
        let coincidenceResolution: CoincidentBooleanFaceOwnershipResolver.Resolution
        if hasCoincidentComponent {
            do {
                coincidenceResolution = try CoincidentBooleanFaceOwnershipResolver().resolve(
                    operation: operation,
                    uvSplitGraph: uvSplitGraph,
                    model: model,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "coincident face ownership",
                    tolerance: tolerance
                )
            }
        } else {
            coincidenceResolution = CoincidentBooleanFaceOwnershipResolver.Resolution(
                forcedActions: [:],
                partiallyCoincidentPairs: []
            )
        }
        let coincidentArrangement: CoincidentBooleanFaceArrangementBoundaryBuilder.Result
        do {
            coincidentArrangement = try CoincidentBooleanFaceArrangementBoundaryBuilder().build(
                operation: operation,
                pairs: coincidenceResolution.partiallyCoincidentPairs,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "coincident face arrangement",
                tolerance: tolerance
            )
        }
        var coincidentFaceActions = coincidenceResolution.forcedActions
        for (faceID, action) in coincidentArrangement.constantActions {
            guard coincidentFaceActions[faceID].map({ $0 != action }) != true else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Coincident Boolean ownership assigned conflicting actions to one face."
                )
            }
            coincidentFaceActions[faceID] = action
        }
        let hasCoincidentArrangement = coincidentArrangement.boundaries.contains(where: \.isPartitioning)
        guard hasOpenComponent || hasClosedComponent || hasCoincidentArrangement else {
            return try WholeBodyBooleanFacePatchMaterializer().materialize(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: featureID,
                model: model,
                sourceSubshapes: sourceSubshapes,
                hasBoundaryContact: hasBoundaryContact,
                tolerance: tolerance
            )
        }
        // Component topology selects the exact partitioning strategy. Closed
        // loops use a containment tree so implicit intersection curves are not
        // resampled and intersected as a general half-edge network. Any open
        // or coincident partition requires the complete face arrangement,
        // which also consumes closed components when the strategies are mixed.
        if hasOpenComponent || requiresPeriodicArrangement
            || hasCoincidentArrangement {
            return try OpenIntersectionFacePatchMaterializer().materialize(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: featureID,
                model: model,
                sourceSubshapes: sourceSubshapes,
                uvSplitGraph: uvSplitGraph,
                regionSelectionGraph: regionSelectionGraph,
                coincidentArrangementBoundaries: coincidentArrangement.boundaries,
                coincidentFaceActions: coincidentFaceActions,
                tolerance: tolerance
            )
        }
        return try ClosedIntersectionFacePatchMaterializer().materialize(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            featureID: featureID,
            model: model,
            sourceSubshapes: sourceSubshapes,
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: regionSelectionGraph,
            coincidentFaceActions: coincidentFaceActions,
            tolerance: tolerance
        )
    }

    private func isNonContractible(
        _ intersection: BooleanClosedFaceIntersection,
        facePair: BooleanFacePairCandidate,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let targetFace = model.faces[facePair.targetFaceID],
              let toolFace = model.faces[facePair.toolFaceID],
              let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
              let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Periodic Boolean strategy selection references missing face geometry."
            )
        }
        let targetLift = try SurfaceParameterLoopLift(
            samples: intersection.samples.map {
                SurfaceParameter(
                    u: $0.uvPoint.targetU,
                    v: $0.uvPoint.targetV
                )
            },
            surface: targetSurface,
            tolerance: tolerance
        )
        if targetLift.isContractible == false {
            return true
        }
        let toolLift = try SurfaceParameterLoopLift(
            samples: intersection.samples.map {
                SurfaceParameter(
                    u: $0.uvPoint.toolU,
                    v: $0.uvPoint.toolV
                )
            },
            surface: toolSurface,
            tolerance: tolerance
        )
        return toolLift.isContractible == false
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        let wrapped = KernelError.wrapping(
            error,
            phase: .topology,
            tolerance: tolerance
        )
        return KernelError(
            phase: wrapped.phase,
            code: wrapped.code,
            featureID: wrapped.featureID,
            subshapeID: wrapped.subshapeID,
            residual: wrapped.residual,
            tolerance: wrapped.tolerance ?? tolerance,
            message: "Exact Boolean region materialization \(stage) failed: \(wrapped.message)"
        )
    }
}
