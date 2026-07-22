import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Face Knife Schema")
struct FaceKnifeSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsLegacyPersistentNameField() throws {
        let featureID = FeatureID()
        let feature = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: featureID),
            face: StableSubshapeReference(
                subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
                geometrySignature: .untrimmedPlane(origin: .origin)
            ),
            loop: [
                .origin,
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ]
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded Face Knife object.")
            return
        }
        object["facePersistentName"] = "legacy"
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FaceKnifeFeature.self, from: legacySchema)
        }
    }
}
