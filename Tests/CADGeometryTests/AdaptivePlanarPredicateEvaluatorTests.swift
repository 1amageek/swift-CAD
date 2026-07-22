import Testing
import CADCore
@testable import CADGeometry

@Suite("Adaptive planar predicates")
struct AdaptivePlanarPredicateEvaluatorTests {
    private let evaluator = AdaptivePlanarPredicateEvaluator()
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-12,
        relative: 1.0e-12
    )

    @Test
    func classifiesInteriorBoundaryAndExteriorWithoutRayDivision() throws {
        let polygon = [
            Point2D(x: 1.0e12, y: 1.0e12),
            Point2D(x: 1.0e12 + 4.0, y: 1.0e12),
            Point2D(x: 1.0e12 + 4.0, y: 1.0e12 + 3.0),
            Point2D(x: 1.0e12, y: 1.0e12 + 3.0),
        ]

        #expect(try evaluator.classify(
            Point2D(x: 1.0e12 + 2.0, y: 1.0e12 + 1.0),
            in: polygon,
            tolerance: tolerance
        ) == .inside)
        #expect(try evaluator.classify(
            Point2D(x: 1.0e12 + 4.0, y: 1.0e12 + 1.0),
            in: polygon,
            tolerance: tolerance
        ) == .boundary)
        #expect(try evaluator.classify(
            Point2D(x: 1.0e12 + 5.0, y: 1.0e12 + 1.0),
            in: polygon,
            tolerance: tolerance
        ) == .outside)
    }

    @Test
    func certifiesTranslatedPolygonOrientationWithExpansionArea() throws {
        let origin = 1.0e12
        let polygon = [
            Point2D(x: origin, y: origin),
            Point2D(x: origin + 4.0, y: origin),
            Point2D(x: origin + 4.0, y: origin + 3.0),
            Point2D(x: origin, y: origin + 3.0),
        ]

        #expect(try evaluator.orientation(
            of: polygon,
            tolerance: tolerance
        ) == .positive)
        #expect(try evaluator.orientation(
            of: Array(polygon.reversed()),
            tolerance: tolerance
        ) == .negative)
        #expect(abs(try evaluator.certifiedSignedArea(
            of: polygon,
            tolerance: tolerance
        ) - 12.0) <= tolerance.distance)
        #expect(abs(try evaluator.certifiedSignedArea(
            of: Array(polygon.reversed()),
            tolerance: tolerance
        ) + 12.0) <= tolerance.distance)
    }

    @Test
    func detectsTranslatedSegmentCrossingAndToleranceTouch() throws {
        #expect(try evaluator.segmentsIntersectOrTouch(
            Point2D(x: 1.0e12, y: 1.0e12),
            Point2D(x: 1.0e12 + 4.0, y: 1.0e12 + 4.0),
            Point2D(x: 1.0e12, y: 1.0e12 + 4.0),
            Point2D(x: 1.0e12 + 4.0, y: 1.0e12),
            tolerance: tolerance
        ))
        #expect(try evaluator.segmentsIntersectOrTouch(
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 2.0, y: 0.0),
            Point2D(x: 2.0 + tolerance.distance * 0.5, y: 0.0),
            Point2D(x: 3.0, y: 0.0),
            tolerance: tolerance
        ))
    }

    @Test
    func distinguishesCollinearityFromSmallResolvableRotation() throws {
        #expect(try evaluator.areCollinear(
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 10.0, y: 0.0),
            Point2D(x: 2.0, y: tolerance.distance * 0.5),
            Point2D(x: 8.0, y: -tolerance.distance * 0.5),
            tolerance: tolerance
        ))
        #expect(try evaluator.areCollinear(
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 10.0, y: 0.0),
            Point2D(x: 2.0, y: tolerance.distance * 4.0),
            Point2D(x: 8.0, y: tolerance.distance * 4.0),
            tolerance: tolerance
        ) == false)
    }

    @Test
    func rejectsNonPolygonClassificationWithTypedDiagnostic() throws {
        #expect(throws: KernelError.self) {
            _ = try evaluator.classify(
                Point2D(x: 0.0, y: 0.0),
                in: [Point2D(x: 0.0, y: 0.0), Point2D(x: 1.0, y: 0.0)],
                tolerance: tolerance
            )
        }
    }

    @Test
    func overflowedExpansionReturnsIndeterminateInsteadOfInventingASign() throws {
        let magnitude = Double.greatestFiniteMagnitude
        let sign = try RobustPredicates.orientation2D(
            Point2D(x: magnitude, y: magnitude),
            Point2D(x: -magnitude, y: magnitude),
            relativeTo: Point2D(x: magnitude, y: -magnitude),
            determinantTolerance: 0.0
        )

        #expect(sign == .indeterminate)
    }
}
