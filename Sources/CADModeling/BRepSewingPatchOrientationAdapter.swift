import CADCore
import CADIR
import CADTopology

package struct BRepSewingPatchOrientationAdapter {
    package init() {}

    package func reorient(
        _ patch: BRepSewingFacePatch,
        to orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        try tolerance.validate()
        guard patch.orientation != orientation else {
            return patch
        }
        let result = BRepSewingFacePatch(
            stableID: patch.stableID,
            surface: patch.surface,
            orientation: orientation,
            loops: try patch.loops.map { loop in
                BRepSewingLoop(
                    stableID: loop.stableID,
                    role: loop.role,
                    edges: try loop.edges.reversed().map { edge in
                        try reversed(edge, tolerance: tolerance)
                    }
                )
            },
            parentSubshapeIDs: patch.parentSubshapeIDs
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func reversed(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: edge.stableID,
            curve: edge.curve,
            startParameter: edge.endParameter,
            endParameter: edge.startParameter,
            startPoint: edge.endPoint,
            endPoint: edge.startPoint,
            surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(
                tolerance: tolerance
            ),
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs
        )
    }
}
