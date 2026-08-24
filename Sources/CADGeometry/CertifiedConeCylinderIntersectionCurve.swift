import CADCore
import Foundation

public struct CertifiedConeCylinderIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case apexLowerNodeInterval
        case apexUpperNodeInterval
        case rulingParallelLinear
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct ThirdOrderDifferentialGeometry {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
        let thirdDerivative: Vector3D
    }

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        var coefficientScale: Double {
            max(absoluteCoefficientMaximum, 1.0)
        }

        var absoluteCoefficientMaximum: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                abs(sineDouble)
            )
        }

        var firstDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (2.0 * abs(cosineDouble)).nextUp,
                (2.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var secondDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (4.0 * abs(cosineDouble)).nextUp,
                (4.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var thirdDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (8.0 * abs(cosineDouble)).nextUp,
                (8.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var fourthDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (16.0 * abs(cosineDouble)).nextUp,
                (16.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var fifthDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (32.0 * abs(cosineDouble)).nextUp,
                (32.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var sixthDerivativeAbsoluteUpperBound: Double {
            [
                abs(cosine),
                abs(sine),
                (64.0 * abs(cosineDouble)).nextUp,
                (64.0 * abs(sineDouble)).nextUp,
            ].reduce(0.0) { ($0 + $1).nextUp }
        }

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine + 4.0 * sineDouble,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine - 4.0 * sineDouble,
                constant - cosine + cosineDouble,
            ]
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }

        func firstDerivative(at angle: Double) -> Double {
            -cosine * sin(angle)
                + sine * cos(angle)
                - 2.0 * cosineDouble * sin(2.0 * angle)
                + 2.0 * sineDouble * cos(2.0 * angle)
        }

        func secondDerivative(at angle: Double) -> Double {
            -cosine * cos(angle)
                - sine * sin(angle)
                - 4.0 * cosineDouble * cos(2.0 * angle)
                - 4.0 * sineDouble * sin(2.0 * angle)
        }

        func thirdDerivative(at angle: Double) -> Double {
            cosine * sin(angle)
                - sine * cos(angle)
                + 8.0 * cosineDouble * sin(2.0 * angle)
                - 8.0 * sineDouble * cos(2.0 * angle)
        }

        func derivative(order: Int, at angle: Double) -> Double {
            guard order > 0 else { return value(at: angle) }
            let firstPhase = Double(order) * Double.pi * 0.5
            let secondPhase = Double(order) * Double.pi * 0.5
            return cosine * cos(angle + firstPhase)
                + sine * sin(angle + firstPhase)
                + cosineDouble * pow(2.0, Double(order))
                    * cos(2.0 * angle + secondPhase)
                + sineDouble * pow(2.0, Double(order))
                    * sin(2.0 * angle + secondPhase)
        }

        var derivativePolynomial: TrigonometricPolynomial {
            TrigonometricPolynomial(
                constant: 0.0,
                cosine: sine,
                sine: -cosine,
                cosineDouble: 2.0 * sineDouble,
                sineDouble: -2.0 * cosineDouble
            )
        }
    }

    private struct Configuration {
        let cone: Cone
        let cylinder: Cylinder
        let cylinderRadialU: Vector3D
        let cylinderRadialV: Vector3D
        let coneMetricScale: Double
        let generatorQuadratic: Double
        let halfLinearPolynomial: TrigonometricPolynomial
        let baseQuadraticPolynomial: TrigonometricPolynomial
        let discriminantPolynomial: TrigonometricPolynomial

        var characteristicLength: Double {
            max(
                (cylinder.origin - cone.apex).length,
                cylinder.radius,
                1.0
            )
        }

        func cylinderBaseOffset(at angle: Double) -> Vector3D {
            cylinder.origin - cone.apex
                + cylinderRadialU * cos(angle)
                + cylinderRadialV * sin(angle)
        }

        func coneMetric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
        let third: Double

        init(
            value: Double,
            first: Double,
            second: Double,
            third: Double
        ) {
            self.value = value
            self.first = first
            self.second = second
            self.third = third
        }

        static func constant(_ value: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value,
                first: 0.0,
                second: 0.0,
                third: 0.0
            )
        }

        func adding(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second,
                third: third + other.third
            )
        }

        func subtracting(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value - other.value,
                first: first - other.first,
                second: second - other.second,
                third: third - other.third
            )
        }

        func scaled(by scale: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scale,
                first: first * scale,
                second: second * scale,
                third: third * scale
            )
        }
    }

    public let coneSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.coneSurface = coneSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        try validate(tolerance: tolerance)
    }

    static func apexContactAngle(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let projection: SurfaceParameterProjection
        do {
            projection = try configuration.cylinder.surface.parameterProjection(
                of: configuration.cone.apex,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .intersectionFailure {
            return nil
        }
        let angle = normalizedAngle(projection.u)
        let discriminantResidual = abs(
            configuration.discriminantPolynomial.value(at: angle)
        )
        guard projection.residual <= tolerance.distance,
              discriminantResidual <= classificationTolerance(
                  configuration: configuration,
                  tolerance: tolerance
              ) * 16.0 else {
            return nil
        }
        return angle
    }

    static func rulingParallelLinearCurveIfApplicable(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedConeCylinderIntersectionCurve? {
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let quadraticTolerance = generatorQuadraticTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard abs(configuration.generatorQuadratic) <= quadraticTolerance else {
            return nil
        }
        let halfLinearTolerance = max(
            Double.ulpOfOne * configuration.characteristicLength * 4_096.0,
            tolerance.distance * 1.0e-6
        )
        _ = try minimumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        )
        return try CertifiedConeCylinderIntersectionCurve(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            componentKind: .rulingParallelLinear,
            lowerAngle: 0.0,
            upperAngle: 2.0 * Double.pi,
            tolerance: tolerance
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        if componentKind != .apexLowerNodeInterval,
           componentKind != .apexUpperNodeInterval {
            try Self.rejectApexContact(
                cone: configuration.cone,
                cylinder: configuration.cylinder,
                tolerance: tolerance
            )
        }
        guard lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperAngle - lowerAngle)
        }
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let quadraticTolerance = Self.generatorQuadraticTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        if componentKind != .rulingParallelLinear {
            guard abs(configuration.generatorQuadratic) > quadraticTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(configuration.generatorQuadratic),
                    tolerance: tolerance,
                    message: "A quadratic cone-cylinder component requires a nonzero generator coefficient."
                )
            }
        }
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let boundaries = try Self.roots(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let minimumDiscriminant = try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  minimumDiscriminant > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumDiscriminant,
                    tolerance: tolerance,
                    message: "A full cone-cylinder branch requires a positive root-free discriminant domain."
                )
            }
        case .boundedAngularInterval:
            let boundaries = try Self.roots(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let lowerResidual = abs(
                configuration.discriminantPolynomial.value(at: lowerAngle)
            )
            let upperResidual = abs(
                configuration.discriminantPolynomial.value(at: upperAngle)
            )
            let lowerSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(at: lowerAngle)
            )
            let upperSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(at: upperAngle)
            )
            let matchesCompleteInterval = Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminantPolynomial,
                classificationTolerance: classificationTolerance
            ).contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            guard lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  lowerSlope > classificationTolerance,
                  upperSlope > classificationTolerance,
                  matchesCompleteInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded cone-cylinder component is not a complete simple-root interval."
                )
            }
        case .apexLowerNodeInterval, .apexUpperNodeInterval:
            let boundaries = try Self.roots(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            guard let apexAngle = try Self.apexContactAngle(
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A cone-cylinder apex node requires the cone apex on the cylinder."
                )
            }
            let apexBoundary = componentKind == .apexLowerNodeInterval
                ? lowerAngle
                : upperAngle
            let simpleBoundary = componentKind == .apexLowerNodeInterval
                ? upperAngle
                : lowerAngle
            let apexResidual = abs(
                configuration.discriminantPolynomial.value(at: apexBoundary)
            )
            let simpleResidual = abs(
                configuration.discriminantPolynomial.value(at: simpleBoundary)
            )
            let apexSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(
                    at: apexBoundary
                )
            )
            let apexCurvature = configuration.discriminantPolynomial
                .secondDerivative(at: apexBoundary)
            let simpleSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(
                    at: simpleBoundary
                )
            )
            let matchesCompleteInterval = Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminantPolynomial,
                classificationTolerance: classificationTolerance
            ).contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            guard Self.angularDistance(apexBoundary, apexAngle) <= tolerance.angle,
                  apexResidual <= classificationTolerance * 16.0,
                  simpleResidual <= classificationTolerance * 16.0,
                  apexSlope <= classificationTolerance * 16.0,
                  apexCurvature > classificationTolerance,
                  simpleSlope > classificationTolerance,
                  matchesCompleteInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(apexResidual, simpleResidual),
                    tolerance: tolerance,
                    message: "A cone-cylinder apex node must cover one complete interval between a double apex root and a simple root."
                )
            }
        case .rulingParallelLinear:
            let halfLinearTolerance = max(
                Double.ulpOfOne * configuration.characteristicLength * 4_096.0,
                tolerance.distance * 1.0e-6
            )
            let minimumHalfLinear = try Self.minimumAbsoluteValue(
                of: configuration.halfLinearPolynomial,
                residualTolerance: halfLinearTolerance,
                tolerance: tolerance
            )
            guard abs(configuration.generatorQuadratic) <= quadraticTolerance,
                  abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  minimumHalfLinear > halfLinearTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: min(
                        abs(configuration.generatorQuadratic),
                        minimumHalfLinear
                    ),
                    tolerance: tolerance,
                    message: "A ruling-parallel cone-cylinder curve requires a globally finite linear height solution."
                )
            }
        }

        let reproducedBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        guard maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound >= reproducedBound,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A cone-cylinder curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let coneProjection = try coneSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(coneProjection.residual, cylinderProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A cone-cylinder curve failed its algebraic reconstruction check."
                )
            }
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        ).position
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let geometry = try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative,
            secondDerivative: geometry.secondDerivative
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        ).thirdDerivative
    }

    private func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> ThirdOrderDifferentialGeometry {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let normalizedFraction = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(at: normalizedFraction)
        let halfLinear = composedDifferential(
            configuration.halfLinearPolynomial,
            angle: angle
        )
        let height: ScalarDifferential
        if componentKind == .rulingParallelLinear {
            let baseQuadratic = composedDifferential(
                configuration.baseQuadraticPolynomial,
                angle: angle
            )
            height = try quotient(
                ScalarDifferential(
                    value: -baseQuadratic.value,
                    first: -baseQuadratic.first,
                    second: -baseQuadratic.second,
                    third: -baseQuadratic.third
                ),
                by: ScalarDifferential(
                    value: 2.0 * halfLinear.value,
                    first: 2.0 * halfLinear.first,
                    second: 2.0 * halfLinear.second,
                    third: 2.0 * halfLinear.third
                ),
                tolerance: tolerance
            )
        } else {
            let discriminant = composedDifferential(
                configuration.discriminantPolynomial,
                angle: angle
            )
            let root = try signedSquareRootDifferential(
                discriminant,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            let inverseQuadratic = 1.0 / configuration.generatorQuadratic
            height = ScalarDifferential(
                value: (-halfLinear.value + root.value) * inverseQuadratic,
                first: (-halfLinear.first + root.first) * inverseQuadratic,
                second: (-halfLinear.second + root.second) * inverseQuadratic,
                third: (-halfLinear.third + root.third) * inverseQuadratic
            )
        }
        let geometry = try configuration.cylinder.surface.differentialGeometry(
            atU: angle.value,
            v: height.value,
            tolerance: tolerance
        )
        let firstDerivative = geometry.tangentU * angle.first
            + geometry.tangentV * height.first
        let secondDerivative = geometry.secondDerivativeUU
                * (angle.first * angle.first)
            + geometry.secondDerivativeUV
                * (2.0 * angle.first * height.first)
            + geometry.secondDerivativeVV
                * (height.first * height.first)
            + geometry.tangentU * angle.second
            + geometry.tangentV * height.second
        let thirdSurface = try configuration.cylinder.surface
            .parameterDerivativesThroughThirdOrder(
                atU: angle.value,
                v: height.value,
                tolerance: tolerance
            )
        let thirdDerivative = thirdSurface.thirdDerivativeUUU
                * (angle.first * angle.first * angle.first)
            + thirdSurface.thirdDerivativeUUV
                * (3.0 * angle.first * angle.first * height.first)
            + thirdSurface.thirdDerivativeUVV
                * (3.0 * angle.first * height.first * height.first)
            + thirdSurface.thirdDerivativeVVV
                * (height.first * height.first * height.first)
            + thirdSurface.secondDerivativeUU
                * (3.0 * angle.first * angle.second)
            + thirdSurface.secondDerivativeUV
                * (3.0 * (angle.second * height.first
                    + angle.first * height.second))
            + thirdSurface.secondDerivativeVV
                * (3.0 * height.first * height.second)
            + thirdSurface.tangentU * angle.third
            + thirdSurface.tangentV * height.third
        let apexResidual = (geometry.position - configuration.cone.apex).length
        guard componentKind == .apexLowerNodeInterval
                || componentKind == .apexUpperNodeInterval
                || apexResidual > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "A certified cone-cylinder curve reaches the cone apex."
            )
        }
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-cylinder component has a singular differential."
            )
        }
        return ThirdOrderDifferentialGeometry(
            position: geometry.position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            thirdDerivative: thirdDerivative
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    func canonicalCylinderAngle(
        of point: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        return try configuration.cylinder.surface.parameterProjection(
            of: point,
            tolerance: tolerance
        ).u
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let maximumHeight: Double
        if componentKind == .rulingParallelLinear {
            let minimumHalfLinear = try Self.minimumAbsoluteValue(
                of: configuration.halfLinearPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let maximumBaseQuadratic = try Self.maximumAbsoluteValue(
                of: configuration.baseQuadraticPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            maximumHeight = maximumBaseQuadratic / (2.0 * minimumHalfLinear)
        } else {
            let maximumHalfLinear = try Self.maximumAbsoluteValue(
                of: configuration.halfLinearPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let maximumDiscriminant = max(
                try Self.extremum(
                    of: configuration.discriminantPolynomial,
                    maximum: true,
                    residualTolerance: classificationTolerance,
                    tolerance: tolerance
                ),
                0.0
            )
            maximumHeight = (maximumHalfLinear + sqrt(maximumDiscriminant))
                / abs(configuration.generatorQuadratic)
        }
        let radius = configuration.cylinder.radius
            + maximumHeight + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.cylinder.origin.x - radius,
                y: configuration.cylinder.origin.y - radius,
                z: configuration.cylinder.origin.z - radius
            ),
            maximum: Point3D(
                x: configuration.cylinder.origin.x + radius,
                y: configuration.cylinder.origin.y + radius,
                z: configuration.cylinder.origin.z + radius
            )
        )
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Root-free cone-cylinder differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let classificationEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let arithmeticEnvelope = try Self.upperProduct(
            classificationEnvelope,
            32.0,
            tolerance: tolerance
        )
        let minimumDiscriminant = (
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - arithmeticEnvelope
        ).nextDown
        guard minimumDiscriminant > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cylinder differential certificate lost its positive discriminant margin."
            )
        }
        let rootLower = sqrt(minimumDiscriminant).nextDown
        guard rootLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cylinder square-root lower bound collapsed."
            )
        }

        let discriminantFirst =
            configuration.discriminantPolynomial
                .firstDerivativeAbsoluteUpperBound
        let discriminantSecond =
            configuration.discriminantPolynomial
                .secondDerivativeAbsoluteUpperBound
        let discriminantThird =
            configuration.discriminantPolynomial
                .thirdDerivativeAbsoluteUpperBound
        let rootFirst = try Self.upperQuotient(
            discriminantFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootSquaredLower = (rootLower * rootLower).nextDown
        let rootCubedLower = (rootSquaredLower * rootLower).nextDown
        let rootSecond = try Self.upperSum(
            Self.upperQuotient(
                discriminantSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    discriminantFirst,
                    discriminantFirst,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootFifthLower = (
            rootCubedLower * rootSquaredLower
        ).nextDown
        let rootThird = try Self.upperSum(
            Self.upperQuotient(
                discriminantThird,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            discriminantFirst,
                            discriminantSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            discriminantFirst,
                            Self.upperProduct(
                                discriminantFirst,
                                discriminantFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )

        let denominatorEnvelope = Self.generatorQuadraticTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let denominatorLower = (
            abs(configuration.generatorQuadratic) - denominatorEnvelope
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cylinder generator denominator lost its positive margin."
            )
        }
        let heightFirst = try Self.upperQuotient(
            Self.upperSum(
                configuration.halfLinearPolynomial
                    .firstDerivativeAbsoluteUpperBound,
                rootFirst,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightSecond = try Self.upperQuotient(
            Self.upperSum(
                configuration.halfLinearPolynomial
                    .secondDerivativeAbsoluteUpperBound,
                rootSecond,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightThird = try Self.upperQuotient(
            Self.upperSum(
                configuration.halfLinearPolynomial
                    .thirdDerivativeAbsoluteUpperBound,
                rootThird,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )

        let angularFirst = hypot(
            configuration.cylinder.radius,
            heightFirst
        ).nextUp
        let angularSecond = hypot(
            configuration.cylinder.radius,
            heightSecond
        ).nextUp
        let angularThird = hypot(
            configuration.cylinder.radius,
            heightThird
        ).nextUp
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: try Self.upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            ),
            second: try Self.upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            ),
            third: try Self.upperProduct(
                periodCubed,
                angularThird,
                tolerance: tolerance
            )
        )
    }

    func rulingParallelSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .rulingParallelLinear else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Ruling-parallel cone-cylinder differential bounds require the certified linear generator branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let classificationEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let halfLinear = configuration.halfLinearPolynomial
        let denominatorLower = (
            2.0 * (try Self.minimumAbsoluteValue(
                of: halfLinear,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ))
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A ruling-parallel cone-cylinder height denominator lost its nonzero margin."
            )
        }
        let numerator = configuration.baseQuadraticPolynomial
        let numeratorMagnitude = (
            try Self.maximumAbsoluteValue(
                of: numerator,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            )
        ).nextUp
        let numeratorFirst = numerator
            .firstDerivativeAbsoluteUpperBound.nextUp
        let numeratorSecond = numerator
            .secondDerivativeAbsoluteUpperBound.nextUp
        let numeratorThird = numerator
            .thirdDerivativeAbsoluteUpperBound.nextUp
        let denominatorFirst = try Self.upperProduct(
            2.0,
            halfLinear.firstDerivativeAbsoluteUpperBound,
            tolerance: tolerance
        )
        let denominatorSecond = try Self.upperProduct(
            2.0,
            halfLinear.secondDerivativeAbsoluteUpperBound,
            tolerance: tolerance
        )
        let denominatorThird = try Self.upperProduct(
            2.0,
            halfLinear.thirdDerivativeAbsoluteUpperBound,
            tolerance: tolerance
        )
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let denominatorFourthLower = (
            denominatorCubedLower * denominatorLower
        ).nextDown
        let heightFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorMagnitude,
                    denominatorFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let heightSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorMagnitude,
                        denominatorSecond,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        Self.upperProduct(
                            2.0,
                            numeratorMagnitude,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            denominatorFirst,
                            denominatorFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let inverseFirst = try Self.upperQuotient(
            denominatorFirst,
            denominatorSquaredLower,
            tolerance: tolerance
        )
        let inverseSecond = try Self.upperSum(
            Self.upperQuotient(
                denominatorSecond,
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    2.0,
                    Self.upperProduct(
                        denominatorFirst,
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                denominatorCubedLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let inverseThird = try Self.upperSum(
            Self.upperQuotient(
                denominatorThird,
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        6.0,
                        Self.upperProduct(
                            denominatorFirst,
                            denominatorSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        6.0,
                        Self.upperProduct(
                            denominatorFirst,
                            Self.upperProduct(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorFourthLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let heightThird = try Self.upperSum(
            Self.upperQuotient(
                numeratorThird,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        numeratorSecond,
                        inverseFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            numeratorFirst,
                            inverseSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    Self.upperProduct(
                        numeratorMagnitude,
                        inverseThird,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return try Self.fullAngleCylinderSpatialBounds(
            radius: configuration.cylinder.radius,
            heightFirst: heightFirst,
            heightSecond: heightSecond,
            heightThird: heightThird,
            tolerance: tolerance
        )
    }

    func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .boundedAngularInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded cone-cylinder differential bounds require a valid complete simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let discriminant = configuration.discriminantPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 131_072.0
        ).nextUp
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        )
        let phaseLower = period * lower
        let phaseUpper = period * upper
        let angleRange = Self.boundedAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: angleRange.lower,
            requestedUpper: angleRange.upper,
            lowerValue: discriminant.value(at: lowerAngle),
            upperValue: discriminant.value(at: upperAngle),
            lowerDerivative: discriminant.firstDerivative(at: lowerAngle),
            upperDerivative: discriminant.firstDerivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                discriminant.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                discriminant.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                discriminant.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                discriminant.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                try Self.restrictedPolynomialRange(
                    discriminant,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope,
                    tolerance: tolerance
                )
            },
            tolerance: tolerance,
            label: "Cone-cylinder bounded branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded cone-cylinder regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try Self.upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try Self.upperSum(
            Self.upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = try Self.upperSum(
            Self.upperQuotient(
                factor.third,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    3.0 * factor.first * factor.second,
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    3.0 * factor.first * factor.first * factor.first,
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let sineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5
        )
        let cosineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0
        )
        let angleFirst = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                period,
                tolerance: tolerance
            ),
            sineMagnitude,
            tolerance: tolerance
        )
        let angleSecond = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                periodSquared,
                tolerance: tolerance
            ),
            cosineMagnitude,
            tolerance: tolerance
        )
        let angleThird = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                periodCubed,
                tolerance: tolerance
            ),
            sineMagnitude,
            tolerance: tolerance
        )
        let signedRootFirst = try Self.upperProduct(
            halfSpan,
            Self.upperSum(
                Self.upperProduct(
                    Self.upperProduct(
                        period,
                        cosineMagnitude,
                        tolerance: tolerance
                    ),
                    rootUpper,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    Self.upperProduct(
                        sineMagnitude,
                        rootFirstByAngle,
                        tolerance: tolerance
                    ),
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootSecond = try Self.upperProduct(
            halfSpan,
            Self.upperSum(
                Self.upperProduct(
                    Self.upperProduct(
                        periodSquared,
                        sineMagnitude,
                        tolerance: tolerance
                    ),
                    rootUpper,
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        Self.upperProduct(
                            Self.upperProduct(
                                2.0,
                                period,
                                tolerance: tolerance
                            ),
                            cosineMagnitude,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            rootFirstByAngle,
                            angleFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    Self.upperProduct(
                        sineMagnitude,
                        Self.upperSum(
                            Self.upperProduct(
                                rootSecondByAngle,
                                Self.upperProduct(
                                    angleFirst,
                                    angleFirst,
                                    tolerance: tolerance
                                ),
                                tolerance: tolerance
                            ),
                            Self.upperProduct(
                                rootFirstByAngle,
                                angleSecond,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootByFractionFirst = (
            rootFirstByAngle * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * angleFirst * angleFirst
                + rootFirstByAngle * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * angleFirst * angleFirst * angleFirst
                + 3.0 * rootSecondByAngle * angleFirst * angleSecond
                + rootFirstByAngle * angleThird
        ).nextUp
        let prefixMagnitude = (halfSpan * sineMagnitude).nextUp
        let prefixFirst = (
            halfSpan * period * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * periodSquared * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * periodCubed * cosineMagnitude
        ).nextUp
        let signedRootThird = (
            prefixThird * rootUpper
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixMagnitude * rootByFractionThird
        ).nextUp
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearFirst = try Self.upperProduct(
            halfLinear.firstDerivativeAbsoluteUpperBound,
            angleFirst,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.upperSum(
            Self.upperProduct(
                halfLinear.secondDerivativeAbsoluteUpperBound,
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                halfLinear.firstDerivativeAbsoluteUpperBound,
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfLinearThird = (
            halfLinear.thirdDerivativeAbsoluteUpperBound
                * angleFirst * angleFirst * angleFirst
                + 3.0 * halfLinear.secondDerivativeAbsoluteUpperBound
                    * angleFirst * angleSecond
                + halfLinear.firstDerivativeAbsoluteUpperBound
                    * angleThird
        ).nextUp
        let denominatorLower = (
            abs(configuration.generatorQuadratic)
                - Self.generatorQuadraticTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded cone-cylinder generator denominator lost its positive margin."
            )
        }
        let heightFirst = try Self.upperQuotient(
            Self.upperSum(
                halfLinearFirst,
                signedRootFirst,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightSecond = try Self.upperQuotient(
            Self.upperSum(
                halfLinearSecond,
                signedRootSecond,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightThird = try Self.upperQuotient(
            Self.upperSum(
                halfLinearThird,
                signedRootThird,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let radialFirst = try Self.upperProduct(
            configuration.cylinder.radius,
            angleFirst,
            tolerance: tolerance
        )
        let radialSecond = try Self.upperProduct(
            configuration.cylinder.radius,
            Self.upperSum(
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let radialThird = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: hypot(radialFirst, heightFirst).nextUp,
            second: hypot(radialSecond, heightSecond).nextUp,
            third: hypot(radialThird, heightThird).nextUp
        )
    }

    func apexNodeSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .apexLowerNodeInterval
                || componentKind == .apexUpperNodeInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Apex-node cone-cylinder differential bounds require a valid mixed double/simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let discriminant = configuration.discriminantPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 262_144.0
        ).nextUp
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let doubleRootAtLower = componentKind == .apexLowerNodeInterval
        let doubleRootAngle = doubleRootAtLower ? lowerAngle : upperAngle
        let simpleRootAngle = doubleRootAtLower ? upperAngle : lowerAngle
        let factor = try EndpointRegularizedFactorBounder()
            .mixedDoubleSimpleBounds(
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                requestedLower: lowerAngle,
                requestedUpper: upperAngle,
                doubleRootAtLower: doubleRootAtLower,
                doubleRootValue: discriminant.value(at: doubleRootAngle),
                doubleRootFirstDerivative:
                    discriminant.firstDerivative(at: doubleRootAngle),
                doubleRootSecondDerivative:
                    discriminant.secondDerivative(at: doubleRootAngle),
                simpleRootValue: discriminant.value(at: simpleRootAngle),
                simpleRootFirstDerivative:
                    discriminant.firstDerivative(at: simpleRootAngle),
                firstDerivativeMagnitudeUpperBound:
                    discriminant.firstDerivativeAbsoluteUpperBound,
                secondDerivativeMagnitudeUpperBound:
                    discriminant.secondDerivativeAbsoluteUpperBound,
                thirdDerivativeMagnitudeUpperBound:
                    discriminant.thirdDerivativeAbsoluteUpperBound,
                fourthDerivativeMagnitudeUpperBound:
                    discriminant.fourthDerivativeAbsoluteUpperBound,
                fifthDerivativeMagnitudeUpperBound:
                    discriminant.fifthDerivativeAbsoluteUpperBound,
                sixthDerivativeMagnitudeUpperBound:
                    discriminant.sixthDerivativeAbsoluteUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                valueRange: { rangeLower, rangeUpper in
                    try Self.restrictedPolynomialRange(
                        discriminant,
                        lower: rangeLower,
                        upper: rangeUpper,
                        arithmeticEnvelope: arithmeticEnvelope,
                        tolerance: tolerance
                    )
                },
                tolerance: tolerance,
                label: "Cone-cylinder apex-node branch"
            )
        let phaseLower = Double.pi * lower
        let phaseUpper = Double.pi * upper
        let sineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5
        )
        let cosineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0
        )
        let doubledSineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: 2.0 * phaseLower,
            upper: 2.0 * phaseUpper,
            phase: Double.pi * 0.5
        )
        let doubledCosineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: 2.0 * phaseLower,
            upper: 2.0 * phaseUpper,
            phase: 0.0
        )
        let span = (upperAngle - lowerAngle).nextUp
        let pi = Double.pi.nextUp
        let piSquared = try Self.upperProduct(
            pi,
            pi,
            tolerance: tolerance
        )
        let piCubed = try Self.upperProduct(
            piSquared,
            pi,
            tolerance: tolerance
        )
        let coordinateFirst = try Self.upperProduct(
            Self.upperProduct(
                span,
                pi,
                tolerance: tolerance
            ),
            cosineMagnitude,
            tolerance: tolerance
        )
        let coordinateSecond = try Self.upperProduct(
            Self.upperProduct(
                span,
                piSquared,
                tolerance: tolerance
            ),
            sineMagnitude,
            tolerance: tolerance
        )
        let coordinateThird = try Self.upperProduct(
            Self.upperProduct(
                span,
                piCubed,
                tolerance: tolerance
            ),
            cosineMagnitude,
            tolerance: tolerance
        )
        let factorFirst = try Self.upperProduct(
            factor.first,
            coordinateFirst,
            tolerance: tolerance
        )
        let factorSecond = try Self.upperSum(
            Self.upperProduct(
                factor.second,
                Self.upperProduct(
                    coordinateFirst,
                    coordinateFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                factor.first,
                coordinateSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let factorThird = (
            factor.third * coordinateFirst * coordinateFirst
                * coordinateFirst
                + 3.0 * factor.second * coordinateFirst
                    * coordinateSecond
                + factor.first * coordinateThird
        ).nextUp
        let inverseDenominatorFirst = try Self.upperProduct(
            pi,
            cosineMagnitude,
            tolerance: tolerance
        )
        let inverseDenominatorSecond = try Self.upperSum(
            Self.upperProduct(
                2.0,
                Self.upperProduct(
                    inverseDenominatorFirst,
                    inverseDenominatorFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                piSquared,
                sineMagnitude,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let inverseDenominatorThird = (
            13.0 * piCubed
        ).nextUp
        let normalizedLower = (factor.lower * 0.5).nextDown
        let normalizedUpper = factor.upper.nextUp
        let normalizedFirst = try Self.upperSum(
            factorFirst,
            Self.upperProduct(
                factor.upper,
                inverseDenominatorFirst,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let normalizedSecond = try Self.upperSum(
            factorSecond,
            Self.upperSum(
                Self.upperProduct(
                    2.0,
                    Self.upperProduct(
                        factorFirst,
                        inverseDenominatorFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    factor.upper,
                    inverseDenominatorSecond,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let normalizedThird = (
            factorThird
                + 3.0 * factorSecond * inverseDenominatorFirst
                + 3.0 * factorFirst * inverseDenominatorSecond
                + factor.upper * inverseDenominatorThird
        ).nextUp
        let normalizedRootLower = sqrt(normalizedLower).nextDown
        let normalizedRootUpper = sqrt(normalizedUpper).nextUp
        guard normalizedRootLower > 0.0,
              normalizedRootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-cylinder apex-node normalized factor lost its positive margin."
            )
        }
        let normalizedRootFirst = try Self.upperQuotient(
            normalizedFirst,
            (2.0 * normalizedRootLower).nextDown,
            tolerance: tolerance
        )
        let normalizedRootCubedLower = (
            normalizedLower * normalizedRootLower
        ).nextDown
        let normalizedRootSecond = try Self.upperSum(
            Self.upperQuotient(
                normalizedSecond,
                (2.0 * normalizedRootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    normalizedFirst,
                    normalizedFirst,
                    tolerance: tolerance
                ),
                (4.0 * normalizedRootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let normalizedRootFifthLower = (
            normalizedLower * normalizedLower * normalizedRootLower
        ).nextDown
        let normalizedRootThird = (
            normalizedThird / (2.0 * normalizedRootLower).nextDown
                + 3.0 * normalizedFirst * normalizedSecond
                    / (4.0 * normalizedRootCubedLower).nextDown
                + 3.0 * normalizedFirst * normalizedFirst
                    * normalizedFirst
                    / (8.0 * normalizedRootFifthLower).nextDown
        ).nextUp
        let spanScale = pow(span, 1.5).nextUp
        let distanceRootMagnitude = try Self.upperProduct(
            spanScale * 0.5,
            doubledSineMagnitude,
            tolerance: tolerance
        )
        let distanceRootFirst = try Self.upperProduct(
            Self.upperProduct(
                spanScale,
                pi,
                tolerance: tolerance
            ),
            doubledCosineMagnitude,
            tolerance: tolerance
        )
        let distanceRootSecond = try Self.upperProduct(
            Self.upperProduct(
                2.0 * spanScale,
                piSquared,
                tolerance: tolerance
            ),
            doubledSineMagnitude,
            tolerance: tolerance
        )
        let distanceRootThird = try Self.upperProduct(
            Self.upperProduct(
                4.0 * spanScale,
                piCubed,
                tolerance: tolerance
            ),
            doubledCosineMagnitude,
            tolerance: tolerance
        )
        let signedRootFirst = try Self.upperSum(
            Self.upperProduct(
                distanceRootFirst,
                normalizedRootUpper,
                tolerance: tolerance
            ),
            Self.upperProduct(
                distanceRootMagnitude,
                normalizedRootFirst,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootSecond = try Self.upperSum(
            Self.upperProduct(
                distanceRootSecond,
                normalizedRootUpper,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    2.0,
                    Self.upperProduct(
                        distanceRootFirst,
                        normalizedRootFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    distanceRootMagnitude,
                    normalizedRootSecond,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootThird = (
            distanceRootThird * normalizedRootUpper
                + 3.0 * distanceRootSecond * normalizedRootFirst
                + 3.0 * distanceRootFirst * normalizedRootSecond
                + distanceRootMagnitude * normalizedRootThird
        ).nextUp
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearFirst = try Self.upperProduct(
            halfLinear.firstDerivativeAbsoluteUpperBound,
            coordinateFirst,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.upperSum(
            Self.upperProduct(
                halfLinear.secondDerivativeAbsoluteUpperBound,
                Self.upperProduct(
                    coordinateFirst,
                    coordinateFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                halfLinear.firstDerivativeAbsoluteUpperBound,
                coordinateSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfLinearThird = (
            halfLinear.thirdDerivativeAbsoluteUpperBound
                * coordinateFirst * coordinateFirst * coordinateFirst
                + 3.0 * halfLinear.secondDerivativeAbsoluteUpperBound
                    * coordinateFirst * coordinateSecond
                + halfLinear.firstDerivativeAbsoluteUpperBound
                    * coordinateThird
        ).nextUp
        let denominatorLower = (
            abs(configuration.generatorQuadratic)
                - Self.generatorQuadraticTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-cylinder apex-node generator denominator lost its positive margin."
            )
        }
        let heightFirst = try Self.upperQuotient(
            Self.upperSum(
                halfLinearFirst,
                signedRootFirst,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightSecond = try Self.upperQuotient(
            Self.upperSum(
                halfLinearSecond,
                signedRootSecond,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let heightThird = try Self.upperQuotient(
            Self.upperSum(
                halfLinearThird,
                signedRootThird,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let radialFirst = try Self.upperProduct(
            configuration.cylinder.radius,
            coordinateFirst,
            tolerance: tolerance
        )
        let radialSecond = try Self.upperProduct(
            configuration.cylinder.radius,
            Self.upperSum(
                Self.upperProduct(
                    coordinateFirst,
                    coordinateFirst,
                    tolerance: tolerance
                ),
                coordinateSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let radialThird = (
            configuration.cylinder.radius * (
                coordinateFirst * coordinateFirst * coordinateFirst
                    + 3.0 * coordinateFirst * coordinateSecond
                    + coordinateThird
            )
        ).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: hypot(radialFirst, heightFirst).nextUp,
            second: hypot(radialSecond, heightSecond).nextUp,
            third: hypot(radialThird, heightThird).nextUp
        )
    }

    private static func fullAngleCylinderSpatialBounds(
        radius: Double,
        heightFirst: Double,
        heightSecond: Double,
        heightThird: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let angularFirst = hypot(radius, heightFirst).nextUp
        let angularSecond = hypot(radius, heightSecond).nextUp
        let angularThird = hypot(radius, heightThird).nextUp
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let periodCubed = try upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: try upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            ),
            second: try upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            ),
            third: try upperProduct(
                periodCubed,
                angularThird,
                tolerance: tolerance
            )
        )
    }

    private func angleDifferential(at fraction: Double) -> ScalarDifferential {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .rulingParallelLinear:
            return ScalarDifferential(
                value: period * fraction,
                first: period,
                second: 0.0,
                third: 0.0
            )
        case .boundedAngularInterval:
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            let phase = period * fraction
            return ScalarDifferential(
                value: midpoint - halfSpan * cos(phase),
                first: halfSpan * period * sin(phase),
                second: halfSpan * period * period * cos(phase),
                third: -halfSpan * period * period * period * sin(phase)
            )
        case .apexLowerNodeInterval, .apexUpperNodeInterval:
            let span = upperAngle - lowerAngle
            let phase = Double.pi * fraction
            let direction = componentKind == .apexLowerNodeInterval ? 1.0 : -1.0
            let apexAngle = componentKind == .apexLowerNodeInterval
                ? lowerAngle
                : upperAngle
            return ScalarDifferential(
                value: apexAngle + direction * span * sin(phase),
                first: direction * span * Double.pi * cos(phase),
                second: -direction * span * Double.pi * Double.pi * sin(phase),
                third: -direction * span * pow(Double.pi, 3.0) * cos(phase)
            )
        }
    }

    private func composedDifferential(
        _ polynomial: TrigonometricPolynomial,
        angle: ScalarDifferential
    ) -> ScalarDifferential {
        let angularFirst = polynomial.firstDerivative(at: angle.value)
        return ScalarDifferential(
            value: polynomial.value(at: angle.value),
            first: angularFirst * angle.first,
            second: polynomial.secondDerivative(at: angle.value)
                * angle.first * angle.first
                + angularFirst * angle.second,
            third: polynomial.thirdDerivative(at: angle.value)
                    * angle.first * angle.first * angle.first
                + 3.0 * polynomial.secondDerivative(at: angle.value)
                    * angle.first * angle.second
                + angularFirst * angle.third
        )
    }

    private func quotient(
        _ numerator: ScalarDifferential,
        by denominator: ScalarDifferential,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        guard abs(denominator.value) > tolerance.distance * 1.0e-6 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator.value),
                tolerance: tolerance,
                message: "A ruling-parallel cone-cylinder evaluator reached an unbounded generator."
            )
        }
        let inverse = 1.0 / denominator.value
        let value = numerator.value * inverse
        let first = numerator.first * inverse
            - numerator.value * denominator.first * inverse * inverse
        let second = numerator.second * inverse
            - numerator.value * denominator.second * inverse * inverse
            - 2.0 * numerator.first * denominator.first * inverse * inverse
            + 2.0 * numerator.value * denominator.first * denominator.first
                * inverse * inverse * inverse
        let inverseThird = -6.0
                * denominator.first * denominator.first * denominator.first
                * pow(inverse, 4.0)
            + 6.0 * denominator.first * denominator.second
                * inverse * inverse * inverse
            - denominator.third * inverse * inverse
        let third = numerator.third * inverse
            + 3.0 * numerator.second
                * (-denominator.first * inverse * inverse)
            + 3.0 * numerator.first * (
                2.0 * denominator.first * denominator.first
                    * inverse * inverse * inverse
                    - denominator.second * inverse * inverse
            )
            + numerator.value * inverseThird
        return ScalarDifferential(
            value: value,
            first: first,
            second: second,
            third: third
        )
    }

    private func signedSquareRootDifferential(
        _ discriminant: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let branchSign: Double
        switch componentKind {
        case .negativeFullBranch:
            branchSign = -1.0
        case .positiveFullBranch:
            branchSign = 1.0
        case .boundedAngularInterval:
            branchSign = sin(2.0 * Double.pi * fraction) < 0.0 ? -1.0 : 1.0
        case .apexLowerNodeInterval, .apexUpperNodeInterval:
            branchSign = cos(Double.pi * fraction) < 0.0 ? -1.0 : 1.0
        case .rulingParallelLinear:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A ruling-parallel cone-cylinder curve does not use a square-root branch."
            )
        }
        if componentKind == .apexLowerNodeInterval
            || componentKind == .apexUpperNodeInterval {
            return try apexNodeRegularizedSquareRootDifferential(
                fraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            )
        }
        if componentKind == .boundedAngularInterval {
            let angle = angleDifferential(at: fraction)
            let factor = try regularizedDiscriminantFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            )
            guard factor.value > 0.0, factor.value.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "A bounded cone-cylinder component lost its positive regularized discriminant factor."
                )
            }
            let root = sqrt(factor.value)
            let rootByAngle = ScalarDifferential(
                value: root,
                first: factor.first / (2.0 * root),
                second: factor.second / (2.0 * root)
                    - factor.first * factor.first
                        / (4.0 * root * root * root),
                third: factor.third / (2.0 * root)
                    - 3.0 * factor.first * factor.second
                        / (4.0 * pow(root, 3.0))
                    + 3.0 * pow(factor.first, 3.0)
                        / (8.0 * pow(root, 5.0))
            )
            let rootByFraction = ScalarDifferential(
                value: rootByAngle.value,
                first: rootByAngle.first * angle.first,
                second: rootByAngle.second * angle.first * angle.first
                    + rootByAngle.first * angle.second,
                third: rootByAngle.third * pow(angle.first, 3.0)
                    + 3.0 * rootByAngle.second
                        * angle.first * angle.second
                    + rootByAngle.first * angle.third
            )
            let period = 2.0 * Double.pi
            let phase = period * fraction
            let sine = ScalarDifferential(
                value: sin(phase),
                first: period * cos(phase),
                second: -period * period * sin(phase),
                third: -period * period * period * cos(phase)
            )
            let result = Self.product(sine, rootByFraction).scaled(
                by: (upperAngle - lowerAngle) * 0.5
            )
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded cone-cylinder regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        guard discriminant.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -discriminant.value,
                tolerance: tolerance,
                message: "A cone-cylinder evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(discriminant.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A cone-cylinder square-root differential is singular."
            )
        }
        let signedValue = branchSign * magnitude
        let first = discriminant.first / (2.0 * signedValue)
        let second = discriminant.second / (2.0 * signedValue)
            - discriminant.first * discriminant.first
                / (4.0 * signedValue * signedValue * signedValue)
        return ScalarDifferential(
            value: signedValue,
            first: first,
            second: second,
            third: (discriminant.third - 6.0 * first * second)
                / (2.0 * signedValue)
        )
    }

    private func apexNodeRegularizedSquareRootDifferential(
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let angle = angleDifferential(at: fraction)
        let direction = componentKind == .apexLowerNodeInterval ? 1.0 : -1.0
        let apexAngle = componentKind == .apexLowerNodeInterval
            ? lowerAngle
            : upperAngle
        let coordinate = ScalarDifferential(
            value: direction * (angle.value - apexAngle),
            first: direction * angle.first,
            second: direction * angle.second,
            third: direction * angle.third
        )
        let factorByCoordinate = try mixedRegularizedDiscriminantFactorDifferential(
            coordinate: coordinate.value,
            direction: direction,
            apexAngle: apexAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        let factor = ScalarDifferential(
            value: factorByCoordinate.value,
            first: factorByCoordinate.first * coordinate.first,
            second: factorByCoordinate.second
                    * coordinate.first * coordinate.first
                + factorByCoordinate.first * coordinate.second,
            third: factorByCoordinate.third * pow(coordinate.first, 3.0)
                + 3.0 * factorByCoordinate.second
                    * coordinate.first * coordinate.second
                + factorByCoordinate.first * coordinate.third
        )
        let phase = Double.pi * fraction
        let sine = ScalarDifferential(
            value: sin(phase),
            first: Double.pi * cos(phase),
            second: -Double.pi * Double.pi * sin(phase),
            third: -pow(Double.pi, 3.0) * cos(phase)
        )
        let normalizedFactor = try Self.differentialQuotient(
            factor,
            ScalarDifferential.constant(1.0).adding(sine),
            tolerance: tolerance,
            message: "A cone-cylinder apex-node normalization lost its positive denominator."
        )
        guard normalizedFactor.value > 0.0,
              normalizedFactor.value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: normalizedFactor.value,
                tolerance: tolerance,
                message: "A cone-cylinder apex-node component lost its positive mixed-root factor."
            )
        }
        let root = sqrt(normalizedFactor.value)
        let rootDifferential = ScalarDifferential(
            value: root,
            first: normalizedFactor.first / (2.0 * root),
            second: normalizedFactor.second / (2.0 * root)
                - normalizedFactor.first * normalizedFactor.first
                    / (4.0 * root * root * root),
            third: normalizedFactor.third / (2.0 * root)
                - 3.0 * normalizedFactor.first * normalizedFactor.second
                    / (4.0 * pow(root, 3.0))
                + 3.0 * pow(normalizedFactor.first, 3.0)
                    / (8.0 * pow(root, 5.0))
        )
        let spanScale = pow(upperAngle - lowerAngle, 1.5)
        let distanceRoot = ScalarDifferential(
            value: spanScale * sin(phase) * cos(phase),
            first: spanScale * Double.pi * cos(2.0 * phase),
            second: -2.0 * spanScale * Double.pi * Double.pi
                * sin(2.0 * phase),
            third: -4.0 * spanScale * pow(Double.pi, 3.0)
                * cos(2.0 * phase)
        )
        let result = Self.product(distanceRoot, rootDifferential)
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite,
              result.third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-cylinder apex-node regularized square-root differential exceeded finite arithmetic."
            )
        }
        return result
    }

    private func mixedRegularizedDiscriminantFactorDifferential(
        coordinate: Double,
        direction: Double,
        apexAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let span = upperAngle - lowerAngle
        let simpleAngle = componentKind == .apexLowerNodeInterval
            ? upperAngle
            : lowerAngle
        guard coordinate >= -tolerance.angle,
              coordinate <= span + tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: min(coordinate, span - coordinate),
                tolerance: tolerance,
                message: "A cone-cylinder mixed-root factor was evaluated outside its certified component."
            )
        }
        let boundedCoordinate = min(max(coordinate, 0.0), span)
        let polynomial = configuration.discriminantPolynomial
        let apexValue = polynomial.value(at: apexAngle)
        let apexFirst = direction
            * polynomial.firstDerivative(at: apexAngle)
        let simpleValue = polynomial.value(at: simpleAngle)
        let correctionQuadratic = (
            simpleValue - apexValue - apexFirst * span
        ) / (span * span)
        if boundedCoordinate <= span - boundedCoordinate {
            let secondDifference = Self.orientedSecondDividedDifference(
                polynomial,
                coordinate: boundedCoordinate,
                apexAngle: apexAngle,
                direction: direction
            )
            return try Self.differentialQuotient(
                secondDifference.subtracting(
                    .constant(correctionQuadratic)
                ),
                ScalarDifferential(
                    value: span - boundedCoordinate,
                    first: -1.0,
                    second: 0.0,
                    third: 0.0
                ),
                tolerance: tolerance,
                message: "A cone-cylinder mixed-root factor lost its simple-endpoint distance."
            )
        }
        let dividedDifference = Self.trigonometricDividedDifference(
            polynomial,
            value: apexAngle + direction * boundedCoordinate,
            endpoint: simpleAngle
        )
        let orientedDifference = ScalarDifferential(
            value: direction * dividedDifference.value,
            first: dividedDifference.first,
            second: direction * dividedDifference.second,
            third: dividedDifference.third
        )
        let numerator = ScalarDifferential(
            value: apexFirst
                + correctionQuadratic * (boundedCoordinate + span),
            first: correctionQuadratic,
            second: 0.0,
            third: 0.0
        ).subtracting(orientedDifference)
        return try Self.differentialQuotient(
            numerator,
            ScalarDifferential(
                value: boundedCoordinate * boundedCoordinate,
                first: 2.0 * boundedCoordinate,
                second: 2.0,
                third: 0.0
            ),
            tolerance: tolerance,
            message: "A cone-cylinder mixed-root factor lost its double-endpoint distance."
        )
    }

    private static func orientedSecondDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        coordinate: Double,
        apexAngle: Double,
        direction: Double
    ) -> ScalarDifferential {
        if abs(coordinate) <= 0.25 {
            var value = 0.0
            var first = 0.0
            var second = 0.0
            var third = 0.0
            var factorial = 1.0
            for order in 1...24 {
                factorial *= Double(order)
                guard order >= 2 else { continue }
                let orientedDerivative = polynomial.derivative(
                    order: order,
                    at: apexAngle
                ) * (order.isMultiple(of: 2) ? 1.0 : direction)
                let coefficient = orientedDerivative / factorial
                let exponent = order - 2
                value += coefficient * pow(
                    coordinate,
                    Double(exponent)
                )
                if exponent > 0 {
                    first += coefficient * Double(exponent)
                        * pow(coordinate, Double(exponent - 1))
                }
                if exponent > 1 {
                    second += coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(coordinate, Double(exponent - 2))
                }
                if exponent > 2 {
                    third += coefficient
                        * Double(exponent * (exponent - 1) * (exponent - 2))
                        * pow(coordinate, Double(exponent - 3))
                }
            }
            return ScalarDifferential(
                value: value,
                first: first,
                second: second,
                third: third
            )
        }
        let angle = apexAngle + direction * coordinate
        let apexValue = polynomial.value(at: apexAngle)
        let apexFirst = direction
            * polynomial.firstDerivative(at: apexAngle)
        let numerator = polynomial.value(at: angle)
            - apexValue - apexFirst * coordinate
        let numeratorFirst = direction
                * polynomial.firstDerivative(at: angle)
            - apexFirst
        let numeratorSecond = polynomial.secondDerivative(at: angle)
        let numeratorThird = direction
            * polynomial.thirdDerivative(at: angle)
        let squared = coordinate * coordinate
        let cubed = squared * coordinate
        let fourth = squared * squared
        return ScalarDifferential(
            value: numerator / squared,
            first: numeratorFirst / squared
                - 2.0 * numerator / cubed,
            second: numeratorSecond / squared
                - 4.0 * numeratorFirst / cubed
                + 6.0 * numerator / fourth,
            third: numeratorThird / squared
                - 6.0 * numeratorSecond / cubed
                + 18.0 * numeratorFirst / fourth
                - 24.0 * numerator / (fourth * coordinate)
        )
    }

    private func regularizedDiscriminantFactorDifferential(
        at angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let span = upperAngle - lowerAngle
        let lowerDistance = angle - lowerAngle
        let upperDistance = upperAngle - angle
        guard span > tolerance.angle,
              lowerDistance >= -tolerance.angle,
              upperDistance >= -tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: min(lowerDistance, upperDistance),
                tolerance: tolerance,
                message: "A bounded cone-cylinder regularized factor was evaluated outside its certified angular component."
            )
        }
        let discriminant = configuration.discriminantPolynomial
        let lowerValue = discriminant.value(at: lowerAngle)
        let upperValue = discriminant.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = Self.trigonometricDividedDifference(
            discriminant,
            value: angle,
            endpoint: endpoint
        )
        let numerator = usesLowerEndpoint
            ? dividedDifference.adding(.constant(-correctionSlope))
            : ScalarDifferential.constant(correctionSlope)
                .subtracting(dividedDifference)
        let denominator = usesLowerEndpoint
            ? ScalarDifferential(
                value: upperAngle - angle,
                first: -1.0,
                second: 0.0,
                third: 0.0
            )
            : ScalarDifferential(
                value: angle - lowerAngle,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
        return try Self.differentialQuotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded cone-cylinder regularized factor lost its opposite-endpoint denominator."
        )
    }

    private static func trigonometricDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ) -> ScalarDifferential {
        var result = ScalarDifferential.constant(0.0)
        for harmonic in [
            (
                order: 1.0,
                cosine: polynomial.cosine,
                sine: polynomial.sine
            ),
            (
                order: 2.0,
                cosine: polynomial.cosineDouble,
                sine: polynomial.sineDouble
            ),
        ] {
            let halfOrder = harmonic.order * 0.5
            let difference = value - endpoint
            let midpoint = (value + endpoint) * halfOrder
            let sinc = sincDifferential(
                at: difference * halfOrder,
                derivativeScale: halfOrder
            )
            let amplitude = ScalarDifferential(
                value: -harmonic.cosine * sin(midpoint)
                    + harmonic.sine * cos(midpoint),
                first: halfOrder * (
                    -harmonic.cosine * cos(midpoint)
                        - harmonic.sine * sin(midpoint)
                ),
                second: -halfOrder * halfOrder * (
                    -harmonic.cosine * sin(midpoint)
                        + harmonic.sine * cos(midpoint)
                ),
                third: pow(halfOrder, 3.0) * (
                    harmonic.cosine * cos(midpoint)
                        + harmonic.sine * sin(midpoint)
                )
            )
            result = result.adding(
                product(sinc, amplitude).scaled(by: harmonic.order)
            )
        }
        return result
    }

    private static func sincDifferential(
        at value: Double,
        derivativeScale: Double
    ) -> ScalarDifferential {
        let valueResult: Double
        let firstByValue: Double
        let secondByValue: Double
        let thirdByValue: Double
        if abs(value) <= 0.25 {
            var accumulatedValue = 0.0
            var accumulatedFirst = 0.0
            var accumulatedSecond = 0.0
            var accumulatedThird = 0.0
            var coefficient = 1.0
            for index in 0...12 {
                let exponent = index * 2
                accumulatedValue += coefficient
                    * pow(value, Double(exponent))
                if exponent > 0 {
                    accumulatedFirst += coefficient * Double(exponent)
                        * pow(value, Double(exponent - 1))
                }
                if exponent > 1 {
                    accumulatedSecond += coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(value, Double(exponent - 2))
                }
                if exponent > 2 {
                    accumulatedThird += coefficient
                        * Double(exponent * (exponent - 1) * (exponent - 2))
                        * pow(value, Double(exponent - 3))
                }
                coefficient /= -Double(
                    (2 * index + 2) * (2 * index + 3)
                )
            }
            valueResult = accumulatedValue
            firstByValue = accumulatedFirst
            secondByValue = accumulatedSecond
            thirdByValue = accumulatedThird
        } else {
            let sine = sin(value)
            let cosine = cos(value)
            let squared = value * value
            valueResult = sine / value
            firstByValue = (value * cosine - sine) / squared
            secondByValue = -sine / value
                - 2.0 * cosine / squared
                + 2.0 * sine / (squared * value)
            thirdByValue = -cosine / value
                + 3.0 * sine / squared
                + 6.0 * cosine / (squared * value)
                - 6.0 * sine / (squared * squared)
        }
        return ScalarDifferential(
            value: valueResult,
            first: firstByValue * derivativeScale,
            second: secondByValue * derivativeScale * derivativeScale,
            third: thirdByValue * pow(derivativeScale, 3.0)
        )
    }

    private static func product(
        _ first: ScalarDifferential,
        _ second: ScalarDifferential
    ) -> ScalarDifferential {
        ScalarDifferential(
            value: first.value * second.value,
            first: first.first * second.value
                + first.value * second.first,
            second: first.second * second.value
                + 2.0 * first.first * second.first
                + first.value * second.second,
            third: first.third * second.value
                + 3.0 * first.second * second.first
                + 3.0 * first.first * second.second
                + first.value * second.third
        )
    }

    private static func differentialQuotient(
        _ numerator: ScalarDifferential,
        _ denominator: ScalarDifferential,
        tolerance: ModelingTolerance,
        message: String
    ) throws -> ScalarDifferential {
        guard abs(denominator.value) > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator.value),
                tolerance: tolerance,
                message: message
            )
        }
        let inverse = 1.0 / denominator.value
        let inverseFirst = -denominator.first * inverse * inverse
        let inverseSecond = 2.0 * denominator.first * denominator.first
                * inverse * inverse * inverse
            - denominator.second * inverse * inverse
        let inverseThird = -6.0
                * denominator.first * denominator.first * denominator.first
                * pow(inverse, 4.0)
            + 6.0 * denominator.first * denominator.second
                * pow(inverse, 3.0)
            - denominator.third * inverse * inverse
        return product(
            numerator,
            ScalarDifferential(
                value: inverse,
                first: inverseFirst,
                second: inverseSecond,
                third: inverseThird
            )
        )
    }

    private static func endpointFractionTolerance(
        tolerance: ModelingTolerance
    ) -> Double {
        max(tolerance.relative, 2.0 * sqrt(Double.ulpOfOne))
    }

    private static func makeConfiguration(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try coneSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
        guard case let .cone(coneCanonical) = CanonicalAnalyticSurface(coneSurface),
              case let .cylinder(cylinderCanonical) = CanonicalAnalyticSurface(
                cylinderSurface
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cone-cylinder curve requires exact cone and cylinder surfaces."
            )
        }
        let cone = try canonicalCone(coneCanonical, tolerance: tolerance)
        let cylinder = try canonicalCylinder(
            cylinderCanonical,
            tolerance: tolerance
        )
        let coneMetricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)
        let generatorQuadratic = 1.0
            - coneMetricScale * pow(cylinder.axis.dot(cone.axis), 2.0)
        let zeroPoint = try cylinder.surface.point(
            u: 0.0,
            v: 0.0,
            tolerance: tolerance
        )
        let quarterPoint = try cylinder.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let radialU = zeroPoint - cylinder.origin
        let radialV = quarterPoint - cylinder.origin
        let baseOffset = cylinder.origin - cone.apex

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }

        func offset(at angle: Double) -> Vector3D {
            baseOffset
                + radialU * cos(angle)
                + radialV * sin(angle)
        }

        let halfLinear = trigonometricPolynomial { angle in
            metric(offset(at: angle), cylinder.axis)
        }
        let baseQuadratic = trigonometricPolynomial { angle in
            let value = offset(at: angle)
            return metric(value, value)
        }
        let discriminant = trigonometricPolynomial { angle in
            let value = offset(at: angle)
            let linear = metric(value, cylinder.axis)
            return linear * linear - generatorQuadratic * metric(value, value)
        }
        return Configuration(
            cone: cone,
            cylinder: cylinder,
            cylinderRadialU: radialU,
            cylinderRadialV: radialV,
            coneMetricScale: coneMetricScale,
            generatorQuadratic: generatorQuadratic,
            halfLinearPolynomial: halfLinear,
            baseQuadraticPolynomial: baseQuadratic,
            discriminantPolynomial: discriminant
        )
    }

    private static func canonicalCone(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ) throws -> Cone {
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        return Cone(apex: cone.apex, axis: axis, halfAngle: cone.halfAngle)
    }

    private static func canonicalCylinder(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Cylinder {
        var axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        let originVector = cylinder.origin - .origin
        let origin = cylinder.origin + axis * -originVector.dot(axis)
        return Cylinder(origin: origin, axis: axis, radius: cylinder.radius)
    }

    private static func trigonometricPolynomial(
        valueAt: (Double) -> Double
    ) -> TrigonometricPolynomial {
        let zero = valueAt(0.0)
        let half = valueAt(Double.pi)
        let quarter = valueAt(Double.pi * 0.5)
        let threeQuarter = valueAt(Double.pi * 1.5)
        let diagonal = valueAt(Double.pi * 0.25)
        let constantPlusDouble = (zero + half) * 0.5
        let constantMinusDouble = (quarter + threeQuarter) * 0.5
        let constant = (constantPlusDouble + constantMinusDouble) * 0.5
        let cosineDouble = (constantPlusDouble - constantMinusDouble) * 0.5
        let cosine = (zero - half) * 0.5
        let sine = (quarter - threeQuarter) * 0.5
        let sineDouble = diagonal
            - constant
            - (cosine + sine) / sqrt(2.0)
        return TrigonometricPolynomial(
            constant: constant,
            cosine: cosine,
            sine: sine,
            cosineDouble: cosineDouble,
            sineDouble: sineDouble
        )
    }

    private static func roots(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let normalizedResidual = max(
            Double.ulpOfOne * 1_024.0,
            residualTolerance / polynomial.coefficientScale
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 0.25, Double.ulpOfOne * 1_024.0),
            residualTolerance: normalizedResidual,
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        var values = try solver.realRoots(
            coefficients: polynomial.tangentHalfAngleCoefficients
        ).map { normalizedAngle(2.0 * atan($0)) }
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            values.append(Double.pi)
        }
        values = values.map { value in
            refinedAngle(
                value,
                polynomial: polynomial,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )
        }.filter { value in
            abs(polynomial.value(at: value)) <= residualTolerance * 16.0
        }.sorted()
        var result: [Double] = []
        for value in values where
            result.last.map({ angularDistance($0, value) <= tolerance.angle }) != true {
            result.append(value)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           angularDistance(first, last) <= tolerance.angle {
            result.removeLast()
        }
        return result
    }

    private static func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let values = ([0.0] + (try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        ))).map(polynomial.value)
        return maximum
            ? values.max() ?? polynomial.value(at: 0.0)
            : values.min() ?? polynomial.value(at: 0.0)
    }

    private static func maximumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        max(
            abs(try extremum(
                of: polynomial,
                maximum: false,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )),
            abs(try extremum(
                of: polynomial,
                maximum: true,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            ))
        )
    }

    private static func validIntervals(
        boundaries: [Double],
        polynomial: TrigonometricPolynomial,
        classificationTolerance: Double
    ) -> [(lower: Double, upper: Double)] {
        guard boundaries.isEmpty == false else { return [] }
        return boundaries.indices.compactMap { index in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return polynomial.value(at: lower + (upper - lower) * 0.5)
                > classificationTolerance
                ? (lower, upper)
                : nil
        }
    }

    private static func boundedAngleRange(
        phaseLower: Double,
        phaseUpper: Double,
        lowerAngle: Double,
        upperAngle: Double
    ) -> (lower: Double, upper: Double) {
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        var values = [
            midpoint - halfSpan * cos(phaseLower),
            midpoint - halfSpan * cos(phaseUpper),
        ]
        for index in 0...2 {
            let phase = Double(index) * Double.pi
            if phase > phaseLower, phase < phaseUpper {
                values.append(midpoint - halfSpan * cos(phase))
            }
        }
        return (
            (values.min() ?? lowerAngle).nextDown,
            (values.max() ?? upperAngle).nextUp
        )
    }

    private static func maximumAbsoluteTrigonometricValue(
        lower: Double,
        upper: Double,
        phase: Double
    ) -> Double {
        var result = max(
            abs(cos(lower - phase)),
            abs(cos(upper - phase))
        )
        for index in -2...4 {
            let extremum = phase + Double(index) * Double.pi
            if extremum > lower, extremum < upper {
                result = 1.0
            }
        }
        return result.nextUp
    }

    private static func restrictedPolynomialRange(
        _ polynomial: TrigonometricPolynomial,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        let residualTolerance = max(
            arithmeticEnvelope,
            Double.ulpOfOne * polynomial.coefficientScale * 4_096.0
        )
        var values = [
            polynomial.value(at: lower),
            polynomial.value(at: upper),
        ]
        let period = 2.0 * Double.pi
        for root in try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        ) {
            for winding in -1...2 {
                let angle = root + Double(winding) * period
                if angle > lower, angle < upper {
                    values.append(polynomial.value(at: angle))
                }
            }
        }
        return (
            ((values.min() ?? 0.0) - arithmeticEnvelope).nextDown,
            ((values.max() ?? 0.0) + arithmeticEnvelope).nextUp
        )
    }

    private static func minimumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let minimum = try extremum(
            of: polynomial,
            maximum: false,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        let maximum = try extremum(
            of: polynomial,
            maximum: true,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        guard minimum > 0.0 || maximum < 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: min(abs(minimum), abs(maximum)),
                tolerance: tolerance,
                message: "A ruling-parallel cone-cylinder solution becomes unbounded."
            )
        }
        return min(abs(minimum), abs(maximum))
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        if componentKind == .rulingParallelLinear {
            let minimumHalfLinear = try minimumAbsoluteValue(
                of: configuration.halfLinearPolynomial,
                residualTolerance: max(
                    Double.ulpOfOne * configuration.characteristicLength * 4_096.0,
                    tolerance.distance * 1.0e-6
                ),
                tolerance: tolerance
            )
            let result = Double.ulpOfOne
                * configuration.characteristicLength * 262_144.0
                / max(minimumHalfLinear, Double.leastNonzeroMagnitude)
            guard result <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result,
                    tolerance: tolerance,
                    message: "Ruling-parallel cone-cylinder reconstruction exceeds the requested tolerance."
                )
            }
            return result
        }
        let denominator = abs(configuration.generatorQuadratic)
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0 / denominator
        let algebraicBound: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            algebraicBound = 0.0
        case .boundedAngularInterval, .apexLowerNodeInterval,
             .apexUpperNodeInterval:
            let rootResidual = max(
                abs(configuration.discriminantPolynomial.value(at: lowerAngle)),
                abs(configuration.discriminantPolynomial.value(at: upperAngle))
            )
            algebraicBound = sqrt(rootResidual) / denominator
        case .rulingParallelLinear:
            algebraicBound = 0.0
        }
        let result = machineBound + algebraicBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Cone-cylinder algebraic reconstruction exceeds the requested tolerance."
            )
        }
        return result
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = configuration.characteristicLength
        let algebraicScale = max(
            configuration.discriminantPolynomial.coefficientScale,
            scale * scale
        )
        return max(
            Double.ulpOfOne * algebraicScale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private static func generatorQuadraticTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * max(configuration.coneMetricScale, 1.0) * 512.0
        )
    }

    private static func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite, second.isFinite,
              first >= 0.0, second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification received an invalid product operand."
            )
        }
        let value = (first * second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification exceeded finite multiplication."
            )
        }
        return value
    }

    private static func upperQuotient(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard numerator.isFinite, denominator.isFinite,
              numerator >= 0.0, denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification received an invalid quotient operand."
            )
        }
        let value = (numerator / denominator).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification exceeded finite division."
            )
        }
        return value
    }

    private static func upperSum(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite, second.isFinite,
              first >= 0.0, second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification received an invalid sum operand."
            )
        }
        let value = (first + second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cylinder differential certification exceeded finite addition."
            )
        }
        return value
    }

    private static func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private static func refinedAngle(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<64 {
            let value = polynomial.value(at: angle)
            if abs(value) <= proofResidualTolerance { break }
            let derivative = polynomial.firstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle * polynomial.coefficientScale else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
    }

    private static func rejectApexContact(
        cone: Cone,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws {
        let offset = cone.apex - cylinder.origin
        let axialDistance = offset.dot(cylinder.axis)
        let radialDistance = (offset - cylinder.axis * axialDistance).length
        let residual = abs(radialDistance - cylinder.radius)
        if residual <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: residual,
                tolerance: tolerance,
                message: "Cone-cylinder intersection passes through the cone's singular apex parameter."
            )
        }
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        let period = 2.0 * Double.pi
        let difference = abs(first - second).truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case coneSurface
        case cylinderSurface
        case componentKind
        case lowerAngle
        case upperAngle
        case certificationTolerance
        case maximumResidualUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .coneSurface,
                .cylinderSurface,
                .componentKind,
                .lowerAngle,
                .upperAngle,
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
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
            cylinderSurface: container.decode(
                Surface3D.self,
                forKey: .cylinderSurface
            ),
            componentKind: container.decode(
                ComponentKind.self,
                forKey: .componentKind
            ),
            lowerAngle: container.decode(Double.self, forKey: .lowerAngle),
            upperAngle: container.decode(Double.self, forKey: .upperAngle),
            tolerance: tolerance
        )
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumResidualUpperBound,
                in: container,
                debugDescription: "The cone-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
