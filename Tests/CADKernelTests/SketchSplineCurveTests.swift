import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Sketch spline curve")
struct SketchSplineCurveTests {
    private func sketchPoints(_ points: [(Double, Double)]) -> [SketchPoint] {
        points.map { SketchPoint(x: .constant(.length($0.0, unit: .meter)), y: .constant(.length($0.1, unit: .meter))) }
    }

    private let explicitPoints: [Point2D] = [
        Point2D(x: 0, y: 0), Point2D(x: 1, y: 1), Point2D(x: 2, y: 1.5), Point2D(x: 3, y: 0.2), Point2D(x: 4, y: 1),
    ]
    private let explicitKnots: [Double] = [0, 0, 0, 0, 0.4, 1, 1, 1, 1]

    @Test func explicitKnotsDecomposeIntoSegmentsOnTheSameCurve() throws {
        let spline = SketchSpline(controlPoints: sketchPoints(explicitPoints.map { ($0.x, $0.y) }), knots: explicitKnots)
        let curve = try SketchSplineCurve(spline: spline, controlPoints: explicitPoints, tolerance: .standard)
        #expect(curve.segments.count == 2)
        #expect(curve.segments.map(\.lowerParameter) == [0, 0.4])
        #expect(curve.segments.map(\.upperParameter) == [0.4, 1])
        for segment in curve.segments {
            #expect(segment.controlPoints.count == 4)
            for step in 0...8 {
                let t = Double(step) / 8
                let onSegment = bezier(segment.controlPoints, t)
                let u = segment.lowerParameter + t * (segment.upperParameter - segment.lowerParameter)
                let onCurve = try curve.bSpline.point(at: u, tolerance: .standard)
                #expect(hypot(onSegment.x - onCurve.x, onSegment.y - onCurve.y) <= 1e-12)
            }
        }
    }

    @Test func aQuinticChainIsItsOwnSegmentsAndTessellatesWithinTheDistance() throws {
        let points = [(0.0, 0.0), (1.0, 2.0), (2.0, -1.0), (3.0, 2.0), (4.0, -1.0), (5.0, 0.0)]
        let spline = SketchSpline(controlPoints: sketchPoints(points), degree: 5)
        let planar = points.map { Point2D(x: $0.0, y: $0.1) }
        let curve = try SketchSplineCurve(spline: spline, controlPoints: planar, tolerance: .standard)
        #expect(curve.segments.count == 1 && curve.segments[0].controlPoints == planar)
        let samples = try SketchSplineTessellator(tolerance: .standard).samples(for: curve)
        #expect(samples.first?.parameter == 0 && samples.last?.parameter == 1)
        // Every chord between consecutive samples stays within the modeling distance of the curve.
        for (a, b) in zip(samples, samples.dropFirst()) {
            let middle = try curve.bSpline.point(at: (a.parameter + b.parameter) / 2, tolerance: .standard)
            let chordMiddle = Point2D(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
            #expect(hypot(middle.x - chordMiddle.x, middle.y - chordMiddle.y) <= ModelingTolerance.standard.distance * 2)
        }
    }

    @Test func extractionKeepsTheDegreeAndKnots() throws {
        let id = SketchEntityID()
        let sketch = Sketch(plane: .xy, entities: [
            id: .spline(SketchSpline(controlPoints: sketchPoints(explicitPoints.map { ($0.x, $0.y) }), knots: explicitKnots)),
        ])
        let curves = try SketchCurveExtractor(tolerance: .standard).extractCurves(
            from: sketch, sourceFeatureID: FeatureID(), parameters: ParameterResolver().resolve(ParameterTable())
        )
        guard case let .bSpline(exact) = try #require(curves.first?.exactCurve) else {
            Issue.record("A spline extracts as a B-spline.")
            return
        }
        #expect(exact.degree == 3 && exact.knots == explicitKnots)
        #expect(curves[0].exactPointParameters?.first == 0 && curves[0].exactPointParameters?.last == 1)
    }

