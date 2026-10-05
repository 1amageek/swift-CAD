import CADCore
import CADGeometry

/// Removes redundant original oriented face occurrences within one shell.
struct OriginalDuplicateFaceRepair {
    private let maximumSubdivisionDepth: Int
    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int?
    private let consumeWork: @Sendable (Int) throws -> Void
    private let consumeStorage: (@Sendable (Int) throws -> Void)?

    init(maximumSubdivisionDepth:Int=32,remainingSourceDepth:Int=16,
        maximumAlgebraicDepth:Int?=nil,
        consumeWork:@escaping @Sendable(Int)throws->Void={ _ in try Task.checkCancellation() },
        consumeStorage:(@Sendable(Int)throws->Void)?=nil) {
        self.maximumSubdivisionDepth=maximumSubdivisionDepth
        self.remainingSourceDepth=remainingSourceDepth
        self.maximumAlgebraicDepth=maximumAlgebraicDepth
        self.consumeWork=consumeWork; self.consumeStorage=consumeStorage
    }
    private struct UseSource: Equatable {
        let curve: Curve3D
        let trim: CurveTrim?
        let orientation: Orientation
        let start: Point3D
        let end: Point3D
        let pcurve: SurfaceParameterCurve
    }
    private struct LoopSource {
        let role: LoopRole
        let uses: [UseSource]
    }

