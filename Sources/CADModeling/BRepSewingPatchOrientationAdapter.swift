import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct BRepSewingPatchOrientationAdapter {
    package init() {}

    package func reorient(
        _ patch: BRepSewingFacePatch,
        to orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try reorient(patch, to: orientation, tolerance: tolerance, using: &execution)
    }

    package func reversed(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try reversed(edge, tolerance: tolerance, using: &execution)
    }

    package func reorient(
        _ patch: BRepSewingFacePatch,
        to orientation: Orientation,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard patch.orientation != orientation else {
            return patch
        }
        try execution.retainStorage(count: patch.loops.count, stride: MemoryLayout<BRepSewingLoop>.stride)
        for loop in patch.loops {
            try execution.consumeWork(1); try execution.retainStorage(count: loop.edges.count, stride: MemoryLayout<BRepSewingEdge>.stride) }
        let result = try BRepSewingFacePatch(
            stableID: patch.stableID,
            surface: patch.surface,
            orientation: orientation,
            loops: try patch.loops.map { loop in
                BRepSewingLoop(
                    stableID: loop.stableID,
                    role: loop.role,
                    edges: try loop.edges.reversed().map { edge in
                        try reversed(edge, tolerance: tolerance, using: &execution)
                    }
                )
            },
            parentSubshapeIDs: patch.parentSubshapeIDs, using: &execution
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    package func reversed(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
        return try BRepSewingEdge(
            stableID: edge.stableID,
            curve: edge.curve,
            startParameter: edge.endParameter,
            endParameter: edge.startParameter,
            startPoint: edge.endPoint,
            endPoint: edge.startPoint,
            surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(
                tolerance: tolerance
            , using: &execution),
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs, using: &execution
        )
    }
}
