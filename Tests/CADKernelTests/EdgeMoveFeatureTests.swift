import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Edge move feature")
struct EdgeMoveFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func translatesStraightEdgeWhilePreservingExactPlanarTopology() throws {
        let sourceDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(sourceDocument.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        let edgeSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 8
        )
        let edgeReference = try source.stableSubshapeReference(for: edgeSubshapeID)
        guard case let .edge(sourceEdgeID) = source.subshapes[edgeSubshapeID],
              let sourceEdge = source.brep.edges[sourceEdgeID],
              let sourceStart = source.brep.vertices[sourceEdge.startVertexID]?.point,
              let sourceEnd = source.brep.vertices[sourceEdge.endVertexID]?.point else {
            Issue.record("Edge move fixture must resolve its source edge.")
            return
        }
        let midpointX = 0.5 * (sourceStart.x + sourceEnd.x)
        let outward = Vector3D(x: midpointX < 0.0 ? -1.0 : 1.0, y: 0.0, z: 0.0)

        for distance in [0.005, -0.005] {
            var document = sourceDocument
            let moveID = FeatureID()
            let operation = FeatureOperation.edgeMove(EdgeMoveFeature(
                target: EdgeMoveTargetReference(featureID: sourceFeatureID),
                edge: edgeReference,
                translation: DirectMoveVector(
                    direction: outward,
                    distance: .constant(.length(distance, unit: .meter))
                )
            ))
            let node = try FeatureNodeFactory.make(operation: operation, id: moveID, in: document, tolerance: .standard)
            document.designGraph.nodes[moveID] = node
            document.designGraph.order.append(moveID)
            document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: moveID))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            let evaluated = try evaluator.evaluate(document)
            let repeated = try evaluator.evaluate(document)
            let expectedArea = 0.040 * 0.020 + 0.5 * 0.020 * distance
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedArea * 0.010) <= 1.0e-12)
            #expect(evaluated.brep == repeated.brep)
            #expect(evaluated.subshapes == repeated.subshapes)
            #expect(evaluated.lineage == repeated.lineage)
            #expect(evaluated.brep.loops.values.allSatisfy { loop in
                loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
            })
            let moveLineage = evaluated.lineage.values.filter { $0.output.featureID == moveID }
            #expect(moveLineage.count == 27)
            #expect(moveLineage.allSatisfy { $0.relation == .preserved && $0.parents.count == 1 })
            let resolved = try StableSubshapeResolver().topologyReference(
                for: edgeReference,
                model: evaluated.brep,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            )
            guard case let .edge(movedEdgeID) = resolved,
                  let movedEdge = evaluated.brep.edges[movedEdgeID],
                  let movedStart = evaluated.brep.vertices[movedEdge.startVertexID]?.point,
                  let movedEnd = evaluated.brep.vertices[movedEdge.endVertexID]?.point else {
                Issue.record("Moved stable edge must resolve to its exact descendant.")
                return
            }
            let displacement = outward * distance
            #expect(movedStart.isApproximatelyEqual(to: sourceStart + displacement, tolerance: 1.0e-12))
            #expect(movedEnd.isApproximatelyEqual(to: sourceEnd + displacement, tolerance: 1.0e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedBodyAndSelectionIdentity() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let unrelated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(unrelatedDocument)
        let edgeSubshapeID = SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 8
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        guard case let .edge(edgeID) = target.subshapes[edgeSubshapeID],
              let edge = target.brep.edges[edgeID],
              let start = target.brep.vertices[edge.startVertexID]?.point,
              let end = target.brep.vertices[edge.endVertexID]?.point else {
            Issue.record("Edge move fixture must resolve its target edge.")
            return
        }
        let direction = Vector3D(x: 0.5 * (start.x + end.x) < 0.0 ? -1.0 : 1.0, y: 0.0, z: 0.0)
        let moveID = FeatureID()
        let result = try EdgeMoveFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: moveID,
                operation: .edgeMove(EdgeMoveFeature(
                    target: EdgeMoveTargetReference(featureID: targetFeatureID),
                    edge: try target.stableSubshapeReference(for: edgeSubshapeID),
                    translation: DirectMoveVector(
                        direction: direction,
                        distance: .constant(.length(0.005, unit: .meter))
                    )
                )),
                inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: fixture.brep,
                profiles: [:],
                subshapes: fixture.subshapes,
                lineage: fixture.lineage,
                tolerance: .standard
            )
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == moveID
        }

        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs == targetSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelatedSubshapeIDs))
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.allSatisfy {
            Set($0.parents).isSubset(of: targetSubshapeIDs)
        })
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsEdgeOwnedByAnotherTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let foreignDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let foreignFeatureID = try #require(foreignDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let foreign = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(foreignDocument)
        let foreignEdgeSubshapeID = SubshapeID(
            featureID: foreignFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 8
        )
        let foreignEdge = try foreign.stableSubshapeReference(for: foreignEdgeSubshapeID)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let moveID = FeatureID()

        do {
            _ = try EdgeMoveFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: moveID,
                    operation: .edgeMove(EdgeMoveFeature(
                        target: EdgeMoveTargetReference(featureID: targetFeatureID),
                        edge: foreignEdge,
                        translation: DirectMoveVector(
                            direction: Vector3D(x: -1.0, y: 0.0, z: 0.0),
                            distance: .constant(.length(0.005, unit: .meter))
                        )
                    )),
                    inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: fixture.brep,
                    profiles: [:],
                    subshapes: fixture.subshapes,
                    lineage: fixture.lineage,
                    tolerance: .standard
                )
            )
            Issue.record("An edge owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == moveID)
            #expect(error.subshapeID == foreignEdge.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }
}
