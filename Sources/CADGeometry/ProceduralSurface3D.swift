import CADCore

public enum ProceduralSurface3D: Hashable, Sendable {
    case offset(OffsetSurface3D)
    case ruled(RuledSurface3D)
    case rollingBall(RollingBallBlendSurface3D)
    case originalAngularTransport(OriginalAngularTransportSurface3D)
    case originalAffineWord(OriginalAffineWordSurface3D)
    case originalImage(OriginalImageSurface3D)
    case originalRevolution(OriginalRevolutionSurface3D)
    case originalCoons(OriginalCoonsSurface3D)
    case originalBoundaryCorrected(OriginalBoundaryCorrectedSurface3D)
    indirect case originalPlaneDerivative(OriginalPlaneDerivativeSurface3D)
    case originalDrafted(OriginalDraftedRuledSurface3D)

    /// Finds the certified closest point on a finite procedural parameter domain.
    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(tolerance: tolerance, using: &execution)
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func parameterDerivatives(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func parameterDerivativesThroughThirdOrder(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterProjectionResult(of: point, options: options, tolerance: tolerance, using: &execution)
    }

    func taylorJet(
        u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intervalJet(over: parameters, tolerance: tolerance, using: &execution)
    }

    package func exactChartPreservingSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try exactChartPreservingSurface(tolerance: tolerance, using: &execution)
    }

    package func closestParameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try closestParameterProjection(of: point, options: options, tolerance: tolerance, using: &execution)
    }

    package func closestParameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterProjection {
        try execution.consumeWork(1)
        return try ProceduralSurfaceParameterProjector().closestProjection(
            of: point, on: .procedural(self), options: options, tolerance: tolerance
        , using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        switch self {
        case let .originalAngularTransport(surface):
            try surface.validateOriginalRelation(tolerance: tolerance, usage: &execution)
        case let .originalAffineWord(surface):
            try surface.validateOriginalRelation(tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        case let .originalImage(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.validate(using: &execution)
        case let .offset(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        case let .ruled(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
        }
    }

    public var uDomain: ParameterDomain {
        switch self {
        case let .originalAngularTransport(surface):
            surface.uDomain
        case let .originalAffineWord(surface):
            surface.uDomain
        case let .originalImage(surface):
            surface.uDomain
        case let .originalRevolution(surface):
            surface.uDomain
        case let .originalCoons(surface):
            surface.uDomain
        case let .originalBoundaryCorrected(surface):
            surface.uDomain
        case let .originalPlaneDerivative(surface):
            surface.uDomain
        case let .originalDrafted(surface):
            surface.uDomain
        case let .rollingBall(surface):
            surface.uDomain
        case let .offset(surface):
            surface.uDomain
        case let .ruled(surface):
            surface.uDomain
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case let .originalAngularTransport(surface):
            surface.vDomain
        case let .originalAffineWord(surface):
            surface.vDomain
        case let .originalImage(surface):
            surface.vDomain
        case let .originalRevolution(surface):
            surface.vDomain
        case let .originalCoons(surface):
            surface.vDomain
        case let .originalBoundaryCorrected(surface):
            surface.vDomain
        case let .originalPlaneDerivative(surface):
            surface.vDomain
        case let .originalDrafted(surface):
            surface.vDomain
        case let .rollingBall(surface):
            surface.vDomain
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
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return switch self {
        case let .originalAngularTransport(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalAffineWord(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalImage(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.point(u: u, v: v, using: &execution)
        case let .offset(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .ruled(surface):
            try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
        }
    }

    public func parameterDerivatives(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives {
        try execution.consumeWork(1)
        return switch self {
        case let .originalAngularTransport(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalAffineWord(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalImage(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.parameterDerivatives(u: u, v: v, using: &execution)
        case let .offset(surface):
            try surface.parameterDerivatives(
                u: u,
                v: v,
                tolerance: tolerance
            , using: &execution)
        case let .ruled(surface):
            try surface.parameterDerivatives(
                u: u,
                v: v,
                tolerance: tolerance
            , using: &execution)
        }
    }

    public func parameterDerivativesThroughThirdOrder(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterThirdOrderDerivatives {
        try execution.consumeWork(1)
        return switch self {
        case let .originalAngularTransport(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalAffineWord(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalImage(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.parameterDerivativesThroughThirdOrder(u: u, v: v, using: &execution)
        case let .offset(surface):
            try surface.parameterDerivativesThroughThirdOrder(
                u: u,
                v: v,
                tolerance: tolerance
            , using: &execution)
        case let .ruled(surface):
            try surface.parameterDerivativesThroughThirdOrder(
                u: u,
                v: v,
                tolerance: tolerance
            , using: &execution)
        }
    }

    func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterProjectionResult {
        try execution.consumeWork(1)
        switch self {
        case .originalAngularTransport, .originalAffineWord, .originalImage, .originalRevolution, .originalCoons, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted:
            let candidate = try ProceduralSurfaceParameterProjector().closestProjection(
                of: point, on: .procedural(self), options: options, tolerance: tolerance, using: &execution)
            return candidate.residual <= tolerance.distance ? .projected(candidate)
                : .outsideTolerance(residual: candidate.residual)
        case let .rollingBall(surface):
            return try ProceduralSurfaceParameterProjector().parameterProjectionResult(
                of: point, on: surface, options: options, tolerance: tolerance
            , using: &execution)
        case let .offset(surface):
            return try ProceduralSurfaceParameterProjector().parameterProjectionResult(
                of: point,
                on: surface,
                options: options,
                tolerance: tolerance
            , using: &execution)
        case let .ruled(surface):
            return try ProceduralSurfaceParameterProjector().parameterProjectionResult(
                of: point,
                on: surface,
                options: options,
                tolerance: tolerance
            , using: &execution)
        }
    }

    func taylorJet(
        u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        return switch self {
        case let .originalAngularTransport(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalAffineWord(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalImage(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.taylorJet(u: u, v: v, throughOrder: order, using: &execution)
        case let .offset(surface):
            try surface.taylorJet(
                u: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            , using: &execution)
        case let .ruled(surface):
            try surface.taylorJet(
                u: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            , using: &execution)
        }
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try execution.consumeWork(1)
        return switch self {
        case let .originalAngularTransport(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalAffineWord(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalImage(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalRevolution(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalCoons(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalBoundaryCorrected(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalPlaneDerivative(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .originalDrafted(surface):
            try surface.intervalJet(over: parameters, tolerance: tolerance, using: &execution)
        case let .rollingBall(surface):
            try surface.intervalJet(over: parameters, using: &execution)
        case let .offset(surface):
            try surface.intervalJet(
                over: parameters,
                tolerance: tolerance
            , using: &execution)
        case let .ruled(surface):
            try surface.intervalJet(
                over: parameters,
                tolerance: tolerance
            , using: &execution)
        }
    }

    /// Returns an exact surface with the preserved parameter chart when the
    /// procedural construction has a closed-form canonical representation.
    package func exactChartPreservingSurface(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Surface3D? {
        try execution.consumeWork(1)
        switch self {
        case .originalAngularTransport, .originalAffineWord, .originalImage, .originalRevolution, .originalCoons, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted, .rollingBall:
            return nil
        case let .offset(surface):
            return try surface.exactChartPreservingSurface(tolerance: tolerance, using: &execution)
        case let .ruled(surface):
            guard let exact = try surface.exactBSplineRepresentation(
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            return .bSpline(exact)
        }
    }
}

#if !hasFeature(Embedded)
extension ProceduralSurface3D: Codable {}
#endif
