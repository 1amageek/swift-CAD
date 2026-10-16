import HashTreeCollections
import CADCore
import CADGeometry

public struct DefaultBRepTopologyValidator: BRepTopologyValidating {
    private struct EdgeUseCount {
        var forward = 0
        var reversed = 0

        var total: Int { forward + reversed }

        mutating func record(_ orientation: Orientation) {
            switch orientation {
            case .forward:
                forward += 1
            case .reversed:
                reversed += 1
            }
        }
    }

    public init() {}

    public func report(for model: BRepModel, request: BRepValidationRequest,
        tolerance: ModelingTolerance) throws -> TopologyValidationReport {
        var execution = try BRepModel.originalValidationExecution()
        return try report(for: model, request: request, tolerance: tolerance, using: &execution)
    }

    public func report(
        for model: BRepModel,
        request: BRepValidationRequest,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> TopologyValidationReport {
        try execution.consumeWork(1)
        try request.validate(tolerance: tolerance, using: &execution)
        var result: [TopologyValidationDiagnostic] = []
        for scope in request.scopes {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf:  try diagnostics(
                for: scope,
                model: model,
                tolerance: tolerance, using: &execution
            ), to: &result, using: &execution)
        }
        return TopologyValidationReport(
            isValid: result.isEmpty,
            diagnostics: result
        )
    }

    private func diagnostics(
        for scope: TopologyValidationScope,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        return switch scope {
        case .references:
            try referenceDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .loops:
            try loopDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .pcurves:
            try pcurveDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .orientation:
            try orientationDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .manifold:
            try manifoldDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .watertight:
            try watertightDiagnostics(model: model, tolerance: tolerance, using: &execution)
        case .volume:
            try volumeDiagnostics(model: model, tolerance: tolerance, using: &execution)
        }
    }

