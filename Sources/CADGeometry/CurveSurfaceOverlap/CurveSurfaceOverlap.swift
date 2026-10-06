import CADCore

/// An owned source interval certified to lie on the retained target surface.
public struct CurveSurfaceOverlap: Sendable {
    public let curveRange: ScalarInterval
    public let start: CurveSurfaceOverlapEndpoint
    public let end: CurveSurfaceOverlapEndpoint
    public let maximumSpatialDeviation: Double
    public var originalTraversal: OriginalCurveRootSpan3D? { originalPlane?.sector.traversal }
    private let curve: Curve3D
    private let surface: Surface3D
    private let tolerance: ModelingTolerance
    private let uRange: ScalarInterval?
    private let vRange: ScalarInterval?
    private let isoparametric: OverlapIsoparametricCorrespondence?
    private let graph: OverlapRegularGraphCorrespondence?
    private let originalPlane: OriginalNativePlaneOverlapCorrespondence?

    init(curve: Curve3D, surface: Surface3D, range: ScalarInterval, deviation: Double,
         options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
         isoparametric: OverlapIsoparametricCorrespondence? = nil) throws {
        self.curve = curve
        self.surface = surface
        self.tolerance = tolerance
        self.isoparametric = isoparametric
        self.graph = nil
        self.originalPlane = nil
        curveRange = range
        maximumSpatialDeviation = deviation
        uRange = options.surfaceURange
        vRange = options.surfaceVRange
        start = try Self.evaluate(curve: curve, surface: surface, parameter: range.lower,
                                  uRange: uRange, vRange: vRange, tolerance: tolerance, isoparametric: isoparametric)
        end = try Self.evaluate(curve: curve, surface: surface, parameter: range.upper,
                                uRange: uRange, vRange: vRange, tolerance: tolerance, isoparametric: isoparametric)
    }

