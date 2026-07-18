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
        for split in uvSplitGraph.splits {
            for component in split.components {
                switch component.geometry {
                case .transverseSegment, .trimmedCurve:
                    hasOpenComponent = true
                case .closedCurve:
                    hasClosedComponent = true
                case .tangent:
                    continue
                case .coincident:
                    throw unsupported(
                        "Coincident Boolean faces require explicit coincident-region ownership resolution.",
                        tolerance: tolerance
                    )
                }
            }
        }
        guard hasOpenComponent || hasClosedComponent else {
            throw unsupported(
                "Exact Boolean materialization requires at least one region-partitioning intersection component.",
                tolerance: tolerance
            )
        }
        // The face arrangement consumes closed components as two exact half-edges
        // whenever any open component requires boundary-connected partitioning.
        // Closed-only evaluation retains its loop-less analytic-face path.
        if hasOpenComponent {
            return try OpenIntersectionFacePatchMaterializer().materialize(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: featureID,
                model: model,
                sourceSubshapes: sourceSubshapes,
                uvSplitGraph: uvSplitGraph,
                regionSelectionGraph: regionSelectionGraph,
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
            tolerance: tolerance
        )
    }

    private func unsupported(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: message
        )
    }
}
