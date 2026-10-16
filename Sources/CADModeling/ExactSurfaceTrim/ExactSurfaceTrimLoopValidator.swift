import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactSurfaceTrimLoopValidation: Sendable {
    package let loops: [SurfaceTrimLoop]
    package let parameterAreaLowerBound: Double
    package let parameterAreaUpperBound: Double
    package let outerParameterAreaLowerBound: Double
    package let outerParameterAreaUpperBound: Double
}

public struct ExactSurfaceTrimLoopValidator: Sendable {
    private typealias FlatBoundarySpan = (start: Point2D, end: Point2D,
        uBounds: ScalarInterval, vBounds: ScalarInterval, tubeRadius: Double)
    private struct HarmonicCell { let lower: Double; let upper: Double; let depth: Int }

    private struct FlatSpan {
        let start: Point2D
        let end: Point2D
        let uBounds: ScalarInterval
        let vBounds: ScalarInterval
        let tubeRadius: Double
        let loopIndex: Int
        let sequenceIndex: Int
    }

    private struct FlatLoop {
        let loopIndex: Int
        let role: SurfaceTrimLoopRole
        let spans: [FlatSpan]

        func polygon(using execution: inout OriginalQueryExecution) throws -> [Point2D] {
            try OriginalParameterQueryStorage.map(spans, using: &execution) { span, execution in span.start }
        }
    }

    private let maximumSubdivisionDepth = 32
    private let maximumFlatSpanCount = 131_072

    public init() {}

