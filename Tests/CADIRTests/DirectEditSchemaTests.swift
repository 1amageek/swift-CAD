import CADCore
import CADGeometry
import Foundation
import Testing
@testable import CADIR

@Suite("Direct Edit Schema")
struct DirectEditSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsAcrossDirectEditRequests() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let face = stableReference(featureID: sourceID, role: "face")
        let edge = stableReference(featureID: sourceID, role: "edge")
        let vertex = stableReference(featureID: sourceID, role: "vertex")
        let translation = DirectMoveVector(
            direction: .unitX,
            distance: .constant(.length(0.005, unit: .meter))
        )

        try expectUnknownFieldRejected(FaceMoveFeature.self, value: FaceMoveFeature(
            target: FaceMoveTargetReference(featureID: sourceID),
            face: face,
            translation: translation
        ))
        try expectUnknownFieldRejected(FaceOffsetFeature.self, value: FaceOffsetFeature(
            target: FaceOffsetTargetReference(featureID: sourceID),
            face: face,
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(EdgeMoveFeature.self, value: EdgeMoveFeature(
            target: EdgeMoveTargetReference(featureID: sourceID),
            edge: edge,
            translation: translation
        ))
        try expectUnknownFieldRejected(VertexMoveFeature.self, value: VertexMoveFeature(
            target: VertexMoveTargetReference(featureID: sourceID),
            vertex: vertex,
            translation: translation
        ))
        try expectUnknownFieldRejected(SurfaceOffsetFeature.self, value: SurfaceOffsetFeature(
            target: SurfaceOperationTargetReference(featureID: sourceID),
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(SurfaceTrimFeature.self, value: SurfaceTrimFeature(
            target: SurfaceOperationTargetReference(featureID: sourceID),
            uDomain: .closed(-0.010, 0.010),
            vDomain: .closed(-0.005, 0.005)
        ))
        try expectUnknownFieldRejected(SurfaceExtendFeature.self, value: SurfaceExtendFeature(
            target: SurfaceOperationTargetReference(featureID: sourceID),
            distances: SurfaceExtensionDistances(
                lowerU: .constant(.length(0.005, unit: .meter))
            )
        ))
        try expectUnknownFieldRejected(SurfaceMatchFeature.self, value: SurfaceMatchFeature(
            source: SurfaceOperationTargetReference(featureID: sourceID),
            target: SurfaceOperationTargetReference(featureID: targetID),
            sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
            targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
            continuity: .positional
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsInSharedDirectEditValues() throws {
        try expectUnknownFieldRejected(DirectMoveVector.self, value: DirectMoveVector(
            direction: .unitX,
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(SurfaceExtensionDistances.self, value: SurfaceExtensionDistances(
            lowerU: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(
            SurfaceOperationTargetReference.self,
            value: SurfaceOperationTargetReference(featureID: FeatureID())
        )
    }

    private func stableReference(
        featureID: FeatureID,
        role: String
    ) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: role, ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
    }

    private func expectUnknownFieldRejected<Value: Codable>(
        _ type: Value.Type,
        value: Value
    ) throws {
        let encoded = try JSONEncoder().encode(value)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded direct edit object.")
            return
        }
        object["legacyPersistentName"] = "legacy"
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: legacySchema)
        }
    }
}