    private func geometryKind(_ edge: Edge, model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        let limits = execution.effectiveLimits
        return try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: nil)
            .kind(of: edge, in: model, tolerance: tolerance, using: &execution)
    }

    private func referenceDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        var referencedShells = Set<ShellID>()
        var referencedFaces = Set<FaceID>()
        var referencedLoops = Set<LoopID>()
        var referencedEdges = Set<EdgeID>()
        var referencedVertices = Set<VertexID>()
        var referencedCurves = Set<CurveID>()
        var referencedSurfaces = Set<SurfaceID>()
        var shellOwners: [ShellID: Int] = [:]
        var faceOwners: [FaceID: Int] = [:]
        var loopOwners: [LoopID: Int] = [:]

        for (key, body) in try sorted(model.bodies, using: &execution) {
            try execution.consumeWork(1)
            if key != body.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Body table key does not match the stored body ID."
                ), to: &result, using: &execution)
            }
            try appendDuplicateDiagnostic(
                values: try body.originalShellIDs(using: &execution),
                ownerID: key,
                childLabel: "shell",
                result: &result, using: &execution
            )
            for shellID in try body.originalShellIDs(using: &execution) {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(shellID, in: &referencedShells, using: &execution)
                try OriginalParameterQueryStorage.set((shellOwners[shellID] ?? 0) + 1,
                    for: shellID, in: &shellOwners, using: &execution)
                if model.shells[shellID] == nil {
                    try OriginalParameterQueryStorage.append(missingReference(
                        ownerID: key,
                        message: "Body references missing shell \(shellID)."
                    ), to: &result, using: &execution)
                }
            }
        }

        for (key, shell) in try sorted(model.shells, using: &execution) {
            try execution.consumeWork(1)
            if key != shell.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Shell table key does not match the stored shell ID."
                ), to: &result, using: &execution)
            }
            try appendDuplicateDiagnostic(
                values: shell.faceIDs,
                ownerID: key,
                childLabel: "face",
                result: &result, using: &execution
            )
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(faceID, in: &referencedFaces, using: &execution)
                try OriginalParameterQueryStorage.set((faceOwners[faceID] ?? 0) + 1,
                    for: faceID, in: &faceOwners, using: &execution)
                if model.faces[faceID] == nil {
                    try OriginalParameterQueryStorage.append(missingReference(
                        ownerID: key,
                        message: "Shell references missing face \(faceID)."
                    ), to: &result, using: &execution)
                }
            }
        }

        for (key, face) in try sorted(model.faces, using: &execution) {
            try execution.consumeWork(1)
            if key != face.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Face table key does not match the stored face ID."
                ), to: &result, using: &execution)
            }
            if model.geometry.surfaces[face.surfaceID] == nil {
                try OriginalParameterQueryStorage.append(missingReference(
                    ownerID: key,
                    message: "Face references missing surface \(face.surfaceID)."
                ), to: &result, using: &execution)
            } else {
                try OriginalParameterQueryStorage.insert(face.surfaceID, in: &referencedSurfaces, using: &execution)
            }
            try appendDuplicateDiagnostic(
                values: face.loops,
                ownerID: key,
                childLabel: "loop",
                result: &result, using: &execution
            )
            for loopID in face.loops {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(loopID, in: &referencedLoops, using: &execution)
                try OriginalParameterQueryStorage.set((loopOwners[loopID] ?? 0) + 1,
                    for: loopID, in: &loopOwners, using: &execution)
                if model.loops[loopID] == nil {
                    try OriginalParameterQueryStorage.append(missingReference(
                        ownerID: key,
                        message: "Face references missing loop \(loopID)."
                    ), to: &result, using: &execution)
                }
            }
        }

        for (key, loop) in try sorted(model.loops, using: &execution) {
            try execution.consumeWork(1)
            if key != loop.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Loop table key does not match the stored loop ID."
                ), to: &result, using: &execution)
            }
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(coedge.edgeID, in: &referencedEdges, using: &execution)
                if model.edges[coedge.edgeID] == nil {
                    try OriginalParameterQueryStorage.append(missingReference(
                        ownerID: key,
                        message: "Loop references missing edge \(coedge.edgeID)."
                    ), to: &result, using: &execution)
                }
            }
        }

        for (key, edge) in try sorted(model.edges, using: &execution) {
            try execution.consumeWork(1)
            if key != edge.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Edge table key does not match the stored edge ID."
                ), to: &result, using: &execution)
            }
            try OriginalParameterQueryStorage.insert(edge.curveID, in: &referencedCurves, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &referencedVertices, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &referencedVertices, using: &execution)
            if try edge.startVertexID == edge.endVertexID && geometryKind(edge, model: model, tolerance: tolerance, using: &execution) == .open {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Edge start and end vertices must be distinct."
                ), to: &result, using: &execution)
            }
            if model.geometry.curves[edge.curveID] == nil {
                try OriginalParameterQueryStorage.append(missingReference(
                    ownerID: key,
                    message: "Edge references missing curve \(edge.curveID)."
                ), to: &result, using: &execution)
            }
            for vertexID in [edge.startVertexID, edge.endVertexID]
                where model.vertices[vertexID] == nil {
                    try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(missingReference(
                    ownerID: key,
                    message: "Edge references missing vertex \(vertexID)."
                ), to: &result, using: &execution)
            }
        }

        for (key, vertex) in try sorted(model.vertices, using: &execution) {
            try execution.consumeWork(1)
            if key != vertex.id {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Vertex table key does not match the stored vertex ID."
                ), to: &result, using: &execution)
            }
            do {
                try vertex.point.validate()
            } catch {
                _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .references,
                    code: .invalidInput,
                    entityID: key,
                    message: "Vertex contains an invalid coordinate: \(KernelError.wrapping(error, phase: .topology, tolerance: tolerance).message)."
                ), to: &result, using: &execution)
            }
        }

        try appendOwnershipDiagnostics(shellOwners, label: "shell", result: &result, using: &execution)
        try appendOwnershipDiagnostics(faceOwners, label: "face", result: &result, using: &execution)
        try appendOwnershipDiagnostics(loopOwners, label: "loop", result: &result, using: &execution)
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.shells.keys, using: &execution),
            referenced: referencedShells,
            label: "shell",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.faces.keys, using: &execution),
            referenced: referencedFaces,
            label: "face",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.loops.keys, using: &execution),
            referenced: referencedLoops,
            label: "loop",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.edges.keys, using: &execution),
            referenced: referencedEdges,
            label: "edge",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.vertices.keys, using: &execution),
            referenced: referencedVertices,
            label: "vertex",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.geometry.curves.keys, using: &execution),
            referenced: referencedCurves,
            label: "curve",
            result: &result, using: &execution
        )
        try appendUnreferencedDiagnostics(
            all: try originalSet(model.geometry.surfaces.keys, using: &execution),
            referenced: referencedSurfaces,
            label: "surface",
            result: &result, using: &execution
        )
        do {
            try model.geometry.validate(tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                maximumAlgebraicDepth: nil, using: &execution)
        } catch {
            let failure = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
            try OriginalParameterQueryStorage.append(diagnostic(scope: .references,
                code: failure.code, residual: failure.residual, message: failure.message),
                to: &result, using: &execution)
        }
        return result
    }

    private func loopDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        var surfacesByLoopID: [LoopID: Surface3D] = [:]
        for (faceID, face) in try sorted(model.faces, using: &execution) {
            try execution.consumeWork(1)
            var outerCount = 0
            for loopID in face.loops {
                try execution.consumeWork(1)
                if model.loops[loopID]?.role == .outer { outerCount += 1 }
            }
            if outerCount != 1 {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: faceID,
                    message: "A face requires exactly one outer loop; found \(outerCount)."
                ), to: &result, using: &execution)
            }
            if let surface = model.geometry.surfaces[face.surfaceID] {
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.set(surface, for: loopID, in: &surfacesByLoopID, using: &execution)
                }
            }
        }
        for (loopID, loop) in try sorted(model.loops, using: &execution) {
            try execution.consumeWork(1)
            guard loop.coedges.isEmpty == false else {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop has no coedges."
                ), to: &result, using: &execution)
                continue
            }
            var repeatedEdges = Set<EdgeID>()
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(coedge.edgeID, in: &repeatedEdges, using: &execution)
            }
            var validRepeatedUses = repeatedEdges.count == loop.coedges.count
            if !validRepeatedUses, let surface = surfacesByLoopID[loopID] {
                validRepeatedUses = try PeriodicFaceSeamValidator().certifiesRepeatedEdgeUses(
                    in: loop, on: surface, tolerance: tolerance,
                    maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumAlgebraicDepth: nil, using: &execution)
            }
            if !validRepeatedUses {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop contains repeated edge references that are not certified periodic seam uses."
                ), to: &result, using: &execution)
            }
            guard let first = orientedVertices(
                for: loop.coedges[0],
                model: model
            ) else {
                continue
            }
            var expected = first.end
            var isClosed = true
            for coedge in loop.coedges.dropFirst() {
                try execution.consumeWork(1)
                guard let vertices = orientedVertices(for: coedge, model: model),
                      vertices.start == expected else {
                    isClosed = false
                    break
                }
                expected = vertices.end
            }
            if isClosed == false || expected != first.start {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop coedges do not form a closed oriented chain."
                ), to: &result, using: &execution)
            }
        }
        return result
    }

    private func pcurveDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        for (faceID, face) in try sorted(model.faces, using: &execution) {
            try execution.consumeWork(1)
            guard let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    guard let pcurve = coedge.surfaceParameterCurve else {
                        try OriginalParameterQueryStorage.append(diagnostic(
                            scope: .pcurves,
                            code: .topologyFailure,
                            entityID: coedge.edgeID,
                            message: "Coedge on face \(faceID) has no face-local pcurve."
                        ), to: &result, using: &execution)
                        continue
                    }
                    do {
                        try pcurve.validate(on: surface, tolerance: tolerance,
                            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                            maximumAlgebraicDepth: nil, using: &execution)
                    } catch {
                        _ = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                        try OriginalParameterQueryStorage.append(diagnostic(
                            scope: .pcurves,
                            code: .topologyFailure,
                            entityID: coedge.edgeID,
                            message: "Face-local pcurve validation failed: \(KernelError.wrapping(error, phase: .topology, tolerance: tolerance).message)."
                        ), to: &result, using: &execution)
                    }
                }
            }
        }
        let prerequisites = try prerequisiteDiagnostics(model: model, tolerance: tolerance, using: &execution)
        if prerequisites.isEmpty, result.isEmpty {
            do {
                try model.validatePcurves(tolerance: tolerance, using: &execution)
            } catch {
                let failure = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                try OriginalParameterQueryStorage.append(diagnostic(scope: .pcurves,
                    code: failure.code, residual: failure.residual, message: failure.message),
                    to: &result, using: &execution)
            }
        }
        return result
    }

    private func orientationDiagnostics(model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        for (shellID, shell) in try sorted(model.shells, using: &execution) {
            try execution.consumeWork(1)
            for (edgeID, use) in try edgeUses(shell: shell, model: model, using: &execution)
                where use.total == 2 && (use.forward != 1 || use.reversed != 1) {
                    try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .orientation,
                    code: .topologyFailure,
                    entityID: edgeID,
                    message: "Shell \(shellID) uses a shared edge without opposite coedge orientations."
                ), to: &result, using: &execution)
            }
        }
        return result
    }

    private func manifoldDiagnostics(model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        let bodyKinds = try shellBodyKinds(model: model, using: &execution)
        for (shellID, shell) in try sorted(model.shells, using: &execution) {
            try execution.consumeWork(1)
            let kind = bodyKinds[shellID]
            for (edgeID, use) in try edgeUses(shell: shell, model: model, using: &execution) {
                try execution.consumeWork(1)
                let singular = try model.edges[edgeID].map { try geometryKind($0, model: model, tolerance: tolerance, using: &execution) == .singular } ?? false
                let valid = singular ? use.total == 1 : (kind == .sheet
                    ? use.total == 1 || use.total == 2
                    : use.total == 2)
                if valid == false {
                    try OriginalParameterQueryStorage.append(diagnostic(
                        scope: .manifold,
                        code: .nonManifoldResult,
                        entityID: edgeID,
                        message: "Shell \(shellID) uses edge \(use.total) times."
                    ), to: &result, using: &execution)
                }
            }
        }
        return result
    }

    private func watertightDiagnostics(model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var result: [TopologyValidationDiagnostic] = []
        for (bodyID, body) in try sorted(model.bodies, using: &execution) {
            try execution.consumeWork(1)
            if try body.originalShellIDs(using: &execution).isEmpty {
                try OriginalParameterQueryStorage.append(diagnostic(
                    scope: .watertight,
                    code: .topologyFailure,
                    entityID: bodyID,
                    message: "Body has no shells."
                ), to: &result, using: &execution)
            }
            guard body.kind == .solid else { continue }
            for shellID in try body.originalShellIDs(using: &execution) {
                try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else { continue }
                if shell.faceIDs.isEmpty {
                    try OriginalParameterQueryStorage.append(diagnostic(
                        scope: .watertight,
                        code: .topologyFailure,
                        entityID: shellID,
                        message: "Solid shell has no faces."
                    ), to: &result, using: &execution)
                }
                for (edgeID, use) in try edgeUses(shell: shell, model: model, using: &execution) {
                    try execution.consumeWork(1)
                    let singleSingular = try model.edges[edgeID].map {
                        try geometryKind($0, model: model, tolerance: tolerance, using: &execution) == .singular && use.total == 1
                    } ?? false
                    if use.total == 2 || singleSingular { continue }
                    try OriginalParameterQueryStorage.append(diagnostic(
                        scope: .watertight,
                        code: .topologyFailure,
                        entityID: edgeID,
                        message: "Solid shell boundary edge is not paired."
                    ), to: &result, using: &execution)
                }
            }
        }
        return result
    }

    private func volumeDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [TopologyValidationDiagnostic] {
        try execution.consumeWork(1)
        var hasSolid = false
        for body in model.bodies.values {
            try execution.consumeWork(1)
            if body.kind == .solid { hasSolid = true; break }
        }
        guard hasSolid else { return [] }
        let prerequisites = try prerequisiteDiagnostics(model: model, tolerance: tolerance, using: &execution)
        guard prerequisites.isEmpty else {
            return try findingArray(diagnostic(
                scope: .volume,
                code: .topologyFailure,
                message: "Volume validation requires valid references, loops, orientation, manifoldness, and watertightness."
            ), using: &execution)
        }
        do {
            _ = try model.volume(tolerance: tolerance, using: &execution)
            return []
        } catch {
            let failure = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
            return try findingArray(diagnostic(scope: .volume,
                code: failure.code, residual: failure.residual, message: failure.message), using: &execution)
        }
    }

    private func edgeUses(
        shell: Shell,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> [(key: EdgeID, value: EdgeUseCount)] {
        try execution.consumeWork(1)
        var uses: [EdgeID: EdgeUseCount] = [:]
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID] else { continue }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    var count = uses[coedge.edgeID] ?? EdgeUseCount()
                    count.record(coedge.orientation)
                    try OriginalParameterQueryStorage.set(count, for: coedge.edgeID, in: &uses, using: &execution)
                }
            }
        }
        return try ordered(uses, using: &execution) { describe($0.key) < describe($1.key) }
    }

    private func shellBodyKinds(model: BRepModel, using execution: inout OriginalQueryExecution) throws -> [ShellID: BodyKind] {
        try execution.consumeWork(1)
        var result: [ShellID: BodyKind] = [:]
        for (_, body) in try sorted(model.bodies, using: &execution) {
            try execution.consumeWork(1)
            for shellID in try body.originalShellIDs(using: &execution) where result[shellID] == nil {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.set(body.kind, for: shellID, in: &result, using: &execution)
            }
        }
        return result
    }

    private func orientedVertices(
        for coedge: Coedge,
        model: BRepModel
    ) -> (start: VertexID, end: VertexID)? {
        guard let edge = model.edges[coedge.edgeID] else { return nil }
        switch coedge.orientation {
        case .forward:
            return (edge.startVertexID, edge.endVertexID)
        case .reversed:
            return (edge.endVertexID, edge.startVertexID)
        }
    }

    private func appendDuplicateDiagnostic<ID: Hashable>(
        values: [ID],
        ownerID: some CustomStringConvertible,
        childLabel: String,
        result: inout [TopologyValidationDiagnostic], using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        if try originalSet(values, using: &execution).count != values.count {
            try OriginalParameterQueryStorage.append(diagnostic(
                scope: .references,
                code: .topologyFailure,
                entityID: ownerID,
                message: "Owner contains duplicate \(childLabel) references."
            ), to: &result, using: &execution)
        }
    }

    private func appendOwnershipDiagnostics<ID: Hashable & CustomStringConvertible>(
        _ owners: [ID: Int],
        label: String,
        result: inout [TopologyValidationDiagnostic], using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        for (id, count) in try ordered(owners, using: &execution, less: { describe($0.key) < describe($1.key) })
            where count != 1 {
            try OriginalParameterQueryStorage.append(diagnostic(
                scope: .references,
                code: .topologyFailure,
                entityID: id,
                message: "The \(label) has \(count) owners; exactly one is required."
            ), to: &result, using: &execution)
        }
    }

    private func appendUnreferencedDiagnostics<ID: Hashable & CustomStringConvertible>(
        all: Set<ID>,
        referenced: Set<ID>,
        label: String,
        result: inout [TopologyValidationDiagnostic], using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        for id in try ordered(all, using: &execution, less: { describe($0) < describe($1) }) where !referenced.contains(id) {
            try OriginalParameterQueryStorage.append(diagnostic(
                scope: .references,
                code: .missingReference,
                entityID: id,
                message: "Unreferenced \(label) remains in the B-rep table."
            ), to: &result, using: &execution)
        }
    }

    private func missingReference(
        ownerID: some CustomStringConvertible,
        message: String
    ) -> TopologyValidationDiagnostic {
        diagnostic(
            scope: .references,
            code: .missingReference,
            entityID: ownerID,
            message: message
        )
    }

    private func diagnostic(
        scope: TopologyValidationScope,
        code: KernelErrorCode,
        entityID: (some CustomStringConvertible)? = String?.none,
        residual: Double? = nil,
        message: String
    ) -> TopologyValidationDiagnostic {
        TopologyValidationDiagnostic(
            scope: scope,
            code: code,
            entityID: entityID.map(describe),
            residual: residual,
            message: message
        )
    }

    private func sorted<Key: Hashable & CustomStringConvertible, Value>(
        _ map: PersistentMap<Key, Value>, using execution: inout OriginalQueryExecution
    ) throws -> [(key: Key, value: Value)] {
        try execution.consumeWork(1)
        return try ordered(map, using: &execution) { describe($0.key) < describe($1.key) }
    }

    private func prerequisiteDiagnostics(model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        func append(_ scope: TopologyValidationScope, using execution: inout OriginalQueryExecution) throws {
            let findings = try diagnostics(for: scope, model: model, tolerance: tolerance, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: findings, to: &result, using: &execution)
        }
        try append(.references, using: &execution)
        try append(.loops, using: &execution)
        try append(.orientation, using: &execution)
        try append(.manifold, using: &execution)
        try append(.watertight, using: &execution)
        return result
    }

    private func findingArray(_ finding: TopologyValidationDiagnostic,
        using execution: inout OriginalQueryExecution) throws -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        try OriginalParameterQueryStorage.append(finding, to: &result, using: &execution)
        return result
    }

    private func ordered<S: Sequence>(_ source: S, using execution: inout OriginalQueryExecution,
        less: (S.Element, S.Element) -> Bool) throws -> [S.Element] {
        var result: [S.Element] = []
        for value in source {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(value, to: &result, using: &execution)
        }
        try OriginalParameterQueryStorage.sort(&result, using: &execution, less: less)
        return result
    }

    private func originalSet<S: Sequence>(_ source: S, using execution: inout OriginalQueryExecution)
        throws -> Set<S.Element> where S.Element: Hashable {
        var result = Set<S.Element>()
        for value in source {
            try OriginalParameterQueryStorage.insert(value, in: &result, using: &execution)
        }
        return result
    }

    private func describe(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}