    public func normalizationReversesLoop(_ loop: SurfaceTrimLoop, on surface: Surface3D,
        inside bounds: RectangularSurfaceParameterBounds, tolerance: ModelingTolerance) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try normalizationReversesLoop(loop, on: surface, inside: bounds, tolerance: tolerance, using: &execution)
    }

    package func validate(_ requestedLoops: [SurfaceTrimLoop], on surface: Surface3D,
        inside bounds: RectangularSurfaceParameterBounds, tolerance: ModelingTolerance) throws -> ExactSurfaceTrimLoopValidation {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(requestedLoops, on: surface, inside: bounds, tolerance: tolerance, using: &execution)
    }

    /// Whether orientation normalization reverses the authored loop.
    ///
    /// The kernel stores and names trim edges in normalized traversal
    /// order — an authored loop wound against its role's orientation is
    /// reversed curve-by-curve — so consumers deriving kernel edge
    /// ordinals for authored edges must apply the same verdict.
    public func normalizationReversesLoop(
        _ loop: SurfaceTrimLoop,
        on surface: Surface3D,
        inside bounds: RectangularSurfaceParameterBounds,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        return try orientationReversalRequired(
            loop,
            on: surface,
            parameterTolerance: try parameterTolerance(
                bounds: bounds,
                tolerance: tolerance
            ),
            tolerance: tolerance
        , using: &execution)
    }

    package func validate(
        _ requestedLoops: [SurfaceTrimLoop],
        on surface: Surface3D,
        inside bounds: RectangularSurfaceParameterBounds,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ExactSurfaceTrimLoopValidation {
        try execution.consumeWork(1)
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        let parameterTolerance = try parameterTolerance(
            bounds: bounds,
            tolerance: tolerance
        )
        let normalizedLoops = try OriginalParameterQueryStorage.map(requestedLoops, using: &execution) { loop, execution in
            try normalized(
                loop,
                on: surface,
                parameterTolerance: parameterTolerance,
                tolerance: tolerance
            , using: &execution)
        }
        var flatLoops: [FlatLoop] = []
        var totalFlatSpanCount = 0
        for (loopIndex, loop) in normalizedLoops.enumerated() {
            try execution.consumeWork(1)
            let flat = try flattened(
                loop,
                loopIndex: loopIndex,
                surface: surface,
                bounds: bounds,
                maximumDeviation: parameterTolerance * 0.125,
                tolerance: tolerance
            , using: &execution)
            totalFlatSpanCount += flat.spans.count
            guard totalFlatSpanCount <= maximumFlatSpanCount else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: Double(totalFlatSpanCount),
                    tolerance: tolerance,
                    "Exact surface trim boundary certification exceeded its adaptive span budget."
                )
            }
            try OriginalParameterQueryStorage.append(flat, to: &flatLoops, using: &execution)
        }
        try validateNonIntersecting(
            flatLoops,
            clearance: parameterTolerance * 0.25,
            tolerance: tolerance
        , using: &execution)
        try validateLoopContainment(
            flatLoops,
            clearance: parameterTolerance * 0.25,
            tolerance: tolerance
        , using: &execution)
        let minimumArea = max(
            parameterTolerance * parameterTolerance,
            Double.ulpOfOne * 4_096.0
        )
        let sourceArea = (bounds.upperU - bounds.lowerU)
            * (bounds.upperV - bounds.lowerV)
        let area = try parameterArea(
            of: normalizedLoops,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        , using: &execution) { lower, upper in
            (lower > minimumArea || upper <= minimumArea)
                && (sourceArea - upper > minimumArea || sourceArea - lower <= minimumArea)
        }
        guard let outerLoop = normalizedLoops.first(where: { $0.role == .outer }) else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                "Exact surface trim validation requires one outer loop."
            )
        }
        let outerArea = try parameterArea(
            of: [outerLoop],
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        , using: &execution) { lower, upper in
            upper - lower <= parameterTolerance
        }
        guard area.lower > minimumArea else {
            throw failure(
                .classificationFailure,
                residual: area.lower,
                tolerance: tolerance,
                "Exact surface trim region has no certifiably positive parameter area."
            )
        }
        guard sourceArea - area.upper > minimumArea else {
            throw failure(
                .invalidInput,
                residual: sourceArea - area.upper,
                tolerance: tolerance,
                "Surface trim must remove a certifiably nonzero parameter region."
            )
        }
        return ExactSurfaceTrimLoopValidation(
            loops: normalizedLoops,
            parameterAreaLowerBound: area.lower,
            parameterAreaUpperBound: area.upper,
            outerParameterAreaLowerBound: outerArea.lower,
            outerParameterAreaUpperBound: outerArea.upper
        )
    }

    private func normalized(
        _ loop: SurfaceTrimLoop,
        on surface: Surface3D,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceTrimLoop {
        try execution.consumeWork(1)
        guard try orientationReversalRequired(
            loop,
            on: surface,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        , using: &execution) else {
            return loop
        }
        return SurfaceTrimLoop(
            role: loop.role,
            parameterCurves: try OriginalParameterQueryStorage.map(loop.parameterCurves.reversed(), using: &execution) { curve, execution in
                try curve.reversed(tolerance: tolerance, using: &execution)
            }
        )
    }

    private func orientationReversalRequired(
        _ loop: SurfaceTrimLoop,
        on surface: Surface3D,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        try loop.validate(tolerance: tolerance)
        for curve in loop.parameterCurves {
            try execution.consumeWork(1)
            try curve.validate(on: surface, tolerance: tolerance, using: &execution)
        }
        try validateClosure(
            loop.parameterCurves,
            on: surface,
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        , using: &execution)
        let area = try parameterArea(
            of: [loop],
            parameterTolerance: parameterTolerance,
            tolerance: tolerance
        , using: &execution) { lower, upper in
            lower > 0.0 || upper < 0.0
        }
        let expectedPositive = loop.role == .outer
        if expectedPositive, area.lower > 0.0 {
            return false
        }
        if expectedPositive == false, area.upper < 0.0 {
            return false
        }
        let hasOppositeOrientation = expectedPositive
            ? area.upper < 0.0
            : area.lower > 0.0
        if hasOppositeOrientation {
            return true
        }
        throw failure(
            .classificationFailure,
            residual: max(abs(area.lower), abs(area.upper)),
            tolerance: tolerance,
            "Surface trim loop orientation could not be certified from its exact pcurves."
        )
    }

    private func validateClosure(
        _ curves: [SurfaceParameterCurve],
        on surface: Surface3D,
        parameterTolerance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for index in curves.indices {
            try execution.consumeWork(1)
            let end = try curves[index].endParameter(tolerance: tolerance, using: &execution)
            let next = try curves[(index + 1) % curves.count]
                .startParameter(tolerance: tolerance, using: &execution)
            let closesInParameters = end.isApproximatelyEqual(
                to: next,
                tolerance: parameterTolerance
            )
            let endPoint = try surface.point(
                u: end.u,
                v: end.v,
                tolerance: tolerance
            , using: &execution)
            let nextPoint = try surface.point(
                u: next.u,
                v: next.v,
                tolerance: tolerance
            , using: &execution)
            guard closesInParameters || endPoint.isApproximatelyEqual(
                to: nextPoint,
                tolerance: tolerance.distance
            ) else {
                throw failure(
                    .topologyFailure,
                    residual: (endPoint - nextPoint).length,
                    tolerance: tolerance,
                    "Surface trim exact pcurves do not form a closed ordered loop."
                )
            }
        }
    }

    private func flattened(
        _ loop: SurfaceTrimLoop,
        loopIndex: Int,
        surface: Surface3D,
        bounds: RectangularSurfaceParameterBounds,
        maximumDeviation: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> FlatLoop {
        try execution.consumeWork(1)
        var spans: [(
            start: Point2D,
            end: Point2D,
            uBounds: ScalarInterval,
            vBounds: ScalarInterval,
            tubeRadius: Double
        )] = []
        for curve in loop.parameterCurves {
            try execution.consumeWork(1)
            if requiresCertifiedEnclosure(curve) {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Surface Trim reaches this
                // original harmonic branch before boundary publication. The old
                // rational proposal has no whole original UV chord-tube receipt;
                // this source family must remain unsupported until that proof exists.
                if case .harmonic = curve {
                    throw failure(.unsupportedCapability, tolerance: tolerance,
                        "Original harmonic trim requires a complete original UV chord-tube proof.")
                }
                let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                    .enclosures(
                        for: curve,
                        on: surface,
                        maximumWidth: maximumDeviation,
                        tolerance: tolerance
                    , using: &execution)
                for enclosure in enclosures {
                    try execution.consumeWork(1)
                    let aligned = try aligned(
                        enclosure,
                        to: bounds,
                        on: surface,
                        tolerance: tolerance
                    )
                    try validateContained(
                        aligned,
                        in: bounds,
                        tolerance: maximumDeviation,
                        modelingTolerance: tolerance
                    , using: &execution)
                    let startParameter = try curve.parameter(
                        atNormalizedFraction: enclosure.lowerFraction,
                        tolerance: tolerance
                    , using: &execution)
                    let endParameter = try curve.parameter(
                        atNormalizedFraction: enclosure.upperFraction,
                        tolerance: tolerance
                    , using: &execution)
                    let start = try alignedPoint(
                        startParameter,
                        in: aligned,
                        on: surface,
                        tolerance: tolerance
                    )
                    let end = try alignedPoint(
                        endParameter,
                        in: aligned,
                        on: surface,
                        tolerance: tolerance
                    )
                    guard hypot(end.x - start.x, end.y - start.y)
                        > maximumDeviation else {
                        throw failure(
                            .singularGeometry,
                            residual: hypot(end.x - start.x, end.y - start.y),
                            tolerance: tolerance,
                            "A certified surface trim pcurve cell collapses within tolerance."
                        )
                    }
                    try OriginalParameterQueryStorage.append((
                        start: start,
                        end: end,
                        uBounds: aligned.u,
                        vBounds: aligned.v,
                        tubeRadius: hypot(
                            aligned.u.width,
                            aligned.v.width
                        ).nextUp
                    ), to: &spans, using: &execution)
                }
                continue
            }
            for patch in try rationalPatches(for: curve, tolerance: tolerance, using: &execution) {
                try execution.consumeWork(1)
                try validateContained(
                    patch,
                    in: bounds,
                    tolerance: maximumDeviation,
                    modelingTolerance: tolerance
                , using: &execution)
                try appendFlatSpans(
                    patch,
                    loopIndex: loopIndex,
                    maximumDeviation: maximumDeviation,
                    depth: 0,
                    spans: &spans,
                    tolerance: tolerance
                , using: &execution)
            }
        }
        guard spans.count >= 3 else {
            throw failure(
                .classificationFailure,
                residual: Double(spans.count),
                tolerance: tolerance,
                "Surface trim loop did not produce three certifiable boundary spans."
            )
        }
        return FlatLoop(
            loopIndex: loopIndex,
            role: loop.role,
            spans: try OriginalParameterQueryStorage.map(spans.enumerated(), using: &execution) { entry, execution in
                let (index, span) = entry
                return FlatSpan(
                    start: span.start,
                    end: span.end,
                    uBounds: span.uBounds,
                    vBounds: span.vBounds,
                    tubeRadius: span.tubeRadius,
                    loopIndex: loopIndex,
                    sequenceIndex: index
                )
            }
        )
    }

    private func rationalPatches(
        for curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBezierCurvePatch2D] {
        try execution.consumeWork(1)
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return try linearPatches(
                points: [
                    Point2D(
                        x: origin.x + direction.x * startParameter,
                        y: origin.y + direction.y * startParameter
                    ),
                    Point2D(
                        x: origin.x + direction.x * endParameter,
                        y: origin.y + direction.y * endParameter
                    ),
                ],
                tolerance: tolerance
            , using: &execution)
        case let .constantU(u, vStart, vEnd):
            return try linearPatches(
                points: [Point2D(x: u, y: vStart), Point2D(x: u, y: vEnd)],
                tolerance: tolerance
            , using: &execution)
        case let .constantV(v, uStart, uEnd):
            return try linearPatches(
                points: [Point2D(x: uStart, y: v), Point2D(x: uEnd, y: v)],
                tolerance: tolerance
            , using: &execution)
        case .harmonic:
            throw failure(.invalidInput, tolerance: tolerance,
                "Original harmonic trims require their retained original chord-tube proof.")
        case let .polyline(parameters):
            return try linearPatches(
                points: try OriginalParameterQueryStorage.map(parameters, using: &execution) { point, execution in Point2D(x: point.u, y: point.v) },
                tolerance: tolerance
            , using: &execution)
        case let .bSpline(curve):
            return try curve.rationalBezierPatches(tolerance: tolerance, using: &execution)
        case .originalBSplineContinuation, .originalImage, .originalAffineWord, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "A certificate-backed pcurve must use its interval enclosure path."
            )
        case let .offsetSurfaceImage(image):
            return try rationalPatches(
                for: image.source,
                tolerance: tolerance
            , using: &execution)
        case let .periodicTranslation(base, uShift, vShift):
            let original = try rationalPatches(for: base, tolerance: tolerance, using: &execution)
            return try OriginalParameterQueryStorage.map(original, using: &execution) { patch, execution in
                try patch.translated(u: uShift, v: vShift, using: &execution)
            }
        }
    }

    private func requiresCertifiedEnclosure(
        _ curve: SurfaceParameterCurve
    ) -> Bool {
        switch curve {
        case .harmonic, .originalBSplineContinuation, .originalImage, .originalAffineWord, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            true
        case let .offsetSurfaceImage(image):
            requiresCertifiedEnclosure(image.source)
        case .affine, .constantU, .constantV, .polyline, .bSpline:
            false
        case let .periodicTranslation(base, _, _):
            requiresCertifiedEnclosure(base)
        }
    }

    private func linearPatches(
        points: [Point2D],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBezierCurvePatch2D] {
        try execution.consumeWork(1)
        guard points.count >= 2 else {
            throw failure(
                .invalidInput,
                residual: Double(points.count),
                tolerance: tolerance,
                "Surface trim polyline requires at least two parameter points."
            )
        }
        return try OriginalParameterQueryStorage.flatMap(1..<points.count, using: &execution) { index, execution in
            try execution.retainStorage(bytes: 4 * MemoryLayout<Double>.stride + 2 * MemoryLayout<Point2D>.stride)
            return try BSplineCurve2D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [points[index - 1], points[index]]
            ).rationalBezierPatches(tolerance: tolerance, using: &execution)
        }
    }

    private func validateContained(
        _ patch: RationalBezierCurvePatch2D,
        in bounds: RectangularSurfaceParameterBounds,
        tolerance: Double,
        modelingTolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard try OriginalParameterQueryStorage.allSatisfy(patch.controlPoints, using: &execution, predicate: { point, execution in
            point.x >= bounds.lowerU - tolerance
                && point.x <= bounds.upperU + tolerance
                && point.y >= bounds.lowerV - tolerance
                && point.y <= bounds.upperV + tolerance
        }) else {
            throw failure(
                .invalidInput,
                tolerance: modelingTolerance,
                "Surface trim pcurve convex hull must be contained in the current rectangular face."
            )
        }
    }

    private func validateContained(
        _ enclosure: SurfaceParameterCurveEnclosure,
        in bounds: RectangularSurfaceParameterBounds,
        tolerance: Double,
        modelingTolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard enclosure.u.lower >= bounds.lowerU - tolerance,
              enclosure.u.upper <= bounds.upperU + tolerance,
              enclosure.v.lower >= bounds.lowerV - tolerance,
              enclosure.v.upper <= bounds.upperV + tolerance else {
            throw failure(
                .invalidInput,
                residual: max(
                    bounds.lowerU - enclosure.u.lower,
                    enclosure.u.upper - bounds.upperU,
                    bounds.lowerV - enclosure.v.lower,
                    enclosure.v.upper - bounds.upperV
                ),
                tolerance: modelingTolerance,
                "A certified surface trim pcurve leaves the current face parameter domain."
            )
        }
    }

    private func aligned(
        _ enclosure: SurfaceParameterCurveEnclosure,
        to bounds: RectangularSurfaceParameterBounds,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveEnclosure {
        SurfaceParameterCurveEnclosure(
            lowerFraction: enclosure.lowerFraction,
            upperFraction: enclosure.upperFraction,
            u: try aligned(
                enclosure.u,
                toLower: bounds.lowerU,
                upper: bounds.upperU,
                domain: surface.uDomain,
                tolerance: tolerance
            ),
            v: try aligned(
                enclosure.v,
                toLower: bounds.lowerV,
                upper: bounds.upperV,
                domain: surface.vDomain,
                tolerance: tolerance
            )
        )
    }

    private func aligned(
        _ interval: ScalarInterval,
        toLower lower: Double,
        upper: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .periodic(period) = domain else { return interval }
        guard period.isFinite, period > tolerance.angle else {
            throw failure(
                .invalidInput,
                residual: period,
                tolerance: tolerance,
                "A periodic surface parameter domain has an invalid period."
            )
        }
        let sourceMidpoint = interval.midpoint
        let targetMidpoint = lower + (upper - lower) * 0.5
        let shift = ((targetMidpoint - sourceMidpoint) / period).rounded() * period
        return try ScalarInterval(
            lower: (interval.lower + shift).nextDown,
            upper: (interval.upper + shift).nextUp
        )
    }

    private func alignedPoint(
        _ parameter: SurfaceParameter,
        in enclosure: SurfaceParameterCurveEnclosure,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let u = try aligned(
            parameter.u,
            to: enclosure.u,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let v = try aligned(
            parameter.v,
            to: enclosure.v,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        guard u >= enclosure.u.lower - parameterTolerance,
              u <= enclosure.u.upper + parameterTolerance,
              v >= enclosure.v.lower - parameterTolerance,
              v <= enclosure.v.upper + parameterTolerance else {
            throw failure(
                .intersectionFailure,
                tolerance: tolerance,
                "A certified pcurve endpoint escaped its interval enclosure."
            )
        }
        return Point2D(x: u, y: v)
    }

    private func aligned(
        _ value: Double,
        to interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard case let .periodic(period) = domain else { return value }
        guard period.isFinite, period > tolerance.angle else {
            throw failure(
                .invalidInput,
                residual: period,
                tolerance: tolerance,
                "A periodic surface parameter domain has an invalid period."
            )
        }
        return value + ((interval.midpoint - value) / period).rounded() * period
    }

    private func appendFlatSpans(
        _ patch: RationalBezierCurvePatch2D,
        loopIndex: Int,
        maximumDeviation: Double,
        depth: Int,
        spans: inout [(
            start: Point2D,
            end: Point2D,
            uBounds: ScalarInterval,
            vBounds: ScalarInterval,
            tubeRadius: Double
        )],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.admitGeometricDepth(depth)
        guard let start = patch.controlPoints.first,
              let end = patch.controlPoints.last else {
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "A rational pcurve patch has no endpoints."
            )
        }
        let chordLength = hypot(end.x - start.x, end.y - start.y)
        guard chordLength > maximumDeviation else {
            if try OriginalParameterQueryStorage.allSatisfy(patch.controlPoints, using: &execution, predicate: { point, execution in
                hypot(point.x - start.x, point.y - start.y) <= maximumDeviation
            }) {
                throw failure(
                    .singularGeometry,
                    residual: chordLength,
                    tolerance: tolerance,
                    "Surface trim contains a pcurve span that collapses within tolerance."
                )
            }
            guard depth < maximumSubdivisionDepth else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: chordLength,
                    tolerance: tolerance,
                    "Surface trim pcurve flatness certification exceeded its subdivision depth."
                )
            }
            for child in try patch.subdivided(tolerance: tolerance, using: &execution) {
                try execution.consumeWork(1)
                try appendFlatSpans(
                    child,
                    loopIndex: loopIndex,
                    maximumDeviation: maximumDeviation,
                    depth: depth + 1,
                    spans: &spans,
                    tolerance: tolerance
                , using: &execution)
            }
            return
        }
        let flatness = try OriginalParameterQueryStorage.reduce(patch.controlPoints,
            initial: -Double.infinity, using: &execution) { maximum, point, execution in
                max(maximum, distance(point, toSegmentFrom: start, to: end))
            }
        if flatness <= maximumDeviation,
           try hasMonotoneChordProjection(patch, start: start, end: end, using: &execution) {
            let uValues = try OriginalParameterQueryStorage.map(patch.controlPoints, using: &execution) { point, execution in point.x }
            let vValues = try OriginalParameterQueryStorage.map(patch.controlPoints, using: &execution) { point, execution in point.y }
            try OriginalParameterQueryStorage.append((
                start: start,
                end: end,
                uBounds: try ScalarInterval(
                    lower: (uValues.min() ?? start.x).nextDown,
                    upper: (uValues.max() ?? end.x).nextUp
                ),
                vBounds: try ScalarInterval(
                    lower: (vValues.min() ?? start.y).nextDown,
                    upper: (vValues.max() ?? end.y).nextUp
                ),
                tubeRadius: flatness.nextUp
            ), to: &spans, using: &execution)
            return
        }
        guard depth < maximumSubdivisionDepth else {
            throw failure(
                .resourceLimitExceeded,
                residual: flatness,
                tolerance: tolerance,
                "Surface trim pcurve flatness certification exceeded its subdivision depth."
            )
        }
        for child in try patch.subdivided(tolerance: tolerance, using: &execution) {
            try execution.consumeWork(1)
            try appendFlatSpans(
                child,
                loopIndex: loopIndex,
                maximumDeviation: maximumDeviation,
                depth: depth + 1,
                spans: &spans,
                tolerance: tolerance
            , using: &execution)
        }
    }

    private func hasMonotoneChordProjection(
        _ patch: RationalBezierCurvePatch2D,
        start: Point2D,
        end: Point2D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let dx = end.x - start.x
        let dy = end.y - start.y
        var previous = -Double.infinity
        for point in patch.controlPoints {
            try execution.consumeWork(1)
            let projection = (point.x - start.x) * dx
                + (point.y - start.y) * dy
            guard projection.isFinite,
                  projection >= previous else {
                return false
            }
            previous = projection
        }
        return true
    }

    private func validateNonIntersecting(
        _ loops: [FlatLoop],
        clearance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let predicateTolerance = ModelingTolerance(
            distance: clearance,
            angle: tolerance.angle,
            relative: tolerance.relative
        )
        let predicates = AdaptivePlanarPredicateEvaluator()
        let spans = try OriginalParameterQueryStorage.flatMap(loops, using: &execution) { loop, execution in loop.spans }
        for firstIndex in spans.indices {
            try execution.consumeWork(1)
            for secondIndex in spans.indices where secondIndex > firstIndex {
                try execution.consumeWork(1)
                let first = spans[firstIndex]
                let second = spans[secondIndex]
                if areAdjacent(first, second, loops: loops) {
                    try validateAdjacentTurn(
                        first,
                        second,
                        clearance: clearance,
                        tolerance: tolerance
                    , using: &execution)
                    continue
                }
                if areSeparatedByCertifiedBounds(
                    first,
                    second,
                    clearance: clearance
                ) {
                    continue
                }
                let chordDistance = segmentDistance(first, second)
                let requiredSeparation = (
                    first.tubeRadius
                        + second.tubeRadius
                        + clearance
                ).nextUp
                if try predicates.segmentsIntersectOrTouch(
                    first.start,
                    first.end,
                    second.start,
                    second.end,
                    tolerance: predicateTolerance
                , using: &execution) || chordDistance.nextDown <= requiredSeparation {
                    throw failure(
                        .classificationFailure,
                        residual: chordDistance,
                        tolerance: tolerance,
                        "Surface trim pcurve tubes intersect or cannot be separated within tolerance."
                    )
                }
            }
        }
    }

    private func areAdjacent(
        _ first: FlatSpan,
        _ second: FlatSpan,
        loops: [FlatLoop]
    ) -> Bool {
        guard first.loopIndex == second.loopIndex else { return false }
        let count = loops[first.loopIndex].spans.count
        let closesLoop = (
            first.sequenceIndex == 0
                && second.sequenceIndex == count - 1
        ) || (
            second.sequenceIndex == 0
                && first.sequenceIndex == count - 1
        )
        return abs(first.sequenceIndex - second.sequenceIndex) == 1
            || closesLoop
    }

    private func areSeparatedByCertifiedBounds(
        _ first: FlatSpan,
        _ second: FlatSpan,
        clearance: Double
    ) -> Bool {
        first.uBounds.upper.nextUp + clearance < second.uBounds.lower
            || second.uBounds.upper.nextUp + clearance < first.uBounds.lower
            || first.vBounds.upper.nextUp + clearance < second.vBounds.lower
            || second.vBounds.upper.nextUp + clearance < first.vBounds.lower
    }

    private func validateAdjacentTurn(
        _ first: FlatSpan,
        _ second: FlatSpan,
        clearance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let joinsInSequence = first.sequenceIndex + 1 == second.sequenceIndex
        let firstJoin = joinsInSequence ? first.end : first.start
        let secondJoin = joinsInSequence ? second.start : second.end
        let joinGap = hypot(
            firstJoin.x - secondJoin.x,
            firstJoin.y - secondJoin.y
        )
        guard joinGap <= clearance else {
            throw failure(
                .topologyFailure,
                residual: joinGap,
                tolerance: tolerance,
                "Adjacent surface trim pcurve enclosure cells do not close in one parameter chart."
            )
        }
        let firstVector = Point2D(
            x: first.end.x - first.start.x,
            y: first.end.y - first.start.y
        )
        let secondVector = Point2D(
            x: second.end.x - second.start.x,
            y: second.end.y - second.start.y
        )
        let firstLength = hypot(firstVector.x, firstVector.y)
        let secondLength = hypot(secondVector.x, secondVector.y)
        guard firstLength > clearance,
              secondLength > clearance else {
            throw failure(
                .singularGeometry,
                residual: min(firstLength, secondLength),
                tolerance: tolerance,
                "Surface trim contains an unresolved adjacent boundary span."
            )
        }
        let dot = (firstVector.x * secondVector.x + firstVector.y * secondVector.y)
            / (firstLength * secondLength)
        guard dot > -cos(tolerance.angle) else {
            throw failure(
                .classificationFailure,
                residual: dot,
                tolerance: tolerance,
                "Surface trim contains a locally reversing boundary."
            )
        }
    }

    private func validateLoopContainment(
        _ loops: [FlatLoop],
        clearance: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let outer = loops.first(where: { $0.role == .outer }) else {
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "Surface trim has no outer loop after normalization."
            )
        }
        let predicateTolerance = ModelingTolerance(
            distance: clearance,
            angle: tolerance.angle,
            relative: tolerance.relative
        )
        let predicates = AdaptivePlanarPredicateEvaluator()
        let innerLoops = try OriginalParameterQueryStorage.filter(loops, using: &execution) { loop, execution in loop.role == .inner }
        for inner in innerLoops {
            try execution.consumeWork(1)
            let witness = try interiorWitness(
                for: inner,
                clearance: clearance,
                predicates: predicates,
                tolerance: predicateTolerance,
                modelingTolerance: tolerance
            , using: &execution)
            guard try predicates.classify(
                witness,
                in: outer.polygon(using: &execution),
                tolerance: predicateTolerance
            , using: &execution) == .inside else {
                throw failure(
                    .classificationFailure,
                    tolerance: tolerance,
                    "Every inner surface trim loop must be certifiably contained by the outer loop."
                )
            }
            for other in innerLoops where other.loopIndex != inner.loopIndex {
                try execution.consumeWork(1)
                let classification = try predicates.classify(
                    witness,
                    in: other.polygon(using: &execution),
                    tolerance: predicateTolerance
                , using: &execution)
                guard classification == .outside else {
                    throw failure(
                        .classificationFailure,
                        tolerance: tolerance,
                        "Nested or overlapping surface trim inner loops are not a valid face region."
                    )
                }
            }
        }
    }

    private func interiorWitness(
        for loop: FlatLoop,
        clearance: Double,
        predicates: AdaptivePlanarPredicateEvaluator,
        tolerance: ModelingTolerance,
        modelingTolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point2D {
        try execution.consumeWork(1)
        let polygon = try loop.polygon(using: &execution)
        for span in loop.spans {
            try execution.consumeWork(1)
            let dx = span.end.x - span.start.x
            let dy = span.end.y - span.start.y
            let length = hypot(dx, dy)
            guard length > clearance else { continue }
            let midpoint = Point2D(
                x: 0.5 * (span.start.x + span.end.x),
                y: 0.5 * (span.start.y + span.end.y)
            )
            let inward = loop.role == .outer
                ? Point2D(x: -dy / length, y: dx / length)
                : Point2D(x: dy / length, y: -dx / length)
            let candidate = Point2D(
                x: midpoint.x + inward.x * clearance * 8.0,
                y: midpoint.y + inward.y * clearance * 8.0
            )
            if try predicates.classify(
                candidate,
                in: polygon,
                tolerance: tolerance
            , using: &execution) == .inside {
                return candidate
            }
        }
        throw failure(
            .classificationFailure,
            tolerance: modelingTolerance,
            "Surface trim loop has no certifiable interior witness."
        )
    }

    /// Certified area bounds tighten adaptively until the caller's decision
    /// predicate is conclusive: rational pcurve enclosures converge only
    /// linearly with subdivision, so requesting the floor width up front can
    /// exhaust the integration budget on decisions that a much looser
    /// enclosure already answers.
    private func parameterArea(
        of loops: [SurfaceTrimLoop],
        parameterTolerance: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        isConclusive: (_ lower: Double, _ upper: Double) -> Bool
    ) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let curveCount = try OriginalParameterQueryStorage.reduce(loops, initial: 0, using: &execution) { count, loop, execution in
            let sum = count.addingReportingOverflow(loop.parameterCurves.count)
            guard !sum.overflow else { throw ExactScalarFailure.countOverflow }
            return sum.partialValue
        }
        let floorCurveWidth = max(
            parameterTolerance * parameterTolerance
                / Double(max(curveCount, 1) * 32),
            Double.ulpOfOne * 1_024.0
        )
        var requestedCurveWidth = max(
            floorCurveWidth,
            1.0e-6 / Double(max(curveCount, 1))
        )
        while true {
            try execution.consumeWork(1)
            var lower = 0.0
            var upper = 0.0
            for loop in loops {
                try execution.consumeWork(1)
                for curve in loop.parameterCurves {
                    try execution.consumeWork(1)
                    let contribution = try SurfaceParameterCurveAreaIntegrator().bounds(
                        for: curve,
                        uShift: 0.0,
                        requestedWidth: requestedCurveWidth,
                        tolerance: tolerance
                    , using: &execution)
                    lower = (lower + contribution.lower).nextDown
                    upper = (upper + contribution.upper).nextUp
                }
            }
            if isConclusive(lower, upper) || requestedCurveWidth <= floorCurveWidth {
                return (lower, upper)
            }
            requestedCurveWidth = max(
                floorCurveWidth,
                requestedCurveWidth / 16.0
            )
        }
    }

    private func parameterTolerance(
        bounds: RectangularSurfaceParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let scale = max(
            abs(bounds.lowerU),
            abs(bounds.upperU),
            abs(bounds.lowerV),
            abs(bounds.upperV),
            1.0
        )
        let result = max(
            tolerance.distance,
            tolerance.angle,
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        guard result.isFinite, result > 0.0 else {
            throw failure(
                .invalidInput,
                residual: result,
                tolerance: tolerance,
                "Surface trim parameter tolerance is invalid."
            )
        }
        return result
    }

    private func segmentDistance(_ first: FlatSpan, _ second: FlatSpan) -> Double {
        min(
            distance(first.start, toSegmentFrom: second.start, to: second.end),
            distance(first.end, toSegmentFrom: second.start, to: second.end),
            distance(second.start, toSegmentFrom: first.start, to: first.end),
            distance(second.end, toSegmentFrom: first.start, to: first.end)
        )
    }

    private func distance(
        _ point: Point2D,
        toSegmentFrom start: Point2D,
        to end: Point2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = dx * dx + dy * dy
        guard denominator > Double.leastNonzeroMagnitude else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy)
            / denominator
        let parameter = min(max(raw, 0.0), 1.0)
        return hypot(
            point.x - (start.x + dx * parameter),
            point.y - (start.y + dy * parameter)
        )
    }

    private func failure(
        _ code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .classification,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
