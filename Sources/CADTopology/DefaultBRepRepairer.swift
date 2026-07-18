import CADCore
import CADGeometry

public struct DefaultBRepRepairer: BRepRepairing {
    private enum LoopRepairOutcome {
        case unchanged
        case repaired([Coedge])
        case rejected(String)
    }

    private let validator: any BRepTopologyValidating

    public init(
        validator: any BRepTopologyValidating = DefaultBRepTopologyValidator()
    ) {
        self.validator = validator
    }

    public func repair(
        _ model: BRepModel,
        request: BRepRepairRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepRepairResult {
        try request.validate(tolerance: tolerance)
        let before = try validator.report(
            for: model,
            request: request.validationRequest,
            tolerance: tolerance
        )
        var repaired = model
        var changes: [BRepRepairChange] = []
        var diagnostics: [BRepRepairDiagnostic] = []
        for action in request.actions {
            switch action {
            case .deduplicateOwnershipReferences:
                deduplicateOwnershipReferences(
                    model: &repaired,
                    changes: &changes
                )
            case .reorderAndOrientLoopCoedges:
                try reorderAndOrientLoopCoedges(
                    model: &repaired,
                    tolerance: tolerance,
                    changes: &changes,
                    diagnostics: &diagnostics
                )
            case .pruneUnreferencedTopology:
                pruneUnreferencedTopology(
                    model: &repaired,
                    changes: &changes
                )
            }
        }
        let after = try validator.report(
            for: repaired,
            request: request.validationRequest,
            tolerance: tolerance
        )
        return BRepRepairResult(
            model: repaired,
            before: before,
            after: after,
            changes: changes,
            diagnostics: diagnostics
        )
    }

    private func deduplicateOwnershipReferences(
        model: inout BRepModel,
        changes: inout [BRepRepairChange]
    ) {
        var bodyIDs: [String] = []
        for (bodyID, var body) in sorted(model.bodies) {
            let uniqueShellIDs = unique(body.shellIDs)
            if uniqueShellIDs != body.shellIDs {
                body.shellIDs = uniqueShellIDs
                model.bodies[bodyID] = body
                bodyIDs.append(describe(bodyID))
            }
        }
        appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: bodyIDs,
            message: "Removed duplicate shell ownership references from bodies.",
            changes: &changes
        )

        var shellIDs: [String] = []
        for (shellID, var shell) in sorted(model.shells) {
            let uniqueFaceIDs = unique(shell.faceIDs)
            if uniqueFaceIDs != shell.faceIDs {
                shell.faceIDs = uniqueFaceIDs
                model.shells[shellID] = shell
                shellIDs.append(describe(shellID))
            }
        }
        appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: shellIDs,
            message: "Removed duplicate face ownership references from shells.",
            changes: &changes
        )

