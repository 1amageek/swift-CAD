import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Subshape geometry signature")
struct SubshapeGeometrySignatureTests {
    @Test
    func exactCurveSpanRoundTrips() throws {
        let signature = try SubshapeGeometrySignature.lineEdge(
            startPoint: .origin,
            endPoint: Point3D(x: 0.010, y: 0.0, z: 0.0)
        )

        let encoded = try JSONEncoder().encode(signature)
        let decoded = try JSONDecoder().decode(
            SubshapeGeometrySignature.self,
            from: encoded
        )

        #expect(decoded == signature)
    }

    @Test
    func rejectsSampleOnlyEdgeSchema() {
        let obsolete = Data("""
        {
          "kind": "edge",
          "curveKind": "line",
          "start": {"x": 0, "y": 0, "z": 0},
          "midpoint": {"x": 0.5, "y": 0, "z": 0},
          "end": {"x": 1, "y": 0, "z": 0}
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                SubshapeGeometrySignature.self,
                from: obsolete
            )
        }
    }
}