    init(curve: Curve3D, surface: Surface3D, range: ScalarInterval, deviation: Double,
         options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
         graph: OverlapRegularGraphCorrespondence, budget: inout OverlapProofBudget) throws {
        guard graph.root.curve.curve == curve, graph.root.originalSurface == surface,
              graph.range.contains(range.lower), graph.range.contains(range.upper) else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                message: "A regular overlap result differs from its certified original operands or source cover.")
        }
        self.curve = curve
        self.surface = surface
        self.tolerance = tolerance
        self.graph = graph
        self.originalPlane = nil
        isoparametric = nil
        curveRange = range
        maximumSpatialDeviation = deviation
        uRange = options.surfaceURange
        vRange = options.surfaceVRange
        start = try Self.evaluate(curve: curve, surface: surface, parameter: range.lower,
            uRange: uRange, vRange: vRange, tolerance: tolerance, graph: graph, budget: &budget)
        end = try Self.evaluate(curve: curve, surface: surface, parameter: range.upper,
            uRange: uRange, vRange: vRange, tolerance: tolerance, graph: graph, budget: &budget)
    }

    init(original: OriginalNativePlaneOverlapCorrespondence) throws {
        originalPlane = original
        curve = original.sector.traversal.source
        surface = .plane(original.sector.plane)
        tolerance = original.tolerance
        graph = nil; isoparametric = nil
        uRange = original.options.surfaceURange; vRange = original.options.surfaceVRange
        curveRange = try original.sourceBounds()
        maximumSpatialDeviation = 0
        start = try original.endpoint(at: 0)
        end = try original.endpoint(at: 1)
    }

    /// Evaluates the original normalized traversal, including algebraic ends.
    public func correspondence(atNormalizedFraction fraction: Double) throws -> CurveSurfaceOverlapEndpoint {
        guard let originalPlane else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Existing regular-graph overlap
            // consumers retain native source parameters. Their exact normalized
            // endpoint transport must be issued before this new facade can use it.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Overlap has no retained normalized original sector correspondence.")
        }
        return try originalPlane.endpoint(at: fraction)
    }

    /// Evaluates owned correspondence in the certified range, including its endpoints.
    /// Coordinates use the requested periodic representative or the canonical chart.
    public func correspondence(at curveParameter: Double) throws -> CurveSurfaceOverlapEndpoint {
        try CurrentTaskCancellationChecker().checkCancellation()
        if originalPlane != nil {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native parameter inversion for
            // algebraic clipped sectors requires exact endpoint transport. Use
            // the retained normalized correspondence instead of rounded cuts.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original clipped sector correspondence requires a normalized fraction.")
        }
        guard curveRange.contains(curveParameter) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Overlap correspondence requires a parameter inside its certified source interval.")
        }
        if let graph {
            var budget = OverlapProofBudget(options: graph.options, tolerance: tolerance)
            return try Self.evaluate(curve: curve, surface: surface, parameter: curveParameter,
                uRange: uRange, vRange: vRange, tolerance: tolerance, graph: graph, budget: &budget)
        }
        return try Self.evaluate(curve: curve, surface: surface, parameter: curveParameter,
                                 uRange: uRange, vRange: vRange, tolerance: tolerance, isoparametric: isoparametric)
    }

    static func evaluate(curve: Curve3D, surface: Surface3D, parameter: Double,
                         uRange: ScalarInterval?, vRange: ScalarInterval?, tolerance: ModelingTolerance,
                         isoparametric: OverlapIsoparametricCorrespondence? = nil) throws -> CurveSurfaceOverlapEndpoint {
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let raw: SurfaceParameter
        if let isoparametric {
            raw = isoparametric.parameter(at: parameter)
        } else if case let .surfaceLift(lift) = curve, lift.surface == surface {
            raw = try lift.parameterCurve.parameter(atNormalizedFraction: parameter, tolerance: tolerance)
        } else {
            let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
            raw = SurfaceParameter(u: projection.u, v: projection.v)
        }
        return try evaluated(point: point, raw: raw, surface: surface, parameter: parameter,
            uRange: uRange, vRange: vRange, tolerance: tolerance)
    }

    static func evaluate(curve: Curve3D, surface: Surface3D, parameter: Double,
                         uRange: ScalarInterval?, vRange: ScalarInterval?, tolerance: ModelingTolerance,
                         graph: OverlapRegularGraphCorrespondence, budget: inout OverlapProofBudget) throws -> CurveSurfaceOverlapEndpoint {
        let raw = try graph.parameter(at: parameter, budget: &budget)
        let point = try curve.point(at: parameter, tolerance: tolerance)
        return try evaluated(point: point, raw: raw, surface: surface, parameter: parameter,
            uRange: uRange, vRange: vRange, tolerance: tolerance)
    }

    private static func evaluated(point: Point3D, raw: SurfaceParameter, surface: Surface3D, parameter: Double,
                                  uRange: ScalarInterval?, vRange: ScalarInterval?, tolerance: ModelingTolerance) throws -> CurveSurfaceOverlapEndpoint {
        let resolver = SurfaceParameterRangeResolver()
        guard let u = resolver.resolvedParameter(raw.u, domain: surface.uDomain, requestedRange: uRange, tolerance: tolerance),
              let v = resolver.resolvedParameter(raw.v, domain: surface.vDomain, requestedRange: vRange, tolerance: tolerance) else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                              message: "Overlap correspondence lies outside the requested target chart ranges.")
        }
        let chartParameter = SurfaceParameter(u: u, v: v)
        let targetPoint = try surface.point(u: u, v: v, tolerance: tolerance)
        let residual = (point - targetPoint).length
        guard residual.isFinite, residual <= tolerance.distance else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, residual: residual, tolerance: tolerance,
                              message: "Continuous overlap correspondence failed forward residual verification.")
        }
        return CurveSurfaceOverlapEndpoint(curveParameter: parameter,
                                          point: point, surfaceParameter: chartParameter, residual: residual,
                                          isSurfaceChartSingular: SurfaceParameterTopology(surface: surface).isUSingular(chartParameter, tolerance: tolerance))
    }
}
