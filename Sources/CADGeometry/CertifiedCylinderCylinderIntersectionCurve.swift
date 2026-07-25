import CADCore
import Foundation

public struct CertifiedCylinderCylinderIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let reference: Cylinder
        let parameterized: Cylinder
        let normal: Vector3D
        let projectedAxis: Vector3D
        let projectedAxisSquaredLength: Double
        let signedDistanceCenter: Double
        let signedDistanceCosine: Double
        let signedDistanceSine: Double
        let linearCenter: Double
        let linearCosine: Double
        let linearSine: Double

        var characteristicLength: Double {
            max(
                (parameterized.origin - reference.origin).length,
                parameterized.radius,
                reference.radius,
                1.0
            )
        }

        var signedDistanceAmplitude: Double {
            hypot(signedDistanceCosine, signedDistanceSine)
        }

        var linearAmplitude: Double {
            hypot(linearCosine, linearSine)
        }

        func signedDistance(at angle: Double) -> Double {
            signedDistanceCenter
                + signedDistanceCosine * cos(angle)
                + signedDistanceSine * sin(angle)
        }

        func signedDistanceFirstDerivative(at angle: Double) -> Double {
            -signedDistanceCosine * sin(angle)
                + signedDistanceSine * cos(angle)
        }

        func signedDistanceSecondDerivative(at angle: Double) -> Double {
            -signedDistanceCosine * cos(angle)
                - signedDistanceSine * sin(angle)
        }

        func radicand(at angle: Double) -> Double {
            let distance = signedDistance(at: angle)
            return reference.radius * reference.radius - distance * distance
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            -2.0 * signedDistance(at: angle)
                * signedDistanceFirstDerivative(at: angle)
        }

        func radicandSecondDerivative(at angle: Double) -> Double {
            let distance = signedDistance(at: angle)
            let first = signedDistanceFirstDerivative(at: angle)
            let second = signedDistanceSecondDerivative(at: angle)
            return -2.0 * (first * first + distance * second)
        }

    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double

        func scaled(by scale: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scale,
                first: first * scale,
                second: second * scale
            )
        }

        func adding(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second
            )
        }
    }

    private struct RegularizedFactorBounds {
        let lower: Double
        let upper: Double
        let first: Double
        let second: Double

        func merged(with other: RegularizedFactorBounds) -> RegularizedFactorBounds {
            RegularizedFactorBounds(
                lower: min(lower, other.lower),
                upper: max(upper, other.upper),
                first: max(first, other.first),
                second: max(second, other.second)
            )
        }
    }

    public let referenceSurface: Surface3D
    public let parameterizedSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.referenceSurface = referenceSurface
        self.parameterizedSurface = parameterizedSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
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
                message: "A cylinder-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
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
                    message: "A full cylinder-cylinder branch requires a positive root-free radicand domain."
                )
            }
        case .boundedAngularInterval:
            let validIntervals = Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance
            )
            let matchesCompleteInterval = validIntervals.contains { interval in
                abs(interval.lower - lowerAngle) <= tolerance.angle
                    && abs(interval.upper - upperAngle) <= tolerance.angle
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
                    message: "A bounded cylinder-cylinder component is not a complete simple-root interval."
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
                message: "A cylinder-cylinder curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let firstProjection = try referenceSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let secondProjection = try parameterizedSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(firstProjection.residual, secondProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A cylinder-cylinder curve failed its algebraic reconstruction check."
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
        let normalizedFraction = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(at: normalizedFraction)
        let baseGeometry = try configuration.parameterized.surface.differentialGeometry(
            atU: angle.value,
            v: 0.0,
            tolerance: tolerance
        )
        let offset = baseGeometry.position - configuration.reference.origin
        let linear = composedProjection(
            offset: offset,
            tangent: baseGeometry.tangentU,
            secondTangent: baseGeometry.secondDerivativeUU,
            direction: configuration.projectedAxis,
            angle: angle
        )
        let signedDistance = composedProjection(
            offset: offset,
            tangent: baseGeometry.tangentU,
            secondTangent: baseGeometry.secondDerivativeUU,
            direction: configuration.normal,
            angle: angle
        )
        let inverseProjectedAxisSquaredLength = 1.0
            / configuration.projectedAxisSquaredLength
        let signedRoot: ScalarDifferential
        if componentKind == .boundedAngularInterval {
            signedRoot = try boundedSignedSquareRootDifferential(
                angle: angle,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
        } else {
            let rawRadicand = ScalarDifferential(
                value: (
                    configuration.reference.radius
                        * configuration.reference.radius
                        - signedDistance.value * signedDistance.value
                ),
                first: -2.0 * signedDistance.value * signedDistance.first,
                second: -2.0 * (
                    signedDistance.first * signedDistance.first
                        + signedDistance.value * signedDistance.second
                )
            )
            signedRoot = try signedSquareRootDifferential(
                rawRadicand.scaled(by: inverseProjectedAxisSquaredLength),
                configuration: configuration,
                tolerance: tolerance
            )
        }
        let height = linear
            .scaled(by: -inverseProjectedAxisSquaredLength)
            .adding(signedRoot)
        let surfaceGeometry = try configuration.parameterized.surface.differentialGeometry(
            atU: angle.value,
            v: height.value,
            tolerance: tolerance
        )
        let firstDerivative = surfaceGeometry.tangentU * angle.first
            + surfaceGeometry.tangentV * height.first
        let secondDerivative = surfaceGeometry.secondDerivativeUU
                * (angle.first * angle.first)
            + surfaceGeometry.secondDerivativeUV
                * (2.0 * angle.first * height.first)
            + surfaceGeometry.secondDerivativeVV
                * (height.first * height.first)
            + surfaceGeometry.tangentU * angle.second
            + surfaceGeometry.tangentV * height.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cylinder-cylinder component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: surfaceGeometry.position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
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

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let maximumLinear = abs(configuration.linearCenter)
            + configuration.linearAmplitude
        let maximumRadicand = max(
            Self.maximumRadicand(configuration: configuration),
            0.0
        )
        let height = maximumLinear / configuration.projectedAxisSquaredLength
            + sqrt(maximumRadicand / configuration.projectedAxisSquaredLength)
        let radius = configuration.parameterized.radius + height + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.parameterized.origin.x - radius,
                y: configuration.parameterized.origin.y - radius,
                z: configuration.parameterized.origin.z - radius
            ),
            maximum: Point3D(
                x: configuration.parameterized.origin.x + radius,
                y: configuration.parameterized.origin.y + radius,
                z: configuration.parameterized.origin.z + radius
            )
        )
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try tolerance.validate()
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cylinder-cylinder full-branch differential bounds require a root-free angular component."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let minimumRawRadicand = (
            Self.minimumRadicand(configuration: configuration)
                - arithmeticEnvelope
        ).nextDown
        let projectedAxisSquaredLengthLower = (
            configuration.projectedAxisSquaredLength
                - max(
                    Double.ulpOfOne
                        * configuration.projectedAxisSquaredLength * 4_096.0,
                    tolerance.relative
                        * configuration.projectedAxisSquaredLength * 1.0e-6
                )
        ).nextDown
        guard minimumRawRadicand > 0.0,
              projectedAxisSquaredLengthLower > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: min(
                    minimumRawRadicand,
                    projectedAxisSquaredLengthLower
                ),
                tolerance: tolerance,
                message: "Cylinder-cylinder full-branch differential certification lost its positive radicand or axis projection margin."
            )
        }

        let distanceMagnitude = Self.upperSum(
            abs(configuration.signedDistanceCenter),
            configuration.signedDistanceAmplitude
        )
        let distanceDerivative = configuration.signedDistanceAmplitude.nextUp
        let rawRadicandFirst = Self.upperProduct(
            2.0,
            Self.upperProduct(distanceMagnitude, distanceDerivative)
        )
        let rawRadicandSecond = Self.upperProduct(
            2.0,
            Self.upperSum(
                Self.upperProduct(distanceDerivative, distanceDerivative),
                Self.upperProduct(distanceMagnitude, distanceDerivative)
            )
        )
        let normalizedRadicandLower = (
            minimumRawRadicand
                / configuration.projectedAxisSquaredLength.nextUp
        ).nextDown
        let normalizedRadicandFirst = (
            rawRadicandFirst / projectedAxisSquaredLengthLower
        ).nextUp
        let normalizedRadicandSecond = (
            rawRadicandSecond / projectedAxisSquaredLengthLower
        ).nextUp
        let rootLower = sqrt(normalizedRadicandLower).nextDown
        guard rootLower > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rootLower,
                tolerance: tolerance,
                message: "Cylinder-cylinder full-branch square-root certification lost its positive lower bound."
            )
        }
        let rootFirst = (
            normalizedRadicandFirst
                / Self.lowerProduct(2.0, rootLower)
        ).nextUp
        let rootSecond = Self.upperSum(
            (
                normalizedRadicandSecond
                    / Self.lowerProduct(2.0, rootLower)
            ).nextUp,
            (
                Self.upperProduct(
                    normalizedRadicandFirst,
                    normalizedRadicandFirst
                ) / (
                    Self.lowerProduct(
                        4.0,
                        Self.lowerProduct(
                            rootLower,
                            Self.lowerProduct(rootLower, rootLower)
                        )
                    )
                )
            ).nextUp
        )
        let linearFirst = (
            configuration.linearAmplitude
                / projectedAxisSquaredLengthLower
        ).nextUp
        let heightFirst = Self.upperSum(linearFirst, rootFirst)
        let heightSecond = Self.upperSum(linearFirst, rootSecond)
        let angularScale = (2.0 * Double.pi).nextUp
        let first = Self.upperProduct(
            angularScale,
            Self.upperSum(configuration.parameterized.radius, heightFirst)
        )
        let second = Self.upperProduct(
            Self.upperProduct(angularScale, angularScale),
            Self.upperSum(configuration.parameterized.radius, heightSecond)
        )
        guard first.isFinite, second.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Cylinder-cylinder full-branch differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp
        )
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            tolerance: tolerance
        )
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try tolerance.validate()
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction - lowerFraction > tolerance.relative else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return try fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        case .boundedAngularInterval:
            return try boundedBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(max(lowerFraction, 0.0), 1.0),
                toNormalizedFraction: min(max(upperFraction, 0.0), 1.0),
                tolerance: tolerance
            )
        }
    }

    private func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try tolerance.validate()
        guard componentKind == .boundedAngularInterval else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cylinder-cylinder bounded-branch differential bounds require a simple-root angular component."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let span = upperAngle - lowerAngle
        let halfSpan = span * 0.5
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let projectedAxisSquaredLengthLower = (
            configuration.projectedAxisSquaredLength
                - max(
                    Double.ulpOfOne
                        * configuration.projectedAxisSquaredLength * 4_096.0,
                    tolerance.relative
                        * configuration.projectedAxisSquaredLength * 1.0e-6
                )
        ).nextDown
        guard span > tolerance.angle,
              projectedAxisSquaredLengthLower > 0.0 else {
            throw Self.resourceFailure(
                residual: min(span, projectedAxisSquaredLengthLower),
                tolerance: tolerance,
                message: "Cylinder-cylinder bounded-branch certification lost its angular or projected-axis margin."
            )
        }

        let lowerResidual = configuration.radicand(at: lowerAngle)
        let upperResidual = configuration.radicand(at: upperAngle)
        let correctionSlope = (upperResidual - lowerResidual) / span
        let lowerSlope = configuration.radicandFirstDerivative(at: lowerAngle)
            - correctionSlope
        let upperSlope = -(
            configuration.radicandFirstDerivative(at: upperAngle)
                - correctionSlope
        )
        let distanceMagnitude = Self.upperSum(
            abs(configuration.signedDistanceCenter),
            configuration.signedDistanceAmplitude
        )
        let distanceDerivative = configuration.signedDistanceAmplitude.nextUp
        let rawFirst = Self.upperProduct(
            2.0,
            Self.upperProduct(distanceMagnitude, distanceDerivative)
        )
        let rawSecond = Self.upperProduct(
            2.0,
            Self.upperSum(
                Self.upperProduct(distanceDerivative, distanceDerivative),
                Self.upperProduct(distanceMagnitude, distanceDerivative)
            )
        )
        let rawThird = Self.upperProduct(
            2.0,
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(distanceDerivative, distanceDerivative)
                ),
                Self.upperProduct(distanceMagnitude, distanceDerivative)
            )
        )
        let regularizedFirst = Self.upperSum(rawFirst, abs(correctionSlope))
        guard lowerSlope > arithmeticEnvelope,
              upperSlope > arithmeticEnvelope,
              rawSecond.isFinite,
              rawThird.isFinite else {
            throw Self.resourceFailure(
                residual: min(lowerSlope, upperSlope),
                tolerance: tolerance,
                message: "Cylinder-cylinder endpoint regularization lost its certified simple-root slopes."
            )
        }

        let lowerWidth = Self.endpointProofWidth(
            span: span,
            endpointSlope: lowerSlope,
            secondDerivativeBound: rawSecond
        )
        let upperWidth = Self.endpointProofWidth(
            span: span,
            endpointSlope: upperSlope,
            secondDerivativeBound: rawSecond
        )
        let angleRange = Self.boundedAngleRange(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        var factorBounds: RegularizedFactorBounds?
        if angleRange.lower < lowerAngle + lowerWidth {
            factorBounds = try Self.endpointFactorBounds(
                span: span,
                width: lowerWidth,
                endpointSlope: lowerSlope,
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound: rawSecond,
                thirdDerivativeBound: rawThird,
                arithmeticEnvelope: arithmeticEnvelope,
                tolerance: tolerance
            )
        }
        if angleRange.upper > upperAngle - upperWidth {
            let upperBounds = try Self.endpointFactorBounds(
                span: span,
                width: upperWidth,
                endpointSlope: upperSlope,
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound: rawSecond,
                thirdDerivativeBound: rawThird,
                arithmeticEnvelope: arithmeticEnvelope,
                tolerance: tolerance
            )
            factorBounds = factorBounds?.merged(with: upperBounds)
                ?? upperBounds
        }
        let interiorLower = max(
            angleRange.lower,
            lowerAngle + lowerWidth
        )
        let interiorUpper = min(
            angleRange.upper,
            upperAngle - upperWidth
        )
        if interiorUpper > interiorLower {
            let interiorBounds = try Self.interiorFactorBounds(
                lower: interiorLower,
                upper: interiorUpper,
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                endpointResidualMagnitude: max(
                    abs(lowerResidual),
                    abs(upperResidual)
                ),
                firstDerivativeBound: regularizedFirst,
                secondDerivativeBound: rawSecond,
                thirdDerivativeBound: rawThird,
                arithmeticEnvelope: arithmeticEnvelope,
                configuration: configuration,
                tolerance: tolerance
            )
            factorBounds = factorBounds?.merged(with: interiorBounds)
                ?? interiorBounds
        }
        guard let factorBounds else {
            throw Self.resourceFailure(
                residual: angleRange.upper - angleRange.lower,
                tolerance: tolerance,
                message: "Cylinder-cylinder localized factor certification produced no angular interval."
            )
        }
        guard factorBounds.lower > 0.0,
              factorBounds.upper.isFinite,
              factorBounds.first.isFinite,
              factorBounds.second.isFinite else {
            throw Self.resourceFailure(
                residual: factorBounds.lower,
                tolerance: tolerance,
                message: "Cylinder-cylinder regularized radicand factor lacks a finite positive certificate."
            )
        }

        let rootLower = sqrt(
            (
                factorBounds.lower
                    / configuration.projectedAxisSquaredLength.nextUp
            ).nextDown
        ).nextDown
        let rootUpper = sqrt(
            (
                factorBounds.upper
                    / projectedAxisSquaredLengthLower
            ).nextUp
        ).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                residual: rootLower,
                tolerance: tolerance,
                message: "Cylinder-cylinder regularized square-root factor lost its positive margin."
            )
        }
        let rootFirst = (
            factorBounds.first / Self.lowerProduct(
                2.0,
                Self.lowerProduct(
                    projectedAxisSquaredLengthLower,
                    rootLower
                )
            )
        ).nextUp
        let rootSecond = Self.upperSum(
            (
                factorBounds.second / Self.lowerProduct(
                    2.0,
                    Self.lowerProduct(
                        projectedAxisSquaredLengthLower,
                        rootLower
                    )
                )
            ).nextUp,
            (
                Self.upperProduct(factorBounds.first, factorBounds.first)
                    / Self.lowerProduct(
                        4.0,
                        Self.lowerProduct(
                            Self.lowerProduct(
                                projectedAxisSquaredLengthLower,
                                projectedAxisSquaredLengthLower
                            ),
                            Self.lowerProduct(
                                rootLower,
                                Self.lowerProduct(rootLower, rootLower)
                            )
                        )
                    )
            ).nextUp
        )

        let phaseScale = (2.0 * Double.pi).nextUp
        let phaseScaleSquared = Self.upperProduct(phaseScale, phaseScale)
        let phaseRange = (
            lower: 2.0 * Double.pi * lowerFraction,
            upper: 2.0 * Double.pi * upperFraction
        )
        let sineMagnitude = Self.maximumAbsoluteSine(
            lower: phaseRange.lower,
            upper: phaseRange.upper
        )
        let cosineMagnitude = Self.maximumAbsoluteCosine(
            lower: phaseRange.lower,
            upper: phaseRange.upper
        )
        let angleFirst = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScale),
            sineMagnitude
        )
        let angleSecond = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleSquared),
            cosineMagnitude
        )
        let rootCurveFirst = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScale),
            Self.upperSum(
                Self.upperProduct(cosineMagnitude, rootUpper),
                Self.upperProduct(
                    Self.upperProduct(
                        halfSpan,
                        Self.upperProduct(
                            sineMagnitude,
                            sineMagnitude
                        )
                    ),
                    rootFirst
                )
            )
        )
        let rootCurveSecond = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleSquared),
            Self.upperSum(
                Self.upperProduct(sineMagnitude, rootUpper),
                Self.upperSum(
                    Self.upperProduct(
                        Self.upperProduct(
                            3.0 * halfSpan,
                            Self.upperProduct(
                                sineMagnitude,
                                cosineMagnitude
                            )
                        ),
                        rootFirst
                    ),
                    Self.upperProduct(
                        Self.upperProduct(
                            Self.upperProduct(halfSpan, halfSpan),
                            Self.upperProduct(
                                Self.upperProduct(
                                    sineMagnitude,
                                    sineMagnitude
                                ),
                                sineMagnitude
                            )
                        ),
                        rootSecond
                    )
                )
            )
        )
        let linearScale = (
            configuration.linearAmplitude / projectedAxisSquaredLengthLower
        ).nextUp
        let heightFirst = Self.upperSum(
            Self.upperProduct(linearScale, angleFirst),
            rootCurveFirst
        )
        let heightSecond = Self.upperSum(
            Self.upperProduct(
                linearScale,
                Self.upperSum(
                    Self.upperProduct(angleFirst, angleFirst),
                    angleSecond
                )
            ),
            rootCurveSecond
        )
        let first = Self.upperSum(
            Self.upperProduct(configuration.parameterized.radius, angleFirst),
            heightFirst
        )
        let second = Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    configuration.parameterized.radius,
                    Self.upperProduct(angleFirst, angleFirst)
                ),
                Self.upperProduct(
                    configuration.parameterized.radius,
                    angleSecond
                )
            ),
            heightSecond
        )
        guard first.isFinite, second.isFinite else {
            throw Self.resourceFailure(
                residual: nil,
                tolerance: tolerance,
                message: "Cylinder-cylinder bounded-branch spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp
        )
    }

    private func angleDifferential(at fraction: Double) -> ScalarDifferential {
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
        }
    }

    private func composedProjection(
        offset: Vector3D,
        tangent: Vector3D,
        secondTangent: Vector3D,
        direction: Vector3D,
        angle: ScalarDifferential
    ) -> ScalarDifferential {
        let angularFirst = tangent.dot(direction)
        return ScalarDifferential(
            value: offset.dot(direction),
            first: angularFirst * angle.first,
            second: secondTangent.dot(direction) * angle.first * angle.first
                + angularFirst * angle.second
        )
    }

    private func boundedSignedSquareRootDifferential(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let factor = try regularizedFactorDifferential(
            at: angle.value,
            configuration: configuration,
            tolerance: tolerance
        )
        let projectedAxisSquaredLength =
            configuration.projectedAxisSquaredLength
        let normalizedFactor = factor.value / projectedAxisSquaredLength
        guard normalizedFactor > 0.0, normalizedFactor.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: normalizedFactor,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder component lost its positive regularized radicand factor."
            )
        }
        let root = sqrt(normalizedFactor)
        let rootFirst = factor.first
            / (2.0 * projectedAxisSquaredLength * root)
        let rootSecond = factor.second
                / (2.0 * projectedAxisSquaredLength * root)
            - factor.first * factor.first
                / (
                    4.0
                        * projectedAxisSquaredLength
                        * projectedAxisSquaredLength
                        * root * root * root
                )
        guard rootFirst.isFinite, rootSecond.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder regularized factor exceeded finite square-root differentiation."
            )
        }

        let phaseScale = 2.0 * Double.pi
        let phase = phaseScale * fraction
        let sine = sin(phase)
        let sineFirst = phaseScale * cos(phase)
        let sineSecond = -phaseScale * phaseScale * sine
        let rootFractionFirst = rootFirst * angle.first
        let rootFractionSecond = rootSecond * angle.first * angle.first
            + rootFirst * angle.second
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        return ScalarDifferential(
            value: halfSpan * sine * root,
            first: halfSpan * (
                sineFirst * root
                    + sine * rootFractionFirst
            ),
            second: halfSpan * (
                sineSecond * root
                    + 2.0 * sineFirst * rootFractionFirst
                    + sine * rootFractionSecond
            )
        )
    }

    private func regularizedFactorDifferential(
        at angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let span = upperAngle - lowerAngle
        let lowerDistance = angle - lowerAngle
        let upperDistance = upperAngle - angle
        guard span > 0.0,
              lowerDistance >= -tolerance.angle,
              upperDistance >= -tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: min(lowerDistance, upperDistance),
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder factor was evaluated outside its certified angular component."
            )
        }
        let lowerResidual = configuration.radicand(at: lowerAngle)
        let upperResidual = configuration.radicand(at: upperAngle)
        let correctionSlope = (upperResidual - lowerResidual) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let distance = max(
            usesLowerEndpoint ? lowerDistance : upperDistance,
            0.0
        )
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let midpoint = usesLowerEndpoint
            ? endpoint + distance * 0.5
            : endpoint - distance * 0.5
        let sineQuotient = Self.halfAngleSineQuotient(distance)
        let cosineCoefficient = configuration.signedDistanceCosine
        let sineCoefficient = configuration.signedDistanceSine
        let multiplier: ScalarDifferential
        if usesLowerEndpoint {
            multiplier = ScalarDifferential(
                value: -2.0 * cosineCoefficient * sin(midpoint)
                    + 2.0 * sineCoefficient * cos(midpoint),
                first: -cosineCoefficient * cos(midpoint)
                    - sineCoefficient * sin(midpoint),
                second: 0.5 * cosineCoefficient * sin(midpoint)
                    - 0.5 * sineCoefficient * cos(midpoint)
            )
        } else {
            multiplier = ScalarDifferential(
                value: 2.0 * cosineCoefficient * sin(midpoint)
                    - 2.0 * sineCoefficient * cos(midpoint),
                first: -cosineCoefficient * cos(midpoint)
                    - sineCoefficient * sin(midpoint),
                second: -0.5 * cosineCoefficient * sin(midpoint)
                    + 0.5 * sineCoefficient * cos(midpoint)
            )
        }
        let distanceDifferenceQuotient = Self.product(
            multiplier,
            sineQuotient
        )

        let evaluatedDistance = configuration.signedDistance(at: angle)
        let endpointDistance = configuration.signedDistance(at: endpoint)
        let distanceFirst = configuration.signedDistanceFirstDerivative(
            at: angle
        ) * (usesLowerEndpoint ? 1.0 : -1.0)
        let distanceSecond = configuration.signedDistanceSecondDerivative(
            at: angle
        )
        let distanceSum = ScalarDifferential(
            value: evaluatedDistance + endpointDistance,
            first: distanceFirst,
            second: distanceSecond
        )
        let radicandDifferenceQuotient = Self.product(
            distanceDifferenceQuotient,
            distanceSum
        ).scaled(by: -1.0)
        let numerator = radicandDifferenceQuotient.adding(
            ScalarDifferential(
                value: usesLowerEndpoint
                    ? -correctionSlope
                    : correctionSlope,
                first: 0.0,
                second: 0.0
            )
        )
        let oppositeDistance = span - distance
        guard oppositeDistance > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: oppositeDistance,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder factor lost its opposite-endpoint denominator."
            )
        }
        let inverse = 1.0 / oppositeDistance
        let firstWithRespectToDistance = numerator.first * inverse
            + numerator.value * inverse * inverse
        let secondWithRespectToDistance = numerator.second * inverse
            + 2.0 * numerator.first * inverse * inverse
            + 2.0 * numerator.value * inverse * inverse * inverse
        let result = ScalarDifferential(
            value: numerator.value * inverse,
            first: usesLowerEndpoint
                ? firstWithRespectToDistance
                : -firstWithRespectToDistance,
            second: secondWithRespectToDistance
        )
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder divided difference exceeded finite arithmetic."
            )
        }
        return result
    }

    private static func halfAngleSineQuotient(
        _ value: Double
    ) -> ScalarDifferential {
        if abs(value) <= 0.25 {
            var result = ScalarDifferential(
                value: 0.0,
                first: 0.0,
                second: 0.0
            )
            var coefficient = 0.5
            for index in 0...12 {
                let exponent = index * 2
                let valueTerm = coefficient
                    * pow(value, Double(exponent))
                let firstTerm = exponent == 0
                    ? 0.0
                    : coefficient * Double(exponent)
                        * pow(value, Double(exponent - 1))
                let secondTerm = exponent < 2
                    ? 0.0
                    : coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(value, Double(exponent - 2))
                result = result.adding(ScalarDifferential(
                    value: valueTerm,
                    first: firstTerm,
                    second: secondTerm
                ))
                let firstFactor = Double(2 * index + 2)
                let secondFactor = Double(2 * index + 3)
                coefficient /= -4.0 * firstFactor * secondFactor
            }
            return result
        }
        let half = value * 0.5
        let sine = sin(half)
        let cosine = cos(half)
        return ScalarDifferential(
            value: sine / value,
            first: (0.5 * value * cosine - sine) / (value * value),
            second: -0.25 * sine / value
                - cosine / (value * value)
                + 2.0 * sine / (value * value * value)
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
                + first.value * second.second
        )
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let algebraicTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        ) / configuration.projectedAxisSquaredLength
        let branchSign: Double
        switch componentKind {
        case .negativeFullBranch:
            branchSign = -1.0
        case .positiveFullBranch:
            branchSign = 1.0
        case .boundedAngularInterval:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder component requires endpoint-regularized square-root evaluation."
            )
        }
        guard radicand.value >= -algebraicTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -radicand.value,
                tolerance: tolerance,
                message: "A cylinder-cylinder evaluator left its certified non-negative radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A cylinder-cylinder square-root differential is singular."
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

    private static func makeConfiguration(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try referenceSurface.validate(tolerance: tolerance)
        try parameterizedSurface.validate(tolerance: tolerance)
        guard case let .cylinder(referenceCanonical) = CanonicalAnalyticSurface(referenceSurface),
              case let .cylinder(parameterizedCanonical) = CanonicalAnalyticSurface(parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cylinder-cylinder curve requires two exact cylinder surfaces."
            )
        }
        let reference = try canonicalCylinder(referenceCanonical, tolerance: tolerance)
        let parameterized = try canonicalCylinder(
            parameterizedCanonical,
            tolerance: tolerance
        )
        let axisCross = parameterized.axis.cross(reference.axis)
        guard axisCross.length > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cylinder-cylinder curve requires non-parallel axes."
            )
        }
        let normal = try axisCross.normalized(tolerance: tolerance.angle)
        let projectedAxis = parameterized.axis
            - reference.axis * parameterized.axis.dot(reference.axis)
        let projectedAxisSquaredLength = projectedAxis.dot(projectedAxis)
        guard projectedAxisSquaredLength > tolerance.angle * tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: projectedAxisSquaredLength,
                tolerance: tolerance,
                message: "A certified cylinder-cylinder generator solve is singular."
            )
        }
        let centerOffset = parameterized.origin - reference.origin
        let zeroPoint = try parameterized.surface.point(
            u: 0.0,
            v: 0.0,
            tolerance: tolerance
        )
        let quarterPoint = try parameterized.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        return Configuration(
            reference: reference,
            parameterized: parameterized,
            normal: normal,
            projectedAxis: projectedAxis,
            projectedAxisSquaredLength: projectedAxisSquaredLength,
            signedDistanceCenter: centerOffset.dot(normal),
            signedDistanceCosine: (zeroPoint - parameterized.origin).dot(normal),
            signedDistanceSine: (quarterPoint - parameterized.origin).dot(normal),
            linearCenter: centerOffset.dot(projectedAxis),
            linearCosine: (zeroPoint - parameterized.origin).dot(projectedAxis),
            linearSine: (quarterPoint - parameterized.origin).dot(projectedAxis)
        )
    }

    private static func canonicalCylinder(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Cylinder {
        var axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        let originVector = cylinder.origin - .origin
        let origin = cylinder.origin + axis * -originVector.dot(axis)
        return Cylinder(origin: origin, axis: axis, radius: cylinder.radius)
    }

    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.signedDistanceAmplitude
        let numericalThreshold = max(
            Double.ulpOfOne * configuration.characteristicLength * 64.0,
            tolerance.distance * 1.0e-6
        )
        guard amplitude > numericalThreshold else { return [] }
        var values = angles(
            target: configuration.reference.radius,
            center: configuration.signedDistanceCenter,
            cosine: configuration.signedDistanceCosine,
            sine: configuration.signedDistanceSine,
            amplitude: amplitude,
            tolerance: tolerance
        )
        values.append(contentsOf: angles(
            target: -configuration.reference.radius,
            center: configuration.signedDistanceCenter,
            cosine: configuration.signedDistanceCosine,
            sine: configuration.signedDistanceSine,
            amplitude: amplitude,
            tolerance: tolerance
        ))
        let canonicalValues = values.map { value in
            refinedBoundaryAngle(
                value,
                configuration: configuration,
                tolerance: tolerance
            )
        }.map { value in
            abs(value - 2.0 * Double.pi) <= tolerance.angle ? 0.0 : value
        }.sorted()
        var result: [Double] = []
        for value in canonicalValues where
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

    private static func angles(
        target: Double,
        center: Double,
        cosine: Double,
        sine: Double,
        amplitude: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let ratio = (target - center) / amplitude
        let ratioTolerance = tolerance.distance / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let clamped = min(max(ratio, -1.0), 1.0)
        let phase = atan2(sine, cosine)
        let offset = acos(clamped)
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
        let maximumAbsoluteDistance = max(
            abs(configuration.signedDistanceCenter
                - configuration.signedDistanceAmplitude),
            abs(configuration.signedDistanceCenter
                + configuration.signedDistanceAmplitude)
        )
        return configuration.reference.radius * configuration.reference.radius
            - maximumAbsoluteDistance * maximumAbsoluteDistance
    }

    private static func maximumRadicand(configuration: Configuration) -> Double {
        let lower = configuration.signedDistanceCenter
            - configuration.signedDistanceAmplitude
        let upper = configuration.signedDistanceCenter
            + configuration.signedDistanceAmplitude
        let minimumAbsoluteDistance: Double
        if lower <= 0.0, upper >= 0.0 {
            minimumAbsoluteDistance = 0.0
        } else {
            minimumAbsoluteDistance = min(abs(lower), abs(upper))
        }
        return configuration.reference.radius * configuration.reference.radius
            - minimumAbsoluteDistance * minimumAbsoluteDistance
    }

    private static func boundedAngleRange(
        lowerFraction: Double,
        upperFraction: Double,
        lowerAngle: Double,
        upperAngle: Double
    ) -> (lower: Double, upper: Double) {
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        let lowerPhase = 2.0 * Double.pi * lowerFraction
        let upperPhase = 2.0 * Double.pi * upperFraction
        var values = [
            midpoint - halfSpan * cos(lowerPhase),
            midpoint - halfSpan * cos(upperPhase),
        ]
        for index in 0...2 {
            let phase = Double(index) * Double.pi
            if phase > lowerPhase, phase < upperPhase {
                values.append(midpoint - halfSpan * cos(phase))
            }
        }
        return (
            lower: values.min() ?? lowerAngle,
            upper: values.max() ?? upperAngle
        )
    }

    private static func maximumAbsoluteSine(
        lower: Double,
        upper: Double
    ) -> Double {
        maximumAbsoluteTrigonometricValue(
            lower: lower,
            upper: upper,
            offset: Double.pi * 0.5
        )
    }

    private static func maximumAbsoluteCosine(
        lower: Double,
        upper: Double
    ) -> Double {
        maximumAbsoluteTrigonometricValue(
            lower: lower,
            upper: upper,
            offset: 0.0
        )
    }

    private static func maximumAbsoluteTrigonometricValue(
        lower: Double,
        upper: Double,
        offset: Double
    ) -> Double {
        var result = max(
            abs(cos(lower - offset)),
            abs(cos(upper - offset))
        )
        for index in -2...4 {
            let extremum = offset + Double(index) * Double.pi
            if extremum > lower, extremum < upper {
                result = 1.0
                break
            }
        }
        return result.nextUp
    }

    private static func endpointProofWidth(
        span: Double,
        endpointSlope: Double,
        secondDerivativeBound: Double
    ) -> Double {
        guard secondDerivativeBound > Double.leastNonzeroMagnitude else {
            return (span * 0.25).nextDown
        }
        return min(
            (span * 0.25).nextDown,
            (endpointSlope / (secondDerivativeBound * 4.0)).nextDown
        )
    }

    private static func endpointFactorBounds(
        span: Double,
        width: Double,
        endpointSlope: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    ) throws -> RegularizedFactorBounds {
        let denominatorLower = (span - width).nextDown
        let averagedSlopeLower = (
            endpointSlope
                - upperProduct(secondDerivativeBound, width)
                - arithmeticEnvelope
        ).nextDown
        guard width > 0.0,
              denominatorLower > 0.0,
              averagedSlopeLower > 0.0 else {
            throw resourceFailure(
                residual: min(width, denominatorLower, averagedSlopeLower),
                tolerance: tolerance,
                message: "Cylinder-cylinder endpoint factor certification lost its positive divided-difference margin."
            )
        }
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        let lower = (
            averagedSlopeLower / span.nextUp
        ).nextDown
        let upper = (
            firstDerivativeBound / denominatorLower
        ).nextUp
        let first = upperSum(
            (
                (secondDerivativeBound * 0.5).nextUp
                    / denominatorLower
            ).nextUp,
            (
                firstDerivativeBound / denominatorSquared
            ).nextUp
        )
        let second = upperSum(
            (
                (thirdDerivativeBound / 3.0).nextUp
                    / denominatorLower
            ).nextUp,
            upperSum(
                (
                    secondDerivativeBound / denominatorSquared
                ).nextUp,
                (
                    upperProduct(2.0, firstDerivativeBound)
                        / denominatorCubed
                ).nextUp
            )
        )
        return RegularizedFactorBounds(
            lower: lower,
            upper: upper,
            first: first,
            second: second
        )
    }

    private static func endpointDerivativeFactorBounds(
        span: Double,
        width: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double
    ) -> RegularizedFactorBounds? {
        let denominatorLower = (span - width).nextDown
        guard width >= 0.0, denominatorLower > 0.0 else {
            return nil
        }
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        return RegularizedFactorBounds(
            lower: .infinity,
            upper: (
                firstDerivativeBound / denominatorLower
            ).nextUp,
            first: upperSum(
                (
                    (secondDerivativeBound * 0.5).nextUp
                        / denominatorLower
                ).nextUp,
                (
                    firstDerivativeBound / denominatorSquared
                ).nextUp
            ),
            second: upperSum(
                (
                    (thirdDerivativeBound / 3.0).nextUp
                        / denominatorLower
                ).nextUp,
                upperSum(
                    (
                        secondDerivativeBound / denominatorSquared
                    ).nextUp,
                    (
                        upperProduct(2.0, firstDerivativeBound)
                            / denominatorCubed
                    ).nextUp
                )
            )
        )
    }

    private static func interiorFactorBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        endpointResidualMagnitude: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> RegularizedFactorBounds {
        let span = componentUpper - componentLower
        var cellLower = lower
        var result: RegularizedFactorBounds?
        var remainingCells = 2_048
        while cellLower < upper {
            guard remainingCells > 0 else {
                throw resourceFailure(
                    residual: upper - cellLower,
                    tolerance: tolerance,
                    message: "Cylinder-cylinder regularized factor subdivision exceeded its cell budget."
                )
            }
            remainingCells -= 1
            let offset = cellLower - componentLower
            let endpointDistance = min(offset, span - offset)
            let step = max(
                endpointDistance * 0.25,
                Double.ulpOfOne * max(span, 1.0) * 4_096.0
            )
            let cellUpper = min(cellLower + step, upper)
            let cell = try interiorFactorCellBounds(
                lower: cellLower,
                upper: cellUpper,
                componentLower: componentLower,
                componentUpper: componentUpper,
                endpointResidualMagnitude: endpointResidualMagnitude,
                firstDerivativeBound: firstDerivativeBound,
                secondDerivativeBound: secondDerivativeBound,
                thirdDerivativeBound: thirdDerivativeBound,
                arithmeticEnvelope: arithmeticEnvelope,
                configuration: configuration,
                tolerance: tolerance
            )
            result = result?.merged(with: cell) ?? cell
            cellLower = cellUpper
        }
        guard let result else {
            throw resourceFailure(
                residual: upper - lower,
                tolerance: tolerance,
                message: "Cylinder-cylinder regularized factor subdivision produced no cells."
            )
        }
        return result
    }

    private static func interiorFactorCellBounds(
        lower: Double,
        upper: Double,
        componentLower: Double,
        componentUpper: Double,
        endpointResidualMagnitude: Double,
        firstDerivativeBound: Double,
        secondDerivativeBound: Double,
        thirdDerivativeBound: Double,
        arithmeticEnvelope: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> RegularizedFactorBounds {
        let span = componentUpper - componentLower
        let lowerOffset = lower - componentLower
        let upperOffset = upper - componentLower
        let lowerDenominator = lowerProduct(
            lowerOffset,
            span - lowerOffset
        )
        let upperDenominator = lowerProduct(
            upperOffset,
            span - upperOffset
        )
        let denominatorLower = min(
            lowerDenominator,
            upperDenominator
        ).nextDown
        let denominatorUpper: Double
        if lowerOffset <= span * 0.5, upperOffset >= span * 0.5 {
            denominatorUpper = (
                upperProduct(span, span) * 0.25
            ).nextUp
        } else {
            denominatorUpper = max(
                lowerOffset * (span - lowerOffset),
                upperOffset * (span - upperOffset)
            ).nextUp
        }
        let rawLower = (
            minimumRadicand(
                lower: lower,
                upper: upper,
                configuration: configuration
            )
                - endpointResidualMagnitude
                - arithmeticEnvelope
        ).nextDown
        guard denominatorLower > 0.0,
              denominatorUpper > 0.0,
              rawLower > 0.0 else {
            throw resourceFailure(
                residual: min(
                    denominatorLower,
                    denominatorUpper,
                    rawLower
                ),
                tolerance: tolerance,
                message: "Cylinder-cylinder interior factor certification lost its positive radicand margin."
            )
        }
        let rawUpper = maximumRadicand(
            lower: lower,
            upper: upper,
            configuration: configuration
        )
        let valueUpper = upperSum(
            upperSum(rawUpper, endpointResidualMagnitude),
            arithmeticEnvelope
        )
        let denominatorSquared = lowerProduct(
            denominatorLower,
            denominatorLower
        )
        let denominatorCubed = lowerProduct(
            denominatorSquared,
            denominatorLower
        )
        let lowerFactor = (
            rawLower / denominatorUpper
        ).nextDown
        let directUpperFactor = (
            valueUpper / denominatorLower
        ).nextUp
        let directFirstFactor = upperSum(
            (
                firstDerivativeBound / denominatorLower
            ).nextUp,
            (
                upperProduct(valueUpper, span) / denominatorSquared
            ).nextUp
        )
        let directSecondFactor = upperSum(
            (
                secondDerivativeBound / denominatorLower
            ).nextUp,
            upperSum(
                (
                    upperProduct(2.0, valueUpper)
                        / denominatorSquared
                ).nextUp,
                upperSum(
                    (
                        upperProduct(
                            2.0,
                            upperProduct(firstDerivativeBound, span)
                        ) / denominatorSquared
                    ).nextUp,
                    (
                        upperProduct(
                            2.0,
                            upperProduct(
                                valueUpper,
                                upperProduct(span, span)
                            )
                        ) / denominatorCubed
                    ).nextUp
                )
            )
        )
        let lowerEndpoint = endpointDerivativeFactorBounds(
            span: span,
            width: upperOffset,
            firstDerivativeBound: firstDerivativeBound,
            secondDerivativeBound: secondDerivativeBound,
            thirdDerivativeBound: thirdDerivativeBound
        )
        let upperEndpoint = endpointDerivativeFactorBounds(
            span: span,
            width: span - lowerOffset,
            firstDerivativeBound: firstDerivativeBound,
            secondDerivativeBound: secondDerivativeBound,
            thirdDerivativeBound: thirdDerivativeBound
        )
        let derivativeCertificates = [
            lowerEndpoint,
            upperEndpoint,
        ].compactMap { $0 }
        let upperFactor = derivativeCertificates.reduce(
            directUpperFactor
        ) {
            min($0, $1.upper)
        }.nextUp
        let firstFactor = derivativeCertificates.reduce(
            directFirstFactor
        ) {
            min($0, $1.first)
        }.nextUp
        let secondFactor = derivativeCertificates.reduce(
            directSecondFactor
        ) {
            min($0, $1.second)
        }.nextUp
        return RegularizedFactorBounds(
            lower: lowerFactor,
            upper: upperFactor,
            first: firstFactor,
            second: secondFactor
        )
    }

    private static func minimumRadicand(
        lower: Double,
        upper: Double,
        configuration: Configuration
    ) -> Double {
        var angles = [lower, upper]
        let phase = atan2(
            configuration.signedDistanceSine,
            configuration.signedDistanceCosine
        )
        for halfTurn in -4...8 {
            let angle = phase + Double(halfTurn) * Double.pi
            if angle > lower, angle < upper {
                angles.append(angle)
            }
        }
        let maximumAbsoluteDistance = angles.map {
            abs(configuration.signedDistance(at: $0))
        }.max() ?? .infinity
        return (
            configuration.reference.radius * configuration.reference.radius
                - maximumAbsoluteDistance * maximumAbsoluteDistance
        ).nextDown
    }

    private static func maximumRadicand(
        lower: Double,
        upper: Double,
        configuration: Configuration
    ) -> Double {
        var angles = [lower, upper]
        let phase = atan2(
            configuration.signedDistanceSine,
            configuration.signedDistanceCosine
        )
        for halfTurn in -4...8 {
            let angle = phase + Double(halfTurn) * Double.pi
            if angle > lower, angle < upper {
                angles.append(angle)
            }
        }
        let amplitude = configuration.signedDistanceAmplitude
        if amplitude > Double.leastNonzeroMagnitude {
            let ratio = -configuration.signedDistanceCenter / amplitude
            if ratio >= -1.0, ratio <= 1.0 {
                let offset = acos(min(max(ratio, -1.0), 1.0))
                for turn in -2...4 {
                    let base = phase + Double(turn) * 2.0 * Double.pi
                    for angle in [base - offset, base + offset]
                        where angle > lower && angle < upper {
                        angles.append(angle)
                    }
                }
            }
        }
        let minimumAbsoluteDistance = angles.map {
            abs(configuration.signedDistance(at: $0))
        }.min() ?? 0.0
        return (
            configuration.reference.radius * configuration.reference.radius
                - minimumAbsoluteDistance * minimumAbsoluteDistance
        ).nextUp
    }

    private static func resourceFailure(
        residual: Double?,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private static func upperSum(_ first: Double, _ second: Double) -> Double {
        (first + second).nextUp
    }

    private static func upperProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextUp
    }

    private static func lowerProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextDown
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
        guard componentKind == .boundedAngularInterval else {
            return machineBound
        }
        let rootResidual = max(
            abs(configuration.radicand(at: lowerAngle)),
            abs(configuration.radicand(at: upperAngle))
        )
        let endpointClosureBound = sqrt(
            rootResidual / configuration.projectedAxisSquaredLength
        )
        let result = endpointClosureBound + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Cylinder-cylinder boundary roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = configuration.characteristicLength
        return max(
            Double.ulpOfOne * scale * scale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private static func refinedBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0
        )
        for _ in 0..<64 {
            let value = configuration.radicand(at: angle)
            if abs(value) <= proofResidualTolerance { break }
            let derivative = configuration.radicandFirstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle else { break }
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

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case referenceSurface
        case parameterizedSurface
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
                .referenceSurface,
                .parameterizedSurface,
                .componentKind,
                .lowerAngle,
                .upperAngle,
                .certificationTolerance,
                .maximumResidualUpperBound,
            ],
            in: decoder
        )
        let referenceSurface = try container.decode(
            Surface3D.self,
            forKey: .referenceSurface
        )
        let parameterizedSurface = try container.decode(
            Surface3D.self,
            forKey: .parameterizedSurface
        )
        let componentKind = try container.decode(
            ComponentKind.self,
            forKey: .componentKind
        )
        let lowerAngle = try container.decode(Double.self, forKey: .lowerAngle)
        let upperAngle = try container.decode(Double.self, forKey: .upperAngle)
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        try self.init(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
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
                debugDescription: "The cylinder-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceSurface, forKey: .referenceSurface)
        try container.encode(parameterizedSurface, forKey: .parameterizedSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
