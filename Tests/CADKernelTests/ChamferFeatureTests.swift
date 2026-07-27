import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Chamfer feature")
struct ChamferFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsValidatedExactBRepAndSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let selectedEdgeID = SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        )
        let selectedReference = try source.stableSubshapeReference(for: selectedEdgeID)
        let selectedLength = try edgeLength(subshapeID: selectedEdgeID, in: source)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let distance = 0.002
        let chamferFeatureID = FeatureID()
        let operation = FeatureOperation.chamfer(ChamferFeature(
            target: ChamferTargetReference(featureID: extrudeFeatureID),
            edges: [selectedReference],
            distance: .constant(.length(distance, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: chamferFeatureID,
            in: document,
            tolerance: .standard
        )
        append(node, dependingOn: extrudeFeatureID, to: &document)

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        let expectedVolume = sourceVolume - 0.5 * distance * distance * selectedLength
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        #expect(evaluated.meshes.isEmpty)

        let edgeDescendants = evaluated.lineage.values.filter {
            $0.output.featureID == chamferFeatureID
                && $0.output.role == GeneratedSubshapeRole.edge.rawValue
                && $0.parents.contains(selectedReference.subshapeID)
        }
        #expect(edgeDescendants.count == 2)
        #expect(edgeDescendants.allSatisfy { $0.relation == .split })
        do {
            _ = try evaluated.topologyReference(for: selectedReference)
            Issue.record("A replaced sharp edge must not resolve to one chamfer boundary implicitly.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == selectedReference.subshapeID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func scopesReplacementAndLineageToTheTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let target = try evaluator.evaluate(targetDocument)
        let unrelated = try evaluator.evaluate(unrelatedDocument)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let targetEdge = try target.stableSubshapeReference(for: SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        ))
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let chamferFeatureID = FeatureID()

        let result = try ChamferFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: chamferFeatureID,
                operation: .chamfer(ChamferFeature(
                    target: ChamferTargetReference(featureID: targetFeatureID),
                    edges: [targetEdge],
                    distance: .constant(.length(0.002, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            ),
            context: context(for: fixture)
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == chamferFeatureID
        }

        #expect(result.removedSubshapeIDs == targetSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelatedSubshapeIDs))
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.allSatisfy {
            Set($0.parents).isSubset(of: targetSubshapeIDs)
        })
        for bodyID in unrelated.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == unrelated.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsEdgeOwnedByAnotherTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let foreignDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let target = try evaluator.evaluate(targetDocument)
        let foreign = try evaluator.evaluate(foreignDocument)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let foreignFeatureID = try #require(foreignDocument.designGraph.order.last)
        let foreignEdge = try foreign.stableSubshapeReference(for: SubshapeID(
            featureID: foreignFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        ))
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let chamferFeatureID = FeatureID()

        do {
            _ = try ChamferFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: chamferFeatureID,
                    operation: .chamfer(ChamferFeature(
                        target: ChamferTargetReference(featureID: targetFeatureID),
                        edges: [foreignEdge],
                        distance: .constant(.length(0.002, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                context: context(for: fixture)
            )
            Issue.record("An edge owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == chamferFeatureID)
            #expect(error.subshapeID == foreignEdge.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsDistanceThatRemovesASourceFace() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        let selectedReference = try source.stableSubshapeReference(for: SubshapeID(
            featureID: extrudeFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        ))
        let chamferFeatureID = FeatureID()
        let operation = FeatureOperation.chamfer(ChamferFeature(
            target: ChamferTargetReference(featureID: extrudeFeatureID),
            edges: [selectedReference],
            distance: .constant(.length(0.100, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: chamferFeatureID,
            in: document,
            tolerance: .standard
        )
        append(node, dependingOn: extrudeFeatureID, to: &document)

        do {
            _ = try DocumentEvaluator(
                tolerance: .standard,
                artifactPolicy: .deferred
            ).evaluate(document)
            Issue.record("A chamfer that removes a source face must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .topologyFailure)
            #expect(error.featureID == chamferFeatureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMultipleEdgesWithTypedCapabilityError() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let references = try [0, 1].map { index in
            try source.stableSubshapeReference(for: SubshapeID(
                featureID: extrudeFeatureID,
                role: GeneratedSubshapeRole.edge.rawValue,
                ordinal: index
            ))
        }
        let chamferFeatureID = FeatureID()
        let operation = FeatureOperation.chamfer(ChamferFeature(
            target: ChamferTargetReference(featureID: extrudeFeatureID),
            edges: references,
            distance: .constant(.length(2.0, unit: .millimeter))
        ))
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: chamferFeatureID,
            in: document,
            tolerance: .standard
        )
        append(node, dependingOn: extrudeFeatureID, to: &document)

        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            Issue.record("The declared chamfer envelope must reject multiple selected edges.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == chamferFeatureID)
            #expect(error.tolerance == .standard)
        }
    }

    private func append(
        _ node: FeatureNode,
        dependingOn sourceID: FeatureID,
        to document: inout CADDocument
    ) {
        document.designGraph.nodes[node.id] = node
        document.designGraph.order.append(node.id)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceID, target: node.id))
        document.designGraph.revision = document.designGraph.revision.advanced()
    }

    private func edgeLength(
        subshapeID: SubshapeID,
        in document: EvaluatedDocument
    ) throws -> Double {
        guard case let .edge(edgeID) = document.subshapes[subshapeID],
              let edge = document.brep.edges[edgeID],
              let start = document.brep.vertices[edge.startVertexID],
              let end = document.brep.vertices[edge.endVertexID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                tolerance: .standard,
                message: "Chamfer fixture edge could not be measured."
            )
        }
        return (end.point - start.point).length
    }

    private func context(
        for fixture: (
            brep: BRepModel,
            subshapes: SubshapeIndex,
            lineage: [SubshapeID: TopologyLineage]
        )
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }
}
