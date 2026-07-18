import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Vertex move feature")
struct VertexMoveFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func movesVertexBySplittingNonPlanarIncidentFacesExactly() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let vertexSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 7
        )
        let vertexReference = try source.stableSubshapeReference(for: vertexSubshapeID)
        guard case let .vertex(sourceVertexID) = source.subshapes[vertexSubshapeID],
              let sourcePoint = source.brep.vertices[sourceVertexID]?.point else {
            Issue.record("Vertex move fixture must resolve its source vertex.")
            return
        }
        let direction = try Vector3D(
            x: sourcePoint.x < 0.0 ? -1.0 : 1.0,
            y: sourcePoint.y < 0.0 ? -1.0 : 1.0,
            z: sourcePoint.z < 0.005 ? -1.0 : 1.0
        ).normalized(tolerance: 1.0e-12)
        let distance = 0.004
        let moveID = FeatureID()
        let operation = FeatureOperation.vertexMove(VertexMoveFeature(
            target: VertexMoveTargetReference(featureID: sourceFeatureID),
            vertex: vertexReference,
            translation: DirectMoveVector(
                direction: direction,
                distance: .constant(.length(distance, unit: .meter))
            )
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: moveID, in: document, tolerance: .standard)
        document.designGraph.nodes[moveID] = node
        document.designGraph.order.append(moveID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: moveID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 9)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(try evaluated.brep.volume(tolerance: .standard) > source.brep.volume(tolerance: .standard))
        let moveLineage = evaluated.lineage.values.filter { $0.output.featureID == moveID }
        #expect(moveLineage.count == 33)
        #expect(moveLineage.filter { $0.relation == .split && $0.output.role == "face" }.count == 6)
        #expect(moveLineage.filter { $0.relation == .generated && $0.output.role == "edge" }.count == 3)
        #expect(moveLineage.filter { $0.relation == .preserved }.count == 24)
        let resolved = try StableSubshapeResolver().topologyReference(
            for: vertexReference,
            model: evaluated.brep,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            tolerance: .standard
        )
        guard case let .vertex(movedVertexID) = resolved,
              let movedPoint = evaluated.brep.vertices[movedVertexID]?.point else {
            Issue.record("Moved stable vertex must resolve to its exact descendant.")
            return
        }
        #expect(movedPoint.isApproximatelyEqual(
            to: sourcePoint + direction * distance,
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedBodyAndSelectionIdentity() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let unrelated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(unrelatedDocument)
        let vertexSubshapeID = SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 7
        )
        guard case let .vertex(vertexID) = target.subshapes[vertexSubshapeID],
              let sourcePoint = target.brep.vertices[vertexID]?.point else {
            Issue.record("Vertex move fixture must resolve its target vertex.")
            return
        }
        let direction = try Vector3D(
            x: sourcePoint.x < 0.0 ? -1.0 : 1.0,
            y: sourcePoint.y < 0.0 ? -1.0 : 1.0,
            z: sourcePoint.z < 0.005 ? -1.0 : 1.0
        ).normalized(tolerance: 1.0e-12)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let result = try VertexMoveFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .vertexMove(VertexMoveFeature(
                    target: VertexMoveTargetReference(featureID: targetFeatureID),
                    vertex: try target.stableSubshapeReference(for: vertexSubshapeID),
                    translation: DirectMoveVector(
                        direction: direction,
                        distance: .constant(.length(0.004, unit: .meter))
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

        try result.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }
}
