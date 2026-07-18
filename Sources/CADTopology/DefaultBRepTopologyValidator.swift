import CADCore

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

    public func report(
        for model: BRepModel,
        request: BRepValidationRequest,
        tolerance: ModelingTolerance
    ) throws -> TopologyValidationReport {
        try request.validate(tolerance: tolerance)
        var result: [TopologyValidationDiagnostic] = []
        for scope in request.scopes {
            result.append(contentsOf: diagnostics(
                for: scope,
                model: model,
                tolerance: tolerance
            ))
        }
        return TopologyValidationReport(
            isValid: result.isEmpty,
            diagnostics: result
        )
    }

    private func diagnostics(
        for scope: TopologyValidationScope,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) -> [TopologyValidationDiagnostic] {
        switch scope {
        case .references:
            referenceDiagnostics(model: model, tolerance: tolerance)
        case .loops:
            loopDiagnostics(model: model)
        case .pcurves:
            pcurveDiagnostics(model: model, tolerance: tolerance)
        case .orientation:
            orientationDiagnostics(model: model)
        case .manifold:
            manifoldDiagnostics(model: model)
        case .watertight:
            watertightDiagnostics(model: model)
        case .volume:
            volumeDiagnostics(model: model, tolerance: tolerance)
        }
    }

    private func referenceDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance
    ) -> [TopologyValidationDiagnostic] {
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

        for (key, body) in sorted(model.bodies) {
            if key != body.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Body table key does not match the stored body ID."
                ))
            }
            appendDuplicateDiagnostic(
                values: body.shellIDs,
                ownerID: key,
                childLabel: "shell",
                result: &result
            )
            for shellID in body.shellIDs {
                referencedShells.insert(shellID)
                shellOwners[shellID, default: 0] += 1
                if model.shells[shellID] == nil {
                    result.append(missingReference(
                        ownerID: key,
                        message: "Body references missing shell \(shellID)."
                    ))
                }
            }
        }

        for (key, shell) in sorted(model.shells) {
            if key != shell.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Shell table key does not match the stored shell ID."
                ))
            }
            appendDuplicateDiagnostic(
                values: shell.faceIDs,
                ownerID: key,
                childLabel: "face",
                result: &result
            )
            for faceID in shell.faceIDs {
                referencedFaces.insert(faceID)
                faceOwners[faceID, default: 0] += 1
                if model.faces[faceID] == nil {
                    result.append(missingReference(
                        ownerID: key,
                        message: "Shell references missing face \(faceID)."
                    ))
                }
            }
        }

        for (key, face) in sorted(model.faces) {
            if key != face.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Face table key does not match the stored face ID."
                ))
            }
            if model.geometry.surfaces[face.surfaceID] == nil {
                result.append(missingReference(
                    ownerID: key,
                    message: "Face references missing surface \(face.surfaceID)."
                ))
            } else {
                referencedSurfaces.insert(face.surfaceID)
            }
            appendDuplicateDiagnostic(
                values: face.loops,
                ownerID: key,
                childLabel: "loop",
                result: &result
            )
            for loopID in face.loops {
                referencedLoops.insert(loopID)
                loopOwners[loopID, default: 0] += 1
                if model.loops[loopID] == nil {
                    result.append(missingReference(
                        ownerID: key,
                        message: "Face references missing loop \(loopID)."
                    ))
                }
            }
        }

        for (key, loop) in sorted(model.loops) {
            if key != loop.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Loop table key does not match the stored loop ID."
                ))
            }
            for coedge in loop.coedges {
                referencedEdges.insert(coedge.edgeID)
                if model.edges[coedge.edgeID] == nil {
                    result.append(missingReference(
                        ownerID: key,
                        message: "Loop references missing edge \(coedge.edgeID)."
                    ))
                }
            }
        }

        for (key, edge) in sorted(model.edges) {
            if key != edge.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Edge table key does not match the stored edge ID."
                ))
            }
            referencedCurves.insert(edge.curveID)
            referencedVertices.formUnion([edge.startVertexID, edge.endVertexID])
            if edge.startVertexID == edge.endVertexID {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Edge start and end vertices must be distinct."
                ))
            }
            if model.geometry.curves[edge.curveID] == nil {
                result.append(missingReference(
                    ownerID: key,
                    message: "Edge references missing curve \(edge.curveID)."
                ))
            }
            for vertexID in [edge.startVertexID, edge.endVertexID]
                where model.vertices[vertexID] == nil {
                result.append(missingReference(
                    ownerID: key,
                    message: "Edge references missing vertex \(vertexID)."
                ))
            }
        }

        for (key, vertex) in sorted(model.vertices) {
            if key != vertex.id {
                result.append(diagnostic(
                    scope: .references,
                    code: .topologyFailure,
                    entityID: key,
                    message: "Vertex table key does not match the stored vertex ID."
                ))
            }
            do {
                try vertex.point.validate()
            } catch {
                result.append(diagnostic(
                    scope: .references,
                    code: .invalidInput,
                    entityID: key,
                    message: "Vertex contains an invalid coordinate: \(error)."
                ))
            }
        }

        appendOwnershipDiagnostics(shellOwners, label: "shell", result: &result)
        appendOwnershipDiagnostics(faceOwners, label: "face", result: &result)
        appendOwnershipDiagnostics(loopOwners, label: "loop", result: &result)
        appendUnreferencedDiagnostics(
            all: Set(model.shells.keys),
            referenced: referencedShells,
            label: "shell",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.faces.keys),
            referenced: referencedFaces,
            label: "face",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.loops.keys),
            referenced: referencedLoops,
            label: "loop",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.edges.keys),
            referenced: referencedEdges,
            label: "edge",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.vertices.keys),
            referenced: referencedVertices,
            label: "vertex",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.geometry.curves.keys),
            referenced: referencedCurves,
            label: "curve",
            result: &result
        )
        appendUnreferencedDiagnostics(
            all: Set(model.geometry.surfaces.keys),
            referenced: referencedSurfaces,
            label: "surface",
            result: &result
        )
        do {
            try model.geometry.validate(tolerance: tolerance)
        } catch let error as KernelError {
            result.append(diagnostic(
                scope: .references,
                code: error.code,
                residual: error.residual,
                message: error.message
            ))
        } catch {
            result.append(diagnostic(
                scope: .references,
                code: .invalidInput,
                message: "Geometry store validation failed: \(error)."
            ))
        }
        return result
    }

    private func loopDiagnostics(model: BRepModel) -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        for (faceID, face) in sorted(model.faces) {
            let existingLoops = face.loops.compactMap { model.loops[$0] }
            let outerCount = existingLoops.filter { $0.role == .outer }.count
            if outerCount != 1 {
                result.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: faceID,
                    message: "A face requires exactly one outer loop; found \(outerCount)."
                ))
            }
        }
        for (loopID, loop) in sorted(model.loops) {
            guard loop.coedges.isEmpty == false else {
                result.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop has no coedges."
                ))
                continue
            }
            if Set(loop.coedges.map(\.edgeID)).count != loop.coedges.count {
                result.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop contains duplicate edge references."
                ))
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
                guard let vertices = orientedVertices(for: coedge, model: model),
                      vertices.start == expected else {
                    isClosed = false
                    break
                }
                expected = vertices.end
            }
            if isClosed == false || expected != first.start {
                result.append(diagnostic(
                    scope: .loops,
                    code: .topologyFailure,
                    entityID: loopID,
                    message: "Loop coedges do not form a closed oriented chain."
                ))
            }
        }
        return result
    }

    private func pcurveDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance
    ) -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        for (faceID, face) in sorted(model.faces) {
            guard let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges {
                    guard let pcurve = coedge.surfaceParameterCurve else {
                        result.append(diagnostic(
                            scope: .pcurves,
                            code: .topologyFailure,
                            entityID: coedge.edgeID,
                            message: "Coedge on face \(faceID) has no face-local pcurve."
                        ))
                        continue
                    }
                    do {
                        try pcurve.validate(on: surface, tolerance: tolerance)
                    } catch {
                        result.append(diagnostic(
                            scope: .pcurves,
                            code: .topologyFailure,
                            entityID: coedge.edgeID,
                            message: "Face-local pcurve validation failed: \(error)."
                        ))
                    }
                }
            }
        }
        let prerequisites = referenceDiagnostics(model: model, tolerance: tolerance)
            + loopDiagnostics(model: model)
            + orientationDiagnostics(model: model)
            + manifoldDiagnostics(model: model)
            + watertightDiagnostics(model: model)
        if prerequisites.isEmpty, result.isEmpty {
            do {
                try model.validatePcurves(tolerance: tolerance)
            } catch let error as KernelError {
                result.append(diagnostic(
                    scope: .pcurves,
                    code: error.code,
                    residual: error.residual,
                    message: error.message
                ))
            } catch {
                result.append(diagnostic(
                    scope: .pcurves,
                    code: .topologyFailure,
                    message: "Geometric pcurve correspondence failed: \(error)."
                ))
            }
        }
        return result
    }

    private func orientationDiagnostics(model: BRepModel) -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        for (shellID, shell) in sorted(model.shells) {
            for (edgeID, use) in edgeUses(shell: shell, model: model)
                where use.total == 2 && (use.forward != 1 || use.reversed != 1) {
                result.append(diagnostic(
                    scope: .orientation,
                    code: .topologyFailure,
                    entityID: edgeID,
                    message: "Shell \(shellID) uses a shared edge without opposite coedge orientations."
                ))
            }
        }
        return result
    }

    private func manifoldDiagnostics(model: BRepModel) -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        let bodyKinds = shellBodyKinds(model: model)
        for (shellID, shell) in sorted(model.shells) {
            let kind = bodyKinds[shellID]
            for (edgeID, use) in edgeUses(shell: shell, model: model) {
                let valid = kind == .sheet
                    ? use.total == 1 || use.total == 2
                    : use.total == 2
                if valid == false {
                    result.append(diagnostic(
                        scope: .manifold,
                        code: .nonManifoldResult,
                        entityID: edgeID,
                        message: "Shell \(shellID) uses edge \(use.total) times."
                    ))
                }
            }
        }
        return result
    }

    private func watertightDiagnostics(model: BRepModel) -> [TopologyValidationDiagnostic] {
        var result: [TopologyValidationDiagnostic] = []
        for (bodyID, body) in sorted(model.bodies) {
            if body.shellIDs.isEmpty {
                result.append(diagnostic(
                    scope: .watertight,
                    code: .topologyFailure,
                    entityID: bodyID,
                    message: "Body has no shells."
                ))
            }
            guard body.kind == .solid else { continue }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else { continue }
                if shell.faceIDs.isEmpty {
                    result.append(diagnostic(
                        scope: .watertight,
                        code: .topologyFailure,
                        entityID: shellID,
                        message: "Solid shell has no faces."
                    ))
                }
                for (edgeID, use) in edgeUses(shell: shell, model: model)
                    where use.total != 2 {
                    result.append(diagnostic(
                        scope: .watertight,
                        code: .topologyFailure,
                        entityID: edgeID,
                        message: "Solid shell boundary edge is not paired."
                    ))
                }
            }
        }
        return result
    }

    private func volumeDiagnostics(
        model: BRepModel,
        tolerance: ModelingTolerance
    ) -> [TopologyValidationDiagnostic] {
        guard model.bodies.values.contains(where: { $0.kind == .solid }) else { return [] }
        let prerequisites = referenceDiagnostics(model: model, tolerance: tolerance)
            + loopDiagnostics(model: model)
            + orientationDiagnostics(model: model)
            + manifoldDiagnostics(model: model)
            + watertightDiagnostics(model: model)
        guard prerequisites.isEmpty else {
            return [diagnostic(
                scope: .volume,
                code: .topologyFailure,
                message: "Volume validation requires valid references, loops, orientation, manifoldness, and watertightness."
            )]
        }
        do {
            _ = try model.volume(tolerance: tolerance)
            return []
        } catch let error as KernelError {
            return [diagnostic(
                scope: .volume,
                code: error.code,
                residual: error.residual,
                message: error.message
            )]
        } catch {
            return [diagnostic(
                scope: .volume,
                code: .topologyFailure,
                message: "Volume validation failed: \(error)."
            )]
        }
    }

    private func edgeUses(
        shell: Shell,
        model: BRepModel
    ) -> [(key: EdgeID, value: EdgeUseCount)] {
        var uses: [EdgeID: EdgeUseCount] = [:]
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges {
                    uses[coedge.edgeID, default: EdgeUseCount()].record(coedge.orientation)
                }
            }
        }
        return uses.sorted { describe($0.key) < describe($1.key) }
    }

    private func shellBodyKinds(model: BRepModel) -> [ShellID: BodyKind] {
        var result: [ShellID: BodyKind] = [:]
        for (_, body) in sorted(model.bodies) {
            for shellID in body.shellIDs where result[shellID] == nil {
                result[shellID] = body.kind
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
        result: inout [TopologyValidationDiagnostic]
    ) {
        if Set(values).count != values.count {
            result.append(diagnostic(
                scope: .references,
                code: .topologyFailure,
                entityID: ownerID,
                message: "Owner contains duplicate \(childLabel) references."
            ))
        }
    }

    private func appendOwnershipDiagnostics<ID: Hashable & CustomStringConvertible>(
        _ owners: [ID: Int],
        label: String,
        result: inout [TopologyValidationDiagnostic]
    ) {
        for (id, count) in owners.sorted(by: { describe($0.key) < describe($1.key) })
            where count != 1 {
            result.append(diagnostic(
                scope: .references,
                code: .topologyFailure,
                entityID: id,
                message: "The \(label) has \(count) owners; exactly one is required."
            ))
        }
    }

    private func appendUnreferencedDiagnostics<ID: Hashable & CustomStringConvertible>(
        all: Set<ID>,
        referenced: Set<ID>,
        label: String,
        result: inout [TopologyValidationDiagnostic]
    ) {
        for id in all.subtracting(referenced).sorted(by: { describe($0) < describe($1) }) {
            result.append(diagnostic(
                scope: .references,
                code: .missingReference,
                entityID: id,
                message: "Unreferenced \(label) remains in the B-rep table."
            ))
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
        _ map: PersistentMap<Key, Value>
    ) -> [(key: Key, value: Value)] {
        map.sorted { describe($0.key) < describe($1.key) }
    }

    private func describe(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}
