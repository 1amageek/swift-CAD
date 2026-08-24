import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("Certified Surface Parameter Loop Predicate")
struct CertifiedSurfaceParameterLoopPredicateTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func adaptiveEnclosuresCertifyInsideOutsideAndBoundary() throws {
        let predicate = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 0.0, y: 0.0), radius: 2.0),
            tolerance: tolerance
        )

        #expect(try predicate.containsStrictly(
            Point2D(x: 0.0, y: 0.0),
            tolerance: tolerance
        ))
        #expect(try predicate.containsStrictly(
            Point2D(x: 3.0, y: 0.0),
            tolerance: tolerance
        ) == false)
        #expect(try predicate.containsStrictly(
            Point2D(x: 2.0, y: 0.0),
            tolerance: tolerance
        ) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptiveBoundaryComparisonSeparatesNestedLoopsAndDetectsCrossing() throws {
        let outer = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 0.0, y: 0.0), radius: 2.0),
            tolerance: tolerance
        )
        let nested = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 0.0, y: 0.0), radius: 0.75),
            tolerance: tolerance
        )
        let crossing = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 1.5, y: 0.0), radius: 1.0),
            tolerance: tolerance
        )

        #expect(try outer.boundaryIntersectsOrTouches(
            nested,
            tolerance: tolerance
        ) == false)
        #expect(try outer.boundaryIntersectsOrTouches(
            crossing,
            tolerance: tolerance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicSheetShiftDoesNotChangeCertifiedTopology() throws {
        let period = 2.0 * Double.pi
        let shiftedOuter = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 0.0, y: 0.0), radius: 2.0),
            uShift: period,
            tolerance: tolerance
        )
        let shiftedInner = try CertifiedSurfaceParameterLoopPredicate(
            curve: circle(center: Point2D(x: 0.0, y: 0.0), radius: 0.5),
            uShift: period,
            tolerance: tolerance
        )

        #expect(try shiftedOuter.containsStrictly(
            Point2D(x: period, y: 0.0),
            tolerance: tolerance
        ))
        #expect(try shiftedOuter.boundaryIntersectsOrTouches(
            shiftedInner,
            tolerance: tolerance
        ) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func multipleExactEdgesFormOneCertifiedPeriodicChartLoop() throws {
        let lowerU = 1.75 * Double.pi
        let upperU = 2.25 * Double.pi
        let predicate = try CertifiedSurfaceParameterLoopPredicate(
            curves: [
                .constantV(v: -1.0, uStart: lowerU, uEnd: upperU),
                .constantU(u: upperU, vStart: -1.0, vEnd: 1.0),
                .constantV(v: 1.0, uStart: upperU, uEnd: lowerU),
                .constantU(u: lowerU, vStart: 1.0, vEnd: -1.0),
            ],
            uPeriod: 2.0 * Double.pi,
            tolerance: tolerance
        )

        #expect(try predicate.classify(
            Point2D(x: 2.0 * Double.pi, y: 0.0),
            tolerance: tolerance
        ) == .inside)
        #expect(try predicate.classify(
            Point2D(x: 1.5 * Double.pi, y: 0.0),
            tolerance: tolerance
        ) == .outside)
        #expect(try predicate.classify(
            Point2D(x: lowerU, y: 0.0),
            tolerance: tolerance
        ) == .boundary)
    }

    @Test(.timeLimit(.minutes(1)))
    func sphericalGreatCircleEnclosuresRetainDeclaredUniversalCoverSheet() throws {
        let start = 2.0 * Double.pi
        let end = 2.5 * Double.pi
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitY,
            sine: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            startParameter: start,
            endParameter: end
        )
        let enclosures = try CertifiedSurfaceParameterCurveEncloser().enclosures(
            for: curve,
            maximumWidth: 0.25,
            tolerance: tolerance
        ).sorted { $0.lowerFraction < $1.lowerFraction }

        let first = try #require(enclosures.first)
        let last = try #require(enclosures.last)
        #expect(first.u.lower <= start)
        #expect(first.u.upper >= start)
        #expect(last.u.lower <= end)
        #expect(last.u.upper >= end)
        for index in 1..<enclosures.count {
            let previous = enclosures[index - 1]
            let current = enclosures[index]
            #expect(previous.u.upper >= current.u.lower)
            #expect(current.u.upper >= previous.u.lower)
            #expect(previous.v.upper >= current.v.lower)
            #expect(current.v.upper >= previous.v.lower)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func borrowedPolylineRangeCanBeCertifiedBelowTopologyDistanceTolerance() throws {
        let curve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.01, v: 0.0),
        ])
        let upperFraction = 1.0 / 16_384.0

        #expect(throws: GeometryError.self) {
            try curve.subcurve(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            )
        }

        let enclosures = try CertifiedSurfaceParameterCurveEncloser().enclosures(
            for: curve,
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: upperFraction,
            maximumWidth: 1.0,
            tolerance: tolerance
        )
        #expect(enclosures.count == 1)
        let enclosure = try #require(enclosures.first)
        let exactUpperU = 0.01 * upperFraction

        #expect(enclosure.lowerFraction == 0.0)
        #expect(enclosure.upperFraction == upperFraction)
        #expect(enclosure.u.lower <= 0.0)
        #expect(enclosure.u.upper >= exactUpperU)
        #expect(enclosure.v.lower <= 0.0)
        #expect(enclosure.v.upper >= 0.0)
    }

    private func circle(center: Point2D, radius: Double) -> SurfaceParameterCurve {
        .harmonic(
            center: center,
            cosine: Point2D(x: radius, y: 0.0),
            sine: Point2D(x: 0.0, y: radius),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
    }
}
