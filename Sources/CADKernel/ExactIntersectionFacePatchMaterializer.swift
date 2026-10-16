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
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.consumeWork(1)
        var hasOpenComponent = false
        var hasClosedComponent = false
        var requiresPeriodicArrangement = false
        var hasCoincidentComponent = false
        var hasBoundaryContact = false
        for split in uvSplitGraph.splits {
            try execution.consumeWork(1)
            for component in split.components {
            try execution.consumeWork(1)
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
                    , using: &execution) {
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
                    operands: operands,
                    tolerance: tolerance
                , using: &execution)
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
                operands: operands,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "coincident face arrangement",
                tolerance: tolerance
            )
        }
        var coincidentFaceActions = coincidenceResolution.forcedActions
        for (faceID, action) in coincidentArrangement.constantActions {
            try execution.consumeWork(1)
            guard coincidentFaceActions[faceID].map({ $0 != action }) != true else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Coincident Boolean ownership assigned conflicting actions to one face."
                )
            }
            try OriginalParameterQueryStorage.set(action, for: faceID, in: &coincidentFaceActions, using: &execution)
        }
        let hasCoincidentArrangement = coincidentArrangement.boundaries.contains(where: \.isPartitioning)
        let hasCoincidentFaceSelection = !coincidentFaceActions.isEmpty
        guard hasOpenComponent || hasClosedComponent || hasCoincidentArrangement
            || hasCoincidentFaceSelection else {
            return try WholeBodyBooleanFacePatchMaterializer().materialize(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: featureID,
                model: model,
                sourceSubshapes: sourceSubshapes,
                hasBoundaryContact: hasBoundaryContact,
                operands: operands,
                tolerance: tolerance
            , using: &execution)
        }
        // Component topology selects the exact partitioning strategy. Closed
        // loops use a containment tree so implicit intersection curves are not
        // resampled and intersected as a general half-edge network. Any open
        // or coincident partition requires the complete face arrangement,
        // which also consumes closed components when the strategies are mixed.
        if hasOpenComponent || requiresPeriodicArrangement
            || hasCoincidentArrangement || hasCoincidentFaceSelection {
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
                operands: operands,
                tolerance: tolerance
            , using: &execution)
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
            operands: operands,
            tolerance: tolerance
        , using: &execution)
    }

    private func isNonContractible(
        _ intersection: BooleanClosedFaceIntersection,
        facePair: BooleanFacePairCandidate,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
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
            samples: try OriginalParameterQueryStorage.map(intersection.samples, using: &execution) { sample, execution in
                SurfaceParameter(
                    u: sample.uvPoint.targetU,
                    v: sample.uvPoint.targetV
                )
            },
            surface: targetSurface,
            tolerance: tolerance
        , using: &execution)
        if targetLift.isContractible == false {
            return true
        }
        let toolLift = try SurfaceParameterLoopLift(
            samples: try OriginalParameterQueryStorage.map(intersection.samples, using: &execution) { sample, execution in
                SurfaceParameter(
                    u: sample.uvPoint.toolU,
                    v: sample.uvPoint.toolV
                )
            },
            surface: toolSurface,
            tolerance: tolerance
        , using: &execution)
        return toolLift.isContractible == false
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> any Error {
        let wrapped = KernelError.wrapping(error, phase: .topology, tolerance: tolerance)
        let classification = KernelError(
            phase: wrapped.phase,
            code: wrapped.code,
            featureID: wrapped.featureID,
            subshapeID: wrapped.subshapeID,
            residual: wrapped.residual,
            tolerance: wrapped.tolerance ?? tolerance,
            message: "Exact Boolean region materialization \(stage) failed: \(wrapped.message)"
        )
        return OriginalQueryFailure.contextualizing(error, classification: classification)
    }
}