    @Test func projectionFindsTheFootOnAGeneralSpline() throws {
        let spline = SketchSpline(controlPoints: sketchPoints(explicitPoints.map { ($0.x, $0.y) }), knots: explicitKnots)
        let curve = try SketchSplineCurve(spline: spline, controlPoints: explicitPoints, tolerance: .standard)
        let target = try curve.bSpline.point(at: 0.7, tolerance: .standard)
        let projection = try SketchCurveProjector(tolerance: .standard).nearest(
            on: .sketchSpline(curve), to: Point2D(x: target.x, y: target.y)
        )
        #expect(abs(projection.parameter - 0.7) <= 1e-6)
        #expect(projection.distance <= 1e-9)
    }

    @Test func uniformSamplesOfACubicChainMatchTheCubicSampler() throws {
        let points = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 2, y: 2), Point2D(x: 3, y: 0),
                      Point2D(x: 4, y: -2), Point2D(x: 5, y: -1), Point2D(x: 6, y: 0)]
        let curve = try SketchSplineCurve(degree: 3, knots: nil, controlPoints: points, tolerance: .standard)
        let sampler = SketchCurveSampler(samplesPerSegment: 8)
        let general = sampler.splineSamples(for: curve)
        let cubic = sampler.splineSamples(for: points)
        #expect(general.count == cubic.count)
        for (a, b) in zip(general, cubic) {
            #expect(abs(a.parameter - b.parameter) <= 1e-12)
            #expect(hypot(a.point.x - b.point.x, a.point.y - b.point.y) <= 1e-12)
            #expect(abs(a.curvature - b.curvature) <= 1e-9 * max(1, abs(b.curvature)))
        }
    }

    @Test func segmentSamplesOfACubicChainMatchTheCubicSampler() throws {
        let points = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 2, y: 2), Point2D(x: 3, y: 0),
                      Point2D(x: 4, y: -2), Point2D(x: 5, y: -1), Point2D(x: 6, y: 0)]
        let curve = try SketchSplineCurve(degree: 3, knots: nil, controlPoints: points, tolerance: .standard)
        let sampler = SketchCurveSampler()
        for segment in 0..<2 {
            for t in [0.0, 0.3, 1.0] {
                let general = try #require(sampler.splineSegmentSample(for: curve, segmentIndex: segment, t: t))
                let cubic = try #require(sampler.splineSegmentSample(for: points, segmentIndex: segment, t: t))
                #expect(abs(general.parameter - cubic.parameter) <= 1e-12)
                #expect(hypot(general.point.x - cubic.point.x, general.point.y - cubic.point.y) <= 1e-12)
                #expect(abs(general.curvature - cubic.curvature) <= 1e-9 * max(1, abs(cubic.curvature)))
            }
        }
        #expect(sampler.splineSegmentSample(for: curve, segmentIndex: 2, t: 0) == nil)
    }

    /// The Bridge Curve whose comb crossed itself: a hook of radius about 0.5 mm at each end.
    @Test func turnBoundedSamplesFollowATightHook() throws {
        let points = [(0.0, 0.0), (-14.142, 0.0), (6.667, 6.667), (10.0, 10.0), (13.333, 13.333), (20.0, 34.142), (20.0, 20.0)]
            .map { Point2D(x: $0.0 / 1000, y: $0.1 / 1000) }
        let curve = try SketchSplineCurve(degree: 3, knots: nil, controlPoints: points, tolerance: .standard)
        let sampler = SketchCurveSampler(samplesPerSegment: 14)
        let uniform = sampler.splineSamples(for: curve)
        let maximumUniformTurn = zip(uniform, uniform.dropFirst()).map { turn($0.tangent, $1.tangent) }.max() ?? 0
        #expect(maximumUniformTurn > Double.pi / 4)
        let bounded = try sampler.turnBoundedSplineSamples(for: curve, maximumTurn: Double.pi / 36)
        #expect(bounded.count > uniform.count)
        for (a, b) in zip(bounded, bounded.dropFirst()) {
            #expect(b.parameter > a.parameter)
            #expect(turn(a.tangent, b.tangent) <= Double.pi / 36 + 1e-12)
        }
        #expect(bounded.first?.parameter == 0 && bounded.last?.parameter == 1)
    }

    private func turn(_ a: Point2D, _ b: Point2D) -> Double {
        abs(atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y))
    }

    private func bezier(_ p: [Point2D], _ t: Double) -> Point2D {
        var level = p
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
        }
        return level[0]
    }
}
