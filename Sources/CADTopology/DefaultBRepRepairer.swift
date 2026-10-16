import HashTreeCollections
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

    public func repair(_ model: BRepModel, request: BRepRepairRequest,
        tolerance: ModelingTolerance) throws -> BRepRepairResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try repair(model, request: request, tolerance: tolerance, using: &execution)
    }

    public func repair(
        _ model: BRepModel,
        request: BRepRepairRequest,
        tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution
    ) throws -> BRepRepairResult {
        try execution.checkpoint()
        try request.validate(tolerance: tolerance, using: &execution)
        let topologyPhase = try execution.makeContributionHandle(
            allocationPolicy: execution.effectiveAllocationPolicy,
            executionLimits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        let before = try execution.withContributionScope(topologyPhase) { execution in
            try validator.report(for: model, request: request.validationRequest,
                tolerance: tolerance, using: &execution)
        }
        var repaired = model
        var changes: [BRepRepairChange] = []
        var diagnostics: [BRepRepairDiagnostic] = []
        var collapsedCurves: [BRepRepairCollapsedCurve] = []
        let requestedActions = try OriginalParameterQueryStorage.set(request.actions, using: &execution)
        try execution.retainStorage(count: 13, stride: MemoryLayout<BRepRepairAction>.stride)
        let orderedActions: [BRepRepairAction] = [.deduplicateOwnershipReferences,
            .reconstructCurveRepresentations, .sewWireVertices, .removeDuplicateWireUses,
            .collapseSmallWireEdges, .reorderAndOrientLoopCoedges, .restoreSingularBoundaryUses, .restorePeriodicCharts,
            .removeDuplicateFaces, .sewShellEdges, .orientShellFaces, .orientSolidComponents, .pruneUnreferencedTopology]
        for action in orderedActions {
            try execution.consumeWork(1)
            guard requestedActions.contains(action) else { continue }
            let previous = repaired
            let previousCollapsedCurves = collapsedCurves
            let firstChange = changes.count
            switch action {
            case .deduplicateOwnershipReferences:
                try deduplicateOwnershipReferences(
                    model: &repaired,
                    changes: &changes
                , using: &execution)
            case .reorderAndOrientLoopCoedges:
                try reorderAndOrientLoopCoedges(
                    model: &repaired,
                    tolerance: tolerance,
                    changes: &changes,
                    diagnostics: &diagnostics
                , using: &execution)
            case .reconstructCurveRepresentations:
                try BoundedBRepRepairEngine().reconstructCurves(model: &repaired, tolerance: tolerance,
                    changes: &changes, diagnostics: &diagnostics, using: &execution)
            case .sewWireVertices:
                try BoundedBRepRepairEngine().sewVertices(model: &repaired, tolerance: tolerance, changes: &changes, using: &execution)
            case .removeDuplicateWireUses:
                try BoundedBRepRepairEngine().removeDuplicateUses(model: &repaired, tolerance: tolerance, changes: &changes, using: &execution)
            case .collapseSmallWireEdges:
                try BoundedBRepRepairEngine().collapseSmallEdges(model: &repaired, tolerance: tolerance,
                    changes: &changes, collapsedCurves: &collapsedCurves, using: &execution)
            case .restoreSingularBoundaryUses:
                try execution.withContributionScope(topologyPhase) { execution in
                    try OriginalCollapsedWireRestorer().restore(model: &repaired, tolerance: tolerance,
                        changes: &changes, diagnostics: &diagnostics, using: &execution)
                }
            case .restorePeriodicCharts:
                try BoundedBRepRepairEngine().restoreCharts(model: &repaired, tolerance: tolerance, changes: &changes, using: &execution)
            case .removeDuplicateFaces:
                try execution.withContributionScope(topologyPhase) { execution in
                    try OriginalDuplicateFaceRepair().repair(model: &repaired, tolerance: tolerance,
                        changes: &changes, using: &execution)
                }
            case .sewShellEdges:
                try BoundedBRepRepairEngine().sewShellEdges(model: &repaired, tolerance: tolerance, changes: &changes, using: &execution)
            case .orientShellFaces:
                try BoundedBRepRepairEngine().orientShells(model: &repaired, tolerance: tolerance,
                    changes: &changes, diagnostics: &diagnostics, using: &execution)
            case .orientSolidComponents:
                try BoundedBRepRepairEngine().orientSolidComponents(model: &repaired,tolerance: tolerance,
                    changes: &changes,diagnostics: &diagnostics, using: &execution)
            case .pruneUnreferencedTopology:
                try pruneUnreferencedTopology(
                    model: &repaired,
                    changes: &changes
                , using: &execution)
            }
            let displacement = try BRepRepairAudit().maximumDisplacement(
                from: model, to: repaired, collapsedCurves: collapsedCurves, tolerance: tolerance, using: &execution)
            if displacement > tolerance.distance {
                repaired = previous
                collapsedCurves = previousCollapsedCurves
                try execution.consumeWork(changes.count - firstChange)
                changes.removeSubrange(firstChange..<changes.count)
                try OriginalParameterQueryStorage.append(.init(action: action, code: .topologyFailure,
                    message: "The candidate action exceeded cumulative displacement from the original source and was rolled back."), to: &diagnostics, using: &execution)
                continue
            }
            if try !OriginalBRepStructuralComparison.models(repaired, previous, using: &execution) {
                let delta = try BRepRepairAudit().entityDelta(from: previous, to: repaired, using: &execution)
                try OriginalParameterQueryStorage.append(.init(action: action, scope: .references,
                    affectedEntityIDs: delta.affected,
                    message: "Audited accepted source changes against the original cumulative displacement allowance.",
                    maximumDisplacement: displacement,
                    generatedEntityIDs: delta.generated, deletedEntityIDs: delta.deleted), to: &changes, using: &execution)
            }
        }
        let after = try execution.withContributionScope(topologyPhase) { execution in
            try validator.report(for: repaired, request: request.validationRequest,
                tolerance: tolerance, using: &execution)
        }
        try appendUnresolvedDiagnostics(
            after: after,
            actions: request.actions,
            diagnostics: &diagnostics
        , using: &execution)
        try execution.checkpoint()
        return BRepRepairResult(
            model: repaired,
            before: before,
            after: after,
            changes: changes,
            diagnostics: diagnostics
        )
    }

    private func appendUnresolvedDiagnostics(
        after: TopologyValidationReport,
        actions: [BRepRepairAction],
        diagnostics: inout [BRepRepairDiagnostic]
    , using execution: inout OriginalQueryExecution) throws {
        for validationDiagnostic in after.diagnostics {
            try execution.consumeWork(1)
            guard let action = try repairAction(
                for: validationDiagnostic.scope,
                actions: actions, using: &execution
            ) else {
                continue
            }
            let isAlreadyReported = try OriginalParameterQueryStorage.contains(diagnostics, using: &execution) { diagnostic, execution in
                guard diagnostic.action == action, diagnostic.code == validationDiagnostic.code else { return false }
                try execution.consumeWork(diagnostic.entityID?.utf8.count ?? 0)
                try execution.consumeWork(validationDiagnostic.entityID?.utf8.count ?? 0)
                return diagnostic.entityID == validationDiagnostic.entityID
            }
            guard isAlreadyReported == false else { continue }
            try OriginalParameterQueryStorage.append(BRepRepairDiagnostic(
                action: action,
                code: validationDiagnostic.code,
                entityID: validationDiagnostic.entityID,
                message: try BRepRepairAudit().composed(prefix: "The requested repair action could not resolve this validation diagnostic: ", value: validationDiagnostic.message, using: &execution)
            ), to: &diagnostics, using: &execution)
        }
    }

    private func repairAction(
        for scope: TopologyValidationScope,
        actions: [BRepRepairAction], using execution: inout OriginalQueryExecution
    ) throws -> BRepRepairAction? {
        for action in actions {
            try execution.consumeWork(1)
            if action.requires(scope), action != .deduplicateOwnershipReferences,
                action != .pruneUnreferencedTopology, action != .reorderAndOrientLoopCoedges { return action }
        }
        func contains(_ action: BRepRepairAction, using execution: inout OriginalQueryExecution) throws -> Bool {
            try OriginalParameterQueryStorage.contains(actions, using: &execution) { value, execution in value == action }
        }
        switch scope {
        case .references:
            if try contains(.deduplicateOwnershipReferences, using: &execution) {
                return .deduplicateOwnershipReferences
            }
            if try contains(.pruneUnreferencedTopology, using: &execution) {
                return .pruneUnreferencedTopology
            }
            return nil
        case .loops, .pcurves, .orientation:
            return try contains(.reorderAndOrientLoopCoedges, using: &execution)
                ? .reorderAndOrientLoopCoedges
                : nil
        case .manifold, .watertight, .volume:
            return nil
        }
    }

    private func deduplicateOwnershipReferences(
        model: inout BRepModel,
        changes: inout [BRepRepairChange]
    , using execution: inout OriginalQueryExecution) throws {
        var bodyIDs: [String] = []
        for (bodyID, var body) in try sorted(model.bodies, using: &execution) {
            try execution.consumeWork(1)
            let deduplicatedTopology = try deduplicated(body.topology, using: &execution)
            try chargeTopology(deduplicatedTopology, using: &execution)
            try chargeTopology(body.topology, using: &execution)
            if deduplicatedTopology != body.topology {
                body.topology = deduplicatedTopology
                try OriginalParameterQueryStorage.set(body, for: bodyID, in: &model.bodies, using: &execution)
                try OriginalParameterQueryStorage.append(try describe(bodyID, using: &execution), to: &bodyIDs, using: &execution)
            }
        }
        try appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: bodyIDs,
            message: "Removed duplicate shell ownership references from bodies.",
            changes: &changes
        , using: &execution)

        var shellIDs: [String] = []
        for (shellID, var shell) in try sorted(model.shells, using: &execution) {
            try execution.consumeWork(1)
            let uniqueFaceIDs = try unique(shell.faceIDs, using: &execution)
            try execution.consumeWork(uniqueFaceIDs.count)
            try execution.consumeWork(shell.faceIDs.count)
            if uniqueFaceIDs != shell.faceIDs {
                shell.faceIDs = uniqueFaceIDs
                try OriginalParameterQueryStorage.set(shell, for: shellID, in: &model.shells, using: &execution)
                try OriginalParameterQueryStorage.append(try describe(shellID, using: &execution), to: &shellIDs, using: &execution)
            }
        }
        try appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: shellIDs,
            message: "Removed duplicate face ownership references from shells.",
            changes: &changes
        , using: &execution)

        var faceIDs: [String] = []
        for (faceID, var face) in try sorted(model.faces, using: &execution) {
            try execution.consumeWork(1)
            let uniqueLoopIDs = try unique(face.loops, using: &execution)
            try execution.consumeWork(uniqueLoopIDs.count)
            try execution.consumeWork(face.loops.count)
            if uniqueLoopIDs != face.loops {
                face.loops = uniqueLoopIDs
                try OriginalParameterQueryStorage.set(face, for: faceID, in: &model.faces, using: &execution)
                try OriginalParameterQueryStorage.append(try describe(faceID, using: &execution), to: &faceIDs, using: &execution)
            }
        }
        try appendChange(
            action: .deduplicateOwnershipReferences,
            scope: .references,
            entityIDs: faceIDs,
            message: "Removed duplicate loop ownership references from faces.",
            changes: &changes
        , using: &execution)
    }

    private func chargeTopology(_ topology: BodyTopology, using execution: inout OriginalQueryExecution) throws {
        switch topology {
        case .sheet(let ids): try execution.consumeWork(ids.count)
        case .solid(let components):
            for component in components {
                try execution.consumeWork(1)
                try execution.consumeWork(component.voidShellIDs.count)
            }
        }
    }

    private func deduplicated(_ topology: BodyTopology, using execution: inout OriginalQueryExecution) throws -> BodyTopology {
        switch topology {
        case .sheet(let shellIDs):
            return .sheet(shellIDs: try unique(shellIDs, using: &execution))
        case .solid(let components):
            let outerShellIDs = try OriginalParameterQueryStorage.map(components, using: &execution) { component, execution in component.outerShellID }
            let uniqueOuterShellIDs = try OriginalParameterQueryStorage.set(outerShellIDs, using: &execution)
            guard uniqueOuterShellIDs.count == outerShellIDs.count else {
                return topology
            }
            var voidOwners: [ShellID: Int] = [:]
            for (componentIndex, component) in components.enumerated() {
                try execution.consumeWork(1)
                for voidShellID in try OriginalParameterQueryStorage.set(component.voidShellIDs, using: &execution) {
                    try execution.consumeWork(1)
                    guard uniqueOuterShellIDs.contains(voidShellID) == false else {
                        return topology
                    }
                    if let owner = voidOwners[voidShellID], owner != componentIndex {
                        return topology
                    }
                    try OriginalParameterQueryStorage.set(componentIndex, for: voidShellID, in: &voidOwners, using: &execution)
                }
            }
            return .solid(components: try OriginalParameterQueryStorage.map(components, using: &execution) { component, execution in
                SolidShellComponent(
                    outerShellID: component.outerShellID,
                    voidShellIDs: try unique(component.voidShellIDs, using: &execution)
                )
            })
        }
    }

    private func reorderAndOrientLoopCoedges(
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange],
        diagnostics: inout [BRepRepairDiagnostic]
    , using execution: inout OriginalQueryExecution) throws {
        for (loopID, loop) in try sorted(model.loops, using: &execution) {
            try execution.consumeWork(1)
            switch try repairedLoop(loop, model: model, tolerance: tolerance, using: &execution) {
            case .unchanged:
                continue
            case let .repaired(coedges):
                try OriginalParameterQueryStorage.set(Loop(
                    id: loop.id,
                    role: loop.role,
                    coedges: coedges
                ), for: loopID, in: &model.loops, using: &execution)
                try OriginalParameterQueryStorage.append(BRepRepairChange(
                    action: .reorderAndOrientLoopCoedges,
                    scope: .loops,
                    affectedEntityIDs: try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in [try describe(loopID, using: &execution)] },
                    message: "Reordered and oriented a unique coedge cycle without changing edge geometry."
                ), to: &changes, using: &execution)
            case let .rejected(message):
                try OriginalParameterQueryStorage.append(BRepRepairDiagnostic(
                    action: .reorderAndOrientLoopCoedges,
                    code: .topologyFailure,
                    entityID: try describe(loopID, using: &execution),
                    message: message
                ), to: &diagnostics, using: &execution)
            }
        }
    }

    private func repairedLoop(
        _ loop: Loop,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> LoopRepairOutcome {
        guard loop.coedges.isEmpty == false else {
            return .rejected("An empty loop has no cycle to reorder.")
        }
        if try OriginalParameterQueryStorage.set(OriginalParameterQueryStorage.map(loop.coedges, using: &execution) { use, execution in use.edgeID }, using: &execution).count != loop.coedges.count {
            let owningFaces = try OriginalParameterQueryStorage.filter(model.faces.values, using: &execution) { face, execution in
                try OriginalParameterQueryStorage.contains(face.loops, using: &execution) { id, execution in id == loop.id }
            }
            if owningFaces.count == 1,
               let surface = model.geometry.surfaces[owningFaces[0].surfaceID],
               try PeriodicFaceSeamValidator().certifiesRepeatedEdgeUses(
                   in: loop,
                   on: surface,
                   tolerance: tolerance,
                   maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
                   remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
                   using: &execution) {
                return .unchanged
            }
            return .rejected(
                "A loop with repeated non-seam edges cannot be repaired without changing topology."
            )
        }
        let ordered = try OriginalParameterQueryStorage.ordered(loop.coedges, using: &execution, less: { $0.edgeID < $1.edgeID })
        guard let first = ordered.first,
              model.edges[first.edgeID] != nil else {
            return .rejected("Loop repair references a missing edge.")
        }
        var candidates: [[Coedge]] = []
        for direction in 0..<2 {
            try execution.consumeWork(1)
            let initial = direction == 1
                ? try reversed(first, tolerance: tolerance, using: &execution)
                : first
            if let cycle = try cycle(
                startingWith: initial,
                remaining: try OriginalParameterQueryStorage.materialize(ordered.dropFirst(), using: &execution),
                model: model,
                tolerance: tolerance
            , using: &execution) {
                try OriginalParameterQueryStorage.append(cycle, to: &candidates, using: &execution)
            }
        }
        guard candidates.isEmpty == false else {
            return .rejected("Coedges do not define a closed cycle.")
        }
        var originalOrientations: [EdgeID: Orientation] = [:]
        for use in loop.coedges {
            try OriginalParameterQueryStorage.set(use.orientation, for: use.edgeID, in: &originalOrientations, using: &execution)
        }
        let ranked = try OriginalParameterQueryStorage.map(candidates, using: &execution) { candidate, execution in
            let reversalCount = try OriginalParameterQueryStorage.reduce(candidate, initial: 0, using: &execution) { count, coedge, execution in
                count + (originalOrientations[coedge.edgeID] != coedge.orientation ? 1 : 0)
            }
            return (candidate: candidate, reversalCount: reversalCount)
        }
        guard let counts = try OriginalParameterQueryStorage.extrema(ranked, using: &execution,
            projection: { value, execution in value.reversalCount }) else {
            return .rejected("Coedges do not define a closed cycle.")
        }
        let minimumCandidates = try OriginalParameterQueryStorage.filter(ranked, using: &execution) { value, execution in
            value.reversalCount == counts.lower
        }
        guard minimumCandidates.count == 1,
              let selected = minimumCandidates.first?.candidate else {
            return .rejected(
                "Both loop directions require the same number of orientation changes."
            )
        }
        for use in selected {
            try execution.consumeWork(1)
            if let curve = use.surfaceParameterCurve { try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution) }
        }
        for use in loop.coedges {
            try execution.consumeWork(1)
            if let curve = use.surfaceParameterCurve { try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution) }
        }
        return selected == loop.coedges ? .unchanged : .repaired(selected)
    }

    private func cycle(
        startingWith first: Coedge,
        remaining source: [Coedge],
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Coedge]? {
        guard let firstVertices = try orientedVertices(for: first, model: model, using: &execution) else {
            return nil
        }
        try execution.retainStorage(count: source.capacity, stride: MemoryLayout<Coedge>.stride)
        var remaining = source
        var result = try OriginalParameterQueryStorage.materialize(CollectionOfOne(first), using: &execution)
        var expectedStart = firstVertices.end
        while remaining.isEmpty == false {
            let candidates = try OriginalParameterQueryStorage.filter(remaining.indices, using: &execution) { index, execution in
                guard let vertices = try unorientedVertices(
                    for: remaining[index],
                    model: model, using: &execution
                ) else {
                    return false
                }
                return vertices.first == expectedStart || vertices.second == expectedStart
            }
            guard candidates.count == 1,
                  let index = candidates.first,
                  let vertices = try orientedVertices(
                    for: remaining[index],
                    model: model, using: &execution
                  ) else {
                return nil
            }
            try execution.consumeWork(remaining.count - index)
            var next = remaining.remove(at: index)
            if vertices.start != expectedStart {
                next = try reversed(next, tolerance: tolerance, using: &execution)
            }
            guard let oriented = try orientedVertices(for: next, model: model, using: &execution),
                  oriented.start == expectedStart else {
                return nil
            }
            try OriginalParameterQueryStorage.append(next, to: &result, using: &execution)
            expectedStart = oriented.end
        }
        return expectedStart == firstVertices.start ? result : nil
    }

    private func reversed(
        _ coedge: Coedge,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Coedge {
        try execution.consumeWork(1)
        let orientation: Orientation = coedge.orientation == .forward
            ? .reversed
            : .forward
        let pcurve: SurfaceParameterCurve?
        if let source = coedge.surfaceParameterCurve {
            pcurve = try source.reversed(tolerance: tolerance, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws {
        var shellIDs = Set<ShellID>(), faceIDs = Set<FaceID>(), loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>(), vertexIDs = Set<VertexID>(), curveIDs = Set<CurveID>(), surfaceIDs = Set<SurfaceID>()
        for body in model.bodies.values {
            try execution.consumeWork(1)
            for id in try body.originalShellIDs(using: &execution) {
                try OriginalParameterQueryStorage.insert(id, in: &shellIDs, using: &execution)
            }
        }
        for id in shellIDs {
            try execution.consumeWork(1)
            if let shell = model.shells[id] {
                for face in shell.faceIDs { try OriginalParameterQueryStorage.insert(face, in: &faceIDs, using: &execution) }
            }
        }
        for id in faceIDs {
            try execution.consumeWork(1)
            if let face = model.faces[id] {
                try OriginalParameterQueryStorage.insert(face.surfaceID, in: &surfaceIDs, using: &execution)
                for loop in face.loops { try OriginalParameterQueryStorage.insert(loop, in: &loopIDs, using: &execution) }
            }
        }
        for id in loopIDs {
            try execution.consumeWork(1)
            if let loop = model.loops[id] {
                for use in loop.coedges { try OriginalParameterQueryStorage.insert(use.edgeID, in: &edgeIDs, using: &execution) }
            }
        }
        for id in edgeIDs {
            try execution.consumeWork(1)
            if let edge = model.edges[id] {
                try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &vertexIDs, using: &execution)
                try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &vertexIDs, using: &execution)
                try OriginalParameterQueryStorage.insert(edge.curveID, in: &curveIDs, using: &execution)
            }
        }

        let removedShells = try removedIDs(model.shells.keys, retaining: shellIDs, using: &execution)
        let removedFaces = try removedIDs(model.faces.keys, retaining: faceIDs, using: &execution)
        let removedLoops = try removedIDs(model.loops.keys, retaining: loopIDs, using: &execution)
        let removedEdges = try removedIDs(model.edges.keys, retaining: edgeIDs, using: &execution)
        let removedVertices = try removedIDs(model.vertices.keys, retaining: vertexIDs, using: &execution)
        let removedCurves = try removedIDs(model.geometry.curves.keys, retaining: curveIDs, using: &execution)
        let removedSurfaces = try removedIDs(model.geometry.surfaces.keys, retaining: surfaceIDs, using: &execution)

        try pruneMap(&model.shells, retaining: shellIDs, using: &execution)
        try pruneMap(&model.faces, retaining: faceIDs, using: &execution)
        try pruneMap(&model.loops, retaining: loopIDs, using: &execution)
        try pruneMap(&model.edges, retaining: edgeIDs, using: &execution)
        try pruneMap(&model.vertices, retaining: vertexIDs, using: &execution)
        try pruneMap(&model.geometry.curves, retaining: curveIDs, using: &execution)
        try pruneMap(&model.geometry.surfaces, retaining: surfaceIDs, using: &execution)
        var deleted: [String] = []
        try OriginalParameterQueryStorage.append(contentsOf: removedShells, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedFaces, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedLoops, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedEdges, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedVertices, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedCurves, to: &deleted, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: removedSurfaces, to: &deleted, using: &execution)

        try appendChange(
            action: .pruneUnreferencedTopology,
            scope: .references,
            entityIDs: deleted,
            message: "Pruned topology and geometry unreachable from a body.",
            changes: &changes
        , using: &execution)
    }

    private func pruneMap<Key: Hashable, Value>(_ map: inout PersistentMap<Key, Value>,
        retaining keys: Set<Key>, using execution: inout OriginalQueryExecution) throws {
        let sourceKeys = try OriginalParameterQueryStorage.materialize(map.keys, using: &execution)
        for key in sourceKeys {
            try execution.consumeWork(1)
            if !keys.contains(key) {
                try execution.retainStorage(count: 1, stride: MemoryLayout<(Key, Value)>.stride)
                map[key] = nil
            }
        }
    }

    private func orientedVertices(
        for coedge: Coedge,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> (start: VertexID, end: VertexID)? {
        try execution.consumeWork(1)
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
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> (first: VertexID, second: VertexID)? {
        try execution.consumeWork(1)
        guard let edge = model.edges[coedge.edgeID] else { return nil }
        return (edge.startVertexID, edge.endVertexID)
    }

    private func unique<Value: Hashable>(_ source: [Value], using execution: inout OriginalQueryExecution) throws -> [Value] {
        var seen = Set<Value>()
        return try OriginalParameterQueryStorage.filter(source, using: &execution) { value, execution in
            try OriginalParameterQueryStorage.insert(value, in: &seen, using: &execution)
        }
    }

    private func removedIDs<Tag>(
        _ source: some Sequence<TaggedID<Tag>>, retaining: Set<TaggedID<Tag>>,
        using execution: inout OriginalQueryExecution
    ) throws -> [String] {
        var result: [String] = []
        for id in source {
           try execution.consumeWork(1)
            if !retaining.contains(id) {
                let text = try describe(id, using: &execution)
                try OriginalParameterQueryStorage.append(text, to: &result, using: &execution)
            }
        }
        try sortText(&result, using: &execution)
        return result
    }

    private func appendChange(
        action: BRepRepairAction,
        scope: TopologyValidationScope,
        entityIDs: [String],
        message: String,
        changes: inout [BRepRepairChange]
    , using execution: inout OriginalQueryExecution) throws {
        guard entityIDs.isEmpty == false else { return }
        var orderedIDs = try OriginalParameterQueryStorage.materialize(entityIDs, using: &execution)
        try sortText(&orderedIDs, using: &execution)
        try OriginalParameterQueryStorage.append(BRepRepairChange(
            action: action,
            scope: scope,
            affectedEntityIDs: orderedIDs,
            message: message,
            deletedEntityIDs: action == .pruneUnreferencedTopology ? orderedIDs : []
        ), to: &changes, using: &execution)
    }

    private func sorted<Key: Hashable & Comparable, Value>(
        _ map: PersistentMap<Key, Value>
    , using execution: inout OriginalQueryExecution) throws -> [(key: Key, value: Value)] {
        try OriginalParameterQueryStorage.ordered(map, using: &execution, less: { $0.key < $1.key })
    }

    private func sortText(_ values: inout [String], using execution: inout OriginalQueryExecution) throws {
        try OriginalParameterQueryStorage.sort(&values, using: &execution) { first, second, execution in
            try execution.consumeWork(first.utf8.count)
            try execution.consumeWork(second.utf8.count)
            return first < second
        }
    }

    private func describe<Tag>(_ value: TaggedID<Tag>, using execution: inout OriginalQueryExecution) throws -> String {
        try BRepRepairAudit().describe(value, using: &execution)
    }
}
