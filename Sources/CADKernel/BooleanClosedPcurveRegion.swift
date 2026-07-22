import CADCore
import CADGeometry

struct BooleanClosedPcurveRegion: Hashable, Sendable {
    enum SurfaceSide: Hashable, Sendable {
        case first
        case second
    }

    let reference: BooleanFaceSplitComponentReference
    let points: [Point2D]
    let signedArea: Double
    let uPeriod: Double?
    let vPeriod: Double?

    init(
        reference: BooleanFaceSplitComponentReference,
        closedIntersection: BooleanClosedFaceIntersection,
        surfaceSide: SurfaceSide,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let rawPoints = closedIntersection.samples.map { sample in
            switch surfaceSide {
            case .first:
                Point2D(x: sample.uvPoint.targetU, y: sample.uvPoint.targetV)
            case .second:
                Point2D(x: sample.uvPoint.toolU, y: sample.uvPoint.toolV)
            }
        }
        guard rawPoints.count >= 8,
              rawPoints.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite
              }) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed Boolean pcurve region requires finite verified samples."
            )
        }
        let uPeriod = Self.period(surface.uDomain)
        let vPeriod = Self.period(surface.vDomain)
        let points = Self.unwrapped(
            rawPoints,
            uPeriod: uPeriod,
            vPeriod: vPeriod
        )
        let closingPoint = Self.aligned(
            points[0],
            to: points[points.count - 1],
            uPeriod: uPeriod,
            vPeriod: vPeriod
        )
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        guard abs(closingPoint.x - points[0].x) <= parameterTolerance,
              abs(closingPoint.y - points[0].y) <= parameterTolerance else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "A non-contractible periodic pcurve requires a surface partition rather than a bounded face region."
            )
        }
        let signedArea = try AdaptivePlanarPredicateEvaluator().certifiedSignedArea(
            of: points,
            tolerance: Self.parameterTolerance(from: tolerance)
        )
        self.reference = reference
        self.points = points
        self.signedArea = signedArea
        self.uPeriod = uPeriod
        self.vPeriod = vPeriod
    }

    var isCounterclockwise: Bool {
        signedArea > 0.0
    }

    var absoluteArea: Double {
        abs(signedArea)
    }

    var centroid: Point2D {
        let origin = points[0]
        return Point2D(
            x: origin.x + points.reduce(0.0) { $0 + ($1.x - origin.x) } / Double(points.count),
            y: origin.y + points.reduce(0.0) { $0 + ($1.y - origin.y) } / Double(points.count)
        )
    }

    func containsStrictly(
        _ point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let point = Self.aligned(
            point,
            to: centroid,
            uPeriod: uPeriod,
            vPeriod: vPeriod
        )
        switch try AdaptivePlanarPredicateEvaluator().classify(
            point,
            in: points,
            tolerance: Self.parameterTolerance(from: tolerance)
        ) {
        case .inside:
            return true
        case .boundary, .outside:
            return false
        case .indeterminate:
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Closed Boolean pcurve containment could not be certified."
            )
        }
    }

    func boundaryIntersects(
        _ other: BooleanClosedPcurveRegion,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let alignedOtherCentroid = Self.aligned(
            other.centroid,
            to: centroid,
            uPeriod: uPeriod,
            vPeriod: vPeriod
        )
        let offsetX = alignedOtherCentroid.x - other.centroid.x
        let offsetY = alignedOtherCentroid.y - other.centroid.y
        let otherPoints = other.points.map { point in
            Point2D(x: point.x + offsetX, y: point.y + offsetY)
        }
        let planarPredicates = AdaptivePlanarPredicateEvaluator()
        let parameterTolerance = Self.parameterTolerance(from: tolerance)
        for firstIndex in points.indices {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % points.count]
            for secondIndex in otherPoints.indices {
                let secondStart = otherPoints[secondIndex]
                let secondEnd = otherPoints[(secondIndex + 1) % otherPoints.count]
                if try planarPredicates.segmentsIntersectOrTouch(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd,
                    tolerance: parameterTolerance
                ) {
                    return true
                }
            }
        }
        return false
    }

    private static func unwrapped(
        _ points: [Point2D],
        uPeriod: Double?,
        vPeriod: Double?
    ) -> [Point2D] {
        var result: [Point2D] = [points[0]]
        for point in points.dropFirst() {
            result.append(aligned(
                point,
                to: result[result.count - 1],
                uPeriod: uPeriod,
                vPeriod: vPeriod
            ))
        }
        return result
    }

    private static func aligned(
        _ point: Point2D,
        to reference: Point2D,
        uPeriod: Double?,
        vPeriod: Double?
    ) -> Point2D {
        Point2D(
            x: aligned(point.x, to: reference.x, period: uPeriod),
            y: aligned(point.y, to: reference.y, period: vPeriod)
        )
    }

    private static func aligned(
        _ value: Double,
        to reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return value }
        return value + ((reference - value) / period).rounded() * period
    }

    private static func period(_ domain: ParameterDomain) -> Double? {
        guard case let .periodic(period) = domain else { return nil }
        return period
    }

    private static func parameterTolerance(
        from tolerance: ModelingTolerance
    ) -> ModelingTolerance {
        ModelingTolerance(
            distance: max(tolerance.distance, tolerance.angle),
            angle: tolerance.angle,
            relative: tolerance.relative
        )
    }
}
