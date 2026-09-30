import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Edge Offset Schema")
struct EdgeOffsetSchemaTests {
    private func reference(_ featureID: FeatureID, _ role: String, _ ordinal: Int) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: role, ordinal: ordinal),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsEveryOptionAndRefusesNoEdge() throws {
        let featureID = FeatureID()
        let feature = EdgeOffsetFeature(
            target: PatternTargetReference(featureID: featureID),
            edges: [reference(featureID, "edge", 0), reference(featureID, "edge", 1)],
            supportFace: reference(featureID, "face", 0),
            distance: .constant(.length(2.0, unit: .millimeter)),
            isSymmetric: true, gapFill: .linear
        )
        let encoded = try JSONEncoder().encode(feature)
        #expect(try JSONDecoder().decode(EdgeOffsetFeature.self, from: encoded) == feature)
        #expect(throws: FeatureEvaluationError.self) {
            try EdgeOffsetFeature(
                target: PatternTargetReference(featureID: featureID), edges: [],
                supportFace: reference(featureID, "face", 0), distance: .constant(.length(1, unit: .millimeter))
            ).validate()
        }
    }
}
