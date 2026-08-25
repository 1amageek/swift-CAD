import CADCore

public enum ProceduralSurface3D: Codable, Hashable, Sendable {
    case offset(OffsetSurface3D)
    case ruled(RuledSurface3D)

    public func validate(tolerance: ModelingTolerance) throws {
        switch self {
        case let .offset(surface):
            try surface.validate(tolerance: tolerance)
        case let .ruled(surface):
            try surface.validate(tolerance: tolerance)
        }
    }

    public var uDomain: ParameterDomain {
        switch self {
        case let .offset(surface):
            surface.uDomain
        case let .ruled(surface):
            surface.uDomain
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case let .offset(surface):
            surface.vDomain
        case let .ruled(surface):
            surface.vDomain
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch self {
        case let .offset(surface):
            try surface.point(u: u, v: v, tolerance: tolerance)
        case let .ruled(surface):
            try surface.point(u: u, v: v, tolerance: tolerance)
        }
    }

    public func parameterDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        switch self {
        case let .offset(surface):
            try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        case let .ruled(surface):
            try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        }
    }

    public func parameterDerivativesThroughThirdOrder(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        switch self {
        case let .offset(surface):
            try surface.parameterDerivativesThroughThirdOrder(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        case let .ruled(surface):
            try surface.parameterDerivativesThroughThirdOrder(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        }
    }

    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        switch self {
        case let .offset(surface):
            try ProceduralSurfaceParameterProjector().parameterProjectionResult(
                of: point,
                on: surface,
                options: options,
                tolerance: tolerance
            )
        case let .ruled(surface):
            try ProceduralSurfaceParameterProjector().parameterProjectionResult(
                of: point,
                on: surface,
                options: options,
                tolerance: tolerance
            )
        }
    }

    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        switch self {
        case let .offset(surface):
            try surface.taylorJet(
                atU: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            )
        case let .ruled(surface):
            try surface.taylorJet(
                atU: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            )
        }
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        switch self {
        case let .offset(surface):
            try surface.intervalJet(
                over: parameters,
                tolerance: tolerance
            )
        case let .ruled(surface):
            try surface.intervalJet(
                over: parameters,
                tolerance: tolerance
            )
        }
    }

    /// Returns an exact surface with the preserved parameter chart when the
    /// procedural construction has a closed-form canonical representation.
    package func exactChartPreservingSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        switch self {
        case let .offset(surface):
            return try surface.exactChartPreservingSurface(tolerance: tolerance)
        case let .ruled(surface):
            guard let exact = try surface.exactBSplineRepresentation(
                tolerance: tolerance
            ) else {
                return nil
            }
            return .bSpline(exact)
        }
    }
}
