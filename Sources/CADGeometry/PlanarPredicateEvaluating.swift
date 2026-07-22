import CADCore

public protocol PlanarPredicateEvaluating: Sendable {
    func orientation(
        _ start: Point2D,
        _ end: Point2D,
        relativeTo point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> RobustSign

    func orientation(
        of polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> RobustSign

    func certifiedSignedArea(
        of polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> Double

    func classify(
        _ point: Point2D,
        in polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> PlanarPointClassification

    func segmentsIntersectOrTouch(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool

    func areCollinear(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
