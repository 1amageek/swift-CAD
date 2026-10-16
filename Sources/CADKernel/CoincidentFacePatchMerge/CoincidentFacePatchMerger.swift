import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Removes duplicate arranged regions, retaining complete boundary provenance.
struct CoincidentFacePatchMerger {
    func merge(_ patches: [BRepSewingFacePatch], tolerance: ModelingTolerance) throws -> [BRepSewingFacePatch] {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try merge(patches, tolerance: tolerance, using: &execution)
    }

    func merge(_ patches: [BRepSewingFacePatch], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        var kept: [BRepSewingFacePatch] = []
        try execution.retainKernelValues(count: patches.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
        for patch in patches.sorted(by: { $0.stableID < $1.stableID }) {
            var merged = false
            for index in kept.indices {
                guard let correspondence = try correspondingLoops(kept[index], patch, tolerance: tolerance, using: &execution) else { continue }
                let original = kept[index]
                let loops = original.loops.enumerated().map { ordinal, loop in
                    let other = patch.loops[correspondence[ordinal].loop]
                    return BRepSewingLoop(stableID: loop.stableID, role: loop.role,
                        edges: loop.edges.enumerated().map { edgeOrdinal, edge in
                            let matching = other.edges[correspondence[ordinal].edges[edgeOrdinal]]
                            let sameDirection = (edge.startPoint - matching.startPoint).length <= tolerance.distance
                            return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve,
                                startParameter: edge.startParameter, endParameter: edge.endParameter,
                                startPoint: edge.startPoint, endPoint: edge.endPoint,
                                surfaceParameterCurve: edge.surfaceParameterCurve,
                                parentSubshapeIDs: edge.parentSubshapeIDs + matching.parentSubshapeIDs,
                                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs +
                                    (sameDirection ? matching.startVertexParentSubshapeIDs : matching.endVertexParentSubshapeIDs),
                                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs +
                                    (sameDirection ? matching.endVertexParentSubshapeIDs : matching.startVertexParentSubshapeIDs))
                        })
                }
                kept[index] = BRepSewingFacePatch(stableID: original.stableID, surface: original.surface,
                    orientation: original.orientation, loops: loops,
                    parentSubshapeIDs: original.parentSubshapeIDs + patch.parentSubshapeIDs)
                merged = true
                break
            }
            if !merged { try OriginalParameterQueryStorage.append(patch, to: &kept, using: &execution) }
        }
        return kept
    }

    private func correspondingLoops(_ first: BRepSewingFacePatch, _ second: BRepSewingFacePatch,
                                    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [(loop: Int, edges: [Int])]? {
        guard first.loops.count == second.loops.count else { return nil }
        var usedLoops = Set<Int>()
        var correspondence: [(loop: Int, edges: [Int])] = []
        for loop in first.loops {
            var match: (loop: Int, edges: [Int])?
            for index in second.loops.indices where !usedLoops.contains(index) {
                let other = second.loops[index]
                guard loop.role == other.role, loop.edges.count == other.edges.count else { continue }
                var usedEdges = Set<Int>()
                var matchedEdges: [Int] = []
                for edge in loop.edges {
                    var edgeMatch: Int?
                    for edgeIndex in other.edges.indices where !usedEdges.contains(edgeIndex) {
                        if try sameTrim(edge, other.edges[edgeIndex], tolerance: tolerance, using: &execution) {
                            edgeMatch = edgeIndex
                            break
                        }
                    }
                    guard let edgeMatch else { break }
                    try OriginalParameterQueryStorage.insert(edgeMatch, in: &usedEdges, using: &execution)
                    try OriginalParameterQueryStorage.append(edgeMatch, to: &matchedEdges, using: &execution)
                }
                if matchedEdges.count == loop.edges.count { match = (index, matchedEdges); break }
            }
            guard let match else { return nil }
            try OriginalParameterQueryStorage.insert(match.loop, in: &usedLoops, using: &execution)
            try OriginalParameterQueryStorage.append(match, to: &correspondence, using: &execution)
        }
        if first.surface != second.surface {
            guard try DefaultSurfaceSurfaceIntersector().intersections(first: first.surface, second: second.surface, options: .init(),
                tolerance: tolerance, using: &execution).contains(where: { if case .coincident = $0 { return true }; return false }) else { return nil }
        }
        return correspondence
    }

    private func sameTrim(_ first: BRepSewingEdge, _ second: BRepSewingEdge,
                          tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        let same = (first.startPoint - second.startPoint).length <= tolerance.distance &&
            (first.endPoint - second.endPoint).length <= tolerance.distance
        let reversed = (first.startPoint - second.endPoint).length <= tolerance.distance &&
            (first.endPoint - second.startPoint).length <= tolerance.distance
        guard same || reversed else { return false }
        if case .coincident = try ExactTrimEdgeIntersector().intersections(first, second, tolerance: tolerance, using: &execution) { return true }
        return false
    }
}
