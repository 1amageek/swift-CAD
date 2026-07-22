import CADCore
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
        var hasCoincidentComponent = false
        var hasBoundaryContact = false
        for split in uvSplitGraph.splits {
            for component in split.components {
                switch component.geometry {
                case .transverseSegment, .trimmedCurve:
                    hasOpenComponent = true
                case .closedCurve:
                    hasClosedComponent = true
                case .tangent:
                    hasBoundaryContact = true
                case .coincident:
                    hasCoincidentComponent = true
                    hasBoundaryContact = true
                }
            }
        }
        let coincidenceResolution = hasCoincidentComponent
            ? try CoincidentBooleanFaceOwnershipResolver().resolve(
                operation: operation,
                uvSplitGraph: uvSplitGraph,
                model: model,
                tolerance: tolerance
            )
            : CoincidentBooleanFaceOwnershipResolver.Resolution(
                forcedActions: [:],
                partiallyCoincidentPairs: []
            )
        let coincidentArrangement = try CoincidentBooleanFaceArrangementBoundaryBuilder().build(
            operation: operation,
            pairs: coincidenceResolution.partiallyCoincidentPairs,
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )
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
        // The face arrangement consumes closed components as two exact half-edges
        // whenever any open component requires boundary-connected partitioning.
        // Closed-only evaluation retains its loop-less analytic-face path.
        if hasOpenComponent || hasCoincidentArrangement {
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
}
