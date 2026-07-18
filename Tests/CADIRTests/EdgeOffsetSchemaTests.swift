import CADCore
import Foundation
import Testing
@testable import CADIR
import CADTopology

@Suite("Edge Offset Schema")
struct EdgeOffsetSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsRemovedGapFillField() throws {
        let featureID = FeatureID()
        let edge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "edge", ordinal: 0),
            geometrySignature: .edge(
                kind: .line,
                start: .origin,
                midpoint: Point3D(x: 0.5, y: 0.0, z: 0.0),
                end: Point3D(x: 1.0, y: 0.0, z: 0.0)
            )
        )
        let face = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
            geometrySignature: .face(kind: .plane, boundaryPoints: [.origin])
        )
        let feature = EdgeOffsetFeature(
            target: EdgeOffsetTargetReference(featureID: featureID),
            edge: edge,
            supportFace: face,
            distance: .constant(.length(2.0, unit: .millimeter))
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded edge offset object.")
            return
        }
        object["gapFill"] = "linear"
        let removedSchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(EdgeOffsetFeature.self, from: removedSchema)
        }
    }
}
