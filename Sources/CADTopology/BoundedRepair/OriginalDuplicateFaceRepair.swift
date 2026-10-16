import HashTreeCollections
import CADCore
import CADGeometry

/// Removes redundant original oriented face occurrences within one shell.
struct OriginalDuplicateFaceRepair {
    private let maximumSubdivisionDepth: Int
    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int?

    init(maximumSubdivisionDepth:Int=32,remainingSourceDepth:Int=16,
        maximumAlgebraicDepth:Int?=nil) {
        self.maximumSubdivisionDepth=maximumSubdivisionDepth
        self.remainingSourceDepth=remainingSourceDepth
        self.maximumAlgebraicDepth=maximumAlgebraicDepth
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

    func repair(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange]) throws {
        var execution = try BRepModel.originalValidationExecution()
        try repair(model: &model, tolerance: tolerance, changes: &changes, using: &execution)
    }

    func repair(model: inout BRepModel, tolerance:ModelingTolerance,
        changes: inout [BRepRepairChange], using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        guard (0...32).contains(maximumSubdivisionDepth),(0...16).contains(remainingSourceDepth),
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original duplicate-face proof capabilities are invalid.")
        }
        let original = model
        var removed = Set<FaceID>()
        var shellIDs = try OriginalParameterQueryStorage.map(original.shells.keys, using: &execution) { id, execution in id }
        try OriginalParameterQueryStorage.sort(&shellIDs, using: &execution, less: <)
        for shellID in shellIDs {
            try execution.consumeWork(1)
            guard var shell = model.shells[shellID] else { continue }
            var retained: [FaceID] = []
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                var duplicate = false
                for owner in retained {
                    try execution.consumeWork(1)
                    if try owner == faceID || equalFaces(owner, faceID, model: original,
                        tolerance: tolerance, using: &execution) { duplicate = true; break }
                }
                if duplicate { try OriginalParameterQueryStorage.insert(faceID, in: &removed, using: &execution) }
                else { try OriginalParameterQueryStorage.append(faceID, to: &retained, using: &execution) }
            }
            shell.faceIDs = retained
            try execution.retainStorage(bytes: MemoryLayout<(ShellID, Shell)>.stride)
            model.shells[shellID] = shell
        }
        guard !removed.isEmpty else { return }
        var referencedFaces = Set<FaceID>()
        for shell in model.shells.values {
            try execution.consumeWork(1)
            for id in shell.faceIDs { try OriginalParameterQueryStorage.insert(id, in: &referencedFaces, using: &execution) }
        }
        var deleted = Set<FaceID>()
        var candidateLoops = Set<LoopID>()
        var candidateSurfaces = Set<SurfaceID>()
        for id in removed where !referencedFaces.contains(id) {
            try OriginalParameterQueryStorage.insert(id, in: &deleted, using: &execution)
            if let face = original.faces[id] {
                try OriginalParameterQueryStorage.insert(face.surfaceID, in: &candidateSurfaces, using: &execution)
                for loopID in face.loops { try OriginalParameterQueryStorage.insert(loopID, in: &candidateLoops, using: &execution) }
            }
        }
        var candidateEdges = Set<EdgeID>()
        for id in candidateLoops {
            try execution.consumeWork(1)
            if let loop = original.loops[id] {
                for use in loop.coedges { try OriginalParameterQueryStorage.insert(use.edgeID, in: &candidateEdges, using: &execution) }
            }
        }
        var candidateVertices = Set<VertexID>()
        var candidateCurves = Set<CurveID>()
        for id in candidateEdges {
            try execution.consumeWork(1)
            if let edge = original.edges[id] {
                try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &candidateVertices, using: &execution)
                try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &candidateVertices, using: &execution)
                try OriginalParameterQueryStorage.insert(edge.curveID, in: &candidateCurves, using: &execution)
            }
        }
        for id in deleted { try execution.consumeWork(1); model.faces[id] = nil }
        var referencedLoops = Set<LoopID>()
        for face in model.faces.values {
            try execution.consumeWork(1)
            for id in face.loops { try OriginalParameterQueryStorage.insert(id, in: &referencedLoops, using: &execution) }
        }
        for id in candidateLoops where !referencedLoops.contains(id) { try execution.consumeWork(1); model.loops[id] = nil }
        var referencedEdges = Set<EdgeID>()
        for loop in model.loops.values {
            try execution.consumeWork(1)
            for use in loop.coedges { try OriginalParameterQueryStorage.insert(use.edgeID, in: &referencedEdges, using: &execution) }
        }
        for id in candidateEdges where !referencedEdges.contains(id) { try execution.consumeWork(1); model.edges[id] = nil }
        var referencedVertices = Set<VertexID>()
        var referencedCurves = Set<CurveID>()
        for edge in model.edges.values {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &referencedVertices, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &referencedVertices, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.curveID, in: &referencedCurves, using: &execution)
        }
        for id in candidateVertices where !referencedVertices.contains(id) { try execution.consumeWork(1); model.vertices[id] = nil }
        for id in candidateCurves where !referencedCurves.contains(id) { try execution.consumeWork(1); model.geometry.curves[id] = nil }
        var referencedSurfaces = Set<SurfaceID>()
        for face in model.faces.values { try OriginalParameterQueryStorage.insert(face.surfaceID, in: &referencedSurfaces, using: &execution) }
        for id in candidateSurfaces where !referencedSurfaces.contains(id) { try execution.consumeWork(1); model.geometry.surfaces[id] = nil }
        let affected = try auditIDs(removed, using: &execution)
        let deletedIDs = try auditIDs(deleted, using: &execution)
        try OriginalParameterQueryStorage.append(.init(action: .removeDuplicateFaces, scope: .manifold,
            affectedEntityIDs: affected,
            message: "Removed exact duplicate oriented source faces within their original shells and their newly orphaned descendants.",
            deletedEntityIDs: deletedIDs), to: &changes, using: &execution)
    }

    private func auditIDs<IDs: Sequence>(_ ids: IDs, using execution: inout OriginalQueryExecution) throws -> [String]
        where IDs.Element: Comparable & CustomStringConvertible {
        var ordered = try OriginalParameterQueryStorage.map(ids, using: &execution) { id, execution in id }
        try OriginalParameterQueryStorage.sort(&ordered, using: &execution, less: <)
        return try OriginalParameterQueryStorage.map(ordered, using: &execution) { id, execution in id.description }
    }

    private func equalFaces(_ firstID: FaceID, _ secondID: FaceID, model: BRepModel,tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard let first = model.faces[firstID], let second = model.faces[secondID],
            first.orientation == second.orientation,
            let firstSurface = model.geometry.surfaces[first.surfaceID],
            let secondSurface = model.geometry.surfaces[second.surfaceID],
            first.loops.count == second.loops.count, !first.loops.isEmpty else { return false }
        try GeometryStructuralComparisonWork.charge(surface: firstSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: secondSurface, using: &execution)
        guard firstSurface == secondSurface else { return false }
        let a = try sources(first, model: model, using: &execution), b = try sources(second, model: model, using: &execution)
        guard a.count == first.loops.count, b.count == second.loops.count else { return false }
        var matched = Set<Int>()
        for loop in a {
            try execution.consumeWork(1)
            var match: Int?
            for index in b.indices where !matched.contains(index) {
                if loop.role == b[index].role, try sameCycle(loop.uses,b[index].uses,on:firstSurface,tolerance:tolerance, using: &execution) { match = index; break }
            }
            guard let match else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public duplicate-face repair still
                // requires exact original chart correspondence for geometrically equal
                // supports/trims authored with different laws. This source-equality path
                // cannot establish the complete equivalent-chart repair domain.
                return false
            }
            try OriginalParameterQueryStorage.insert(match, in: &matched, using: &execution)
        }
        return true
    }

    private func sources(_ face: Face, model: BRepModel, using execution: inout OriginalQueryExecution) throws -> [LoopSource] {
        var result: [LoopSource] = []
        for id in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[id], !loop.coedges.isEmpty else { return [] }
            var uses: [UseSource] = []
            for use in loop.coedges {
                try execution.consumeWork(1)
                guard let edge = model.edges[use.edgeID], let curve = model.geometry.curves[edge.curveID],
                    let start = model.vertices[edge.startVertexID]?.point,
                    let end = model.vertices[edge.endVertexID]?.point,
                    let pcurve = use.surfaceParameterCurve else { return [] }
                try OriginalParameterQueryStorage.append(.init(curve: curve, trim: edge.trim, orientation: use.orientation,
                    start: start, end: end, pcurve: pcurve), to: &uses, using: &execution)
            }
            try OriginalParameterQueryStorage.append(.init(role: loop.role, uses: uses), to: &result, using: &execution)
        }
        return result
    }

    private func sameCycle(_ first: [UseSource], _ second: [UseSource],on surface:Surface3D,tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard !first.isEmpty, first.count == second.count else { return false }
        for offset in second.indices {
            try execution.consumeWork(1)
            var equal = true
            for index in first.indices {
                try execution.consumeWork(1)
                let a=first[index],b=second[(index + offset) % second.count]
                try GeometryStructuralComparisonWork.charge(curve: a.curve, using: &execution)
                try GeometryStructuralComparisonWork.charge(curve: b.curve, using: &execution)
                try GeometryStructuralComparisonWork.charge(parameterCurve: a.pcurve, using: &execution)
                try GeometryStructuralComparisonWork.charge(parameterCurve: b.pcurve, using: &execution)
                guard a.curve==b.curve,a.trim==b.trim,a.orientation==b.orientation,
                    a.start==b.start,a.end==b.end else { equal=false; break }
                if a.pcurve != b.pcurve,
                    !(try OriginalPeriodicSeamProof.proves(first:a.pcurve,second:b.pcurve,
                        on:surface,tolerance:tolerance,remainingSourceDepth:remainingSourceDepth,
                        maximumSubdivisionDepth:maximumSubdivisionDepth,maximumAlgebraicDepth:maximumAlgebraicDepth,
                        secondIsReversed:false,using:&execution)) { equal=false; break }
            }
            if equal { return true }
        }
        return false
    }
}
