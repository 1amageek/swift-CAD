import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Tessellated face-run provenance")
struct MeshTessellatorFaceRunTests {
    // MARK: - Fixtures

    private static func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private static func boxModel() throws -> BRepModel {
        var document = CADDocument(units: .meters)
        let featureID = FeatureID()
        let node = try FeatureNodeFactory.make(
            operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
                width: length(2.0),
                depth: length(3.0),
                height: length(4.0)
            )))),
            id: featureID,
            name: "face-run-box",
            in: document,
            tolerance: .standard
        )
        document.designGraph.nodes[featureID] = node
        document.designGraph.order.append(featureID)
        document.designGraph.revision = document.designGraph.revision.advanced()
        return try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document).brep
    }

    /// The faces of one body in the order the tessellator traverses them.
    private static func traversedFaceIDs(
        of bodyID: BodyID,
        in model: BRepModel
    ) throws -> [FaceID] {
        let body = try #require(model.bodies[bodyID])
        return try body.shellIDs.flatMap { shellID -> [FaceID] in
            try #require(model.shells[shellID]).faceIDs
        }
    }

    // MARK: - Emission contracts

    @Test(.timeLimit(.minutes(1)))
    func runsPartitionEveryTriangleInTraversalOrder() throws {
        let model = try Self.boxModel()

        let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model)

        #expect(meshes.count == 1)
        let bodyID = try #require(meshes.keys.first)
        let mesh = try #require(meshes[bodyID])
        let traversedFaceIDs = try Self.traversedFaceIDs(of: bodyID, in: model)

        #expect(mesh.faceRuns.map(\.faceID) == traversedFaceIDs)
        #expect(mesh.faceRuns.allSatisfy { $0.triangleCount > 0 })
        #expect(mesh.faceRuns.reduce(0) { $0 + $1.triangleCount } == mesh.indices.count / 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlanarBoxRecordsTwoTrianglesPerFace() throws {
        let model = try Self.boxModel()

        let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model)
        let mesh = try #require(meshes.values.first)

        #expect(mesh.faceRuns.count == 6)
        #expect(mesh.faceRuns.allSatisfy { $0.triangleCount == 2 })
        #expect(mesh.indices.count == 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func incrementalExtractionPreservesTheRecordedRuns() throws {
        let model = try Self.boxModel()
        let tessellator = MeshTessellator(tolerance: .standard)
        let full = try tessellator.tessellate(model: model)
        let bodyID = try #require(full.keys.first)

        // Incremental re-tessellation runs on an extracted submodel. The runs a
        // reused mesh carries are only valid if the extracted body traverses its
        // faces in the same order.
        let extracted = try BRepBodySubmodelExtractor().extract(
            bodyIDs: [bodyID],
            from: model
        )
        let incremental = try tessellator.tessellate(model: extracted)

        #expect(incremental[bodyID]?.faceRuns == full[bodyID]?.faceRuns)
        #expect(incremental[bodyID] == full[bodyID])
    }
}
