import CADCore
import Foundation
import Testing
@testable import CADIR

@Suite("Curve derived sampling schema")
struct CurveDerivedSamplingSchemaTests {
    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func bridgeCurveRejectsRemovedSampleCountField() throws {
        let feature = BridgeCurveFeature(
            start: BridgeCurveEndpointTarget(
                curve: .line(Line3D(origin: .origin, direction: .unitX)),
                parameter: 0.0,
                requiredLevel: .tangent
            ),
            end: BridgeCurveEndpointTarget(
                curve: .line(Line3D(
                    origin: Point3D(x: 2.0, y: 1.0, z: 0.0),
                    direction: .unitX
                )),
                parameter: 0.0,
                requiredLevel: .tangent
            ),
            continuityTolerances: .standard(modelingTolerance: Self.testTolerance)
        )
        let legacySchema = try addingRemovedSampleCount(to: feature)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeCurveFeature.self, from: legacySchema)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveEditRejectsRemovedSampleCountField() throws {
        let source = CurveOutputReference(featureID: FeatureID())
        let feature = CurveEditFeature(
            source: source,
            edits: [
                .setControlPoint(CurveControlPointEdit(
                    target: CurveControlPointReference(
                        curve: source,
                        controlPointIndex: 0
                    ),
                    point: Point3D(x: 1.0, y: 2.0, z: 3.0)
                )),
            ]
        )
        let legacySchema = try addingRemovedSampleCount(to: feature)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CurveEditFeature.self, from: legacySchema)
        }
    }

    private func addingRemovedSampleCount<T: Encodable>(to value: T) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Expected an encoded curve feature object."
                )
            )
        }
        object["sampleCount"] = 17
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
