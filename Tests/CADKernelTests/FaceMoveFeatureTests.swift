import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Face move feature")
struct FaceMoveFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func translatesPlanarFaceByArbitraryVectorWithExactLineage() throws {
        let sourceDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(sourceDocument.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        let faceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let faceReference = try source.stableSubshapeReference(for: faceSubshapeID)
        let sourceFaceReference = try StableSubshapeResolver().topologyReference(
            for: faceReference,
            model: source.brep,
            subshapes: source.subshapes,
            lineage: source.lineage,
            tolerance: .standard
        )
        guard case let .face(sourceFaceID) = sourceFaceReference,
              let sourceFace = source.brep.faces[sourceFaceID],
              case let .plane(sourcePlane) = source.brep.geometry.surfaces[sourceFace.surfaceID] else {
            Issue.record("Source stable face must resolve to its exact planar topology.")
            return
        }

        for signedDistance in [0.007071067811865476, -0.007071067811865476] {
            var document = sourceDocument
            let moveID = FeatureID()
            let operation = FeatureOperation.faceMove(FaceMoveFeature(
                target: FaceMoveTargetReference(featureID: sourceFeatureID),
                face: faceReference,
                translation: DirectMoveVector(
                    direction: Vector3D(x: 1.0, y: 0.0, z: 1.0),
                    distance: .constant(.length(signedDistance, unit: .meter))
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
            let component = signedDistance.sign == .minus ? -0.005 : 0.005
            let expectedDepth = 0.010 + component
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * expectedDepth) <= 1.0e-12)
            #expect(evaluated.brep == repeated.brep)
            #expect(evaluated.subshapes == repeated.subshapes)
            #expect(evaluated.lineage == repeated.lineage)
            let moveLineage = evaluated.lineage.values.filter { $0.output.featureID == moveID }
            #expect(moveLineage.count == 27)
            #expect(moveLineage.allSatisfy { $0.relation == .preserved && $0.parents.count == 1 })
            let resolved = try StableSubshapeResolver().topologyReference(
                for: faceReference,
                model: evaluated.brep,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            )
            guard case let .face(faceID) = resolved,
                  let face = evaluated.brep.faces[faceID],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else {
                Issue.record("Moved stable face must resolve to its exact planar descendant.")
                return
            }
            #expect(abs(plane.origin.z - expectedDepth) <= 1.0e-12)
            #expect(abs(plane.origin.x - (sourcePlane.origin.x + component)) <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedBodyAndSelectionIdentity() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let unrelated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(unrelatedDocument)
        let faceSubshapeID = SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let featureID = FeatureID()
        let result = try FaceMoveFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .faceMove(FaceMoveFeature(
                    target: FaceMoveTargetReference(featureID: targetFeatureID),
                    face: try target.stableSubshapeReference(for: faceSubshapeID),
                    translation: DirectMoveVector(
                        direction: .unitZ,
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

        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }
}
