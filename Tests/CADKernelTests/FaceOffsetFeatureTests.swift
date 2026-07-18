import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Face offset feature")
struct FaceOffsetFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func translatesImportedAnalyticPlaneRepresentation() throws {
        let document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let faceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let resolved = try StableSubshapeResolver().topologyReference(
            for: source.stableSubshapeReference(for: faceSubshapeID),
            model: source.brep,
            subshapes: source.subshapes,
            lineage: source.lineage,
            tolerance: .standard
        )
        guard case let .face(faceID) = resolved,
              let face = source.brep.faces[faceID],
              case let .plane(plane) = source.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("Extruded end face must provide the canonical planar fixture.")
            return
        }
        let bodyID = try #require(source.brep.bodies.keys.first)
        let loopID = try #require(face.loops.first)
        let vertexIDs = try source.brep.orderedVertexIDs(for: loopID)
        let originalPoints = try Dictionary(uniqueKeysWithValues: vertexIDs.map { vertexID in
            (vertexID, try #require(source.brep.vertices[vertexID]).point)
        })
        var importedModel = source.brep
        importedModel.geometry.surfaces[face.surfaceID] = .analytic(.plane(
            origin: plane.origin,
            normal: plane.normal
        ))
        let displacement = Vector3D(x: 0.001, y: 0.002, z: 0.003)
        let translator = PlanarFaceTranslator()

        let outwardNormal = try translator.outwardNormal(
            faceID: faceID,
            bodyID: bodyID,
            featureID: FeatureID(),
            model: importedModel,
            tolerance: .standard
        )
        try translator.translate(
            faceID: faceID,
            bodyID: bodyID,
            displacement: displacement,
            featureID: FeatureID(),
            model: &importedModel,
            tolerance: .standard
        )

        #expect(outwardNormal.dot(.unitZ) > 1.0 - 1.0e-12)
        for vertexID in vertexIDs {
            let original = try #require(originalPoints[vertexID])
            let translated = try #require(importedModel.vertices[vertexID]).point
            #expect((translated - (original + displacement)).length <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetsPlanarFaceAlongItsOutwardNormalWithExactLineage() throws {
        let sourceDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(sourceDocument.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        let faceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let faceReference = try source.stableSubshapeReference(for: faceSubshapeID)

        for distance in [0.005, -0.005] {
            var document = sourceDocument
            let offsetID = FeatureID()
            let operation = FeatureOperation.faceOffset(FaceOffsetFeature(
                target: FaceOffsetTargetReference(featureID: sourceFeatureID),
                face: faceReference,
                distance: .constant(.length(distance, unit: .meter))
            ))
            let node = try FeatureNodeFactory.make(operation: operation, id: offsetID, in: document, tolerance: .standard)
            document.designGraph.nodes[offsetID] = node
            document.designGraph.order.append(offsetID)
            document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: offsetID))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            let evaluated = try evaluator.evaluate(document)
            let repeated = try evaluator.evaluate(document)
            let expectedDepth = 0.010 + distance
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * expectedDepth) <= 1.0e-12)
            #expect(evaluated.brep == repeated.brep)
            #expect(evaluated.subshapes == repeated.subshapes)
            #expect(evaluated.lineage == repeated.lineage)
            let offsetLineage = evaluated.lineage.values.filter { $0.output.featureID == offsetID }
            #expect(offsetLineage.count == 27)
            #expect(offsetLineage.allSatisfy { $0.relation == .preserved && $0.parents.count == 1 })
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
                Issue.record("Offset stable face must resolve to its exact planar descendant.")
                return
            }
            #expect(abs(plane.origin.z - expectedDepth) <= 1.0e-12)
        }
    }
}
