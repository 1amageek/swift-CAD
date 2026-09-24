import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADModeling

@Suite("Exact periodic conic spans")
struct ExactBSplineCurveSpanBuilderTests {
    @Test(arguments: [0.0, 0.12345, -0.5], [2 * Double.pi, -2 * Double.pi])
    func fullProfileTurnsShareOneSeam(startAngle: Double, sweep: Double) throws {
        let circle = Circle3D(center: Point3D(x: 0.3, y: -0.2, z: 0.7), normal: .unitZ, radius: 0.002)
        let curve = Curve3D.circle(circle)
        let start = try curve.point(at: startAngle, tolerance: .standard)
        let samples = try (0..<4).map {
            try curve.point(at: startAngle + sweep * Double($0) / 4, tolerance: .standard)
        }
        let loop = ProfileLoop(vertices: samples, boundarySegments: [.circularArc(
            ProfileCircularArcSegment(center: circle.center, normal: circle.normal, radius: circle.radius,
                start: start, end: start, sweepAngle: sweep))])
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: .standard).profileSpans(from: loop)
        #expect(spans.count == 4)
        for index in spans.indices {
            #expect(spans[index].endPoint == spans[(index + 1) % spans.count].startPoint)
            let midpoint = try spans[index].curve.point(at: 0.5, tolerance: .standard)
            #expect(abs((midpoint - circle.center).length - circle.radius) < 1e-12)
        }
    }

    @Test(arguments: [false, true])
    func partialSectionsDoNotCloseByTolerance(ellipse: Bool) throws {
        let curve: Curve3D = ellipse
            ? .analytic(.ellipse(center: .origin, normal: .unitZ, majorAxis: .unitX,
                majorRadius: 2, minorRadius: 1))
            : .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1))
        let upper = (2 * Double.pi).nextDown
        let start = try curve.point(at: 0, tolerance: .standard)
        let end = try curve.point(at: upper, tolerance: .standard)
        let section = EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [start, try curve.point(at: .pi, tolerance: .standard), end], isClosed: false, exactCurve: curve,
            exactParameterDomain: .closed(0, upper), exactPointParameters: [0, .pi, upper])
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: .standard).sectionSpans(from: section)
        #expect(spans.first?.startPoint == start)
        #expect(spans.last?.endPoint == end)
        #expect(spans.first?.startPoint != spans.last?.endPoint)
    }

    @Test(arguments: [Double.nan, Double.infinity, 0.0, Double.greatestFiniteMagnitude, 4 * Double.pi])
    func invalidSweepsFailBeforeSpanAllocation(sweep: Double) throws {
        let start = Point3D(x: 1, y: 0, z: 0)
        let loop = ProfileLoop(vertices: [start], boundarySegments: [.circularArc(
            ProfileCircularArcSegment(center: .origin, normal: .unitZ, radius: 1,
                start: start, end: start, sweepAngle: sweep))])
        #expect(throws: KernelError.self) {
            _ = try ExactBSplineCurveSpanBuilder(tolerance: .standard).profileSpans(from: loop)
        }
    }
}
