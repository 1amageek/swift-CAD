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
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        let componentOperations: [(namespace: String, operation: BooleanOperation)] = [
            ("difference", .difference),
            ("intersection", .intersect),
        ]
        var requests: [(namespace: String, request: BRepSewingRequest)] = []
        for component in componentOperations {
            let selectionGraph = BooleanRegionSelectionGraph(
                decisions: sliceRegionSelectionGraph.decisions.map { decision in
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
                )
                requests.append((component.namespace, request))
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
            let prefix = "slice:\(entry.namespace)"
            switch entry.request.bodyTopology {
            case let .solid(components) where operands.resultBodyKind == .solid:
                solidComponents.append(contentsOf: components.map {
                    BRepSewingSolidComponent(
                        outerShellStableID: namespaced($0.outerShellStableID, prefix: prefix),
                        voidShellStableIDs: $0.voidShellStableIDs.map {
                            namespaced($0, prefix: prefix)
                        }
                    )
                })
            case let .sheet(shellStableIDs) where operands.resultBodyKind == .sheet:
                sheetShellStableIDs.append(contentsOf: shellStableIDs.map { namespaced($0, prefix: prefix) })
            default:
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Boolean slice component materialization must produce the pass's body kind."
                )
            }
            shells.append(contentsOf: entry.request.shells.map {
                namespaced($0, prefix: prefix)
            })
            bodyParentSubshapeIDs.formUnion(entry.request.bodyParentSubshapeIDs)
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyTopology: operands.resultBodyKind == .solid
                ? .solid(components: solidComponents)
                : .sheet(shellStableIDs: sheetShellStableIDs),
            shells: shells,
            bodyParentSubshapeIDs: Array(bodyParentSubshapeIDs)
        )
        try request.validate(tolerance: tolerance)
        return request
    }

    private func namespaced(
        _ shell: BRepSewingShell,
        prefix: String
    ) -> BRepSewingShell {
        BRepSewingShell(
            stableID: namespaced(shell.stableID, prefix: prefix),
            patches: shell.patches.map { namespaced($0, prefix: prefix) },
            orientation: shell.orientation
        )
    }

    private func namespaced(
        _ patch: BRepSewingFacePatch,
        prefix: String
    ) -> BRepSewingFacePatch {
        BRepSewingFacePatch(
            stableID: namespaced(patch.stableID, prefix: prefix),
            surface: patch.surface,
            orientation: patch.orientation,
            loops: patch.loops.map { namespaced($0, prefix: prefix) },
            parentSubshapeIDs: patch.parentSubshapeIDs
        )
    }

    private func namespaced(
        _ loop: BRepSewingLoop,
        prefix: String
    ) -> BRepSewingLoop {
        BRepSewingLoop(
            stableID: namespaced(loop.stableID, prefix: prefix),
            role: loop.role,
            edges: loop.edges.map { namespaced($0, prefix: prefix) }
        )
    }

    private func namespaced(
        _ edge: BRepSewingEdge,
        prefix: String
    ) -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: namespaced(edge.stableID, prefix: prefix),
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

    private func namespaced(_ stableID: String, prefix: String) -> String {
        "\(prefix):\(stableID)"
    }

    private func isEmptyResult(_ error: any Error) -> Bool {
        if let error = error as? KernelError {
            return error.code == .emptyResult
        }
        if case FeatureEvaluationError.emptyResult = error {
            return true
        }
        return false
    }
}
