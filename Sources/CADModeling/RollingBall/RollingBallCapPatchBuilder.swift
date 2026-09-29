import CADCore
import CADGeometry

// FIXME(INCOMPLETE_IMPLEMENTATION): Only machining tests currently consume this
// builder. Global intersection, closed-solid and lineage admission are required
// before these boundaries may be published by a fillet feature.
package struct RollingBallCapPatchBuilder {
    package init() {}

    package func build(
        source: BRepSewingFacePatch,
        replacing replacements: [String: BRepSewingEdge],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        try source.validate(tolerance: tolerance)
        guard !replacements.isEmpty else { throw invalid(tolerance, "A cap treatment requires replacement rails.") }
        let affected = source.loops.indices.filter { index in
            source.loops[index].edges.contains { replacements[$0.stableID] != nil }
        }
        guard affected.count == 1, let loopIndex = affected.first else {
            throw invalid(tolerance, "A cap treatment must identify exactly one source loop.")
        }
        let loop = source.loops[loopIndex]
        let mask = loop.edges.map { replacements[$0.stableID] != nil }
        guard mask.filter({ $0 }).count == replacements.count else {
            throw invalid(tolerance, "A cap replacement references an unknown or repeated source edge.")
        }
        var edges = try loop.edges.map { original in
            guard let edge = replacements[original.stableID] else { return original }
            guard case .surfaceLift(let lift) = edge.curve, lift.surface == source.surface else {
                throw invalid(tolerance, "A cap rail must retain its exact source support.")
            }
            let span = try lift.parameterCurve.subcurve(
                fromNormalizedFraction: min(edge.startParameter, edge.endParameter),
                toNormalizedFraction: max(edge.startParameter, edge.endParameter), tolerance: tolerance)
            let parameters = try edge.startParameter < edge.endParameter
                ? span : span.reversed(tolerance: tolerance)
            return BRepSewingEdge(stableID: original.stableID, curve: edge.curve,
                startParameter: edge.startParameter, endParameter: edge.endParameter,
                startPoint: edge.startPoint, endPoint: edge.endPoint,
                surfaceParameterCurve: parameters,
                parentSubshapeIDs: original.parentSubshapeIDs + edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        if replacements.count != edges.count {
            let starts = edges.indices.filter { mask[$0] && !mask[($0 + edges.count - 1) % edges.count] }
            guard starts.count == 1, let start = starts.first else {
                throw invalid(tolerance, "Cap replacement rails must form one contiguous cyclic chain.")
            }
            var end = start
            while mask[(end + 1) % edges.count] { end = (end + 1) % edges.count }
            let before = (start + edges.count - 1) % edges.count
            let after = (end + 1) % edges.count
            for index in Set([before, after]) {
                let original = loop.edges[index]
                let first = index == after ? edges[end].endPoint : original.startPoint
                let last = index == before ? edges[start].startPoint : original.endPoint
                let pieces = try BRepSewingEdgeSubdivider().subdivide(original,
                    at: [first, last], tolerance: tolerance)
                let retained = pieces.filter {
                    ($0.startPoint - first).length <= tolerance.distance
                        && ($0.endPoint - last).length <= tolerance.distance
                }
                guard retained.count == 1, let piece = retained.first else {
                    throw invalid(tolerance, "Cap contacts do not identify one retained neighboring edge segment.")
                }
                edges[index] = BRepSewingEdge(stableID: piece.stableID, curve: piece.curve,
                    startParameter: piece.startParameter, endParameter: piece.endParameter,
                    startPoint: first, endPoint: last, surfaceParameterCurve: piece.surfaceParameterCurve,
                    parentSubshapeIDs: piece.parentSubshapeIDs,
                    startVertexParentSubshapeIDs: piece.startVertexParentSubshapeIDs,
                    endVertexParentSubshapeIDs: piece.endVertexParentSubshapeIDs)
            }
        }
        var loops = source.loops
        loops[loopIndex] = BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)
        let result = BRepSewingFacePatch(stableID: source.stableID, surface: source.surface,
            orientation: source.orientation, loops: loops, parentSubshapeIDs: source.parentSubshapeIDs)
        try result.validate(tolerance: tolerance)
        return result
    }

    private func invalid(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
