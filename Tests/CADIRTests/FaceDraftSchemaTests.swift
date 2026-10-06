import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Face Draft Schema")
struct FaceDraftSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func defaultMethodRoundTripsWithoutChangingEarlierSchema() throws {
        let id = FeatureID()
        let face = StableSubshapeReference(subshapeID: .init(featureID: id, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin))
        let neutral = StableSubshapeReference(subshapeID: .init(featureID: id, role: "face", ordinal: 1),
            geometrySignature: .untrimmedPlane(origin: .init(x: 0, y: 0, z: 1)))
        let feature = FaceDraftFeature(target: .init(featureID: id), faces: [face], neutralFace: neutral,
            angle: .constant(.angle(5, unit: .degree)))
        let data = try JSONEncoder().encode(feature)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["method"] == nil)
        #expect(try JSONDecoder().decode(FaceDraftFeature.self, from: data) == feature)
        #expect(try JSONDecoder().decode(FaceDraftFeature.self, from: data).method == .isocline)
        var explicit = feature
        explicit.method = .surface(reference: neutral)
        #expect(try JSONDecoder().decode(FaceDraftFeature.self,
            from: JSONEncoder().encode(explicit)) == explicit)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsLegacyPullDirectionField() throws {
        let featureID = FeatureID()
        let target = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
        let neutral = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 1),
            geometrySignature: .untrimmedPlane(
                origin: Point3D(x: 0.0, y: 0.0, z: 1.0)
            )
        )
        let feature = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: featureID),
            faces: [target],
            neutralFace: neutral,
            angle: .constant(.angle(5.0, unit: .degree))
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded Face Draft object.")
            return
        }
        object["pullDirection"] = ["x": 0.0, "y": 0.0, "z": 1.0]
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FaceDraftFeature.self, from: legacySchema)
        }
    }
}
