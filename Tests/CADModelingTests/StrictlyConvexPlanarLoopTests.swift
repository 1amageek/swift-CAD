import Testing
import CADCore
@testable import CADModeling

@Suite("Strictly convex planar loop")
struct StrictlyConvexPlanarLoopTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9,
        relative: 1.0e-9
    )

    @Test
    func preservesOrientationAndContainmentAfterLargeTranslation() throws {
        let origin = 1.0e12
        let points = [
            Point2D(x: origin, y: origin),
            Point2D(x: origin + 4.0, y: origin),
            Point2D(x: origin + 4.0, y: origin + 3.0),
            Point2D(x: origin, y: origin + 3.0),
        ]
        let counterclockwise = try StrictlyConvexPlanarLoop(
            points: points,
            tolerance: tolerance
        )
        let clockwise = try StrictlyConvexPlanarLoop(
            points: Array(points.reversed()),
            tolerance: tolerance
        )

        #expect(try counterclockwise.contains(
            Point2D(x: origin + 2.0, y: origin + 1.5),
            tolerance: tolerance
        ))
        #expect(try clockwise.contains(
            Point2D(x: origin + 2.0, y: origin + 1.5),
            tolerance: tolerance
        ))
        #expect(try counterclockwise.contains(
            Point2D(x: origin + 5.0, y: origin + 1.5),
            tolerance: tolerance
        ) == false)
    }

    @Test
    func rejectsToleranceDegeneratePolygonWithTypedClassificationFailure() throws {
        do {
            _ = try StrictlyConvexPlanarLoop(
                points: [
                    Point2D(x: 0.0, y: 0.0),
                    Point2D(x: 10.0, y: 0.0),
                    Point2D(x: 10.0, y: tolerance.distance * 0.1),
                    Point2D(x: 0.0, y: tolerance.distance * 0.1),
                ],
                tolerance: tolerance
            )
            Issue.record("Expected the tolerance-degenerate polygon to be rejected.")
        } catch let error as KernelError {
            #expect(error.phase == .classification)
            #expect(error.code == .classificationFailure)
        }
    }

    @Test
    func rejectsConcavePolygonInsteadOfSelectingAnUnstableWinding() throws {
        #expect(throws: KernelError.self) {
            _ = try StrictlyConvexPlanarLoop(
                points: [
                    Point2D(x: 0.0, y: 0.0),
                    Point2D(x: 4.0, y: 0.0),
                    Point2D(x: 2.0, y: 1.0),
                    Point2D(x: 4.0, y: 3.0),
                    Point2D(x: 0.0, y: 3.0),
                ],
                tolerance: tolerance
            )
        }
    }
}
