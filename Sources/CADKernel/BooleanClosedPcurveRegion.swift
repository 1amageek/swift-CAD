import CADCore
import CADGeometry
import CADTopology

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
    private let boundaryPredicate: CertifiedSurfaceParameterLoopPredicate

    init(
        reference: BooleanFaceSplitComponentReference,
        closedIntersection: BooleanClosedFaceIntersection,
        surfaceSide: SurfaceSide,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let rawParameters = closedIntersection.samples.map { sample in
            switch surfaceSide {
            case .first:
                SurfaceParameter(
                    u: sample.uvPoint.targetU,
                    v: sample.uvPoint.targetV
                )
            case .second:
                SurfaceParameter(
                    u: sample.uvPoint.toolU,
                    v: sample.uvPoint.toolV
                )
            }
        }
        guard rawParameters.count >= 8 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed Boolean pcurve region requires finite verified samples."
            )
        }
        let topology = SurfaceParameterTopology(surface: surface)
        let uPeriod = topology.uPeriod
        let vPeriod = topology.vPeriod
        let lift = try SurfaceParameterLoopLift(
            samples: rawParameters,
            surface: surface,
            tolerance: tolerance
        )
        // Strategy selection routes essential periodic loops through the
        // source face's explicit seam arrangement. Reaching this bounded
        // containment type with one is therefore an internal topology error.
        guard let points = lift.planarBoundary else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Closed pcurve containment received an essential periodic loop with winding (\(lift.uWinding), \(lift.vWinding)) instead of the seam arrangement strategy."
            )
        }
        let indexedArea = try AdaptivePlanarPredicateEvaluator().certifiedSignedArea(
            of: points,
            tolerance: Self.parameterTolerance(from: tolerance)
        )
        let parameterCurve = switch surfaceSide {
        case .first:
            closedIntersection.intersection.firstSurfaceParameterCurve
        case .second:
            closedIntersection.intersection.secondSurfaceParameterCurve
        }
        let curveStart = try parameterCurve.startParameter(tolerance: tolerance)
        let curveUShift = Self.aligned(
            curveStart.u,
            to: points[0].x,
            period: uPeriod
        ) - curveStart.u
        let curveVShift = Self.aligned(
            curveStart.v,
            to: points[0].y,
            period: vPeriod
        ) - curveStart.v
        let requestedAreaWidth = max(
            abs(indexedArea) * 0.25,
            Self.parameterTolerance(from: tolerance).distance
                * Self.parameterTolerance(from: tolerance).distance
        )
        let exactArea = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: parameterCurve,
            uShift: curveUShift,
            requestedWidth: requestedAreaWidth,
            tolerance: tolerance
        )
        guard exactArea.lower > 0.0 || exactArea.upper < 0.0 else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: (exactArea.upper - exactArea.lower).nextUp,
                tolerance: tolerance,
                message: "Closed Boolean pcurve orientation could not be certified from its exact boundary."
            )
        }
        self.reference = reference
        self.points = points
        self.signedArea = exactArea.lower
            + (exactArea.upper - exactArea.lower) * 0.5
        self.uPeriod = uPeriod
        self.vPeriod = vPeriod
        self.boundaryPredicate = try CertifiedSurfaceParameterLoopPredicate(
            curve: parameterCurve,
            uShift: curveUShift,
            vShift: curveVShift,
            uPeriod: uPeriod,
            vPeriod: vPeriod,
            tolerance: tolerance
        )
    }

    var isCounterclockwise: Bool {
        signedArea > 0.0
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
        return try boundaryPredicate.containsStrictly(
            point,
            tolerance: tolerance
        )
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
        return try boundaryPredicate.boundaryIntersectsOrTouches(
            other.boundaryPredicate,
            otherUShift: offsetX,
            otherVShift: offsetY,
            tolerance: tolerance
        )
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
