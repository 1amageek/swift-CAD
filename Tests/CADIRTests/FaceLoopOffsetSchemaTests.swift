import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Face Loop Offset Schema")
struct FaceLoopOffsetSchemaTests {
    private func face(_ featureID: FeatureID, _ ordinal: Int) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: ordinal),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsEveryOptionAndRejectsUnknownFields() throws {
        let featureID = FeatureID()
        let feature = FaceLoopOffsetFeature(
            target: PatternTargetReference(featureID: featureID),
            faces: [face(featureID, 0), face(featureID, 1)],
            distance: .constant(.length(2.0, unit: .millimeter)),
            side: .symmetric, gapFill: .natural, isIndividual: false
        )
        let encoded = try JSONEncoder().encode(feature)
        #expect(try JSONDecoder().decode(FaceLoopOffsetFeature.self, from: encoded) == feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded face loop offset object.")
            return
        }
        object["face"] = object["faces"]
        let unknown = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(FaceLoopOffsetFeature.self, from: unknown) }
    }

    @Test(.timeLimit(.minutes(1)))
    func refusesNoFaceAndRepeatedFaces() throws {
        let featureID = FeatureID()
        #expect(throws: FeatureEvaluationError.self) {
            try FaceLoopOffsetFeature(target: PatternTargetReference(featureID: featureID), faces: [], distance: .constant(.length(1, unit: .millimeter))).validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try FaceLoopOffsetFeature(
                target: PatternTargetReference(featureID: featureID), faces: [face(featureID, 0), face(featureID, 0)],
                distance: .constant(.length(1, unit: .millimeter))
            ).validate()
        }
    }
}
