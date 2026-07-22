import CADCore

public struct SurfaceParameterDomain2D: Codable, Sendable, Hashable {
    public var uLowerBound: Double
    public var uUpperBound: Double
    public var vLowerBound: Double
    public var vUpperBound: Double

    public init(
        uLowerBound: Double,
        uUpperBound: Double,
        vLowerBound: Double,
        vUpperBound: Double
    ) {
        self.uLowerBound = uLowerBound
        self.uUpperBound = uUpperBound
        self.vLowerBound = vLowerBound
        self.vUpperBound = vUpperBound
    }

    public static func fullDomain(
        of surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDomain2D {
        try surface.validate(tolerance: tolerance)
        guard case let .closed(uLowerBound, uUpperBound) = surface.uDomain,
              case let .closed(vLowerBound, vUpperBound) = surface.vDomain else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-spline surface feature requires finite U and V domains."
            )
        }
        return SurfaceParameterDomain2D(
            uLowerBound: uLowerBound,
            uUpperBound: uUpperBound,
            vLowerBound: vLowerBound,
            vUpperBound: vUpperBound
        )
    }

    public func validate(
        containedIn surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        let values = [uLowerBound, uUpperBound, vLowerBound, vUpperBound]
        guard values.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: values.first(where: { $0.isFinite == false }),
                tolerance: tolerance,
                message: "A surface parameter domain requires finite bounds."
            )
        }
        guard uUpperBound - uLowerBound > tolerance.distance,
              vUpperBound - vLowerBound > tolerance.distance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: min(uUpperBound - uLowerBound, vUpperBound - vLowerBound),
                tolerance: tolerance,
                message: "A surface parameter domain requires positive U and V spans."
            )
        }
        guard try surface.uDomain.containsSpan(
            from: uLowerBound,
            to: uUpperBound,
            tolerance: tolerance
        ), try surface.vDomain.containsSpan(
            from: vLowerBound,
            to: vUpperBound,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface parameter domain must be contained in its source surface."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case uLowerBound
        case uUpperBound
        case vLowerBound
        case vUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.uLowerBound, .uUpperBound, .vLowerBound, .vUpperBound],
            in: decoder
        )
        uLowerBound = try container.decode(Double.self, forKey: .uLowerBound)
        uUpperBound = try container.decode(Double.self, forKey: .uUpperBound)
        vLowerBound = try container.decode(Double.self, forKey: .vLowerBound)
        vUpperBound = try container.decode(Double.self, forKey: .vUpperBound)
    }
}
