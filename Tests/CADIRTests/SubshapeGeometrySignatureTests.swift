import Foundation
import Testing
import CADCore
import CADGeometry
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
