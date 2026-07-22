import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Sketch spline tangency constraint schema")
struct SketchSplineTangencyConstraintTests {
    @Test(.timeLimit(.minutes(1)))
    func roundTripsEveryExplicitOrientationBranch() throws {
        let spline = SketchEntityID()
        let otherSpline = SketchEntityID()
        let line = SketchEntityID()
        let first = SketchSplineEndpointReference(splineID: spline, endpoint: .end)
        let second = SketchSplineEndpointReference(splineID: otherSpline, endpoint: .start)

        for orientation in SketchTangentOrientation.allCases {
            let constraints: [SketchConstraint] = [
                .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: first,
                    line: line,
                    orientation: orientation
                )),
                .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: first,
                    second: second,
                    orientation: orientation
                )),
                .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: first,
                    second: second,
                    orientation: orientation
                )),
            ]
            for constraint in constraints {
                let data = try JSONEncoder().encode(constraint)
                #expect(try JSONDecoder().decode(SketchConstraint.self, from: data) == constraint)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsRemovedFlatSplineLineSchema() throws {
        let constraint = SketchConstraint.splineEndpointTangent(
            SketchSplineLineTangencyConstraint(
                splineEndpoint: SketchSplineEndpointReference(
                    splineID: SketchEntityID(),
                    endpoint: .start
                ),
                line: SketchEntityID(),
                orientation: .aligned
            )
        )
        var object = try jsonObject(from: JSONEncoder().encode(constraint))
        guard let nested = object.removeValue(forKey: "splineLineTangency") as? [String: Any],
              let endpoint = nested["splineEndpoint"] as? [String: Any] else {
            throw SchemaError.invalidPackage("Expected typed spline-line tangency payload.")
        }
        object["splineID"] = endpoint["splineID"]
        object["endpoint"] = endpoint["endpoint"]
        object["lineID"] = nested["line"]

        try expectDecodingFailure(from: object)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownNestedTangencyField() throws {
        let constraint = SketchConstraint.tangentSplineEndpoints(
            SketchSplineEndpointTangencyConstraint(
                first: SketchSplineEndpointReference(
                    splineID: SketchEntityID(),
                    endpoint: .end
                ),
                second: SketchSplineEndpointReference(
                    splineID: SketchEntityID(),
                    endpoint: .start
                ),
                orientation: .opposed
            )
        )
        var object = try jsonObject(from: JSONEncoder().encode(constraint))
        guard var nested = object["splineEndpointTangency"] as? [String: Any] else {
            throw SchemaError.invalidPackage("Expected typed spline endpoint tangency payload.")
        }
        nested["legacyDirection"] = true
        object["splineEndpointTangency"] = nested

        try expectDecodingFailure(from: object)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSelfTangencyDuringEncoding() {
        let reference = SketchSplineEndpointReference(
            splineID: SketchEntityID(),
            endpoint: .start
        )
        let constraint = SketchConstraint.tangentSplineEndpoints(
            SketchSplineEndpointTangencyConstraint(
                first: reference,
                second: reference,
                orientation: .aligned
            )
        )

        #expect(throws: SketchError.self) {
            _ = try JSONEncoder().encode(constraint)
        }
    }

    private func expectDecodingFailure(from object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SketchConstraint.self, from: data)
        }
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchemaError.invalidPackage("Expected JSON object fixture.")
        }
        return object
    }
}
