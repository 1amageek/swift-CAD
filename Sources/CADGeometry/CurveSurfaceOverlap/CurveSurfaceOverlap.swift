import CADCore

/// An owned source interval certified to lie on the retained target surface.
public struct CurveSurfaceOverlap: Sendable {
    public let curveRange: ScalarInterval
    public let start: CurveSurfaceOverlapEndpoint
    public let end: CurveSurfaceOverlapEndpoint
    public let maximumSpatialDeviation: Double
    private let curve: Curve3D
    private let surface: Surface3D
    private let tolerance: ModelingTolerance
    private let uRange: ScalarInterval?
    private let vRange: ScalarInterval?
    private let isoparametric: OverlapIsoparametricCorrespondence?

    init(curve: Curve3D, surface: Surface3D, range: ScalarInterval, deviation: Double,
         options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
         isoparametric: OverlapIsoparametricCorrespondence? = nil) throws {
        self.curve = curve
        self.surface = surface
        self.tolerance = tolerance
        self.isoparametric = isoparametric
        curveRange = range
        maximumSpatialDeviation = deviation
        uRange = options.surfaceURange
        vRange = options.surfaceVRange
        start = try Self.evaluate(curve: curve, surface: surface, parameter: range.lower,
                                  uRange: uRange, vRange: vRange, tolerance: tolerance, isoparametric: isoparametric)
        end = try Self.evaluate(curve: curve, surface: surface, parameter: range.upper,
                                uRange: uRange, vRange: vRange, tolerance: tolerance, isoparametric: isoparametric)
    }

    /// Evaluates owned correspondence in the certified range, including its endpoints.
    /// Coordinates use the requested periodic representative or the canonical chart.
    public func correspondence(at curveParameter: Double) throws -> CurveSurfaceOverlapEndpoint {
        try Task.checkCancellation()
        guard curveRange.contains(curveParameter) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Overlap correspondence requires a parameter inside its certified source interval.")
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
