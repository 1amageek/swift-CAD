import CADCore
import Foundation

public struct CertifiedConeConeIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case apexReducedAngularInterval
    }

    enum ApexContactTopology {
        case isolatedPoint
        case isolatedPointAndLoop
        case nodeIntervals([ClosedRange<Double>])
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        var coefficientScale: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                abs(sineDouble),
                1.0
            )
        }

        var absoluteCoefficientSum: Double {
            abs(constant)
                + abs(cosine)
                + abs(sine)
                + abs(cosineDouble)
                + abs(sineDouble)
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
        let reference: Cone
        let parameterized: Cone
        let parameterizedBasisU: Vector3D
        let parameterizedBasisV: Vector3D
        let baseOffset: Vector3D
        let referenceMetricScale: Double
        let constantTerm: Double
        let halfLinearPolynomial: TrigonometricPolynomial
        let quadraticPolynomial: TrigonometricPolynomial
        let discriminantPolynomial: TrigonometricPolynomial

        var characteristicLength: Double {
            max(baseOffset.length, 1.0)
        }

        func direction(at angle: Double) -> Vector3D {
            parameterized.axis * cos(parameterized.halfAngle)
                + radial(at: angle) * sin(parameterized.halfAngle)
        }

        func directionFirstDerivative(at angle: Double) -> Vector3D {
            tangent(at: angle) * sin(parameterized.halfAngle)
        }

        func directionSecondDerivative(at angle: Double) -> Vector3D {
            -radial(at: angle) * sin(parameterized.halfAngle)
        }

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - referenceMetricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }

        private func radial(at angle: Double) -> Vector3D {
            parameterizedBasisU * cos(angle)
                + parameterizedBasisV * sin(angle)
        }

        private func tangent(at angle: Double) -> Vector3D {
            -parameterizedBasisU * sin(angle)
                + parameterizedBasisV * cos(angle)
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    private struct CertifiedInterval {
        let lower: Double
        let upper: Double

        var absoluteUpperBound: Double {
            max(abs(lower), abs(upper)).nextUp
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

    static func apexContactTopology(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ApexContactTopology? {
        let configuration = try makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        guard apexReductionResidualUpperBound(
            configuration: configuration
        ) <= tolerance.distance else {
            return nil
        }
        let halfLinearTolerance = max(
            Double.ulpOfOne * configuration.characteristicLength * 4_096.0,
            tolerance.distance * 1.0e-6
        )
        let maximumHalfLinear = try maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        )
        guard maximumHalfLinear > halfLinearTolerance else {
            return .isolatedPoint
        }
        let boundaries = try roots(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        )
        guard boundaries.isEmpty == false else {
            return .isolatedPointAndLoop
        }
        let intervals = boundaries.indices.map { index in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return lower...upper
        }
        return .nodeIntervals(intervals)
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
                message: "A cone-cone curve cannot satisfy a stricter tolerance than its stored certificate."
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
        let boundaries = try Self.roots(
            of: configuration.discriminantPolynomial,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let minimumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: false,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let maximumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: true,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let quadraticTolerance = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
        guard minimumQuadratic > quadraticTolerance
                || maximumQuadratic < -quadraticTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: min(abs(minimumQuadratic), abs(maximumQuadratic)),
                tolerance: tolerance,
                message: "A certified cone-cone curve contains an asymptotic ruling."
            )
        }

        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
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
                    message: "A full cone-cone branch requires a positive root-free discriminant domain."
                )
            }
        case .boundedAngularInterval:
            let lowerResidual = abs(configuration.discriminantPolynomial.value(at: lowerAngle))
            let upperResidual = abs(configuration.discriminantPolynomial.value(at: upperAngle))
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
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
                  matchesCompleteInterval,
                  configuration.discriminantPolynomial.value(at: midpoint)
                    > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded cone-cone component failed endpoint or interior certification."
                )
            }
        case .apexReducedAngularInterval:
            guard let topology = try Self.apexContactTopology(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: Self.apexReductionResidualUpperBound(
                        configuration: configuration
                    ),
                    tolerance: tolerance,
                    message: "An apex-reduced cone-cone component requires a certified cone-apex contact."
                )
            }
            let matchesTopology: Bool
            switch topology {
            case .isolatedPoint:
                matchesTopology = false
            case .isolatedPointAndLoop:
                matchesTopology = abs(lowerAngle) <= tolerance.angle
                    && abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle
            case let .nodeIntervals(intervals):
                matchesTopology = intervals.contains { interval in
                    abs(interval.lowerBound - lowerAngle) <= tolerance.angle
                        && abs(interval.upperBound - upperAngle) <= tolerance.angle
                }
            }
            guard matchesTopology else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An apex-reduced cone-cone component must cover one complete non-apex root interval."
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
                message: "A cone-cone curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let referenceProjection = try referenceSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let parameterizedProjection = try parameterizedSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            guard max(referenceProjection.residual, parameterizedProjection.residual)
                    <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(referenceProjection.residual, parameterizedProjection.residual),
                    tolerance: tolerance,
                    message: "A cone-cone curve failed its algebraic reconstruction check."
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
        let halfLinear = composedDifferential(
            configuration.halfLinearPolynomial,
            angle: angle
        )
        let quadratic = composedDifferential(
            configuration.quadraticPolynomial,
            angle: angle
        )
        let numerator: ScalarDifferential
        if componentKind == .apexReducedAngularInterval {
            numerator = ScalarDifferential(
                value: -2.0 * halfLinear.value,
                first: -2.0 * halfLinear.first,
                second: -2.0 * halfLinear.second
            )
        } else {
            let discriminant = composedDifferential(
                configuration.discriminantPolynomial,
                angle: angle
            )
            let signedRoot = try signedSquareRootDifferential(
                discriminant,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            numerator = ScalarDifferential(
                value: -halfLinear.value + signedRoot.value,
                first: -halfLinear.first + signedRoot.first,
                second: -halfLinear.second + signedRoot.second
            )
        }
        let slant = try quotient(
            numerator,
            by: quadratic,
            configuration: configuration,
            tolerance: tolerance
        )
        guard componentKind == .apexReducedAngularInterval
                || abs(slant.value) > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(slant.value),
                tolerance: tolerance,
                message: "A certified cone-cone curve reaches a cone apex."
            )
        }
        let direction = configuration.direction(at: angle.value)
        let directionFirst = configuration.directionFirstDerivative(at: angle.value)
            * angle.first
        let directionSecond = configuration.directionSecondDerivative(at: angle.value)
            * (angle.first * angle.first)
            + configuration.directionFirstDerivative(at: angle.value) * angle.second
        let position = configuration.parameterized.apex + direction * slant.value
        let firstDerivative = directionFirst * slant.value
            + direction * slant.first
        let secondDerivative = directionSecond * slant.value
            + directionFirst * (2.0 * slant.first)
            + direction * slant.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-cone component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        guard Self.isEquivalent(surface, to: referenceSurface)
                || Self.isEquivalent(surface, to: parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-cone pcurve was requested on an unrelated surface."
            )
        }
        if Self.isEquivalent(surface, to: parameterizedSurface) {
            let normalizedFraction = min(max(fraction, 0.0), 1.0)
            let configuration = try Self.makeConfiguration(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            )
            let angle = angleDifferential(at: normalizedFraction)
            let halfLinear = composedDifferential(
                configuration.halfLinearPolynomial,
                angle: angle
            )
            let quadratic = composedDifferential(
                configuration.quadraticPolynomial,
                angle: angle
            )
            let numerator: ScalarDifferential
            if componentKind == .apexReducedAngularInterval {
                numerator = ScalarDifferential(
                    value: -2.0 * halfLinear.value,
                    first: -2.0 * halfLinear.first,
                    second: -2.0 * halfLinear.second
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
                numerator = ScalarDifferential(
                    value: -halfLinear.value + root.value,
                    first: -halfLinear.first + root.first,
                    second: -halfLinear.second + root.second
                )
            }
            let slant = try quotient(
                numerator,
                by: quadratic,
                configuration: configuration,
                tolerance: tolerance
            )
            return SurfaceParameter(u: angle.value, v: slant.value)
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
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let minimumQuadratic = try Self.minimumAbsoluteValue(
            of: configuration.quadraticPolynomial,
            residualTolerance: Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let maximumHalfLinear = try Self.maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let maximumDiscriminant = max(
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: true,
                residualTolerance: Self.classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            0.0
        )
        let radius = (maximumHalfLinear + sqrt(maximumDiscriminant))
            / minimumQuadratic
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.parameterized.apex.x - radius,
                y: configuration.parameterized.apex.y - radius,
                z: configuration.parameterized.apex.z - radius
            ),
            maximum: Point3D(
                x: configuration.parameterized.apex.x + radius,
                y: configuration.parameterized.apex.y + radius,
                z: configuration.parameterized.apex.z + radius
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
                message: "Root-free cone-cone differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
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
                message: "A root-free cone-cone differential certificate lost its positive discriminant margin."
            )
        }
        let rootLower = sqrt(minimumDiscriminant).nextDown
        guard rootLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone square-root lower bound collapsed."
            )
        }

        let discriminant = configuration.discriminantPolynomial
        let discriminantValue = try Self.polynomialAbsoluteUpperBound(
            discriminant,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let discriminantFirst = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let discriminantSecond = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
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

        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let numeratorValue = try Self.upperSum(
            halfLinearValue,
            sqrt(discriminantValue).nextUp,
            tolerance: tolerance
        )
        let numeratorFirst = try Self.upperSum(
            halfLinearFirst,
            rootFirst,
            tolerance: tolerance
        )
        let numeratorSecond = try Self.upperSum(
            halfLinearSecond,
            rootSecond,
            tolerance: tolerance
        )

        let quadratic = configuration.quadraticPolynomial
        let quadraticFirst = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticSecond = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone ruling denominator lost its nonzero margin."
            )
        }
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let slantValue = try Self.upperQuotient(
            numeratorValue,
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
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
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        quadraticFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        ),
                        try Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
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

        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let angularFirst = try Self.upperSum(
            Self.upperProduct(
                generatorDerivative,
                slantValue,
                tolerance: tolerance
            ),
            slantFirst,
            tolerance: tolerance
        )
        let angularSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    generatorDerivative,
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        2.0,
                        generatorDerivative,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            slantSecond,
            tolerance: tolerance
        )
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let coarseBounds = SpatialDifferentialMagnitudeBounds(
            first: try Self.upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            ),
            second: try Self.upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            )
        )
        let piecewiseBounds = try Self.piecewiseSpatialDifferentialBounds(
            configuration: configuration,
            branchSign: componentKind == .negativeFullBranch ? -1.0 : 1.0,
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: min(coarseBounds.first, piecewiseBounds.first),
            second: min(coarseBounds.second, piecewiseBounds.second)
        )
    }

    func apexReducedBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .apexReducedAngularInterval else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Apex-reduced cone-cone differential bounds require an apex graph loop."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let classificationEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirstByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticSecondByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "An apex-reduced cone-cone ruling denominator lost its nonzero margin."
            )
        }
        let span = (upperAngle - lowerAngle).nextUp
        let spanSquared = try Self.upperProduct(
            span,
            span,
            tolerance: tolerance
        )
        let numeratorValue = try Self.upperProduct(
            2.0,
            halfLinearValue,
            tolerance: tolerance
        )
        let numeratorFirst = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearFirst,
                tolerance: tolerance
            ),
            span,
            tolerance: tolerance
        )
        let numeratorSecond = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearSecond,
                tolerance: tolerance
            ),
            spanSquared,
            tolerance: tolerance
        )
        let quadraticFirst = try Self.upperProduct(
            quadraticFirstByAngle,
            span,
            tolerance: tolerance
        )
        let quadraticSecond = try Self.upperProduct(
            quadraticSecondByAngle,
            spanSquared,
            tolerance: tolerance
        )
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let slantValue = try Self.upperQuotient(
            numeratorValue,
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
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
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        quadraticFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
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
        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let first = try Self.upperSum(
            Self.upperProduct(
                try Self.upperProduct(
                    generatorDerivative,
                    span,
                    tolerance: tolerance
                ),
                slantValue,
                tolerance: tolerance
            ),
            slantFirst,
            tolerance: tolerance
        )
        let second = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    try Self.upperProduct(
                        generatorDerivative,
                        spanSquared,
                        tolerance: tolerance
                    ),
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            generatorDerivative,
                            tolerance: tolerance
                        ),
                        span,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            slantSecond,
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second
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
        case .apexReducedAngularInterval:
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0
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
                + angularFirst * angle.second
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
        case .apexReducedAngularInterval:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An apex-reduced cone-cone curve does not use a square-root branch."
            )
        }
        if componentKind == .boundedAngularInterval,
           abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0),
           abs(discriminant.value) <= classificationTolerance * 32.0 {
            let squaredSlope = discriminant.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A cone-cone discriminant endpoint has no regular square-root continuation."
                )
            }
            let isUpper = cos(2.0 * Double.pi * fraction) < 0.0
            return ScalarDifferential(
                value: 0.0,
                first: (isUpper ? -1.0 : 1.0) * sqrt(squaredSlope),
                second: 0.0
            )
        }
        guard discriminant.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -discriminant.value,
                tolerance: tolerance,
                message: "A cone-cone evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(discriminant.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A cone-cone square-root differential is singular."
            )
        }
        let signedValue = branchSign * magnitude
        return ScalarDifferential(
            value: signedValue,
            first: discriminant.first / (2.0 * signedValue),
            second: discriminant.second / (2.0 * signedValue)
                - discriminant.first * discriminant.first
                    / (4.0 * signedValue * signedValue * signedValue)
        )
    }

    private func quotient(
        _ numerator: ScalarDifferential,
        by denominator: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let denominatorTolerance = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
        guard abs(denominator.value) > denominatorTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator.value),
                tolerance: tolerance,
                message: "A cone-cone evaluator reached an asymptotic ruling."
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
        return ScalarDifferential(value: value, first: first, second: second)
    }

    private static func makeConfiguration(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try referenceSurface.validate(tolerance: tolerance)
        try parameterizedSurface.validate(tolerance: tolerance)
        guard case let .cone(referenceCanonical) = CanonicalAnalyticSurface(referenceSurface),
              case let .cone(parameterizedCanonical) = CanonicalAnalyticSurface(parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cone-cone curve requires two exact cone surfaces."
            )
        }
        let reference = try canonicalCone(referenceCanonical, tolerance: tolerance)
        let parameterized = try canonicalCone(parameterizedCanonical, tolerance: tolerance)
        let basis = try analyticOrthonormalBasis(
            parameterized.axis,
            tolerance: tolerance
        )
        let baseOffset = parameterized.apex - reference.apex
        let metricScale = 1.0 / pow(cos(reference.halfAngle), 2.0)
        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - metricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }
        func direction(at angle: Double) -> Vector3D {
            parameterized.axis * cos(parameterized.halfAngle)
                + (basis.u * cos(angle) + basis.v * sin(angle))
                    * sin(parameterized.halfAngle)
        }
        let constant = metric(baseOffset, baseOffset)
        let halfLinear = trigonometricPolynomial { angle in
            metric(baseOffset, direction(at: angle))
        }
        let quadratic = trigonometricPolynomial { angle in
            let generator = direction(at: angle)
            return metric(generator, generator)
        }
        let discriminant = trigonometricPolynomial { angle in
            let generator = direction(at: angle)
            let linear = metric(baseOffset, generator)
            return linear * linear - metric(generator, generator) * constant
        }
        return Configuration(
            reference: reference,
            parameterized: parameterized,
            parameterizedBasisU: basis.u,
            parameterizedBasisV: basis.v,
            baseOffset: baseOffset,
            referenceMetricScale: metricScale,
            constantTerm: constant,
            halfLinearPolynomial: halfLinear,
            quadraticPolynomial: quadratic,
            discriminantPolynomial: discriminant
        )
    }

    private static func canonicalCone(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ) throws -> Cone {
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Cone(apex: cone.apex, axis: axis, halfAngle: cone.halfAngle)
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
                message: "A cone-cone parameterization crosses an asymptotic ruling."
            )
        }
        return min(abs(minimum), abs(maximum))
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

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0
        if componentKind == .apexReducedAngularInterval {
            let result = apexReductionResidualUpperBound(
                configuration: configuration
            ) + machineBound
            guard result <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result,
                    tolerance: tolerance,
                    message: "Cone-cone apex reduction does not certify the requested geometric tolerance."
                )
            }
            return result
        }
        guard componentKind == .boundedAngularInterval else {
            return machineBound
        }
        let minimumQuadratic = try minimumAbsoluteValue(
            of: configuration.quadraticPolynomial,
            residualTolerance: classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootResidual = max(
            abs(configuration.discriminantPolynomial.value(at: lowerAngle)),
            abs(configuration.discriminantPolynomial.value(at: upperAngle))
        )
        let endpointClosureBound = sqrt(rootResidual / minimumQuadratic)
        let result = endpointClosureBound + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Cone-cone boundary roots do not certify the requested geometric tolerance."
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

    private static func quadraticTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
    }

    private static func piecewiseSpatialDifferentialBounds(
        configuration: Configuration,
        branchSign: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let cellCount = 1_024
        let period = 2.0 * Double.pi
        let discriminant = configuration.discriminantPolynomial
        let discriminantFirst = discriminant.derivativePolynomial
        let discriminantSecond = discriminantFirst.derivativePolynomial
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearFirst = halfLinear.derivativePolynomial
        let halfLinearSecond = halfLinearFirst.derivativePolynomial
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirst = quadratic.derivativePolynomial
        let quadraticSecond = quadraticFirst.derivativePolynomial
        var maximumAngularFirst = 0.0
        var maximumAngularSecond = 0.0

        for index in 0..<cellCount {
            let lower = period * Double(index) / Double(cellCount)
            let upper = period * Double(index + 1) / Double(cellCount)
            let discriminantRange = try polynomialRange(
                discriminant,
                derivativeBound: discriminantFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            guard discriminantRange.lower > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A root-free cone-cone interval lost its positive discriminant margin."
                )
            }
            let root = CertifiedInterval(
                lower: sqrt(discriminantRange.lower).nextDown,
                upper: sqrt(discriminantRange.upper).nextUp
            )
            let discriminantFirstRange = try polynomialRange(
                discriminantFirst,
                derivativeBound: discriminantSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let discriminantSecondRange = try polynomialRange(
                discriminantSecond,
                derivativeBound: discriminantSecond.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let rootFirst = try divided(
                discriminantFirstRange,
                by: scaled(root, by: 2.0, tolerance: tolerance),
                tolerance: tolerance
            )
            let rootSecond = try subtracting(
                divided(
                    discriminantSecondRange,
                    by: scaled(root, by: 2.0, tolerance: tolerance),
                    tolerance: tolerance
                ),
                divided(
                    multiplied(
                        discriminantFirstRange,
                        discriminantFirstRange,
                        tolerance: tolerance
                    ),
                    by: scaled(
                        multiplied(
                            multiplied(root, root, tolerance: tolerance),
                            root,
                            tolerance: tolerance
                        ),
                        by: 4.0,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )

            let halfLinearRange = try polynomialRange(
                halfLinear,
                derivativeBound: halfLinearFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let halfLinearFirstRange = try polynomialRange(
                halfLinearFirst,
                derivativeBound: halfLinearSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let halfLinearSecondRange = try polynomialRange(
                halfLinearSecond,
                derivativeBound: halfLinearSecond.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let numerator = try adding(
                scaled(halfLinearRange, by: -1.0, tolerance: tolerance),
                scaled(root, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )
            let numeratorFirst = try adding(
                scaled(halfLinearFirstRange, by: -1.0, tolerance: tolerance),
                scaled(rootFirst, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )
            let numeratorSecond = try adding(
                scaled(halfLinearSecondRange, by: -1.0, tolerance: tolerance),
                scaled(rootSecond, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )

            let denominator = try polynomialRange(
                quadratic,
                derivativeBound: quadraticFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let denominatorFirst = try polynomialRange(
                quadraticFirst,
                derivativeBound: quadraticSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let denominatorSecond = try polynomialRange(
                quadraticSecond,
                derivativeBound: quadraticSecond.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            guard denominator.lower > 0.0 || denominator.upper < 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A root-free cone-cone interval lost its ruling denominator margin."
                )
            }
            let denominatorSquared = try multiplied(
                denominator,
                denominator,
                tolerance: tolerance
            )
            let denominatorCubed = try multiplied(
                denominatorSquared,
                denominator,
                tolerance: tolerance
            )
            let slant = try divided(
                numerator,
                by: denominator,
                tolerance: tolerance
            )
            let slantFirst = try subtracting(
                divided(
                    numeratorFirst,
                    by: denominator,
                    tolerance: tolerance
                ),
                divided(
                    multiplied(
                        numerator,
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    by: denominatorSquared,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            let slantSecond = try adding(
                subtracting(
                    subtracting(
                        divided(
                            numeratorSecond,
                            by: denominator,
                            tolerance: tolerance
                        ),
                        divided(
                            multiplied(
                                numerator,
                                denominatorSecond,
                                tolerance: tolerance
                            ),
                            by: denominatorSquared,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    divided(
                        scaled(
                            multiplied(
                                numeratorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            by: 2.0,
                            tolerance: tolerance
                        ),
                        by: denominatorSquared,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                divided(
                    scaled(
                        multiplied(
                            numerator,
                            multiplied(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        by: 2.0,
                        tolerance: tolerance
                    ),
                    by: denominatorCubed,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )

            let generatorDerivative = sin(
                configuration.parameterized.halfAngle
            ).nextUp
            let angularFirst = (
                generatorDerivative * slant.absoluteUpperBound
                    + slantFirst.absoluteUpperBound
            ).nextUp
            let angularSecond = (
                generatorDerivative * slant.absoluteUpperBound
                    + 2.0 * generatorDerivative
                        * slantFirst.absoluteUpperBound
                    + slantSecond.absoluteUpperBound
            ).nextUp
            maximumAngularFirst = max(maximumAngularFirst, angularFirst)
            maximumAngularSecond = max(maximumAngularSecond, angularSecond)
        }
        return SpatialDifferentialMagnitudeBounds(
            first: (period.nextUp * maximumAngularFirst).nextUp,
            second: (
                (period.nextUp * period.nextUp).nextUp
                    * maximumAngularSecond
            ).nextUp
        )
    }

    private static func polynomialRange(
        _ polynomial: TrigonometricPolynomial,
        derivativeBound: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let midpoint = lower + (upper - lower) * 0.5
        let halfWidth = ((upper - lower) * 0.5).nextUp
        let center = polynomial.value(at: midpoint)
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 65_536.0
        ).nextUp
        let radius = (
            derivativeBound.nextUp * halfWidth + arithmeticEnvelope
        ).nextUp
        return try certifiedInterval(
            lower: center - radius,
            upper: center + radius,
            tolerance: tolerance
        )
    }

    private static func adding(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        try certifiedInterval(
            lower: (first.lower + second.lower).nextDown,
            upper: (first.upper + second.upper).nextUp,
            tolerance: tolerance
        )
    }

    private static func subtracting(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        try certifiedInterval(
            lower: (first.lower - second.upper).nextDown,
            upper: (first.upper - second.lower).nextUp,
            tolerance: tolerance
        )
    }

    private static func multiplied(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let products = [
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ]
        guard let lower = products.min(), let upper = products.max() else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone interval multiplication produced no bounds."
            )
        }
        return try certifiedInterval(
            lower: lower.nextDown,
            upper: upper.nextUp,
            tolerance: tolerance
        )
    }

    private static func divided(
        _ numerator: CertifiedInterval,
        by denominator: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        guard denominator.lower > 0.0 || denominator.upper < 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone interval division crossed zero."
            )
        }
        let reciprocal = try certifiedInterval(
            lower: min(
                1.0 / denominator.lower,
                1.0 / denominator.upper
            ).nextDown,
            upper: max(
                1.0 / denominator.lower,
                1.0 / denominator.upper
            ).nextUp,
            tolerance: tolerance
        )
        return try multiplied(
            numerator,
            reciprocal,
            tolerance: tolerance
        )
    }

    private static func scaled(
        _ interval: CertifiedInterval,
        by scale: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let first = interval.lower * scale
        let second = interval.upper * scale
        return try certifiedInterval(
            lower: min(first, second).nextDown,
            upper: max(first, second).nextUp,
            tolerance: tolerance
        )
    }

    private static func certifiedInterval(
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential interval arithmetic exceeded finite ordered bounds."
            )
        }
        return CertifiedInterval(lower: lower, upper: upper)
    }

    private static func polynomialAbsoluteUpperBound(
        _ polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let extremumBound = try maximumAbsoluteValue(
            of: polynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 65_536.0
        ).nextUp
        return try upperSum(
            extremumBound.nextUp,
            arithmeticEnvelope,
            tolerance: tolerance
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
                message: "Cone-cone differential certification received an invalid product operand."
            )
        }
        let value = (first * second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite multiplication."
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
                message: "Cone-cone differential certification received an invalid quotient operand."
            )
        }
        let value = (numerator / denominator).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite division."
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
                message: "Cone-cone differential certification received an invalid sum operand."
            )
        }
        let value = (first + second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite addition."
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

    private static func apexReductionResidualUpperBound(
        configuration: Configuration
    ) -> Double {
        sqrt(abs(configuration.constantTerm))
    }

    private static func isEquivalent(
        _ first: Surface3D,
        to second: Surface3D
    ) -> Bool {
        if first == second { return true }
        guard case let .cone(firstCone) = CanonicalAnalyticSurface(first),
              case let .cone(secondCone) = CanonicalAnalyticSurface(second) else {
            return false
        }
        return firstCone.apex == secondCone.apex
            && firstCone.halfAngle == secondCone.halfAngle
            && (firstCone.axis == secondCone.axis
                || firstCone.axis == -secondCone.axis)
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
            ],
            in: decoder
        )
        try self.init(
            referenceSurface: container.decode(Surface3D.self, forKey: .referenceSurface),
            parameterizedSurface: container.decode(Surface3D.self, forKey: .parameterizedSurface),
            componentKind: container.decode(ComponentKind.self, forKey: .componentKind),
            lowerAngle: container.decode(Double.self, forKey: .lowerAngle),
            upperAngle: container.decode(Double.self, forKey: .upperAngle),
            tolerance: container.decode(
                ModelingTolerance.self,
                forKey: .certificationTolerance
            )
        )
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
    }
}
