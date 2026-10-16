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

public struct CertifiedCylinderCylinderIntersectionCurve: Hashable, Sendable {
    public enum ComponentKind: String, Hashable, Sendable {
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

    private struct HeightDifferentialMagnitudeBounds {
        let first: Double
        let second: Double
        let third: Double
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        self.referenceSurface = referenceSurface
        self.parameterizedSurface = parameterizedSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance,
            using: &execution)
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        try validate(tolerance: tolerance, using: &execution)
            try execution.checkpoint()
    }

    private func validateImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
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
                message: "A cylinder-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance,
            using: &execution)
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
        let boundaries = try Self.boundaryAngles(
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let minimumRadicand = try Self.minimumRadicand(configuration: configuration, using: &execution)
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
            let validIntervals = try Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                using: &execution)
            let matchesCompleteInterval = try validIntervals.contains { interval in
                try execution.consumeWork(1)
                return abs(interval.lower - lowerAngle) <= tolerance.angle
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
            tolerance: tolerance,
            using: &execution)
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
        try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance,
                using: &execution)
            let firstProjection = try referenceSurface.parameterProjection(
                of: point,
                tolerance: tolerance,
                using: &execution)
            let secondProjection = try parameterizedSurface.parameterProjection(
                of: point,
                tolerance: tolerance,
                using: &execution)
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

    private func pointImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            using: &execution).position
    }

    private func differentialImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            tolerance: tolerance,
            using: &execution)
        let angle = angleDifferential(at: normalizedFraction)
        let baseGeometry = try configuration.parameterized.surface.differentialGeometry(
            u: angle.value,
            v: 0.0,
            tolerance: tolerance,
            using: &execution)
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
                tolerance: tolerance,
                using: &execution)
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
                tolerance: tolerance,
                using: &execution)
        }
        let height = linear
            .scaled(by: -inverseProjectedAxisSquaredLength)
            .adding(signedRoot)
        let surfaceGeometry = try configuration.parameterized.surface.differentialGeometry(
            u: angle.value,
            v: height.value,
            tolerance: tolerance,
            using: &execution)
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

    private func thirdDerivativeImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance,
            using: &execution)
        let source = CurveTaylorScalarJet.variable(clamped)
        let angle = angleTaylorJet(at: source)
        let linear = CurveTaylorScalarJet(value: configuration.linearCenter)
            + angle.cosine().scaled(by: configuration.linearCosine)
            + angle.sine().scaled(by: configuration.linearSine)
        let root = try signedSquareRootTaylorJet(
            angle: angle,
            fraction: source,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let inverseProjectedAxisSquaredLength = 1.0
            / configuration.projectedAxisSquaredLength
        let height = linear.scaled(by: -inverseProjectedAxisSquaredLength)
            + root
        let surface = try configuration.parameterized.surface
            .parameterDerivativesThroughThirdOrder(
                u: angle.value,
                v: height.value,
                tolerance: tolerance,
                using: &execution)
        let firstParameter = Point2D(
            x: angle.firstDerivative,
            y: height.firstDerivative
        )
        let secondParameter = Point2D(
            x: angle.secondDerivative,
            y: height.secondDerivative
        )
        let thirdParameter = Point2D(
            x: angle.thirdDerivative,
            y: height.thirdDerivative
        )
        let lower = try differential(
            atNormalizedFraction: clamped,
            tolerance: tolerance,
            using: &execution)
        let reconstructedFirst = SurfaceParameterThirdOrderChainRule.firstDerivative(
            surface: surface,
            parameter: firstParameter
        )
        let reconstructedSecond = SurfaceParameterThirdOrderChainRule.secondDerivative(
            surface: surface,
            firstParameterDerivative: firstParameter,
            secondParameterDerivative: secondParameter
        )
        let firstScale = max(lower.firstDerivative.length, 1.0)
        let secondScale = max(lower.secondDerivative.length, 1.0)
        let residual = max(
            (reconstructedFirst - lower.firstDerivative).length / firstScale,
            (reconstructedSecond - lower.secondDerivative).length / secondScale
        )
        guard residual <= tolerance.relative * 64.0 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Cylinder-cylinder Taylor differentiation disagrees with the certified lower-order differential."
            )
        }
        return SurfaceParameterThirdOrderChainRule.thirdDerivative(
            surface: surface,
            firstParameterDerivative: firstParameter,
            secondParameterDerivative: secondParameter,
            thirdParameterDerivative: thirdParameter)
    }

    private func parameterImplementation(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            using: &execution)
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance,
            using: &execution)
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    private func boundingBoxImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance,
            using: &execution)
        let maximumLinear = abs(configuration.linearCenter)
            + configuration.linearAmplitude
        let maximumRadicand = max(
            try Self.maximumRadicand(configuration: configuration, using: &execution),
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

    private func fullBranchSpatialDifferentialMagnitudeBoundsImplementation(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            tolerance: tolerance,
            using: &execution)
        let height = try fullBranchHeightDifferentialMagnitudeBounds(
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let angularScale = (2.0 * Double.pi).nextUp
        let first = Self.upperProduct(
            angularScale,
            Self.upperSum(configuration.parameterized.radius, height.first)
        )
        let second = Self.upperProduct(
            Self.upperProduct(angularScale, angularScale),
            Self.upperSum(configuration.parameterized.radius, height.second)
        )
        let third = Self.upperProduct(
            Self.upperProduct(
                Self.upperProduct(angularScale, angularScale),
                angularScale
            ),
            Self.upperSum(configuration.parameterized.radius, height.third)
        )
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Cylinder-cylinder full-branch differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp,
            third: third.nextUp
        )
    }

    private func fullBranchHeightDifferentialMagnitudeBounds(
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> HeightDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let minimumRawRadicand = (
            try Self.minimumRadicand(configuration: configuration, using: &execution)
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
        let rawRadicandThird = Self.upperProduct(
            2.0,
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(distanceDerivative, distanceDerivative)
                ),
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
        let normalizedRadicandThird = (
            rawRadicandThird / projectedAxisSquaredLengthLower
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
                ) / Self.lowerProduct(
                    4.0,
                    Self.lowerProduct(
                        rootLower,
                        Self.lowerProduct(rootLower, rootLower)
                    )
                )
            ).nextUp
        )
        let rootCubedLower = Self.lowerProduct(
            rootLower,
            Self.lowerProduct(rootLower, rootLower)
        )
        let rootFifthLower = Self.lowerProduct(
            rootCubedLower,
            Self.lowerProduct(rootLower, rootLower)
        )
        let rootThird = Self.upperSum(
            (
                normalizedRadicandThird
                    / Self.lowerProduct(2.0, rootLower)
            ).nextUp,
            Self.upperSum(
                (
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            normalizedRadicandFirst,
                            normalizedRadicandSecond
                        )
                    ) / Self.lowerProduct(4.0, rootCubedLower)
                ).nextUp,
                (
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            normalizedRadicandFirst,
                            Self.upperProduct(
                                normalizedRadicandFirst,
                                normalizedRadicandFirst
                            )
                        )
                    ) / Self.lowerProduct(8.0, rootFifthLower)
                ).nextUp
            )
        )
        let linearFirst = (
            configuration.linearAmplitude
                / projectedAxisSquaredLengthLower
        ).nextUp
        return HeightDifferentialMagnitudeBounds(
            first: Self.upperSum(linearFirst, rootFirst),
            second: Self.upperSum(linearFirst, rootSecond),
            third: Self.upperSum(linearFirst, rootThird)
        )
    }

    private func parameterizedParameterBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CertifiedCylinderCylinderParameterizedParameterBounds? {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            return nil
        }
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              upperFraction > lowerFraction,
              upperFraction - lowerFraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(upperFraction - lowerFraction)
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance,
            using: &execution)
        let height = try fullBranchHeightDifferentialMagnitudeBounds(
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let period = 2.0 * Double.pi
        let chartZero = try parameter(
            on: parameterizedSurface,
            atNormalizedFraction: 0.0,
            tolerance: tolerance,
            using: &execution).u
        let chartQuarter = try parameter(
            on: parameterizedSurface,
            atNormalizedFraction: 0.25,
            tolerance: tolerance,
            using: &execution).u
        let rawQuarterTurn = chartQuarter - chartZero
        let quarterTurn = rawQuarterTurn
            - round(rawQuarterTurn / period) * period
        let expectedQuarterTurn = Double.pi * 0.5
        guard abs(abs(quarterTurn) - expectedQuarterTurn)
                <= max(tolerance.angle * 16.0, tolerance.relative * 16.0) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: abs(abs(quarterTurn) - expectedQuarterTurn),
                tolerance: tolerance,
                message: "Cylinder-cylinder parameter bounds could not certify the support chart orientation."
            )
        }
        let chartOrientation = quarterTurn >= 0.0 ? 1.0 : -1.0
        let internalAngleLower = period * lowerFraction
        let internalAngleUpper = period * upperFraction
        let chartFirst = chartZero + chartOrientation * internalAngleLower
        let chartSecond = chartZero + chartOrientation * internalAngleUpper
        let angleLower = min(chartFirst, chartSecond).nextDown
        let angleUpper = max(chartFirst, chartSecond).nextUp
        let angleSpan = (
            internalAngleUpper - internalAngleLower
        ).nextUp
        let middleFraction = lowerFraction
            + (upperFraction - lowerFraction) * 0.5
        let remainder = middleFraction.truncatingRemainder(dividingBy: 1.0)
        let canonicalMiddleFraction = remainder >= 0.0
            ? remainder
            : remainder + 1.0
        let middleParameter = try parameter(
            on: parameterizedSurface,
            atNormalizedFraction: canonicalMiddleFraction,
            tolerance: tolerance,
            using: &execution)
        let totalVariationV = Self.upperProduct(height.first, angleSpan)
        let valueRoundoff = (
            Double.ulpOfOne * max(
                abs(middleParameter.v),
                totalVariationV,
                1.0
            ) * 8_192.0
        ).nextUp
        let vRadius = Self.upperSum(totalVariationV * 0.5, valueRoundoff)
        let firstU = angleSpan
        let firstV = totalVariationV
        let secondV = Self.upperProduct(
            height.second,
            Self.upperProduct(angleSpan, angleSpan)
        )
        let thirdV = Self.upperProduct(
            height.third,
            Self.upperProduct(
                angleSpan,
                Self.upperProduct(angleSpan, angleSpan)
            )
        )
        return CertifiedCylinderCylinderParameterizedParameterBounds(
            uLift: try ScalarInterval(lower: angleLower, upper: angleUpper),
            vLift: try ScalarInterval(
                lower: (middleParameter.v - vRadius).nextDown,
                upper: (middleParameter.v + vRadius).nextUp
            ),
            totalVariationU: angleSpan,
            totalVariationV: totalVariationV,
            firstDerivativeMagnitude: hypot(firstU, firstV).nextUp,
            secondDerivativeMagnitude: secondV.nextUp,
            thirdDerivativeMagnitude: thirdV.nextUp
        )
    }

    private func spatialDifferentialMagnitudeBoundsImplementation(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            tolerance: tolerance,
            using: &execution)
    }

    private func spatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              // A bound over any positive stretch holds (an endpoint's enclosure asks for one
              // narrower than the relative tolerance).
              upperFraction > lowerFraction else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return try fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance,
                using: &execution)
        case .boundedAngularInterval:
            return try boundedBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(max(lowerFraction, 0.0), 1.0),
                toNormalizedFraction: min(max(upperFraction, 0.0), 1.0),
                tolerance: tolerance,
                using: &execution)
        }
    }

    private func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            tolerance: tolerance,
            using: &execution)
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
        let rawFourth = Self.upperProduct(
            2.0,
            Self.upperSum(
                Self.upperProduct(
                    7.0,
                    Self.upperProduct(distanceDerivative, distanceDerivative)
                ),
                Self.upperProduct(distanceMagnitude, distanceDerivative)
            )
        )
        let angleRange = try Self.boundedAngleRange(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            using: &execution)
        let factorBounds = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: angleRange.lower,
            requestedUpper: angleRange.upper,
            lowerValue: lowerResidual,
            upperValue: upperResidual,
            lowerDerivative: configuration.radicandFirstDerivative(
                at: lowerAngle
            ),
            upperDerivative: configuration.radicandFirstDerivative(
                at: upperAngle
            ),
            firstDerivativeMagnitudeUpperBound: rawFirst,
            secondDerivativeMagnitudeUpperBound: rawSecond,
            thirdDerivativeMagnitudeUpperBound: rawThird,
            fourthDerivativeMagnitudeUpperBound: rawFourth,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { lower, upper, execution in
                (
                    try Self.minimumRadicand(
                        lower: lower,
                        upper: upper,
                        configuration: configuration,
                        using: &execution),
                    try Self.maximumRadicand(
                        lower: lower,
                        upper: upper,
                        configuration: configuration,
                        using: &execution)
                )
            },
            tolerance: tolerance,
            label: "Cylinder-cylinder bounded branch",
            using: &execution)

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
        let projectedAxisFourth = Self.lowerProduct(
            projectedAxisSquaredLengthLower,
            projectedAxisSquaredLengthLower
        )
        let projectedAxisSixth = Self.lowerProduct(
            projectedAxisFourth,
            projectedAxisSquaredLengthLower
        )
        let rootCubedLower = Self.lowerProduct(
            rootLower,
            Self.lowerProduct(rootLower, rootLower)
        )
        let rootFifthLower = Self.lowerProduct(
            rootCubedLower,
            Self.lowerProduct(rootLower, rootLower)
        )
        let rootThird = Self.upperSum(
            (
                factorBounds.third / Self.lowerProduct(
                    2.0,
                    Self.lowerProduct(
                        projectedAxisSquaredLengthLower,
                        rootLower
                    )
                )
            ).nextUp,
            Self.upperSum(
                (
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            factorBounds.first,
                            factorBounds.second
                        )
                    ) / Self.lowerProduct(
                        4.0,
                        Self.lowerProduct(
                            projectedAxisFourth,
                            rootCubedLower
                        )
                    )
                ).nextUp,
                (
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            factorBounds.first,
                            Self.upperProduct(
                                factorBounds.first,
                                factorBounds.first
                            )
                        )
                    ) / Self.lowerProduct(
                        8.0,
                        Self.lowerProduct(
                            projectedAxisSixth,
                            rootFifthLower
                        )
                    )
                ).nextUp
            )
        )

        let phaseScale = (2.0 * Double.pi).nextUp
        let phaseScaleSquared = Self.upperProduct(phaseScale, phaseScale)
        let phaseScaleCubed = Self.upperProduct(
            phaseScaleSquared,
            phaseScale
        )
        let phaseRange = (
            lower: 2.0 * Double.pi * lowerFraction,
            upper: 2.0 * Double.pi * upperFraction
        )
        let sineMagnitude = try Self.maximumAbsoluteSine(
            lower: phaseRange.lower,
            upper: phaseRange.upper,
            using: &execution)
        let cosineMagnitude = try Self.maximumAbsoluteCosine(
            lower: phaseRange.lower,
            upper: phaseRange.upper,
            using: &execution)
        let angleFirst = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScale),
            sineMagnitude
        )
        let angleSecond = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleSquared),
            cosineMagnitude
        )
        let angleThird = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleCubed),
            sineMagnitude
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
        let rootByFractionFirst = Self.upperProduct(
            rootFirst,
            angleFirst
        )
        let rootByFractionSecond = Self.upperSum(
            Self.upperProduct(
                rootSecond,
                Self.upperProduct(angleFirst, angleFirst)
            ),
            Self.upperProduct(rootFirst, angleSecond)
        )
        let rootByFractionThird = Self.upperSum(
            Self.upperProduct(
                rootThird,
                Self.upperProduct(
                    angleFirst,
                    Self.upperProduct(angleFirst, angleFirst)
                )
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        rootSecond,
                        Self.upperProduct(angleFirst, angleSecond)
                    )
                ),
                Self.upperProduct(rootFirst, angleThird)
            )
        )
        let endpointDistanceMagnitude = Self.upperProduct(
            halfSpan,
            sineMagnitude
        )
        let endpointDistanceFirst = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScale),
            cosineMagnitude
        )
        let endpointDistanceSecond = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleSquared),
            sineMagnitude
        )
        let endpointDistanceThird = Self.upperProduct(
            Self.upperProduct(halfSpan, phaseScaleCubed),
            cosineMagnitude
        )
        let rootCurveThird = Self.upperSum(
            Self.upperProduct(endpointDistanceThird, rootUpper),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        endpointDistanceSecond,
                        rootByFractionFirst
                    )
                ),
                Self.upperSum(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            endpointDistanceFirst,
                            rootByFractionSecond
                        )
                    ),
                    Self.upperProduct(
                        endpointDistanceMagnitude,
                        rootByFractionThird
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
        let angularThirdCombination = Self.upperSum(
            Self.upperProduct(
                angleFirst,
                Self.upperProduct(angleFirst, angleFirst)
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(angleFirst, angleSecond)
                ),
                angleThird
            )
        )
        let heightThird = Self.upperSum(
            Self.upperProduct(linearScale, angularThirdCombination),
            rootCurveThird
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
        let third = Self.upperSum(
            Self.upperProduct(
                configuration.parameterized.radius,
                angularThirdCombination
            ),
            heightThird
        )
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                residual: nil,
                tolerance: tolerance,
                message: "Cylinder-cylinder bounded-branch spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp,
            third: third.nextUp
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

    private func angleTaylorJet(
        at fraction: CurveTaylorScalarJet
    ) -> CurveTaylorScalarJet {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return fraction.scaled(by: period)
        case .boundedAngularInterval:
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            return CurveTaylorScalarJet(value: midpoint)
                - fraction.scaled(by: period).cosine().scaled(by: halfSpan)
        }
    }

    private func signedSquareRootTaylorJet(
        angle: CurveTaylorScalarJet,
        fraction: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Cylinder-cylinder third derivative"
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedFactorTaylorJet(
                angle: angle,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution).scaled(by: 1.0 / configuration.projectedAxisSquaredLength)
            let prefix = fraction.scaled(by: 2.0 * Double.pi).sine()
                .scaled(by: (upperAngle - lowerAngle) * 0.5)
            return try (
                prefix * factor.squareRoot(
                    tolerance: tolerance,
                    diagnosticContext: context
                )
            ).validated(tolerance: tolerance, diagnosticContext: context)
        }
        let signedDistance = CurveTaylorScalarJet(
            value: configuration.signedDistanceCenter
        ) + angle.cosine().scaled(by: configuration.signedDistanceCosine)
            + angle.sine().scaled(by: configuration.signedDistanceSine)
        let radicand = (
            CurveTaylorScalarJet(
                value: configuration.reference.radius
                    * configuration.reference.radius
            ) - signedDistance * signedDistance
        ).scaled(by: 1.0 / configuration.projectedAxisSquaredLength)
        let sign = componentKind == .negativeFullBranch ? -1.0 : 1.0
        return try radicand.squareRoot(
            tolerance: tolerance,
            diagnosticContext: context
        ).scaled(by: sign).validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
    }

    private func regularizedFactorTaylorJet(
        angle: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Cylinder-cylinder regularized radicand"
        let span = upperAngle - lowerAngle
        let usesLowerEndpoint = angle.value - lowerAngle
            <= upperAngle - angle.value
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let distance = usesLowerEndpoint
            ? angle - CurveTaylorScalarJet(value: endpoint)
            : CurveTaylorScalarJet(value: endpoint) - angle
        let midpoint = usesLowerEndpoint
            ? CurveTaylorScalarJet(value: endpoint) + distance.scaled(by: 0.5)
            : CurveTaylorScalarJet(value: endpoint) - distance.scaled(by: 0.5)
        let multiplier: CurveTaylorScalarJet
        if usesLowerEndpoint {
            multiplier = midpoint.sine().scaled(
                by: -2.0 * configuration.signedDistanceCosine
            ) + midpoint.cosine().scaled(
                by: 2.0 * configuration.signedDistanceSine
            )
        } else {
            multiplier = midpoint.sine().scaled(
                by: 2.0 * configuration.signedDistanceCosine
            ) + midpoint.cosine().scaled(
                by: -2.0 * configuration.signedDistanceSine
            )
        }
        let halfAngleSineQuotient = try distance.scaled(by: 0.5).sinc(
            tolerance: tolerance,
            diagnosticContext: context
        ).scaled(by: 0.5)
        let evaluatedDistance = CurveTaylorScalarJet(
            value: configuration.signedDistanceCenter
        ) + angle.cosine().scaled(by: configuration.signedDistanceCosine)
            + angle.sine().scaled(by: configuration.signedDistanceSine)
        let endpointDistance = configuration.signedDistance(at: endpoint)
        let radicandDifferenceQuotient = -(
            multiplier * halfAngleSineQuotient
                * (evaluatedDistance + CurveTaylorScalarJet(value: endpointDistance))
        )
        let lowerResidual = configuration.radicand(at: lowerAngle)
        let upperResidual = configuration.radicand(at: upperAngle)
        let correctionSlope = (upperResidual - lowerResidual) / span
        let numerator = radicandDifferenceQuotient
            + CurveTaylorScalarJet(
                value: usesLowerEndpoint ? -correctionSlope : correctionSlope
            )
        let startDistance = CurveTaylorScalarJet(value: span) - distance
        return try numerator.divided(
            by: startDistance,
            tolerance: tolerance,
            diagnosticContext: context
        ).validated(tolerance: tolerance, diagnosticContext: context)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let factor = try regularizedFactorDifferential(
            at: angle.value,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        let sineQuotient = try Self.halfAngleSineQuotient(distance, using: &execution)
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
        let startDistance = span - distance
        guard startDistance > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: startDistance,
                tolerance: tolerance,
                message: "A bounded cylinder-cylinder factor lost its opposite-endpoint denominator."
            )
        }
        let inverse = 1.0 / startDistance
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
        _ value: Double,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        if abs(value) <= 0.25 {
            var result = ScalarDifferential(
                value: 0.0,
                first: 0.0,
                second: 0.0
            )
            var coefficient = 0.5
            for index in 0...12 {
                try execution.consumeWork(1)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try referenceSurface.validate(tolerance: tolerance, using: &execution)
        try parameterizedSurface.validate(tolerance: tolerance, using: &execution)
        // Canonicalization may traverse the retained offset source chain.
        try GeometryStructuralComparisonWork.charge(surface: referenceSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: parameterizedSurface, using: &execution)
        guard case let .cylinder(referenceCanonical) = CanonicalAnalyticSurface(referenceSurface),
              case let .cylinder(parameterizedCanonical) = CanonicalAnalyticSurface(parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cylinder-cylinder curve requires two exact cylinder surfaces."
            )
        }
        let reference = try canonicalCylinder(referenceCanonical, tolerance: tolerance, using: &execution)
        let parameterized = try canonicalCylinder(
            parameterizedCanonical,
            tolerance: tolerance,
            using: &execution)
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
            tolerance: tolerance,
            using: &execution)
        let quarterPoint = try parameterized.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance,
            using: &execution)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Cylinder {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let amplitude = configuration.signedDistanceAmplitude
        let numericalThreshold = max(
            Double.ulpOfOne * configuration.characteristicLength * 64.0,
            tolerance.distance * 1.0e-6
        )
        guard amplitude > numericalThreshold else { return [] }
        var values = try angles(
            target: configuration.reference.radius,
            center: configuration.signedDistanceCenter,
            cosine: configuration.signedDistanceCosine,
            sine: configuration.signedDistanceSine,
            amplitude: amplitude,
            tolerance: tolerance,
            using: &execution)
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(4, in: &values, using: &execution)
        values.append(contentsOf: try angles(
            target: -configuration.reference.radius,
            center: configuration.signedDistanceCenter,
            cosine: configuration.signedDistanceCosine,
            sine: configuration.signedDistanceSine,
            amplitude: amplitude,
            tolerance: tolerance,
            using: &execution))
        let refined = try CertifiedAnalyticCurveEvaluation.map(values, using: &execution) { value, execution in
            try refinedBoundaryAngle(value, configuration: configuration, tolerance: tolerance, using: &execution)
        }
        let canonical = try CertifiedAnalyticCurveEvaluation.map(refined, using: &execution) { value, _ in
            abs(value - 2.0 * Double.pi) <= tolerance.angle ? 0.0 : value
        }
        let canonicalValues = try CertifiedAnalyticCurveEvaluation.sorted(canonical, using: &execution)
        var result: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(canonicalValues.count, in: &result, using: &execution)
        for value in canonicalValues {
            try execution.consumeWork(1)
            if result.last.map({ angularDistance($0, value) <= tolerance.angle }) == true { continue }
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let ratio = (target - center) / amplitude
        let ratioTolerance = tolerance.distance / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let clamped = min(max(ratio, -1.0), 1.0)
        let phase = atan2(sine, cosine)
        let offset = acos(clamped)
        return try CertifiedAnalyticCurveEvaluation.values(normalizedAngle(phase - offset),
            normalizedAngle(phase + offset), using: &execution)
    }

    private static func validIntervals(
        boundaries: [Double],
        configuration: Configuration,
        classificationTolerance: Double,
        using execution: inout OriginalQueryExecution) throws -> [(lower: Double, upper: Double)] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard boundaries.isEmpty == false else { return [] }
        try OriginalCoefficientAllocation.reserve(count: boundaries.count, of: (lower: Double, upper: Double).self, using: &execution)
        var result: [(lower: Double, upper: Double)] = []; result.reserveCapacity(boundaries.count)
        for index in boundaries.indices {
            try execution.consumeWork(1)
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count ? boundaries[index + 1] : boundaries[0] + 2.0 * Double.pi
            if configuration.radicand(at: lower + (upper - lower) * 0.5) > classificationTolerance {
                result.append((lower, upper))
            }
        }
        return result
    }

    private static func minimumRadicand(configuration: Configuration, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let maximumAbsoluteDistance = max(
            abs(configuration.signedDistanceCenter
                - configuration.signedDistanceAmplitude),
            abs(configuration.signedDistanceCenter
                + configuration.signedDistanceAmplitude)
        )
        return configuration.reference.radius * configuration.reference.radius
            - maximumAbsoluteDistance * maximumAbsoluteDistance
    }

    private static func maximumRadicand(configuration: Configuration, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        upperAngle: Double,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        let lowerPhase = 2.0 * Double.pi * lowerFraction
        let upperPhase = 2.0 * Double.pi * upperFraction
        var values: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(5, in: &values, using: &execution)
        values.append(midpoint - halfSpan * cos(lowerPhase))
        values.append(midpoint - halfSpan * cos(upperPhase))

        for index in 0...2 {
            try execution.consumeWork(1)
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
        upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try maximumAbsoluteTrigonometricValue(
            lower: lower,
            upper: upper,
            offset: Double.pi * 0.5,
            using: &execution)
    }

    private static func maximumAbsoluteCosine(
        lower: Double,
        upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try maximumAbsoluteTrigonometricValue(
            lower: lower,
            upper: upper,
            offset: 0.0,
            using: &execution)
    }

    private static func maximumAbsoluteTrigonometricValue(
        lower: Double,
        upper: Double,
        offset: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result = max(
            abs(cos(lower - offset)),
            abs(cos(upper - offset))
        )
        for index in -2...4 {
            try execution.consumeWork(1)
            let extremum = offset + Double(index) * Double.pi
            if extremum > lower, extremum < upper {
                result = 1.0
                break
            }
        }
        return result.nextUp
    }

    private static func minimumRadicand(
        lower: Double,
        upper: Double,
        configuration: Configuration,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var angles: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(15, in: &angles, using: &execution)
        angles.append(lower)
        angles.append(upper)

        let phase = atan2(
            configuration.signedDistanceSine,
            configuration.signedDistanceCosine
        )
        for halfTurn in -4...8 {
            try execution.consumeWork(1)
            let angle = phase + Double(halfTurn) * Double.pi
            if angle > lower, angle < upper {
                angles.append(angle)
            }
        }
        let distances = try CertifiedAnalyticCurveEvaluation.map(angles, using: &execution) { value, _ in abs(configuration.signedDistance(at: value)) }
        try execution.consumeWork(distances.count)
        let maximumAbsoluteDistance = distances.max() ?? .infinity
        return (
            configuration.reference.radius * configuration.reference.radius
                - maximumAbsoluteDistance * maximumAbsoluteDistance
        ).nextDown
    }

    private static func maximumRadicand(
        lower: Double,
        upper: Double,
        configuration: Configuration,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var angles: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(29, in: &angles, using: &execution)
        angles.append(lower)
        angles.append(upper)

        let phase = atan2(
            configuration.signedDistanceSine,
            configuration.signedDistanceCosine
        )
        for halfTurn in -4...8 {
            try execution.consumeWork(1)
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
                    try execution.consumeWork(1)
                    let base = phase + Double(turn) * 2.0 * Double.pi
                    try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
                    for angle in [base - offset, base + offset] {
                        try execution.consumeWork(1)
                        guard angle > lower && angle < upper else { continue }
                        angles.append(angle)
                    }
                }
            }
        }
        let distances = try CertifiedAnalyticCurveEvaluation.map(angles, using: &execution) { value, _ in abs(configuration.signedDistance(at: value)) }
        try execution.consumeWork(distances.count)
        let minimumAbsoluteDistance = distances.min() ?? 0.0
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var angle = normalizedAngle(initial)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0
        )
        for _ in 0..<64 {
            try execution.consumeWork(1)
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


    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try validateImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        let result = try pointImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        let result = try differentialImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        let result = try thirdDerivativeImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        let result = try parameterImplementation(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
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

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try fullBranchSpatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try fullBranchSpatialDifferentialMagnitudeBoundsImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    package func parameterizedParameterBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedCylinderCylinderParameterizedParameterBounds? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterizedParameterBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    package func parameterizedParameterBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CertifiedCylinderCylinderParameterizedParameterBounds? {
        try execution.checkpoint()
        let result = try parameterizedParameterBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try spatialDifferentialMagnitudeBoundsImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try spatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    public init(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(referenceSurface: referenceSurface, parameterizedSurface: parameterizedSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case referenceSurface
        case parameterizedSurface
        case componentKind
        case lowerAngle
        case upperAngle
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
        , using: &execution)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceSurface, forKey: .referenceSurface)
        try container.encode(parameterizedSurface, forKey: .parameterizedSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedCylinderCylinderIntersectionCurve: Codable {}
extension CertifiedCylinderCylinderIntersectionCurve.ComponentKind: Codable {}
#endif
