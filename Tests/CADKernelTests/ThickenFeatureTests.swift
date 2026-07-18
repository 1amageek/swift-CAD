import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Thicken feature")
struct ThickenFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func thickensPlanarSheetOnEveryDeclaredSide() throws {
        let fixture = try planarSheetFixture()
        let sheetFaceID = SubshapeID(
            featureID: fixture.sheetFeatureID,
            role: GeneratedSubshapeRole.face.rawValue,
            ordinal: 0
        )
        let sheetFace = try fixture.evaluated.stableSubshapeReference(for: sheetFaceID)
        let sourceFaceID = try #require(fixture.evaluated.subshapes[sheetFaceID]?.faceID)
        let sourceFace = try #require(fixture.evaluated.brep.faces[sourceFaceID])
        guard case let .plane(plane) = fixture.evaluated.brep.geometry.surfaces[sourceFace.surfaceID] else {
            Issue.record("Thicken fixture source must be planar.")
            return
        }
        let normal = sourceFace.orientation == .forward ? plane.normal : -plane.normal
        let sourceCoordinate = Vector3D(
            x: plane.origin.x,
            y: plane.origin.y,
            z: plane.origin.z
        ).dot(normal)
        let thickness = 0.004
        for side in [ThickenSide.positive, .negative, .symmetric] {
            var document = fixture.document
            let featureID = FeatureID()
            let operation = FeatureOperation.thicken(ThickenFeature(
                target: ThickenTargetReference(featureID: fixture.sheetFeatureID),
                thickness: .constant(.length(thickness, unit: .meter)),
                side: side
            ))
            let node = try FeatureNodeFactory.make(operation: operation, id: featureID, in: document, tolerance: .standard)
            document.designGraph.nodes[featureID] = node
            document.designGraph.order.append(featureID)
            document.designGraph.dependencies.append(DependencyEdge(source: fixture.sheetFeatureID, target: featureID))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * thickness) <= 1.0e-12)
            let coordinates = evaluated.brep.vertices.values.map { vertex in
                Vector3D(x: vertex.point.x, y: vertex.point.y, z: vertex.point.z).dot(normal)
            }
            let lower = try #require(coordinates.min()) - sourceCoordinate
            let upper = try #require(coordinates.max()) - sourceCoordinate
            switch side {
            case .positive:
                #expect(abs(lower) <= 1.0e-12)
                #expect(abs(upper - thickness) <= 1.0e-12)
            case .negative:
                #expect(abs(lower + thickness) <= 1.0e-12)
                #expect(abs(upper) <= 1.0e-12)
            case .symmetric:
                #expect(abs(lower + 0.5 * thickness) <= 1.0e-12)
                #expect(abs(upper - 0.5 * thickness) <= 1.0e-12)
            }
            let faceDescendants = evaluated.lineage.values.filter {
                $0.output.featureID == featureID
                    && $0.output.role == GeneratedSubshapeRole.face.rawValue
                    && $0.parents.contains(sheetFace.subshapeID)
            }
            #expect(faceDescendants.count == 2)
            #expect(faceDescendants.allSatisfy { $0.relation == .split })
        }
    }

    private func planarSheetFixture() throws -> (
        document: CADDocument,
        sheetFeatureID: FeatureID,
        evaluated: EvaluatedDocument
    ) {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let solidFeatureID = try #require(document.designGraph.order.last)
        let solid = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let retainedID = SubshapeID(
            featureID: solidFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let removedFaces = try solid.subshapes.entries.keys.filter { subshapeID in
            guard subshapeID != retainedID,
                  case .face = solid.subshapes[subshapeID] else { return false }
            return true
        }.map { try solid.stableSubshapeReference(for: $0) }
        #expect(removedFaces.count == 5)
        let sheetFeatureID = FeatureID()
        let operation = FeatureOperation.faceDelete(FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: solidFeatureID),
            faces: removedFaces
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: sheetFeatureID, in: document, tolerance: .standard)
        document.designGraph.nodes[sheetFeatureID] = node
        document.designGraph.order.append(sheetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: solidFeatureID, target: sheetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        return (document, sheetFeatureID, evaluated)
    }
}

private extension TopologyReference {
    var faceID: FaceID? {
        if case let .face(faceID) = self { return faceID }
        return nil
    }
}
