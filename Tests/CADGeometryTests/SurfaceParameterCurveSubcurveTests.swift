import CADCore
@testable import CADGeometry
import Testing

@Suite("Surface parameter curve subdivision")
struct SurfaceParameterCurveSubcurveTests {
    @Test(.timeLimit(.minutes(1)))
    func completeNormalizedSpanIsAnExactIdentity() throws {
        let curves: [SurfaceParameterCurve] = [
            .constantU(u: 0.2, vStart: -0.3, vEnd: 0.3),
            .constantV(v: -0.3, uStart: 0.4, uEnd: 1.0),
            .polyline([
                SurfaceParameter(u: 0.2, v: -0.3),
                SurfaceParameter(u: 0.2, v: 0.3),
            ]),
        ]

        for curve in curves {
            let identity = try curve.subcurve(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                tolerance: .standard
            )
            #expect(identity == curve)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func normalizedSpanUsesRelativeRatherThanSpatialResolution() throws {
        let curve = SurfaceParameterCurve.constantU(
            u: 0.25,
            vStart: 0.0,
            vEnd: 1.0
        )
        let tolerance = ModelingTolerance(
            distance: 8.0e-6,
            angle: 1.0e-9,
            relative: 1.0e-9
        )
        let upperFraction = 4.0e-6

        let result = try curve.subcurve(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: upperFraction,
            tolerance: tolerance
        )

        #expect(result == .constantU(
            u: 0.25,
            vStart: 0.0,
            vEnd: upperFraction
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsPolylineThroughInteriorVertices() throws {
        let curve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
            SurfaceParameter(u: 1.0, v: 1.0),
            SurfaceParameter(u: 2.0, v: 1.0),
        ])

        let trimmed = try curve.trimmed(
            from: 0.5,
            to: 2.5,
            curveDomain: .closed(0.0, 3.0),
            tolerance: .standard
        )

        guard case let .polyline(points) = trimmed else {
            Issue.record("Polyline trimming must preserve an exact polyline representation.")
            return
        }
        #expect(points == [
            SurfaceParameter(u: 0.5, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
            SurfaceParameter(u: 1.0, v: 1.0),
            SurfaceParameter(u: 1.5, v: 1.0),
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsClosedPolylineAcrossPeriodicSeam() throws {
        let curve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
            SurfaceParameter(u: 1.0, v: 1.0),
            SurfaceParameter(u: 0.0, v: 1.0),
            SurfaceParameter(u: 0.0, v: 0.0),
        ])

        let trimmed = try curve.trimmed(
            from: 3.5,
            to: 4.5,
            curveDomain: .periodic(period: 4.0),
            tolerance: .standard
        )

        guard case let .polyline(points) = trimmed else {
            Issue.record("Periodic polyline trimming must preserve an exact polyline representation.")
            return
        }
        #expect(points == [
            SurfaceParameter(u: 0.0, v: 0.5),
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.5, v: 0.0),
        ])
    }
}
