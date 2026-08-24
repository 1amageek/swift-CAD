import CADCore
import Foundation

public struct CertifiedParallelTorusCylinderIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case negativeInternalTangencyInterval
        case positiveInternalTangencyInterval
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
        let radialU: Vector3D
        let radialV: Vector3D
    }

    private struct Configuration {
        let torus: Torus
        let cylinder: Cylinder
        let radialSquaredCenter: Double
        let radialSquaredCosine: Double
        let radialSquaredSine: Double

        var characteristicLength: Double {
            max(
                torus.majorRadius + torus.minorRadius,
                cylinder.radius,
                (cylinder.origin - torus.center).length,
                1.0
            )
        }

        var harmonicAmplitude: Double {
            hypot(radialSquaredCosine, radialSquaredSine)
        }

        func radialSquared(at angle: Double) -> Double {
            radialSquaredCenter
                + radialSquaredCosine * cos(angle)
                + radialSquaredSine * sin(angle)
        }

        func radialSquaredFirstDerivative(at angle: Double) -> Double {
            -radialSquaredCosine * sin(angle)
                + radialSquaredSine * cos(angle)
        }

        func radialSquaredSecondDerivative(at angle: Double) -> Double {
            -radialSquaredCosine * cos(angle)
                - radialSquaredSine * sin(angle)
        }

        func radicand(at angle: Double) -> Double {
            let radialDistance = sqrt(max(radialSquared(at: angle), 0.0))
            let tubeRadialDistance = radialDistance - torus.majorRadius
            return torus.minorRadius * torus.minorRadius
                - tubeRadialDistance * tubeRadialDistance
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            let squared = radialSquared(at: angle)
            guard squared > Double.leastNonzeroMagnitude else { return .infinity }
            let radial = sqrt(squared)
            let radialFirst = radialSquaredFirstDerivative(at: angle) / (2.0 * radial)
            return -2.0 * (radial - torus.majorRadius) * radialFirst
        }

        func radicandSecondDerivative(at angle: Double) -> Double {
            let squared = radialSquared(at: angle)
            guard squared > Double.leastNonzeroMagnitude else { return .infinity }
            let radial = sqrt(squared)
            let squaredFirst = radialSquaredFirstDerivative(at: angle)
            let radialFirst = squaredFirst / (2.0 * radial)
            let radialSecond = radialSquaredSecondDerivative(at: angle) / (2.0 * radial)
                - squaredFirst * squaredFirst / (4.0 * radial * radial * radial)
            return -2.0 * (
                radialFirst * radialFirst
                    + (radial - torus.majorRadius) * radialSecond
            )
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    public let torusSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.torusSurface = torusSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
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
                message: "A parallel torus-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
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
        let boundaries = Self.boundaryAngles(
            configuration: configuration,
            tolerance: tolerance
        )
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let minimumRadicand = Self.minimumRadicand(configuration: configuration)
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  minimumRadicand > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumRadicand,
                    tolerance: tolerance,
                    message: "A full parallel torus-cylinder branch requires a positive root-free radicand domain."
                )
            }
        case .boundedAngularInterval:
            let intervals = Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance
            )
            let matchesCompleteInterval = intervals.contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerSlope = abs(configuration.radicandFirstDerivative(at: lowerAngle))
            let upperSlope = abs(configuration.radicandFirstDerivative(at: upperAngle))
            guard matchesCompleteInterval,
                  lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  lowerSlope > classificationTolerance,
                  upperSlope > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded parallel torus-cylinder component is not a complete simple-root interval."
                )
            }
        case .negativeInternalTangencyInterval,
             .positiveInternalTangencyInterval:
            let intervals = Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance
            )
            let matchesCompleteInterval = intervals.contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerSlope = abs(configuration.radicandFirstDerivative(at: lowerAngle))
            let upperSlope = abs(configuration.radicandFirstDerivative(at: upperAngle))
            let lowerCurvature = configuration.radicandSecondDerivative(at: lowerAngle)
            let upperCurvature = configuration.radicandSecondDerivative(at: upperAngle)
            let hasInternalTangency = (
                lowerSlope <= classificationTolerance * 16.0
                    && lowerCurvature > classificationTolerance
            ) || (
                upperSlope <= classificationTolerance * 16.0
                    && upperCurvature > classificationTolerance
            )
            guard matchesCompleteInterval,
                  lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  hasInternalTangency else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "An internal-tangency torus-cylinder branch is not a complete nonnegative radicand interval with a verified double root."
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
                message: "A parallel torus-cylinder curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(torusProjection.residual, cylinderProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A parallel torus-cylinder curve failed its algebraic reconstruction check."
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
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let angle = try angleDifferential(
            at: clamped,
            configuration: configuration,
            tolerance: tolerance
        )
        let radialSquared = composedRadialSquared(
            angle: angle,
            configuration: configuration
        )
        guard radialSquared.value > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sqrt(max(radialSquared.value, 0.0)),
                tolerance: tolerance,
                message: "A parallel torus-cylinder curve reached a singular torus radial coordinate."
            )
        }
        let radialDistance = squareRootDifferential(radialSquared)
        let tubeDistance = ScalarDifferential(
            value: radialDistance.value - configuration.torus.majorRadius,
            first: radialDistance.first,
            second: radialDistance.second
        )
        let radicand = ScalarDifferential(
            value: configuration.torus.minorRadius * configuration.torus.minorRadius
                - tubeDistance.value * tubeDistance.value,
            first: -2.0 * tubeDistance.value * tubeDistance.first,
            second: -2.0 * (
                tubeDistance.first * tubeDistance.first
                    + tubeDistance.value * tubeDistance.second
            )
        )
        let height = try signedSquareRootDifferential(
            radicand,
            fraction: clamped,
            configuration: configuration,
            tolerance: tolerance
        )
        let radial = radialDifferential(
            angle: angle,
            configuration: configuration
        )
        let position = configuration.cylinder.origin
            + radial.value
            + configuration.cylinder.axis * height.value
        let firstDerivative = radial.first
            + configuration.cylinder.axis * height.first
        let secondDerivative = radial.second
            + configuration.cylinder.axis * height.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified parallel torus-cylinder component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let lower = try differential(
            atNormalizedFraction: clamped,
            tolerance: tolerance
        )
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let source = CurveTaylorScalarJet.variable(clamped)
        let angle = try angleTaylorJet(
            at: source,
            configuration: configuration,
            tolerance: tolerance
        )
        let radialSquared = CurveTaylorScalarJet(
            value: configuration.radialSquaredCenter
        ) + angle.cosine().scaled(
            by: configuration.radialSquaredCosine
        ) + angle.sine().scaled(by: configuration.radialSquaredSine)
        guard radialSquared.value > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sqrt(max(radialSquared.value, 0.0)),
                tolerance: tolerance,
                message: "A parallel torus-cylinder third-order evaluator reached a singular radial coordinate."
            )
        }
        let context = "Parallel torus-cylinder third derivative"
        let radialDistance = try radialSquared.squareRoot(
            tolerance: tolerance,
            diagnosticContext: context
        )
        let tubeDistance = radialDistance
            - CurveTaylorScalarJet(value: configuration.torus.majorRadius)
        let radicand = CurveTaylorScalarJet(
            value: configuration.torus.minorRadius
                * configuration.torus.minorRadius
        ) - tubeDistance * tubeDistance
        let height = (lower.position - configuration.cylinder.origin).dot(
            configuration.cylinder.axis
        )
        let heightFirst = lower.firstDerivative.dot(
            configuration.cylinder.axis
        )
        let heightSecond = lower.secondDerivative.dot(
            configuration.cylinder.axis
        )
        let heightThird: Double
        let heightThreshold = max(
            tolerance.distance * 1.0e-4,
            Double.ulpOfOne * configuration.characteristicLength * 4_096.0
        )
        if abs(height) > heightThreshold {
            heightThird = (
                radicand.thirdDerivative
                    - 6.0 * heightFirst * heightSecond
            ) / (2.0 * height)
        } else {
            let derivativeScale = max(
                lower.firstDerivative.length,
                configuration.characteristicLength,
                1.0
            )
            let derivativeFloor = max(
                tolerance.relative,
                Double.ulpOfOne * 4_096.0
            ) * derivativeScale
            guard abs(heightFirst) > derivativeFloor else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(heightFirst) / derivativeScale,
                    tolerance: tolerance,
                    message: "A parallel torus-cylinder endpoint has no regular third-order square-root continuation."
                )
            }
            heightThird = (
                radicand.fourthDerivative
                    - 6.0 * heightSecond * heightSecond
            ) / (8.0 * heightFirst)
        }
        let radialThird = configuration.cylinder.radialU
                * angle.cosine().thirdDerivative
            + configuration.cylinder.radialV
                * angle.sine().thirdDerivative
        let result = radialThird
            + configuration.cylinder.axis * heightThird
        guard heightThird.isFinite,
              result.x.isFinite,
              result.y.isFinite,
              result.z.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Parallel torus-cylinder third-order reconstruction exceeded finite arithmetic."
            )
        }
        return result
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        guard surface == torusSurface || surface == cylinderSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parallel torus-cylinder pcurve was requested on an unrelated surface."
            )
        }
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

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let radius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.torus.center.x - radius,
                y: configuration.torus.center.y - radius,
                z: configuration.torus.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.torus.center.x + radius,
                y: configuration.torus.center.y + radius,
                z: configuration.torus.center.z + radius
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
                message: "Parallel torus-cylinder differential bounds require a root-free full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 65_536.0
        ).nextUp
        let radialSquaredLower = (
            configuration.radialSquaredCenter
                - configuration.harmonicAmplitude
                - arithmeticEnvelope
        ).nextDown
        guard radialSquaredLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A parallel torus-cylinder full branch lost its positive radial-distance margin."
            )
        }
        let radialLower = sqrt(radialSquaredLower).nextDown
        let radialUpper = sqrt(
            (
                configuration.radialSquaredCenter
                    + configuration.harmonicAmplitude
                    + arithmeticEnvelope
            ).nextUp
        ).nextUp
        let harmonicDerivative = configuration.harmonicAmplitude.nextUp
        let radialFirst = (
            harmonicDerivative / (2.0 * radialLower).nextDown
        ).nextUp
        let radialCubedLower = (
            radialSquaredLower * radialLower
        ).nextDown
        let radialSecond = (
            harmonicDerivative / (2.0 * radialLower).nextDown
                + harmonicDerivative * harmonicDerivative
                    / (4.0 * radialCubedLower).nextDown
        ).nextUp
        let radialFifthLower = (
            radialSquaredLower * radialSquaredLower * radialLower
        ).nextDown
        let radialThird = (
            harmonicDerivative / (2.0 * radialLower).nextDown
                + 3.0 * harmonicDerivative * harmonicDerivative
                    / (4.0 * radialCubedLower).nextDown
                + 3.0 * harmonicDerivative * harmonicDerivative
                    * harmonicDerivative
                    / (8.0 * radialFifthLower).nextDown
        ).nextUp
        let tubeDistance = max(
            abs(radialLower - configuration.torus.majorRadius),
            abs(radialUpper - configuration.torus.majorRadius)
        ).nextUp
        let minimumRadicand = (
            Self.minimumRadicand(configuration: configuration)
                - arithmeticEnvelope
        ).nextDown
        guard minimumRadicand > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A parallel torus-cylinder full branch lost its positive tube-height radicand margin."
            )
        }
        let heightLower = sqrt(minimumRadicand).nextDown
        let radicandFirst = (
            2.0 * tubeDistance * radialFirst
        ).nextUp
        let radicandSecond = (
            2.0 * (
                radialFirst * radialFirst
                    + tubeDistance * radialSecond
            )
        ).nextUp
        let radicandThird = (
            2.0 * (
                3.0 * radialFirst * radialSecond
                    + tubeDistance * radialThird
            )
        ).nextUp
        let heightFirst = (
            radicandFirst / (2.0 * heightLower).nextDown
        ).nextUp
        let heightCubedLower = (
            minimumRadicand * heightLower
        ).nextDown
        let heightSecond = (
            radicandSecond / (2.0 * heightLower).nextDown
                + radicandFirst * radicandFirst
                    / (4.0 * heightCubedLower).nextDown
        ).nextUp
        let heightFifthLower = (
            minimumRadicand * minimumRadicand * heightLower
        ).nextDown
        let heightThird = (
            radicandThird / (2.0 * heightLower).nextDown
                + 3.0 * radicandFirst * radicandSecond
                    / (4.0 * heightCubedLower).nextDown
                + 3.0 * radicandFirst * radicandFirst * radicandFirst
                    / (8.0 * heightFifthLower).nextDown
        ).nextUp
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
        let periodSquared = (period * period).nextUp
        let periodCubed = (periodSquared * period).nextUp
        let first = (angularFirst * period).nextUp
        let second = (angularSecond * periodSquared).nextUp
        let third = (angularThird * periodCubed).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Parallel torus-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
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
                message: "Bounded parallel torus-cylinder differential bounds require a valid complete simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 262_144.0
        ).nextUp
        let derivativeBounds = try Self.radicandDerivativeMagnitudeBounds(
            configuration: configuration,
            arithmeticEnvelope: arithmeticEnvelope,
            tolerance: tolerance
        )
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = (period * period).nextUp
        let periodCubed = (periodSquared * period).nextUp
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
            lowerValue: configuration.radicand(at: lowerAngle),
            upperValue: configuration.radicand(at: upperAngle),
            lowerDerivative:
                configuration.radicandFirstDerivative(at: lowerAngle),
            upperDerivative:
                configuration.radicandFirstDerivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound: derivativeBounds.first,
            secondDerivativeMagnitudeUpperBound: derivativeBounds.second,
            thirdDerivativeMagnitudeUpperBound: derivativeBounds.third,
            fourthDerivativeMagnitudeUpperBound: derivativeBounds.fourth,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                Self.restrictedRadicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                )
            },
            tolerance: tolerance,
            label: "Parallel torus-cylinder bounded branch"
        )
        let factorRootLower = sqrt(factor.lower).nextDown
        let factorRootUpper = sqrt(factor.upper).nextUp
        guard factorRootLower > 0.0,
              factorRootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded parallel torus-cylinder factor lost its positive square-root margin."
            )
        }
        let factorRootFirst = (
            factor.first / (2.0 * factorRootLower).nextDown
        ).nextUp
        let factorRootCubedLower = (
            factor.lower * factorRootLower
        ).nextDown
        let factorRootSecond = (
            factor.second / (2.0 * factorRootLower).nextDown
                + factor.first * factor.first
                    / (4.0 * factorRootCubedLower).nextDown
        ).nextUp
        let factorRootFifthLower = (
            factor.lower * factor.lower * factorRootLower
        ).nextDown
        let factorRootThird = (
            factor.third / (2.0 * factorRootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * factorRootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * factorRootFifthLower).nextDown
        ).nextUp
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
        let angleFirst = (
            halfSpan * period * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * periodSquared * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * periodCubed * sineMagnitude
        ).nextUp
        let heightFirst = (
            halfSpan * (
                period * cosineMagnitude * factorRootUpper
                    + sineMagnitude * factorRootFirst * angleFirst
            )
        ).nextUp
        let heightSecond = (
            halfSpan * (
                periodSquared * sineMagnitude * factorRootUpper
                    + 2.0 * period * cosineMagnitude
                        * factorRootFirst * angleFirst
                    + sineMagnitude * (
                        factorRootSecond * angleFirst * angleFirst
                            + factorRootFirst * angleSecond
                    )
            )
        ).nextUp
        let rootByFractionFirst = (
            factorRootFirst * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            factorRootSecond * angleFirst * angleFirst
                + factorRootFirst * angleSecond
        ).nextUp
        let rootByFractionThird = (
            factorRootThird * angleFirst * angleFirst * angleFirst
                + 3.0 * factorRootSecond * angleFirst * angleSecond
                + factorRootFirst * angleThird
        ).nextUp
        let prefixValue = (halfSpan * sineMagnitude).nextUp
        let prefixFirst = (
            halfSpan * period * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * periodSquared * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * periodCubed * cosineMagnitude
        ).nextUp
        let heightThird = (
            prefixThird * factorRootUpper
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixValue * rootByFractionThird
        ).nextUp
        let radialFirst = (
            configuration.cylinder.radius * angleFirst
        ).nextUp
        let radialSecond = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst + angleSecond
            )
        ).nextUp
        let radialThird = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let first = hypot(radialFirst, heightFirst).nextUp
        let second = hypot(radialSecond, heightSecond).nextUp
        let third = hypot(radialThird, heightThird).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Bounded parallel torus-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    func internalTangencySpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .negativeInternalTangencyInterval
                || componentKind == .positiveInternalTangencyInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Internal-tangency torus-cylinder differential bounds require a valid certified source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 524_288.0
        ).nextUp
        let derivativeBounds = try Self.radicandDerivativeMagnitudeBounds(
            configuration: configuration,
            arithmeticEnvelope: arithmeticEnvelope,
            tolerance: tolerance
        )
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let lowerAngleValue = try angleDifferential(
            at: lower,
            configuration: configuration,
            tolerance: tolerance
        ).value
        let upperAngleValue = try angleDifferential(
            at: upper,
            configuration: configuration,
            tolerance: tolerance
        ).value
        let requestedAngleLower = min(
            lowerAngleValue,
            upperAngleValue
        ).nextDown
        let requestedAngleUpper = max(
            lowerAngleValue,
            upperAngleValue
        ).nextUp
        let lowerIsDouble = abs(
            configuration.radicandFirstDerivative(at: lowerAngle)
        ) <= classificationTolerance * 16.0
        let upperIsDouble = abs(
            configuration.radicandFirstDerivative(at: upperAngle)
        ) <= classificationTolerance * 16.0
        guard lowerIsDouble || upperIsDouble else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "An internal-tangency torus-cylinder component lost its double-root endpoint."
            )
        }
        let factor: EndpointRegularizedFactorBounder.Bounds
        if lowerIsDouble && upperIsDouble {
            factor = try EndpointRegularizedFactorBounder()
                .doubleDoubleBounds(
                    componentLower: lowerAngle,
                    componentUpper: upperAngle,
                    requestedLower: requestedAngleLower,
                    requestedUpper: requestedAngleUpper,
                    lowerValue: configuration.radicand(at: lowerAngle),
                    lowerFirstDerivative:
                        configuration.radicandFirstDerivative(at: lowerAngle),
                    lowerSecondDerivative:
                        configuration.radicandSecondDerivative(at: lowerAngle),
                    upperValue: configuration.radicand(at: upperAngle),
                    upperFirstDerivative:
                        configuration.radicandFirstDerivative(at: upperAngle),
                    upperSecondDerivative:
                        configuration.radicandSecondDerivative(at: upperAngle),
                    firstDerivativeMagnitudeUpperBound:
                        derivativeBounds.first,
                    secondDerivativeMagnitudeUpperBound:
                        derivativeBounds.second,
                    thirdDerivativeMagnitudeUpperBound:
                        derivativeBounds.third,
                    fifthDerivativeMagnitudeUpperBound:
                        derivativeBounds.fifth,
                    sixthDerivativeMagnitudeUpperBound:
                        derivativeBounds.sixth,
                    seventhDerivativeMagnitudeUpperBound:
                        derivativeBounds.seventh,
                    arithmeticEnvelope: arithmeticEnvelope,
                    valueRange: { rangeLower, rangeUpper in
                        Self.restrictedRadicandRange(
                            configuration: configuration,
                            lower: rangeLower,
                            upper: rangeUpper,
                            arithmeticEnvelope: arithmeticEnvelope
                        )
                    },
                    tolerance: tolerance,
                    label: "Parallel torus-cylinder two-double-root branch"
                )
        } else {
            let doubleAtLower = lowerIsDouble
            let doubleAngle = doubleAtLower ? lowerAngle : upperAngle
            let simpleAngle = doubleAtLower ? upperAngle : lowerAngle
            factor = try EndpointRegularizedFactorBounder()
                .mixedDoubleSimpleBounds(
                    componentLower: lowerAngle,
                    componentUpper: upperAngle,
                    requestedLower: requestedAngleLower,
                    requestedUpper: requestedAngleUpper,
                    doubleRootAtLower: doubleAtLower,
                    doubleRootValue:
                        configuration.radicand(at: doubleAngle),
                    doubleRootFirstDerivative:
                        configuration.radicandFirstDerivative(at: doubleAngle),
                    doubleRootSecondDerivative:
                        configuration.radicandSecondDerivative(at: doubleAngle),
                    simpleRootValue:
                        configuration.radicand(at: simpleAngle),
                    simpleRootFirstDerivative:
                        configuration.radicandFirstDerivative(at: simpleAngle),
                    firstDerivativeMagnitudeUpperBound:
                        derivativeBounds.first,
                    secondDerivativeMagnitudeUpperBound:
                        derivativeBounds.second,
                    thirdDerivativeMagnitudeUpperBound:
                        derivativeBounds.third,
                    fourthDerivativeMagnitudeUpperBound:
                        derivativeBounds.fourth,
                    fifthDerivativeMagnitudeUpperBound:
                        derivativeBounds.fifth,
                    sixthDerivativeMagnitudeUpperBound:
                        derivativeBounds.sixth,
                    arithmeticEnvelope: arithmeticEnvelope,
                    valueRange: { rangeLower, rangeUpper in
                        Self.restrictedRadicandRange(
                            configuration: configuration,
                            lower: rangeLower,
                            upper: rangeUpper,
                            arithmeticEnvelope: arithmeticEnvelope
                        )
                    },
                    tolerance: tolerance,
                    label: "Parallel torus-cylinder mixed-root branch"
                )
        }
        let span = (upperAngle - lowerAngle).nextUp
        let halfPi = (Double.pi * 0.5).nextUp
        let halfPiSquared = (halfPi * halfPi).nextUp
        let angleFirst: Double
        let angleSecond: Double
        let angleThird: Double
        let normalizedLower: Double
        let normalizedUpper: Double
        let normalizedFirst: Double
        let normalizedSecond: Double
        let normalizedThird: Double
        let distanceRootMagnitude: Double
        let distanceRootFirst: Double
        let distanceRootSecond: Double
        let distanceRootThird: Double
        if lowerIsDouble && upperIsDouble {
            angleFirst = span
            angleSecond = 0.0
            angleThird = 0.0
            normalizedLower = factor.lower
            normalizedUpper = factor.upper
            normalizedFirst = (factor.first * angleFirst).nextUp
            normalizedSecond = (
                factor.second * angleFirst * angleFirst
            ).nextUp
            normalizedThird = (
                factor.third * angleFirst * angleFirst * angleFirst
            ).nextUp
            let spanSquared = (span * span).nextUp
            distanceRootMagnitude = (spanSquared * 0.25).nextUp
            distanceRootFirst = spanSquared.nextUp
            distanceRootSecond = (2.0 * spanSquared).nextUp
            distanceRootThird = 0.0
        } else {
            angleFirst = (span * halfPi).nextUp
            angleSecond = (span * halfPiSquared).nextUp
            let halfPiCubed = (halfPiSquared * halfPi).nextUp
            angleThird = (span * halfPiCubed).nextUp
            let factorFirst = (factor.first * angleFirst).nextUp
            let factorSecond = (
                factor.second * angleFirst * angleFirst
                    + factor.first * angleSecond
            ).nextUp
            let factorThird = (
                factor.third * angleFirst * angleFirst * angleFirst
                    + 3.0 * factor.second * angleFirst * angleSecond
                    + factor.first * angleThird
            ).nextUp
            let inverseFirst = halfPi
            let inverseSecond = (
                3.0 * halfPiSquared
            ).nextUp
            let inverseThird = (13.0 * halfPiCubed).nextUp
            normalizedLower = (factor.lower * 0.5).nextDown
            normalizedUpper = factor.upper.nextUp
            normalizedFirst = (
                factorFirst + factor.upper * inverseFirst
            ).nextUp
            normalizedSecond = (
                factorSecond
                    + 2.0 * factorFirst * inverseFirst
                    + factor.upper * inverseSecond
            ).nextUp
            normalizedThird = (
                factorThird
                    + 3.0 * factorSecond * inverseFirst
                    + 3.0 * factorFirst * inverseSecond
                    + factor.upper * inverseThird
            ).nextUp
            let spanScale = pow(span, 1.5).nextUp
            distanceRootMagnitude = (spanScale * 0.5).nextUp
            distanceRootFirst = (spanScale * halfPi).nextUp
            distanceRootSecond = (
                2.0 * spanScale * halfPiSquared
            ).nextUp
            distanceRootThird = (
                4.0 * spanScale * halfPiCubed
            ).nextUp
        }
        let rootLower = sqrt(normalizedLower).nextDown
        let rootUpper = sqrt(normalizedUpper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "An internal-tangency torus-cylinder factor lost its positive square-root margin."
            )
        }
        let rootFirst = (
            normalizedFirst / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (
            normalizedLower * rootLower
        ).nextDown
        let rootSecond = (
            normalizedSecond / (2.0 * rootLower).nextDown
                + normalizedFirst * normalizedFirst
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let rootFifthLower = (
            normalizedLower * normalizedLower * rootLower
        ).nextDown
        let rootThird = (
            normalizedThird / (2.0 * rootLower).nextDown
                + 3.0 * normalizedFirst * normalizedSecond
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * normalizedFirst * normalizedFirst
                    * normalizedFirst
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let heightFirst = (
            distanceRootFirst * rootUpper
                + distanceRootMagnitude * rootFirst
        ).nextUp
        let heightSecond = (
            distanceRootSecond * rootUpper
                + 2.0 * distanceRootFirst * rootFirst
                + distanceRootMagnitude * rootSecond
        ).nextUp
        let heightThird = (
            distanceRootThird * rootUpper
                + 3.0 * distanceRootSecond * rootFirst
                + 3.0 * distanceRootFirst * rootSecond
                + distanceRootMagnitude * rootThird
        ).nextUp
        let radialFirst = (
            configuration.cylinder.radius * angleFirst
        ).nextUp
        let radialSecond = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst + angleSecond
            )
        ).nextUp
        let radialThird = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let first = hypot(radialFirst, heightFirst).nextUp
        let second = hypot(radialSecond, heightSecond).nextUp
        let third = hypot(radialThird, heightThird).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Internal-tangency torus-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func angleDifferential(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return ScalarDifferential(
                value: period * fraction,
                first: period,
                second: 0.0
            )
        case .boundedAngularInterval:
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            let phase = period * fraction
            return ScalarDifferential(
                value: midpoint - halfSpan * cos(phase),
                first: halfSpan * period * sin(phase),
                second: halfSpan * period * period * cos(phase)
            )
        case .negativeInternalTangencyInterval,
             .positiveInternalTangencyInterval:
            let span = upperAngle - lowerAngle
            let classificationTolerance = Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let lowerIsInternal = abs(
                configuration.radicandFirstDerivative(at: lowerAngle)
            ) <= classificationTolerance * 16.0
            let upperIsInternal = abs(
                configuration.radicandFirstDerivative(at: upperAngle)
            ) <= classificationTolerance * 16.0
            let normalized: ScalarDifferential
            switch (lowerIsInternal, upperIsInternal) {
            case (true, true):
                normalized = ScalarDifferential(
                    value: fraction,
                    first: 1.0,
                    second: 0.0
                )
            case (false, true):
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: 1.0 - cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.25 * cos(phase)
                )
            case (true, false):
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: sin(phase),
                    first: Double.pi * 0.5 * cos(phase),
                    second: -Double.pi * Double.pi * 0.25 * sin(phase)
                )
            case (false, false):
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An internal-tangency interval has no verified double-root endpoint."
                )
            }
            return ScalarDifferential(
                value: lowerAngle + span * normalized.value,
                first: span * normalized.first,
                second: span * normalized.second
            )
        }
    }

    private func angleTaylorJet(
        at fraction: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> CurveTaylorScalarJet {
        let span = upperAngle - lowerAngle
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return fraction.scaled(by: 2.0 * Double.pi)
        case .boundedAngularInterval:
            let period = 2.0 * Double.pi
            let midpoint = lowerAngle + span * 0.5
            return CurveTaylorScalarJet(value: midpoint)
                - fraction.scaled(by: period).cosine()
                    .scaled(by: span * 0.5)
        case .negativeInternalTangencyInterval,
             .positiveInternalTangencyInterval:
            let classificationTolerance = Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let lowerIsInternal = abs(
                configuration.radicandFirstDerivative(at: lowerAngle)
            ) <= classificationTolerance * 16.0
            let upperIsInternal = abs(
                configuration.radicandFirstDerivative(at: upperAngle)
            ) <= classificationTolerance * 16.0
            let scale = Double.pi * 0.5
            let normalized: CurveTaylorScalarJet
            switch (lowerIsInternal, upperIsInternal) {
            case (true, true):
                normalized = fraction
            case (false, true):
                normalized = CurveTaylorScalarJet(value: 1.0)
                    - fraction.scaled(by: scale).cosine()
            case (true, false):
                normalized = fraction.scaled(by: scale).sine()
            case (false, false):
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An internal-tangency interval has no verified double-root endpoint."
                )
            }
            return CurveTaylorScalarJet(value: lowerAngle)
                + normalized.scaled(by: span)
        }
    }

    private func composedRadialSquared(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> ScalarDifferential {
        let angularFirst = configuration.radialSquaredFirstDerivative(at: angle.value)
        return ScalarDifferential(
            value: configuration.radialSquared(at: angle.value),
            first: angularFirst * angle.first,
            second: configuration.radialSquaredSecondDerivative(at: angle.value)
                    * angle.first * angle.first
                + angularFirst * angle.second
        )
    }

    private func squareRootDifferential(
        _ input: ScalarDifferential
    ) -> ScalarDifferential {
        let root = sqrt(input.value)
        return ScalarDifferential(
            value: root,
            first: input.first / (2.0 * root),
            second: input.second / (2.0 * root)
                - input.first * input.first / (4.0 * root * root * root)
        )
    }

    private func radialDifferential(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> (value: Vector3D, first: Vector3D, second: Vector3D) {
        let value = configuration.cylinder.radialU * cos(angle.value)
            + configuration.cylinder.radialV * sin(angle.value)
        let angularFirst = configuration.cylinder.radialU * -sin(angle.value)
            + configuration.cylinder.radialV * cos(angle.value)
        return (
            value,
            angularFirst * angle.first,
            -value * (angle.first * angle.first) + angularFirst * angle.second
        )
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
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
        case .negativeInternalTangencyInterval:
            branchSign = -1.0
        case .positiveInternalTangencyInterval:
            branchSign = 1.0
        }
        let endpointTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let isLowerEndpoint = fraction <= endpointTolerance
        let isUpperEndpoint = fraction >= 1.0 - endpointTolerance
        let isCertifiedEndpoint: Bool
        switch componentKind {
        case .boundedAngularInterval:
            isCertifiedEndpoint = abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0)
        case .negativeInternalTangencyInterval,
             .positiveInternalTangencyInterval:
            isCertifiedEndpoint = isLowerEndpoint || isUpperEndpoint
        case .negativeFullBranch, .positiveFullBranch:
            isCertifiedEndpoint = false
        }
        if isCertifiedEndpoint,
           abs(radicand.value) <= classificationTolerance * 32.0 {
            let squaredSlope = radicand.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A parallel torus-cylinder boundary has no regular square-root continuation."
                )
            }
            let endpointDirection: Double
            switch componentKind {
            case .boundedAngularInterval:
                endpointDirection = cos(2.0 * Double.pi * fraction) < 0.0
                    ? -1.0
                    : 1.0
            case .negativeInternalTangencyInterval,
                 .positiveInternalTangencyInterval:
                endpointDirection = isUpperEndpoint ? -1.0 : 1.0
            case .negativeFullBranch, .positiveFullBranch:
                endpointDirection = 1.0
            }
            let signedEndpointDirection = componentKind == .boundedAngularInterval
                ? endpointDirection
                : branchSign * endpointDirection
            return ScalarDifferential(
                value: 0.0,
                first: signedEndpointDirection * sqrt(squaredSlope),
                second: 0.0
            )
        }
        guard radicand.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -radicand.value,
                tolerance: tolerance,
                message: "A parallel torus-cylinder evaluator left its certified radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A parallel torus-cylinder square-root differential is singular."
            )
        }
        let signedValue = branchSign * magnitude
        return ScalarDifferential(
            value: signedValue,
            first: radicand.first / (2.0 * signedValue),
            second: radicand.second / (2.0 * signedValue)
                - radicand.first * radicand.first
                    / (4.0 * signedValue * signedValue * signedValue)
        )
    }

    private static func radicandDerivativeMagnitudeBounds(
        configuration: Configuration,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    ) throws -> (
        first: Double,
        second: Double,
        third: Double,
        fourth: Double,
        fifth: Double,
        sixth: Double,
        seventh: Double
    ) {
        let radialSquaredLower = (
            configuration.radialSquaredCenter
                - configuration.harmonicAmplitude
                - arithmeticEnvelope
        ).nextDown
        let radialSquaredUpper = (
            configuration.radialSquaredCenter
                + configuration.harmonicAmplitude
                + arithmeticEnvelope
        ).nextUp
        guard radialSquaredLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A parallel torus-cylinder branch lost its positive radial-distance margin."
            )
        }
        let radialLower = sqrt(radialSquaredLower).nextDown
        let radialUpper = sqrt(radialSquaredUpper).nextUp
        let harmonic = configuration.harmonicAmplitude.nextUp
        var radialDerivatives = Array(repeating: 0.0, count: 8)
        radialDerivatives[0] = radialUpper
        for order in 1...7 {
            var convolution = 0.0
            if order > 1 {
                for index in 1..<order {
                    convolution = (
                        convolution
                            + Self.binomial(order, index)
                                * radialDerivatives[index]
                                * radialDerivatives[order - index]
                    ).nextUp
                }
            }
            radialDerivatives[order] = (
                (harmonic + convolution)
                    / (2.0 * radialLower).nextDown
            ).nextUp
        }
        let tubeDistance = max(
            abs(radialLower - configuration.torus.majorRadius),
            abs(radialUpper - configuration.torus.majorRadius)
        ).nextUp
        var radicandDerivatives = Array(repeating: 0.0, count: 8)
        for order in 1...7 {
            var value = (
                2.0 * tubeDistance * radialDerivatives[order]
            ).nextUp
            if order > 1 {
                for index in 1..<order {
                    value = (
                        value
                            + Self.binomial(order, index)
                                * radialDerivatives[index]
                                * radialDerivatives[order - index]
                    ).nextUp
                }
            }
            radicandDerivatives[order] = value
        }
        guard radicandDerivatives.dropFirst().allSatisfy(\.isFinite) else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Parallel torus-cylinder radicand derivative bounds exceeded finite arithmetic."
            )
        }
        return (
            radicandDerivatives[1],
            radicandDerivatives[2],
            radicandDerivatives[3],
            radicandDerivatives[4],
            radicandDerivatives[5],
            radicandDerivatives[6],
            radicandDerivatives[7]
        )
    }

    private static func binomial(_ order: Int, _ index: Int) -> Double {
        guard index > 0, index < order else { return 1.0 }
        let selected = min(index, order - index)
        var result = 1.0
        for step in 1...selected {
            result *= Double(order - selected + step) / Double(step)
        }
        return result.nextUp
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

    private static func restrictedRadicandRange(
        configuration: Configuration,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double
    ) -> (lower: Double, upper: Double) {
        var values = [
            configuration.radicand(at: lower),
            configuration.radicand(at: upper),
        ]
        let phase = atan2(
            configuration.radialSquaredSine,
            configuration.radialSquaredCosine
        )
        let period = 2.0 * Double.pi
        for base in [phase, phase + Double.pi] {
            for winding in -1...2 {
                let angle = base + Double(winding) * period
                if angle > lower, angle < upper {
                    values.append(configuration.radicand(at: angle))
                }
            }
        }
        return (
            ((values.min() ?? 0.0) - arithmeticEnvelope).nextDown,
            ((values.max() ?? 0.0) + arithmeticEnvelope).nextUp
        )
    }

    private static func makeConfiguration(
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try torusSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
        guard case let .torus(sourceTorus) = CanonicalAnalyticSurface(torusSurface),
              case let .cylinder(sourceCylinder) = CanonicalAnalyticSurface(cylinderSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified parallel torus-cylinder curve requires one exact torus and one exact cylinder."
            )
        }
        guard AnalyticAxisRelation.areParallel(
            sourceTorus.axis,
            sourceCylinder.axis,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parallel torus-cylinder curve requires parallel source axes."
            )
        }
        let torusAxis = try sourceTorus.axis.normalized(tolerance: tolerance.distance)
        let cylinderAxis = try sourceCylinder.axis.normalized(tolerance: tolerance.distance)
        let alignedAxis = cylinderAxis.dot(torusAxis) >= 0.0
            ? torusAxis
            : -torusAxis
        let originOffset = sourceTorus.center - sourceCylinder.origin
        let origin = sourceCylinder.origin
            + alignedAxis * originOffset.dot(alignedAxis)
        let basis = try analyticOrthonormalBasis(alignedAxis, tolerance: tolerance)
        let radialU = basis.u * sourceCylinder.radius
        let radialV = basis.v * sourceCylinder.radius
        let centerOffset = origin - sourceTorus.center
        return Configuration(
            torus: Torus(
                center: sourceTorus.center,
                axis: torusAxis,
                majorRadius: sourceTorus.majorRadius,
                minorRadius: sourceTorus.minorRadius
            ),
            cylinder: Cylinder(
                origin: origin,
                axis: alignedAxis,
                radius: sourceCylinder.radius,
                radialU: radialU,
                radialV: radialV
            ),
            radialSquaredCenter: centerOffset.dot(centerOffset)
                + sourceCylinder.radius * sourceCylinder.radius,
            radialSquaredCosine: 2.0 * centerOffset.dot(radialU),
            radialSquaredSine: 2.0 * centerOffset.dot(radialV)
        )
    }

    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let values = [
            configuration.torus.majorRadius - configuration.torus.minorRadius,
            configuration.torus.majorRadius + configuration.torus.minorRadius,
        ].flatMap { radialDistance in
            boundaryAngles(
                radialDistance: radialDistance,
                configuration: configuration,
                tolerance: tolerance
            )
        }.map {
            refinedBoundaryAngle(
                $0,
                configuration: configuration,
                tolerance: tolerance
            )
        }.sorted()
        var result: [Double] = []
        for value in values where result.last.map({
            angularDistance($0, value) <= tolerance.angle
        }) != true {
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

    private static func boundaryAngles(
        radialDistance: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.harmonicAmplitude
        let numericalThreshold = radialSquaredClassificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard amplitude > numericalThreshold else { return [] }
        let ratio = (
            radialDistance * radialDistance
                - configuration.radialSquaredCenter
        ) / amplitude
        let ratioTolerance = numericalThreshold / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let phase = atan2(
            configuration.radialSquaredSine,
            configuration.radialSquaredCosine
        )
        let offset = acos(min(max(ratio, -1.0), 1.0))
        return [
            normalizedAngle(phase - offset),
            normalizedAngle(phase + offset),
        ]
    }

    private static func validIntervals(
        boundaries: [Double],
        configuration: Configuration,
        classificationTolerance: Double
    ) -> [(lower: Double, upper: Double)] {
        guard boundaries.isEmpty == false else { return [] }
        return boundaries.indices.compactMap { index in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return configuration.radicand(at: lower + (upper - lower) * 0.5)
                > classificationTolerance
                ? (lower, upper)
                : nil
        }
    }

    private static func minimumRadicand(configuration: Configuration) -> Double {
        let squaredLower = max(
            configuration.radialSquaredCenter - configuration.harmonicAmplitude,
            0.0
        )
        let squaredUpper = max(
            configuration.radialSquaredCenter + configuration.harmonicAmplitude,
            0.0
        )
        let radialLower = sqrt(squaredLower)
        let radialUpper = sqrt(squaredUpper)
        let maximumTubeDistance = max(
            abs(radialLower - configuration.torus.majorRadius),
            abs(radialUpper - configuration.torus.majorRadius)
        )
        return configuration.torus.minorRadius * configuration.torus.minorRadius
            - maximumTubeDistance * maximumTubeDistance
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0
        let hasBoundaryRoots: Bool
        switch componentKind {
        case .boundedAngularInterval,
             .negativeInternalTangencyInterval,
             .positiveInternalTangencyInterval:
            hasBoundaryRoots = true
        case .negativeFullBranch, .positiveFullBranch:
            hasBoundaryRoots = false
        }
        guard hasBoundaryRoots else {
            return machineBound
        }
        let rootResidual = max(
            abs(configuration.radicand(at: lowerAngle)),
            abs(configuration.radicand(at: upperAngle))
        )
        let result = sqrt(rootResidual) + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Parallel torus-cylinder boundary roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 4_096.0,
            tolerance.distance
                * (2.0 * configuration.torus.minorRadius + tolerance.distance)
                * 1.0e-6
        )
    }

    private static func radialSquaredClassificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let outerRadius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
        return max(
            Double.ulpOfOne * max(
                outerRadius * outerRadius,
                configuration.cylinder.radius * configuration.cylinder.radius,
                configuration.radialSquaredCenter,
                1.0
            ) * 128.0,
            tolerance.distance * (2.0 * outerRadius + tolerance.distance) * 1.0e-6
        )
    }

    private static func refinedBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let residualTolerance = max(
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0,
            Double.leastNonzeroMagnitude
        )
        for _ in 0..<64 {
            let value = configuration.radicand(at: angle)
            if abs(value) <= residualTolerance { break }
            let derivative = configuration.radicandFirstDerivative(at: angle)
            guard derivative.isFinite,
                  abs(derivative) > tolerance.angle else { break }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
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

    private enum CodingKeys: String, CodingKey {
        case torusSurface
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
                .torusSurface,
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
            torusSurface: container.decode(Surface3D.self, forKey: .torusSurface),
            cylinderSurface: container.decode(
                Surface3D.self,
                forKey: .cylinderSurface
            ),
            componentKind: container.decode(ComponentKind.self, forKey: .componentKind),
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
                debugDescription: "The parallel torus-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
