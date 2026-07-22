import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Face Delete Schema")
struct FaceDeleteSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsLegacyPersistentNameField() throws {
        let featureID = FeatureID()
        let feature = FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: featureID),
            faces: [StableSubshapeReference(
                subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
                geometrySignature: .untrimmedPlane(origin: .origin)
            )]
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded Face Delete object.")
            return
        }
        object["facePersistentNames"] = ["legacy"]
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FaceDeleteFeature.self, from: legacySchema)
        }
    }
}