    func repair(model: inout BRepModel, tolerance:ModelingTolerance,
        changes: inout [BRepRepairChange]) throws {
        try tolerance.validate()
        guard (0...32).contains(maximumSubdivisionDepth),(0...16).contains(remainingSourceDepth),
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original duplicate-face proof capabilities are invalid.")
        }
        let original = model
        var removed = Set<FaceID>()
        for shellID in original.shells.keys.sorted() {
            try Task.checkCancellation(); try consumeWork(0)
            guard var shell = model.shells[shellID] else { continue }
            var retained: [FaceID] = []
            for faceID in shell.faceIDs {
                try Task.checkCancellation(); try consumeWork(0)
                var duplicate = false
                for owner in retained {
                    try Task.checkCancellation(); try consumeWork(0)
                    if try owner == faceID || equalFaces(owner, faceID, model: original,tolerance:tolerance) { duplicate = true; break }
                }
                if duplicate { removed.insert(faceID) }
                else { retained.append(faceID) }
            }
            shell.faceIDs = retained
            model.shells[shellID] = shell
        }
        guard !removed.isEmpty else { return }
        let referencedFaces = Set(model.shells.values.flatMap(\.faceIDs))
        let deleted = removed.subtracting(referencedFaces)
        let candidateLoops = Set(deleted.flatMap { original.faces[$0]?.loops ?? [] })
        let candidateEdges = Set(candidateLoops.flatMap { original.loops[$0]?.coedges.map(\.edgeID) ?? [] })
        let candidateVertices = Set(candidateEdges.flatMap { id -> [VertexID] in
            guard let edge = original.edges[id] else { return [] }
            return [edge.startVertexID, edge.endVertexID]
        })
        let candidateCurves = Set(candidateEdges.compactMap { original.edges[$0]?.curveID })
        let candidateSurfaces = Set(deleted.compactMap { original.faces[$0]?.surfaceID })
        for id in deleted { try Task.checkCancellation(); try consumeWork(0); model.faces[id] = nil }
        let referencedLoops = Set(model.faces.values.flatMap(\.loops))
        for id in candidateLoops where !referencedLoops.contains(id) { try Task.checkCancellation(); try consumeWork(0); model.loops[id] = nil }
        let referencedEdges = Set(model.loops.values.flatMap { $0.coedges.map(\.edgeID) })
        for id in candidateEdges where !referencedEdges.contains(id) { try Task.checkCancellation(); try consumeWork(0); model.edges[id] = nil }
        let referencedVertices = Set(model.edges.values.flatMap { [$0.startVertexID, $0.endVertexID] })
        for id in candidateVertices where !referencedVertices.contains(id) { try Task.checkCancellation(); try consumeWork(0); model.vertices[id] = nil }
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        for id in candidateCurves where !referencedCurves.contains(id) { try Task.checkCancellation(); try consumeWork(0); model.geometry.curves[id] = nil }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        for id in candidateSurfaces where !referencedSurfaces.contains(id) { try Task.checkCancellation(); try consumeWork(0); model.geometry.surfaces[id] = nil }
        changes.append(.init(action: .removeDuplicateFaces, scope: .manifold,
            affectedEntityIDs: removed.sorted().map { String(describing: $0) },
            message: "Removed exact duplicate oriented source faces within their original shells and their newly orphaned descendants.",
            deletedEntityIDs: deleted.sorted().map { String(describing: $0) }))
    }

    private func equalFaces(_ firstID: FaceID, _ secondID: FaceID, model: BRepModel,tolerance:ModelingTolerance) throws -> Bool {
        guard let first = model.faces[firstID], let second = model.faces[secondID],
            first.orientation == second.orientation,
            let firstSurface = model.geometry.surfaces[first.surfaceID],
            let secondSurface = model.geometry.surfaces[second.surfaceID],
            firstSurface == secondSurface, first.loops.count == second.loops.count,
            !first.loops.isEmpty else { return false }
        let a = try sources(first, model: model), b = try sources(second, model: model)
        guard a.count == first.loops.count, b.count == second.loops.count else { return false }
        var matched = Set<Int>()
        for loop in a {
            try Task.checkCancellation(); try consumeWork(0)
            var match: Int?
            for index in b.indices where !matched.contains(index) {
                if loop.role == b[index].role, try sameCycle(loop.uses,b[index].uses,on:firstSurface,tolerance:tolerance) { match = index; break }
            }
            guard let match else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public duplicate-face repair still
                // requires exact original chart correspondence for geometrically equal
                // supports/trims authored with different laws. This source-equality path
                // cannot establish the complete equivalent-chart repair domain.
                return false
            }
            matched.insert(match)
        }
        return true
    }

    private func sources(_ face: Face, model: BRepModel) throws -> [LoopSource] {
        var result: [LoopSource] = []
        for id in face.loops {
            try Task.checkCancellation(); try consumeWork(0)
            guard let loop = model.loops[id], !loop.coedges.isEmpty else { return [] }
            var uses: [UseSource] = []
            for use in loop.coedges {
                try Task.checkCancellation(); try consumeWork(0)
                guard let edge = model.edges[use.edgeID], let curve = model.geometry.curves[edge.curveID],
                    let start = model.vertices[edge.startVertexID]?.point,
                    let end = model.vertices[edge.endVertexID]?.point,
                    let pcurve = use.surfaceParameterCurve else { return [] }
                uses.append(.init(curve: curve, trim: edge.trim, orientation: use.orientation,
                    start: start, end: end, pcurve: pcurve))
            }
            result.append(.init(role: loop.role, uses: uses))
        }
        return result
    }

    private func sameCycle(_ first: [UseSource], _ second: [UseSource],on surface:Surface3D,tolerance:ModelingTolerance) throws -> Bool {
        guard !first.isEmpty, first.count == second.count else { return false }
        for offset in second.indices {
            try Task.checkCancellation(); try consumeWork(0)
            var equal = true
            for index in first.indices {
                try Task.checkCancellation(); try consumeWork(0)
                let a=first[index],b=second[(index + offset) % second.count]
                guard a.curve==b.curve,a.trim==b.trim,a.orientation==b.orientation,
                    a.start==b.start,a.end==b.end else { equal=false; break }
                if a.pcurve != b.pcurve,
                    !(try OriginalPeriodicSeamProof.proves(first:a.pcurve,second:b.pcurve,
                        on:surface,tolerance:tolerance,remainingSourceDepth:remainingSourceDepth,
                        maximumSubdivisionDepth:maximumSubdivisionDepth,consumeWork:consumeWork,
                        consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth,
                        secondIsReversed:false)) { equal=false; break }
            }
            if equal { return true }
        }
        return false
    }
}
