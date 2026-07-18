import CADCore

public struct BridgeSurfaceFeature: Codable, Sendable, Hashable {
    public enum EndOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public var startBoundary: BSplineCurve3D
    public var endBoundary: BSplineCurve3D
    public var endOrientation: EndOrientation
    public var material: MaterialID?

    public init(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        endOrientation: EndOrientation = .forward,
        material: MaterialID? = nil
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.endOrientation = endOrientation
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case endOrientation
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .endOrientation, .material],
            in: decoder
        )
        startBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .startBoundary
        )
        endBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .endBoundary
        )
        endOrientation = try container.decode(
            EndOrientation.self,
            forKey: .endOrientation
        )
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        try container.encode(endOrientation, forKey: .endOrientation)
        try container.encodeIfPresent(material, forKey: .material)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        _ = try surface(tolerance: tolerance)
    }

    public func surface(tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        try tolerance.validate()
        try startBoundary.validate(tolerance: tolerance)
        try endBoundary.validate(tolerance: tolerance)
        let orientedEnd = try orientedEndBoundary(tolerance: tolerance)
        guard startBoundary.degree == orientedEnd.degree,
              startBoundary.controlPointCount == orientedEnd.controlPointCount,
              startBoundary.knots.count == orientedEnd.knots.count else {
            throw invalidInput(
                tolerance: tolerance,
                message: "Bridge surface boundaries must have compatible B-spline bases."
            )
        }
        let startNormalizedKnots = try normalizedKnots(
            of: startBoundary,
            tolerance: tolerance
        )
        let endNormalizedKnots = try normalizedKnots(
            of: orientedEnd,
            tolerance: tolerance
        )
        let knotResidual = zip(startNormalizedKnots, endNormalizedKnots)
            .map { abs($0 - $1) }
            .max() ?? 0.0
        guard knotResidual <= tolerance.angle else {
            throw invalidInput(
                residual: knotResidual,
                tolerance: tolerance,
                message: "Bridge surface boundary knot distributions are incompatible."
            )
        }

        let surface = BSplineSurface3D(
            uDegree: startBoundary.degree,
            vDegree: 1,
            uKnots: startBoundary.knots,
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                startBoundary.controlPoints,
                orientedEnd.controlPoints,
            ],
            weights: [
                startBoundary.weights,
                orientedEnd.weights,
            ]
        )
        try surface.validate(tolerance: tolerance)
        try verifyBoundaries(
            surface,
            orientedEnd: orientedEnd,
            tolerance: tolerance
        )
        try verifyRegularity(surface, tolerance: tolerance)
        return surface
    }

    private func orientedEndBoundary(
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        switch endOrientation {
        case .forward:
            return endBoundary
        case .reversed:
            return try endBoundary.reversed(tolerance: tolerance)
        }
    }

    private func normalizedKnots(
        of curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard case let .closed(lower, upper) = curve.domain,
              upper - lower > tolerance.angle else {
            throw invalidInput(
                residual: 0.0,
                tolerance: tolerance,
                message: "Bridge surface boundaries require finite non-degenerate domains."
            )
        }
        return curve.knots.map { ($0 - lower) / (upper - lower) }
    }

    private func verifyBoundaries(
        _ surface: BSplineSurface3D,
        orientedEnd: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .closed(startLower, startUpper) = startBoundary.domain,
              case let .closed(endLower, endUpper) = orientedEnd.domain else {
            throw invalidInput(
                tolerance: tolerance,
                message: "Bridge surface boundary verification requires finite domains."
            )
        }
        var maximumResidual = 0.0
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let surfaceParameter = startLower + (startUpper - startLower) * fraction
            let endParameter = endLower + (endUpper - endLower) * fraction
            let startResidual = try (
                surface.point(u: surfaceParameter, v: 0.0, tolerance: tolerance)
                    - startBoundary.point(at: surfaceParameter, tolerance: tolerance)
            ).length
            let endResidual = try (
                surface.point(u: surfaceParameter, v: 1.0, tolerance: tolerance)
                    - orientedEnd.point(at: endParameter, tolerance: tolerance)
            ).length
            maximumResidual = max(maximumResidual, startResidual, endResidual)
        }
        guard maximumResidual <= tolerance.distance else {
            throw invalidInput(
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Bridge surface did not preserve its exact boundary curves."
            )
        }
    }

    private func verifyRegularity(
        _ surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .closed(uLower, uUpper) = surface.uDomain else {
            throw invalidInput(
                tolerance: tolerance,
                message: "Bridge surface requires a finite U domain."
            )
        }
        for uIndex in 0...8 {
            let u = uLower + (uUpper - uLower) * Double(uIndex) / 8.0
            for vIndex in 0...4 {
                let v = Double(vIndex) / 4.0
                _ = try surface.differentialGeometry(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
            }
        }
    }

    private func invalidInput(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .validation,
            code: .invalidInput,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
