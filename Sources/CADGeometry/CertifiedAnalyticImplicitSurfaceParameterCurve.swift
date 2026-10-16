#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

public struct CertifiedAnalyticImplicitSurfaceParameterCurve: Hashable, Sendable {
    public let intersection: CertifiedAnalyticBSplineIntersectionCurve
    public let startFraction: Double
    public let endFraction: Double

    init(
        validatedIntersection intersection: CertifiedAnalyticBSplineIntersectionCurve,
        startFraction: Double,
        endFraction: Double
    ) {
        self.intersection = intersection
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    public init(
        intersection: CertifiedAnalyticBSplineIntersectionCurve,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(intersection: intersection, startFraction: startFraction, endFraction: endFraction, tolerance: tolerance, using: &execution)
    }

    public init(
        intersection: CertifiedAnalyticBSplineIntersectionCurve,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= -tolerance.relative,
              startFraction <= 1.0 + tolerance.relative,
              endFraction >= -tolerance.relative,
              endFraction <= 1.0 + tolerance.relative,
              abs(endFraction - startFraction) > tolerance.relative else {
            throw GeometryError.invalidDistance(endFraction - startFraction)
        }
        self.intersection = intersection
        self.startFraction = min(max(startFraction, 0.0), 1.0)
        self.endFraction = min(max(endFraction, 0.0), 1.0)
        try intersection.validate(tolerance: tolerance)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(on: surface, tolerance: tolerance, using: &execution)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try intersection.validate(tolerance: tolerance, using: &execution)
        guard surface == intersection.analyticSurface,
              startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= 0.0,
              startFraction <= 1.0,
              endFraction >= 0.0,
              endFraction <= 1.0,
              abs(endFraction - startFraction) > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic implicit pcurve does not belong to the requested surface."
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        let mapped = try mappedFraction(fraction, tolerance: tolerance, using: &execution)
        let pair = try intersection.implicitCurve.parameterPair(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        , using: &execution)
        let point = try intersection.implicitCurve.point(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        , using: &execution)
        let internalParameter = intersection.analyticIsFirst ? pair.first : pair.second
        let result = try AnalyticSurfaceRationalParameterMap(
            surface: intersection.analyticSurface,
            periodicSeamOffset: intersection.periodicSeamOffset,
            tolerance: tolerance
        , using: &execution).parameter(fromRational: internalParameter, tolerance: tolerance, using: &execution)
        let reconstructed = try intersection.analyticSurface.point(
            u: result.u,
            v: result.v,
            tolerance: tolerance
        , using: &execution)
        let residual = (reconstructed - point).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified analytic pcurve failed exact point reconstruction."
            )
        }
        return result
    }

    package func parameterEnclosure(
        for subcell: CertifiedImplicitIntersectionGraphSubcell,
        tolerance: ModelingTolerance
    ) throws -> AnalyticSurfaceRationalParameterMap.Enclosure {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterEnclosure(for: subcell, tolerance: tolerance, using: &execution)
    }

    package func parameterEnclosure(
        for subcell: CertifiedImplicitIntersectionGraphSubcell,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> AnalyticSurfaceRationalParameterMap.Enclosure {
        try execution.consumeWork(1)
        let coordinateCount = SurfaceIntersectionParameterCoordinate.allCases.count
        guard subcell.parameterDerivativeBounds.count == coordinateCount else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic pcurve enclosure requires one derivative interval per intersection coordinate."
            )
        }
        let analyticU: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstU
            : .secondU
        let analyticV: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstV
            : .secondV
        return try AnalyticSurfaceRationalParameterMap(
            surface: intersection.analyticSurface,
            periodicSeamOffset: intersection.periodicSeamOffset,
            tolerance: tolerance
        , using: &execution).enclosure(
            rationalU: subcell.parameterBox.interval(for: analyticU),
            rationalV: subcell.parameterBox.interval(for: analyticV),
            rationalUDerivative: subcell.parameterDerivativeBounds[analyticU.rawValue],
            rationalVDerivative: subcell.parameterDerivativeBounds[analyticV.rawValue],
            tolerance: tolerance
        , using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
        let mapped = try mappedFraction(fraction, tolerance: tolerance, using: &execution)
        let parameter = try parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        let curveDifferential = try intersection.implicitCurve.differential(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        , using: &execution)
        let surfaceDifferential = try intersection.analyticSurface.differentialGeometry(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        , using: &execution)
        let tangentU = surfaceDifferential.tangentU
        let tangentV = surfaceDifferential.tangentV
        let metricUU = tangentU.dot(tangentU)
        let metricUV = tangentU.dot(tangentV)
        let metricVV = tangentV.dot(tangentV)
        let determinant = metricUU * metricVV - metricUV * metricUV
        let metricScale = max(metricUU * metricVV, Double.leastNonzeroMagnitude)
        let determinantFloor = max(
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * metricScale
        guard determinant.isFinite,
              determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A certified analytic pcurve differential is singular."
            )
        }
        let spatialDerivative = curveDifferential.firstDerivative
        let rightU = tangentU.dot(spatialDerivative)
        let rightV = tangentV.dot(spatialDerivative)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructedDerivative = tangentU * derivativeU + tangentV * derivativeV
        let derivativeResidual = (reconstructedDerivative - spatialDerivative).length
        let derivativeScale = max(spatialDerivative.length, 1.0)
        guard derivativeResidual <= tolerance.relative * derivativeScale else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: derivativeResidual / derivativeScale,
                tolerance: tolerance,
                message: "A certified analytic pcurve failed tangent reconstruction."
            )
        }
        let parameterSecondDerivative = try SurfaceParameterSecondDerivativeSolver().solve(
            surface: surfaceDifferential,
            firstParameterDerivative: Point2D(x: derivativeU, y: derivativeV),
            spatialSecondDerivative: curveDifferential.secondDerivative,
            tolerance: tolerance,
            diagnosticContext: "Certified analytic pcurve"
        , using: &execution)
        let scale = endFraction - startFraction
        return SurfaceParameterCurveDifferential(
            parameter: parameter,
            firstDerivative: Point2D(
                x: derivativeU * scale,
                y: derivativeV * scale
            ),
            secondDerivative: Point2D(
                x: parameterSecondDerivative.x * scale * scale,
                y: parameterSecondDerivative.y * scale * scale
            )
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point2D {
        try execution.consumeWork(1)
        let mapped = try mappedFraction(fraction, tolerance: tolerance, using: &execution)
        let lower = try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        let scale = endFraction - startFraction
        let spatialThird = try intersection.implicitCurve.thirdDerivative(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        , using: &execution) * (scale * scale * scale)
        let surface = try intersection.analyticSurface
            .parameterDerivativesThroughThirdOrder(
                u: lower.parameter.u,
                v: lower.parameter.v,
                tolerance: tolerance
            , using: &execution)
        return try SurfaceParameterThirdDerivativeSolver().solve(
            surface: surface,
            firstParameterDerivative: lower.firstDerivative,
            secondParameterDerivative: lower.secondDerivative,
            spatialThirdDerivative: spatialThird,
            tolerance: tolerance,
            diagnosticContext: "Certified analytic pcurve"
        , using: &execution)
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reversed(tolerance: tolerance, using: &execution)
    }

    public func reversed(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        try execution.consumeWork(1)
        try tolerance.validate()
        return CertifiedAnalyticImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            startFraction: endFraction,
            endFraction: startFraction)
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subcurve(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        return CertifiedAnalyticImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            startFraction: try interpolate(
                startFraction,
                endFraction,
                fraction: min(max(lower, 0.0), 1.0)
            , using: &execution),
            endFraction: try interpolate(
                startFraction,
                endFraction,
                fraction: min(max(upper, 0.0), 1.0)
            , using: &execution)
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trimmed(from: startParameter, to: endParameter, curveDomain: curveDomain, tolerance: tolerance, using: &execution)
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        try execution.consumeWork(1)
        return try subcurve(
            fromNormalizedFraction: try normalizedFraction(
                startParameter,
                domain: curveDomain,
                tolerance: tolerance
            , using: &execution),
            toNormalizedFraction: try normalizedFraction(
                endParameter,
                domain: curveDomain,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
    }



    private func mappedFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return try interpolate(
            startFraction,
            endFraction,
            fraction: min(max(fraction, 0.0), 1.0)
        , using: &execution)
    }



    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard case let .closed(lower, upper) = domain,
              parameter.isFinite,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        return (parameter - lower) / (upper - lower)
    }



    private func interpolate(
        _ lower: Double,
        _ upper: Double,
        fraction: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return lower + (upper - lower) * fraction
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case intersection
        case startFraction
        case endFraction
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.intersection, .startFraction, .endFraction],
            in: decoder
        )
        let intersection = try container.decode(
            CertifiedAnalyticBSplineIntersectionCurve.self,
            forKey: .intersection
        )
        try self.init(
            intersection: intersection,
            startFraction: container.decode(Double.self, forKey: .startFraction),
            endFraction: container.decode(Double.self, forKey: .endFraction),
            tolerance: intersection.implicitCurve.certificationTolerance
        , using: &execution)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(
            on: intersection.analyticSurface,
            tolerance: intersection.implicitCurve.certificationTolerance
        , using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intersection, forKey: .intersection)
        try container.encode(startFraction, forKey: .startFraction)
        try container.encode(endFraction, forKey: .endFraction)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedAnalyticImplicitSurfaceParameterCurve: Codable {}
#endif
