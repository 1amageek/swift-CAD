import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Rational B-spline Curve Intersector 2D")
struct RationalBSplineCurveIntersector2DTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseLinearCurvesProduceOneCertifiedIntersection() throws {
        let first = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 1.0),
            ]
        )
        let second = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 1.0),
                Point2D(x: 1.0, y: 0.0),
            ]
        )

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: first,
            second: second,
            maximumSubdivisionDepth: 16,
            maximumSubdivisionCells: 4_096,
            accepting: { $0.pointEnclosure.maximumWidth <= 1.0e-10 },
            tolerance: tolerance
        )

        let intersection = try #require(intersections.only)
        #expect(intersection.firstParameterEnclosure.contains(0.5))
        #expect(intersection.secondParameterEnclosure.contains(0.5))
        #expect(intersection.pointEnclosure.contains(Point2D(x: 0.5, y: 0.5)))
        #expect(intersection.pointEnclosure.maximumWidth <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticAndLineUseTheRationalDifferenceCertificate() throws {
        let first = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.0, y: 1.0),
            ],
            weights: [1.0, sqrt(0.5), 1.0]
        )
        let second = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 1.0),
            ]
        )

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: first,
            second: second,
            maximumSubdivisionDepth: 16,
            maximumSubdivisionCells: 4_096,
            accepting: { $0.pointEnclosure.maximumWidth <= 1.0e-10 },
            tolerance: tolerance
        )

        let intersection = try #require(intersections.only)
        #expect(intersection.firstParameterEnclosure.contains(0.5))
        #expect(intersection.secondParameterEnclosure.contains(sqrt(0.5)))
        #expect(intersection.pointEnclosure.contains(Point2D(
            x: sqrt(0.5),
            y: sqrt(0.5)
        )))
        #expect(intersection.pointEnclosure.maximumWidth <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCurvesAreCertifiedAsDisjoint() throws {
        let first = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 0.0),
            ]
        )
        let second = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 1.0),
                Point2D(x: 1.0, y: 1.0),
            ]
        )

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: first,
            second: second,
            maximumSubdivisionDepth: 16,
            maximumSubdivisionCells: 4_096,
            accepting: { _ in true },
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func endpointRootIsCertifiedInsideAnExtendedProofDomain() throws {
        let quadratic = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: -1.0, y: 0.0),
                Point2D(x: 0.0, y: 1.0),
                Point2D(x: 1.0, y: 0.0),
            ]
        )
        let line = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: -1.0),
                Point2D(x: 1.0, y: 1.0),
            ]
        )

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: quadratic,
            second: line,
            maximumSubdivisionDepth: 32,
            maximumSubdivisionCells: 65_536,
            accepting: { $0.pointEnclosure.maximumWidth <= 1.0e-10 },
            tolerance: tolerance
        )

        let intersection = try #require(intersections.only)
        #expect(intersection.firstParameterEnclosure.contains(1.0))
        #expect(intersection.secondParameterEnclosure.contains(0.5))
        #expect(intersection.pointEnclosure.contains(Point2D(x: 1.0, y: 0.0)))
    }

    @Test(.timeLimit(.minutes(1)))
    func exactQuadraticLineTangencyProducesOneDoubleRoot() throws {
        let quadratic = BSplineCurveCurveFixture.parabola
        let tangent = BSplineCurveCurveFixture.horizontalLine(y: 0.5)

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: quadratic,
            second: tangent,
            maximumSubdivisionDepth: 32,
            maximumSubdivisionCells: 65_536,
            accepting: { $0.pointEnclosure.maximumWidth <= 1.0e-10 },
            tolerance: tolerance
        )

        let intersection = try #require(intersections.only)
        #expect(intersection.firstParameterEnclosure.contains(0.5))
        #expect(intersection.secondParameterEnclosure.contains(0.5))
        #expect(intersection.pointEnclosure.contains(Point2D(x: 0.0, y: 0.5)))
    }

    @Test(.timeLimit(.minutes(1)))
    func lineAboveQuadraticTangencyIsCertifiedAsDisjoint() throws {
        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: BSplineCurveCurveFixture.parabola,
            second: BSplineCurveCurveFixture.horizontalLine(y: 0.500_001),
            maximumSubdivisionDepth: 32,
            maximumSubdivisionCells: 65_536,
            accepting: { $0.pointEnclosure.maximumWidth <= 1.0e-10 },
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func proofDomainTangencyOutsideAuthoredDomainIsNotAModeledRoot() throws {
        let exteriorRoot = 0.005
        let squaredRoot = exteriorRoot * exteriorRoot
        let curve = BSplineCurve2D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: squaredRoot),
                Point2D(
                    x: 1.0 / 3.0,
                    y: squaredRoot + 2.0 * exteriorRoot / 3.0
                ),
                Point2D(
                    x: 2.0 / 3.0,
                    y: squaredRoot + 4.0 * exteriorRoot / 3.0 + 1.0 / 3.0
                ),
                Point2D(x: 1.0, y: (1.0 + exteriorRoot) * (1.0 + exteriorRoot)),
            ]
        )

        let intersections = try RationalBSplineCurveIntersector2D().intersections(
            first: curve,
            second: BSplineCurveCurveFixture.horizontalLine(y: 0.0),
            maximumSubdivisionDepth: 32,
            maximumSubdivisionCells: 65_536,
            accepting: { _ in true },
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }
}

private enum BSplineCurveCurveFixture {
    static let parabola = BSplineCurve2D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: [
            Point2D(x: -1.0, y: 0.0),
            Point2D(x: 0.0, y: 1.0),
            Point2D(x: 1.0, y: 0.0),
        ]
    )

    static func horizontalLine(y: Double) -> BSplineCurve2D {
        BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: -1.0, y: y),
                Point2D(x: 1.0, y: y),
            ]
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
