import CADCore
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

public struct CertifiedBoundedPlaneConeIntersectionCurve: Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public let planeSurface: Surface3D
    public let coneSurface: Surface3D
    public let analyticCurve: AnalyticCurve3D
    public let startParameter: Double
    public let endParameter: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        planeSurface: Surface3D,
        coneSurface: Surface3D,
        analyticCurve: AnalyticCurve3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(planeSurface: planeSurface, coneSurface: coneSurface, analyticCurve: analyticCurve, startParameter: startParameter, endParameter: endParameter, tolerance: tolerance, using: &execution)
    }


    public init(
        planeSurface: Surface3D,
        coneSurface: Surface3D,
        analyticCurve: AnalyticCurve3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        self.planeSurface = planeSurface
        self.coneSurface = coneSurface
        self.analyticCurve = analyticCurve
        self.startParameter = startParameter
        self.endParameter = endParameter
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        try validate(tolerance: tolerance, using: &execution)
            try execution.checkpoint()
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }


    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try validateImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
    }



    private func validateImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try GeometryStructuralComparisonWork.charge(surface: planeSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: coneSurface, using: &execution)
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        guard case .plane = CanonicalAnalyticSurface(planeSurface),
              case .cone = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve requires one plane and one cone."
            )
        }
        switch analyticCurve {
        case .hyperbola, .parabola:
            break
        case .line, .circle, .arc, .ellipse, .planeTorus:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve requires an exact hyperbola or parabola."
            )
        }
        try planeSurface.validate(tolerance: tolerance, using: &execution)
        try coneSurface.validate(tolerance: tolerance, using: &execution)
        try analyticCurve.validate(tolerance: tolerance, using: &execution)
        guard startParameter.isFinite,
              endParameter.isFinite,
              endParameter > startParameter,
              maximumResidualUpperBound == certificationTolerance.distance,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A bounded plane-cone curve has an invalid interval or residual certificate."
            )
        }
        let exactCandidates = try Self.exactAnalyticCandidates(
            planeSurface: planeSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        guard exactCandidates.contains(analyticCurve) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A bounded plane-cone curve no longer matches the exact conic classified from its source surfaces."
            )
        }
        let start = try analyticCurve.point(at: startParameter, tolerance: tolerance, using: &execution)
        let end = try analyticCurve.point(at: endParameter, tolerance: tolerance, using: &execution)
        guard (end - start).length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: (end - start).length,
                tolerance: tolerance,
                message: "A bounded plane-cone interval collapsed within modeling tolerance."
            )
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: Double.self))
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance,
                validatingCertificate: false
            , using: &execution)
            try verify(point: point, on: planeSurface, tolerance: tolerance, using: &execution)
            try verify(point: point, on: coneSurface, tolerance: tolerance, using: &execution)
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        let result = try pointImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func pointImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            validatingCertificate: false
        , using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        let result = try differentialImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func differentialImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        let parameter = try mappedParameter(fraction, tolerance: tolerance, using: &execution)
        let geometry = try analyticCurve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        , using: &execution)
        let scale = endParameter - startParameter
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative * scale,
            secondDerivative: geometry.secondDerivative * (scale * scale)
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        let result = try thirdDerivativeImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func thirdDerivativeImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let parameter = try mappedParameter(fraction, tolerance: tolerance, using: &execution)
        let derivative = try Curve3D.analytic(analyticCurve)
            .parameterDerivativesThroughThirdOrder(
                at: parameter,
                tolerance: tolerance
            , using: &execution).thirdDerivative
        let scale = endParameter - startParameter
        return derivative * (scale * scale * scale)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        let result = try parameterImplementation(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func parameterImplementation(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard surface == planeSurface || surface == coneSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            validatingCertificate: false
        , using: &execution)
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
        let u: Double
        if surface == coneSurface {
            let middlePoint = try self.point(
                atNormalizedFraction: 0.5,
                tolerance: tolerance,
                validatingCertificate: false
            , using: &execution)
            let middleProjection = try coneSurface.parameterProjection(
                of: middlePoint,
                tolerance: tolerance
            , using: &execution)
            u = Self.unwrappedAngle(projection.u, nearest: middleProjection.u)
        } else {
            u = projection.u
        }
        let reconstructed = try surface.point(
            u: u,
            v: projection.v,
            tolerance: tolerance
        , using: &execution)
        let residual = (reconstructed - point).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A bounded plane-cone pcurve failed exact point reconstruction."
            )
        }
        return SurfaceParameter(u: u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }


    public func boundingBox(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.checkpoint()
        let result = try boundingBoxImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func boundingBoxImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        var parameters = [startParameter, endParameter]
        var parametersCapacity = parameters.count
        switch analyticCurve {
        case let .hyperbola(curve):
            let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
                tolerance: tolerance.distance
            )
            let first = curve.transverseAxis * curve.transverseRadius
            let second = conjugateAxis * curve.conjugateRadius
            for (a, b) in [
                (first.x, second.x),
                (first.y, second.y),
                (first.z, second.z),
            ] where abs(a) > Double.leastNonzeroMagnitude {
                try execution.consumeWork(1)
                let ratio = -b / a
                if abs(ratio) < 1.0 {
                    let candidate = atanh(ratio)
                    if candidate > startParameter, candidate < endParameter {
                        try CertifiedAnalyticCurveEvaluation.append(candidate, to: &parameters, using: &execution, capacity: &parametersCapacity)
                    }
                }
            }
        case let .parabola(curve):
            let transverseAxis = try curve.normal.cross(curve.axis).normalized(
                tolerance: tolerance.distance
            )
            let quadratic = curve.axis * (1.0 / (4.0 * curve.focalLength))
            for (linear, second) in [
                (transverseAxis.x, quadratic.x),
                (transverseAxis.y, quadratic.y),
                (transverseAxis.z, quadratic.z),
            ] where abs(second) > Double.leastNonzeroMagnitude {
                try execution.consumeWork(1)
                let candidate = -linear / (2.0 * second)
                if candidate > startParameter, candidate < endParameter {
                    try CertifiedAnalyticCurveEvaluation.append(candidate, to: &parameters, using: &execution, capacity: &parametersCapacity)
                }
            }
        case .line, .circle, .arc, .ellipse, .planeTorus:
            break
        }
        return try BoundingBox3D(points: (try CertifiedAnalyticCurveEvaluation.map(parameters, using: &execution) { element, execution in 
            try analyticCurve.point(at: element, tolerance: tolerance, using: &execution)
         }))
    }

    private func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        validatingCertificate: Bool
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        if validatingCertificate {
            try validate(tolerance: tolerance, using: &execution)
        }
        return try analyticCurve.point(
            at: mappedParameter(fraction, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
    }

    private func mappedParameter(
        _ fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return startParameter
            + (endParameter - startParameter) * min(max(fraction, 0.0), 1.0)
    }

    private func verify(
        point: Point3D,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
        guard projection.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: projection.residual,
                tolerance: tolerance,
                message: "A bounded plane-cone certificate exceeded its source-surface residual."
            )
        }
    }

    private static func exactAnalyticCandidates(
        planeSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [AnalyticCurve3D] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard case let .plane(plane) = CanonicalAnalyticSurface(planeSurface),
              case let .cone(cone) = CanonicalAnalyticSurface(coneSurface) else {
            return []
        }
        return try (try CertifiedAnalyticCurveEvaluation.compactMap(PlaneConeSurfaceIntersector().intersections(
            plane: plane,
            cone: cone,
            firstSurface: planeSurface,
            secondSurface: coneSurface,
            tolerance: tolerance
        , using: &execution), using: &execution) { intersection, execution in
            guard case let .curve(value) = intersection,
                  case let .parametric(.analytic(curve)) = value.truth else {
                return nil
            }
            switch curve {
            case .hyperbola, .parabola:
                return curve
            case .line, .circle, .arc, .ellipse, .planeTorus:
                return nil
            }
         })
    }

    private static func unwrappedAngle(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + ((reference - angle) / period).rounded() * period
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case planeSurface
        case coneSurface
        case analyticCurve
        case startParameter
        case endParameter
        case certificationTolerance
        case maximumResidualUpperBound
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .planeSurface,
                .coneSurface,
                .analyticCurve,
                .startParameter,
                .endParameter,
                .certificationTolerance,
                .maximumResidualUpperBound,
            ],
            in: decoder
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        try self.init(
            planeSurface: container.decode(Surface3D.self, forKey: .planeSurface),
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
            analyticCurve: container.decode(AnalyticCurve3D.self, forKey: .analyticCurve),
            startParameter: container.decode(Double.self, forKey: .startParameter),
            endParameter: container.decode(Double.self, forKey: .endParameter),
            tolerance: tolerance
        , using: &execution)
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: storedBound,
                tolerance: tolerance,
                message: "A decoded bounded plane-cone residual certificate was altered."
            )
        }
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)

        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planeSurface, forKey: .planeSurface)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(analyticCurve, forKey: .analyticCurve)
        try container.encode(startParameter, forKey: .startParameter)
        try container.encode(endParameter, forKey: .endParameter)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedBoundedPlaneConeIntersectionCurve: Codable {}
#endif
