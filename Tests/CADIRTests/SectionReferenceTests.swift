import Foundation
import Testing
import CADCore
import CADIR

@Suite("Shared section reference")
struct SectionReferenceTests {
    @Test
    func preservesSourceRoleAndIndex() throws {
        let source = FeatureID()
        let references: [SectionReference] = [
            .profile(ProfileReference(featureID: source, profileIndex: 3)),
            .curve(CurveSectionReference(featureID: source)),
        ]
        for reference in references {
            let data = try JSONEncoder().encode(reference)
            let restored = try JSONDecoder().decode(SectionReference.self, from: data)
            #expect(restored == reference)
            #expect(restored.featureID == source)
            #expect(restored.inputRole == (reference.isProfile ? .profile : .curve))
        }
    }

    @Test
    func rejectsInvalidIndexesAndMixedReferenceFields() throws {
        let source = FeatureID()
        let invalid = SectionReference.profile(ProfileReference(featureID: source, profileIndex: -1))
        #expect(throws: FeatureEvaluationError.self) { try JSONEncoder().encode(invalid) }

        let valid = SectionReference.profile(ProfileReference(featureID: source))
        let data = try JSONEncoder().encode(valid)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["profileIndex"] = -1
        let invalidData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: FeatureEvaluationError.self) {
            try JSONDecoder().decode(SectionReference.self, from: invalidData)
        }
        object["kind"] = "curve"
        let mixedData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SectionReference.self, from: mixedData)
        }
    }
}
