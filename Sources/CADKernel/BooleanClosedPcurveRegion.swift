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
        let signedArea = Self.signedArea(points)
        guard signedArea.isFinite,
              abs(signedArea) > parameterTolerance * parameterTolerance else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: abs(signedArea),
                tolerance: tolerance,
                message: "Closed Boolean pcurve does not enclose a resolvable parameter-space region."
            )
        }
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
        Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
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
        let determinantTolerance = Self.determinantTolerance(
            points: points + [point],
            tolerance: tolerance
        )
        var windingNumber = 0
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let orientation = try RobustPredicates.orientation2D(
                start,
                end,
                relativeTo: point,
                determinantTolerance: determinantTolerance
            )
            guard orientation != .zero,
                  orientation != .indeterminate else {
                return false
            }
            if start.y <= point.y {
                if end.y > point.y, orientation == .positive {
                    windingNumber += 1
                }
            } else if end.y <= point.y, orientation == .negative {
                windingNumber -= 1
            }
        }
        return windingNumber != 0
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
        let determinantTolerance = Self.determinantTolerance(
            points: points + otherPoints,
            tolerance: tolerance
        )
        for firstIndex in points.indices {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % points.count]
            for secondIndex in otherPoints.indices {
                let secondStart = otherPoints[secondIndex]
                let secondEnd = otherPoints[(secondIndex + 1) % otherPoints.count]
                guard Self.boundingBoxesOverlap(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd,
                    tolerance: max(tolerance.distance, tolerance.angle)
                ) else {
                    continue
                }
                let firstStartSign = try RobustPredicates.orientation2D(
                    secondStart,
                    secondEnd,
                    relativeTo: firstStart,
                    determinantTolerance: determinantTolerance
                )
                let firstEndSign = try RobustPredicates.orientation2D(
                    secondStart,
                    secondEnd,
                    relativeTo: firstEnd,
                    determinantTolerance: determinantTolerance
                )
                let secondStartSign = try RobustPredicates.orientation2D(
                    firstStart,
                    firstEnd,
                    relativeTo: secondStart,
                    determinantTolerance: determinantTolerance
                )
                let secondEndSign = try RobustPredicates.orientation2D(
                    firstStart,
                    firstEnd,
                    relativeTo: secondEnd,
                    determinantTolerance: determinantTolerance
                )
                if Self.opposite(firstStartSign, firstEndSign),
                   Self.opposite(secondStartSign, secondEndSign) {
                    return true
                }
                if [firstStartSign, firstEndSign, secondStartSign, secondEndSign].contains(where: {
                    $0 == .zero || $0 == .indeterminate
                }) {
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

    private static func signedArea(_ points: [Point2D]) -> Double {
        var doubledArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            doubledArea += current.x * next.y - current.y * next.x
        }
        return doubledArea * 0.5
    }

    private static func determinantTolerance(
        points: [Point2D],
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = max(
            1.0,
            points.reduce(0.0) { partial, point in
                max(partial, max(abs(point.x), abs(point.y)))
            }
        )
        return max(tolerance.distance, tolerance.angle) * scale
    }

    private static func boundingBoxesOverlap(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: Double
    ) -> Bool {
        max(firstStart.x, firstEnd.x) + tolerance >= min(secondStart.x, secondEnd.x)
            && max(secondStart.x, secondEnd.x) + tolerance >= min(firstStart.x, firstEnd.x)
            && max(firstStart.y, firstEnd.y) + tolerance >= min(secondStart.y, secondEnd.y)
            && max(secondStart.y, secondEnd.y) + tolerance >= min(firstStart.y, firstEnd.y)
    }

    private static func opposite(_ first: RobustSign, _ second: RobustSign) -> Bool {
        (first == .negative && second == .positive)
            || (first == .positive && second == .negative)
    }
}