        var faceIDs: [String] = []
        for (faceID, var face) in sorted(model.faces) {
            let uniqueLoopIDs = unique(face.loops)
            if uniqueLoopIDs != face.loops {
                face.loops = uniqueLoopIDs
                model.faces[faceID] = face
                faceIDs.append(describe(faceID))
            }
        }
        appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: faceIDs,
            message: "Removed duplicate loop ownership references from faces.",
            changes: &changes
        )
    }

    private func reorderAndOrientLoopCoedges(
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange],
        diagnostics: inout [BRepRepairDiagnostic]
    ) throws {
        for (loopID, loop) in sorted(model.loops) {
            switch try repairedLoop(loop, model: model, tolerance: tolerance) {
            case .unchanged:
                continue
            case let .repaired(coedges):
                model.loops[loopID] = Loop(
                    id: loop.id,
                    role: loop.role,
                    coedges: coedges
                )
                changes.append(BRepRepairChange(
                    action: .reorderAndOrientLoopCoedges,
                    scope: .loops,
                    affectedEntityIDs: [describe(loopID)],
                    message: "Reordered and oriented a unique coedge cycle without changing edge geometry."
                ))
            case let .rejected(message):
                diagnostics.append(BRepRepairDiagnostic(
                    action: .reorderAndOrientLoopCoedges,
                    code: .topologyFailure,
                    entityID: describe(loopID),
                    message: message
                ))
            }
        }
    }

    private func repairedLoop(
        _ loop: Loop,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> LoopRepairOutcome {
        guard loop.coedges.isEmpty == false else {
            return .rejected("An empty loop has no cycle to reorder.")
        }
        guard Set(loop.coedges.map(\.edgeID)).count == loop.coedges.count else {
            return .rejected("A loop with duplicate edges cannot be repaired without changing topology.")
        }
        let ordered = loop.coedges.sorted {
            describe($0.edgeID) < describe($1.edgeID)
        }
        guard let first = ordered.first,
              model.edges[first.edgeID] != nil else {
            return .rejected("Loop repair references a missing edge.")
        }
        for reverseFirst in [false, true] {
            let initial = reverseFirst
                ? try reversed(first, tolerance: tolerance)
                : first
            if let cycle = try cycle(
                startingWith: initial,
                remaining: Array(ordered.dropFirst()),
                model: model,
                tolerance: tolerance
            ) {
                return cycle == loop.coedges ? .unchanged : .repaired(cycle)
            }
        }
        return .rejected("Coedges do not define one unambiguous closed cycle.")
    }

    private func cycle(
        startingWith first: Coedge,
        remaining source: [Coedge],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [Coedge]? {
        guard let firstVertices = orientedVertices(for: first, model: model) else {
            return nil
        }
        var remaining = source
        var result = [first]
        var expectedStart = firstVertices.end
        while remaining.isEmpty == false {
            let candidates = remaining.indices.filter { index in
                guard let vertices = unorientedVertices(
                    for: remaining[index],
                    model: model
                ) else {
                    return false
                }
                return vertices.first == expectedStart || vertices.second == expectedStart
            }
            guard candidates.count == 1,
                  let index = candidates.first,
                  let vertices = orientedVertices(
                    for: remaining[index],
                    model: model
                  ) else {
                return nil
            }
            var next = remaining.remove(at: index)
            if vertices.start != expectedStart {
                next = try reversed(next, tolerance: tolerance)
            }
            guard let oriented = orientedVertices(for: next, model: model),
                  oriented.start == expectedStart else {
                return nil
            }
            result.append(next)
            expectedStart = oriented.end
        }
        return expectedStart == firstVertices.start ? result : nil
    }

    private func reversed(
        _ coedge: Coedge,
        tolerance: ModelingTolerance
    ) throws -> Coedge {
        let orientation: Orientation = coedge.orientation == .forward
            ? .reversed
            : .forward
        let pcurve: SurfaceParameterCurve?
        if let source = coedge.surfaceParameterCurve {
            pcurve = try source.reversed(tolerance: tolerance)
        } else {
            pcurve = nil
        }
        return Coedge(
            edgeID: coedge.edgeID,
            orientation: orientation,
            surfaceParameterCurve: pcurve
        )
    }

    private func pruneUnreferencedTopology(
        model: inout BRepModel,
        changes: inout [BRepRepairChange]
    ) {
        let shellIDs = Set(model.bodies.values.flatMap(\.shellIDs))
        let faceIDs = Set(shellIDs.compactMap { model.shells[$0] }.flatMap(\.faceIDs))
        let loopIDs = Set(faceIDs.compactMap { model.faces[$0] }.flatMap(\.loops))
        let edgeIDs = Set(loopIDs.compactMap { model.loops[$0] }.flatMap {
            $0.coedges.map(\.edgeID)
        })
        let edges = edgeIDs.compactMap { model.edges[$0] }
        let vertexIDs = Set(edges.flatMap { [$0.startVertexID, $0.endVertexID] })
        let curveIDs = Set(edges.map(\.curveID))
        let surfaceIDs = Set(faceIDs.compactMap { model.faces[$0]?.surfaceID })

        let removedShells = removedIDs(model.shells.keys, retaining: shellIDs)
        let removedFaces = removedIDs(model.faces.keys, retaining: faceIDs)
        let removedLoops = removedIDs(model.loops.keys, retaining: loopIDs)
        let removedEdges = removedIDs(model.edges.keys, retaining: edgeIDs)
        let removedVertices = removedIDs(model.vertices.keys, retaining: vertexIDs)
        let removedCurves = removedIDs(model.geometry.curves.keys, retaining: curveIDs)
        let removedSurfaces = removedIDs(model.geometry.surfaces.keys, retaining: surfaceIDs)

        model.shells = PersistentMap(model.shells.materializedDictionary().filter {
            shellIDs.contains($0.key)
        })
        model.faces = PersistentMap(model.faces.materializedDictionary().filter {
            faceIDs.contains($0.key)
        })
        model.loops = PersistentMap(model.loops.materializedDictionary().filter {
            loopIDs.contains($0.key)
        })
        model.edges = PersistentMap(model.edges.materializedDictionary().filter {
            edgeIDs.contains($0.key)
        })
        model.vertices = PersistentMap(model.vertices.materializedDictionary().filter {
            vertexIDs.contains($0.key)
        })
        model.geometry.curves = PersistentMap(
            model.geometry.curves.materializedDictionary().filter {
                curveIDs.contains($0.key)
            }
        )
        model.geometry.surfaces = PersistentMap(
            model.geometry.surfaces.materializedDictionary().filter {
                surfaceIDs.contains($0.key)
            }
        )

        appendChange(
            action: .pruneUnreferencedTopology,
            scope: .references,
            entityIDs: removedShells + removedFaces + removedLoops + removedEdges
                + removedVertices + removedCurves + removedSurfaces,
            message: "Pruned topology and geometry unreachable from a body.",
            changes: &changes
        )
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

    private func unorientedVertices(
        for coedge: Coedge,
        model: BRepModel
    ) -> (first: VertexID, second: VertexID)? {
        guard let edge = model.edges[coedge.edgeID] else { return nil }
        return (edge.startVertexID, edge.endVertexID)
    }

    private func unique<Value: Hashable>(_ source: [Value]) -> [Value] {
        var seen = Set<Value>()
        return source.filter { seen.insert($0).inserted }
    }

    private func removedIDs<ID: Hashable & CustomStringConvertible>(
        _ source: some Sequence<ID>,
        retaining: Set<ID>
    ) -> [String] {
        source.filter { retaining.contains($0) == false }
            .map(describe)
            .sorted()
    }

    private func appendChange(
        action: BRepRepairAction,
        scope: TopologyValidationScope,
        entityIDs: [String],
        message: String,
        changes: inout [BRepRepairChange]
    ) {
        guard entityIDs.isEmpty == false else { return }
        changes.append(BRepRepairChange(
            action: action,
            scope: scope,
            affectedEntityIDs: entityIDs.sorted(),
            message: message
        ))
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
