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
            .curve(CurveSectionReference(featureID: source, parameterDomain: .closed(0.2, 0.8), isReversed: true)),
        ]
        for reference in references {
            let data = try JSONEncoder().encode(reference)
            let restored = try JSONDecoder().decode(SectionReference.self, from: data)
            #expect(restored == reference)
            #expect(restored.featureID == source)
            #expect(restored.inputRole == (reference.isProfile ? .profile : .curve))
        }
    }

    @Test func rejectsInvalidCurveIntervalsOnBothPersistencePaths() throws {
        for domain in [ParameterDomain.unbounded, .periodic(period: 1), .closed(1, 0), .closed(0, 0), .closed(0, .infinity)] {
            let reference = CurveSectionReference(featureID: FeatureID(), parameterDomain: domain)
            #expect(throws: FeatureEvaluationError.self) { try JSONEncoder().encode(reference) }
            #expect(throws: FeatureEvaluationError.self) { try JSONEncoder().encode(SectionReference.curve(reference)) }
        }
        let reference = CurveSectionReference(featureID: FeatureID(), parameterDomain: .closed(2, 3))
        #expect(try JSONDecoder().decode(CurveSectionReference.self,
            from: JSONEncoder().encode(reference)) == reference)
    }

    @Test func rejectsCurvePayloadWithoutExplicitDirection() throws {
        let reference = SectionReference.curve(CurveSectionReference(featureID: FeatureID()))
        let data = try JSONEncoder().encode(reference)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isReversed")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SectionReference.self, from: JSONSerialization.data(withJSONObject: object))
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
