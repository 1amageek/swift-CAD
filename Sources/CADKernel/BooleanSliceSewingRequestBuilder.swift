import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Materializes a slice as the disjoint components `target \ tool` and `target ∩ tool` while
/// reusing one certified intersection graph: solid components for a target with material,
/// sheet shells for an empty target.
struct BooleanSliceSewingRequestBuilder {
    func materialize(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        sliceRegionSelectionGraph: BooleanRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.consumeWork(1)
        try tolerance.validate()
        let componentOperations: [(namespace: String, operation: BooleanOperation)] = [
            ("difference", .difference),
            ("intersection", .intersect),
        ]
        var requests: [(namespace: String, request: BRepSewingRequest)] = []
        for component in componentOperations {
            try execution.consumeWork(1)
            let selectionGraph = BooleanRegionSelectionGraph(
                decisions: try OriginalParameterQueryStorage.map(sliceRegionSelectionGraph.decisions, using: &execution) { decision, execution in
                    BooleanRegionSelectionGraph.Decision(
                        sample: decision.sample,
                        action: operands.rule.action(
                            operation: component.operation,
                            sample: decision.sample
                        )
                    )
                }
            )
            do {
                let request = try ExactIntersectionFacePatchMaterializer().materialize(
                    operation: component.operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    featureID: featureID,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    uvSplitGraph: uvSplitGraph,
                    regionSelectionGraph: selectionGraph,
                    operands: operands,
                    tolerance: tolerance
                , using: &execution)
                try OriginalParameterQueryStorage.append((component.namespace, request), to: &requests, using: &execution)
            } catch {
                guard isEmptyResult(error) else { throw error }
            }
        }
        guard requests.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .emptyResult,
                tolerance: tolerance,
                message: "Boolean slice produced no material component."
            )
        }

        var shells: [BRepSewingShell] = []
        var solidComponents: [BRepSewingSolidComponent] = []
        var sheetShellStableIDs: [String] = []
        var bodyParentSubshapeIDs = Set<SubshapeID>()
        for entry in requests {
            try execution.consumeWork(1)
            let prefix = "slice:\(entry.namespace)"
            switch entry.request.bodyTopology {
            case let .solid(components) where operands.resultBodyKind == .solid:
                try OriginalParameterQueryStorage.append(contentsOf: try OriginalParameterQueryStorage.map(components, using: &execution) { component, execution in
                    BRepSewingSolidComponent(
                        outerShellStableID: try namespaced(component.outerShellStableID, prefix: prefix, using: &execution),
                        voidShellStableIDs: try OriginalParameterQueryStorage.map(component.voidShellStableIDs, using: &execution) { id, execution in
                            try namespaced(id, prefix: prefix, using: &execution)
                        }
                    )
                }, to: &solidComponents, using: &execution)
            case let .sheet(shellStableIDs) where operands.resultBodyKind == .sheet:
                try OriginalParameterQueryStorage.append(contentsOf: try OriginalParameterQueryStorage.map(shellStableIDs, using: &execution) { id, execution in try namespaced(id, prefix: prefix, using: &execution) }, to: &sheetShellStableIDs, using: &execution)
            default:
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Boolean slice component materialization must produce the pass's body kind."
                )
            }
            try OriginalParameterQueryStorage.append(contentsOf: try OriginalParameterQueryStorage.map(entry.request.shells, using: &execution) { shell, execution in
                try namespaced(shell, prefix: prefix, using: &execution)
            }, to: &shells, using: &execution)
            for id in entry.request.bodyParentSubshapeIDs {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(id, in: &bodyParentSubshapeIDs, using: &execution) }
        }
        try execution.retainKernelValues(count: bodyParentSubshapeIDs.count, stride: MemoryLayout<SubshapeID>.stride)
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyTopology: operands.resultBodyKind == .solid
                ? .solid(components: solidComponents)
                : .sheet(shellStableIDs: sheetShellStableIDs),
            shells: shells,
            bodyParentSubshapeIDs: Array(bodyParentSubshapeIDs)
        )
        try request.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return request
    }

    private func namespaced(
        _ shell: BRepSewingShell,
        prefix: String
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingShell {
        try execution.consumeWork(1)
        return BRepSewingShell(
            stableID: try namespaced(shell.stableID, prefix: prefix, using: &execution),
            patches: try OriginalParameterQueryStorage.map(shell.patches, using: &execution) { patch, execution in try namespaced(patch, prefix: prefix, using: &execution) },
            orientation: shell.orientation
        )
    }

    private func namespaced(
        _ patch: BRepSewingFacePatch,
        prefix: String
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        return BRepSewingFacePatch(
            stableID: try namespaced(patch.stableID, prefix: prefix, using: &execution),
            surface: patch.surface,
            orientation: patch.orientation,
            loops: try OriginalParameterQueryStorage.map(patch.loops, using: &execution) { loop, execution in try namespaced(loop, prefix: prefix, using: &execution) },
            parentSubshapeIDs: patch.parentSubshapeIDs
        )
    }

    private func namespaced(
        _ loop: BRepSewingLoop,
        prefix: String
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingLoop {
        try execution.consumeWork(1)
        return BRepSewingLoop(
            stableID: try namespaced(loop.stableID, prefix: prefix, using: &execution),
            role: loop.role,
            edges: try OriginalParameterQueryStorage.map(loop.edges, using: &execution) { edge, execution in try namespaced(edge, prefix: prefix, using: &execution) }
        )
    }

    private func namespaced(
        _ edge: BRepSewingEdge,
        prefix: String
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
        return BRepSewingEdge(
            stableID: try namespaced(edge.stableID, prefix: prefix, using: &execution),
            curve: edge.curve,
            startParameter: edge.startParameter,
            endParameter: edge.endParameter,
            startPoint: edge.startPoint,
            endPoint: edge.endPoint,
            surfaceParameterCurve: edge.surfaceParameterCurve,
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
        )
    }

    private func namespaced(_ stableID: String, prefix: String, using execution: inout OriginalQueryExecution) throws -> String {
        try execution.consumeWork(1)
        let count = prefix.utf8.count.addingReportingOverflow(stableID.utf8.count)
        let withColon = count.partialValue.addingReportingOverflow(1)
        guard !count.overflow, !withColon.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: withColon.partialValue)
        return "\(prefix):\(stableID)"
    }

    private func isEmptyResult(_ error: any Error) -> Bool {
        if let classification = OriginalQueryFailure.classification(of: error) {
            return classification.code == .emptyResult
        }
        if case FeatureEvaluationError.emptyResult = error {
            return true
        }
        return false
    }
}
