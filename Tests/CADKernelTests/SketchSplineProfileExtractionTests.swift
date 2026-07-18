import Testing
import CADCore
import CADIR
import CADKernel

@Suite("Exact spline profile extraction")
struct SketchSplineProfileExtractionTests {
    @Test(.timeLimit(.minutes(1)))
    func cubicSketchSplineIsNotReducedToLineSegments() throws {
        let splineID = SketchEntityID()
        let lineID = SketchEntityID()
        let start = point(0.01, 0.0)
        let end = point(0.01, 0.02)
        let sketch = Sketch(
            plane: .xy,
            entities: [
                splineID: .spline(SketchSpline(controlPoints: [
                    start,
                    point(0.02, 0.005),
                    point(0.02, 0.015),
                    end,
                ])),
                lineID: .line(SketchLine(start: end, end: start)),
            ]
        )
        let sourceFeatureID = FeatureID()
        let profiles = try SketchProfileExtractor(
            tolerance: .standard
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: sourceFeatureID,
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let splineBoundary = try #require(profile.boundarySegments.first {
            if case .spline = $0 { return true }
            return false
        })
        guard case let .spline(spline) = splineBoundary else {
            Issue.record("Expected an exact spline boundary.")
            return
        }

        #expect(profile.boundarySegments.count == 2)
        #expect(spline.curve.degree == 3)
        #expect(spline.curve.controlPoints.count == 4)
        #expect(spline.curve.knots == [
            0.0, 0.0, 0.0, 0.0,
            1.0, 1.0, 1.0, 1.0,
        ])
        let midpoint = try spline.curve.point(
            at: 0.5,
            tolerance: .standard
        )
        #expect(abs(midpoint.x - 0.0175) <= 1.0e-12)
        #expect(abs(midpoint.y - 0.01) <= 1.0e-12)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
