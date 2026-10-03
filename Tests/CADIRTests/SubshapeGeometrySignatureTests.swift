import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADIR

@Suite("Subshape geometry signature")
struct SubshapeGeometrySignatureTests {
    @Test(.timeLimit(.minutes(1)))
    func exactPeriodicFaceRetainsBothAxesAndRejectsCorruptedSource() throws {
        let tolerance = ModelingTolerance.standard
        let source = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 2,
            uKnots: [0, 1, 2, 3], vKnots: [0, 1, 2, 3],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)],
                [Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: 1), Point3D(x: 0, y: 1, z: 1)],
                [Point3D(x: 0, y: 0, z: 2), Point3D(x: 1, y: 0, z: 2), Point3D(x: 0, y: 1, z: 2)]],
            weights: [[1, 1.5, 1], [1.25, 1, 1.75], [1, 2, 1]],
            isUPeriodic: true, isVPeriodic: true, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .u, to: 2.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: -0.25, tolerance: tolerance)
        let signature = SubshapeGeometrySignature.untrimmedFace(surface: .bSpline(source))
        let data = try JSONEncoder().encode(signature)
        let decoded = try JSONDecoder().decode(SubshapeGeometrySignature.self, from: data)
        #expect(decoded == signature)
        guard case let .face(face) = decoded, case let .bSpline(surface) = face.surface else {
            Issue.record("Face transport replaced exact periodic tensor geometry."); return
        }
        for (u, v) in [(2.75, -0.1), (3.0, 0.0), (6.25, 5.75)] {
            #expect(try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance)
                == source.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance))
        }
        var damaged = source
        damaged.weights[damaged.vControlPointCount - 1][0] *= 2
        #expect(throws: KernelError.self) {
            try JSONEncoder().encode(SubshapeGeometrySignature.untrimmedFace(surface: .bSpline(damaged)))
        }
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var encodedFace = try #require(root["face"] as? [String: Any])
        var encodedSurface = try #require(encodedFace["surface"] as? [String: Any])
        var spline = try #require(encodedSurface["bSpline"] as? [String: Any])
        spline.removeValue(forKey: "isVPeriodic")
        encodedSurface["bSpline"] = spline
        encodedFace["surface"] = encodedSurface
        root["face"] = encodedFace
        let missingAxis = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SubshapeGeometrySignature.self, from: missingAxis) }
    }

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

    @Test(.timeLimit(.minutes(1)))
    func exactPeriodicSpanRetainsItsCycleAndFundamentalOriginThroughTransport() throws {
        let tolerance = ModelingTolerance.standard
        let source = try BSplineCurve3D.periodic(degree: 3, cycleKnots: [3, 3.5, 5, 6, 8],
            controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 2, z: 0.5),
                Point3D(x: -1, y: 0, z: 1), Point3D(x: 0, y: -2, z: 0.5)],
            weights: [1, 2, 0.5, 1.5], tolerance: tolerance)
            .insertingKnot(3, tolerance: tolerance).changingPeriodicOrigin(to: 7.25, tolerance: tolerance)
        let signature = SubshapeGeometrySignature.edge(CurveSpanGeometrySignature(
            curve: .bSpline(source), startParameter: 7.75, endParameter: 8.25,
            startPoint: try source.point(at: 7.75, tolerance: tolerance),
            endPoint: try source.point(at: 8.25, tolerance: tolerance)))
        let decoded = try JSONDecoder().decode(SubshapeGeometrySignature.self, from: JSONEncoder().encode(signature))
        #expect(decoded == signature)
        guard case let .edge(span) = decoded, case let .bSpline(curve) = span.curve else {
            Issue.record("Periodic source transport replaced exact curve geometry.")
            return
        }
        #expect(curve.isPeriodic && curve.periodicOrigin == 7.25)
        #expect(curve.domain == .periodic(period: 5))
        for parameter in [7.75, 8, 8.25, 13.25] {
            #expect(try curve.parameterDerivatives(at: parameter, tolerance: tolerance)
                == source.parameterDerivatives(at: parameter, tolerance: tolerance))
        }
        var corrupted = source
        corrupted.weights[corrupted.controlPointCount - 1] *= 2
        let invalid = SubshapeGeometrySignature.edge(CurveSpanGeometrySignature(
            curve: .bSpline(corrupted), startParameter: 7.75, endParameter: 8.25,
            startPoint: span.startPoint, endPoint: span.endPoint))
        #expect(throws: KernelError.self) { _ = try JSONEncoder().encode(invalid) }
    }
}
