import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Face Loop Offset Schema")
struct FaceLoopOffsetSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsRemovedGapFillField() throws {
        let featureID = FeatureID()
        let feature = FaceLoopOffsetFeature(
            target: FaceLoopOffsetTargetReference(featureID: featureID),
            face: StableSubshapeReference(
                subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
                geometrySignature: .face(
                    kind: .plane,
                    boundaryPoints: [Point3D(x: 0.0, y: 0.0, z: 0.0)]
                )
            ),
            distance: .constant(.length(2.0, unit: .millimeter))
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded face loop offset object.")
            return
        }
        object["gapFill"] = "linear"
        let removedSchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FaceLoopOffsetFeature.self, from: removedSchema)
        }
    }
}
