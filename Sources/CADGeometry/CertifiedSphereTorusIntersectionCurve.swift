import CADCore
import Foundation

public struct CertifiedSphereTorusIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case negativeOpenAngularInterval
        case positiveOpenAngularInterval
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

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine + 4.0 * sineDouble,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine - 4.0 * sineDouble,
                constant - cosine + cosineDouble,
            ]
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
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let torus: Torus
        let radialU: Vector3D
        let radialV: Vector3D
        let centerOffset: Vector3D
        let radialCosine: Double
        let radialSine: Double
        let axialCoefficient: Double
        let discriminant: TrigonometricPolynomial

        var characteristicLength: Double {
            max(
                sphere.radius,
                torus.majorRadius + torus.minorRadius,
                centerOffset.length,
                1.0
            )
        }

        func radialOffset(at angle: Double) -> Double {
            radialCosine * cos(angle) + radialSine * sin(angle)
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double

        func adding(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second
            )
        }

        func subtracting(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value - other.value,
                first: first - other.first,
                second: second - other.second
            )
        }

        func multiplied(by other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value * other.value,
                first: first * other.value + value * other.first,
                second: second * other.value
                    + 2.0 * first * other.first
                    + value * other.second
            )
        }

        func multiplied(by scalar: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scalar,
                first: first * scalar,
                second: second * scalar
            )
        }

        func divided(by other: ScalarDifferential) throws -> ScalarDifferential {
            guard other.value.isFinite,
                  abs(other.value) > Double.leastNonzeroMagnitude else {
                throw GeometryError.invalidDistance(other.value)
            }
            let inverse = ScalarDifferential(
                value: 1.0 / other.value,
                first: -other.first / (other.value * other.value),
                second: 2.0 * other.first * other.first
                        / (other.value * other.value * other.value)
                    - other.second / (other.value * other.value)
            )
            return multiplied(by: inverse)
        }
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
    }

    public let sphereSurface: Surface3D
    public let torusSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.sphereSurface = sphereSurface
        self.torusSurface = torusSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
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

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        return try spherePoleContacts(
            configuration: configuration,
            tolerance: tolerance
        ).map { (angle: $0.angle, branch: $0.branch) }
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
                message: "A sphere-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        guard lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperAngle - lowerAngle)
        }
        let minimumAmplitude = Self.minimumAmplitude(
            configuration: configuration,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        guard minimumAmplitude > tolerance.distance * 1.0e-6 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: minimumAmplitude,
                tolerance: tolerance,
                message: "Sphere-torus intersection has a singular tube-angle amplitude on its component domain."
            )
        }
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let boundaries = try Self.roots(
            of: configuration.discriminant,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            ).contains { $0.branch == branch }
            let minimumDiscriminant = try Self.extremum(
                of: configuration.discriminant,
                maximum: false,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  hasSpherePoleContact == false,
                  minimumDiscriminant > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumDiscriminant,
                    tolerance: tolerance,
                    message: "A full sphere-torus branch requires a positive root-free, sphere-pole-free discriminant domain."
                )
            }
        case .boundedAngularInterval:
            let intervals = Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminant,
                classificationTolerance: classificationTolerance
            )
            let matchesCompleteInterval = intervals.contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.discriminant.value(at: lowerAngle))
            let upperResidual = abs(configuration.discriminant.value(at: upperAngle))
            let lowerSlope = abs(
                configuration.discriminant.firstDerivative(at: lowerAngle)
            )
            let upperSlope = abs(
                configuration.discriminant.firstDerivative(at: upperAngle)
            )
            let containsSpherePole = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            ).contains { contact in
                let adjusted = Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                )
                return adjusted >= lowerAngle - tolerance.angle
                    && adjusted <= upperAngle + tolerance.angle
            }
            guard matchesCompleteInterval,
                  lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  lowerSlope > classificationTolerance,
                  upperSlope > classificationTolerance,
                  containsSpherePole == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded sphere-torus component is not a complete simple-root interval."
                )
            }
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let branch = componentKind == .negativeOpenAngularInterval ? -1.0 : 1.0
            let contacts = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            ).filter { $0.branch == branch }
            let lowerIsPole = contacts.contains {
                Self.angularDistance($0.angle, lowerAngle) <= tolerance.angle
            }
            let upperIsPole = contacts.contains {
                Self.angularDistance($0.angle, upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.discriminant.value(at: lowerAngle))
            let upperResidual = abs(configuration.discriminant.value(at: upperAngle))
            let lowerIsRoot = lowerResidual <= classificationTolerance * 16.0
            let upperIsRoot = upperResidual <= classificationTolerance * 16.0
            let lowerSlope = abs(
                configuration.discriminant.firstDerivative(at: lowerAngle)
            )
            let upperSlope = abs(
                configuration.discriminant.firstDerivative(at: upperAngle)
            )
            let lowerIsRegularNode = (lowerIsPole || lowerIsRoot)
                && (lowerIsRoot == false || lowerSlope > classificationTolerance)
            let upperIsRegularNode = (upperIsPole || upperIsRoot)
                && (upperIsRoot == false || upperSlope > classificationTolerance)
            let hasInteriorPole = contacts.contains { contact in
                let adjusted = Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                )
                return adjusted > lowerAngle + tolerance.angle
                    && adjusted < upperAngle - tolerance.angle
            }
            let minimumDiscriminant = try Self.minimumDiscriminant(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration,
                tolerance: tolerance
            )
            guard lowerIsRegularNode,
                  upperIsRegularNode,
                  hasInteriorPole == false,
                  minimumDiscriminant >= -classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(
                        max(lowerResidual, upperResidual),
                        max(0.0, -minimumDiscriminant)
                    ),
                    tolerance: tolerance,
                    message: "An open sphere-torus branch is not one complete nonnegative interval between consecutive certified graph nodes."
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
                message: "A sphere-torus curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let sphereProjection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(sphereProjection.residual, torusProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A sphere-torus curve failed its algebraic reconstruction check."
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
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(
            at: clamped,
            configuration: configuration,
            tolerance: tolerance
        )
        let radialOffset = radialOffsetDifferential(
            angle: angle,
            configuration: configuration
        )
        let cosineCoefficient = radialOffset.adding(ScalarDifferential(
            value: configuration.torus.majorRadius,
            first: 0.0,
            second: 0.0
        ))
        let valueCoefficient = radialOffset
            .multiplied(by: -configuration.torus.majorRadius / configuration.torus.minorRadius)
            .adding(ScalarDifferential(
                value: (
                    configuration.sphere.radius * configuration.sphere.radius
                        - configuration.centerOffset.dot(configuration.centerOffset)
                        - configuration.torus.majorRadius * configuration.torus.majorRadius
                        - configuration.torus.minorRadius * configuration.torus.minorRadius
                ) / (2.0 * configuration.torus.minorRadius),
                first: 0.0,
                second: 0.0
            ))
        let axial = ScalarDifferential(
            value: configuration.axialCoefficient,
            first: 0.0,
            second: 0.0
        )
        let amplitudeSquared = cosineCoefficient.multiplied(by: cosineCoefficient)
            .adding(axial.multiplied(by: axial))
        let amplitudeFloor = tolerance.distance * tolerance.distance * 1.0e-12
        guard amplitudeSquared.value > amplitudeFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sqrt(max(amplitudeSquared.value, 0.0)),
                tolerance: tolerance,
                message: "A sphere-torus evaluator reached a singular tube-angle amplitude."
            )
        }
        let discriminant = amplitudeSquared.subtracting(
            valueCoefficient.multiplied(by: valueCoefficient)
        )
        let signedRoot = try signedSquareRootDifferential(
            discriminant,
            fraction: clamped,
            configuration: configuration,
            tolerance: tolerance
        )
        let minorCosine = try cosineCoefficient
            .multiplied(by: valueCoefficient)
            .subtracting(axial.multiplied(by: signedRoot))
            .divided(by: amplitudeSquared)
        let minorSine = try axial
            .multiplied(by: valueCoefficient)
            .adding(cosineCoefficient.multiplied(by: signedRoot))
            .divided(by: amplitudeSquared)

        let radial = radialDifferential(
            angle: angle,
            configuration: configuration
        )
        let radialScale = minorCosine
            .multiplied(by: configuration.torus.minorRadius)
            .adding(ScalarDifferential(
                value: configuration.torus.majorRadius,
                first: 0.0,
                second: 0.0
            ))
        let height = minorSine.multiplied(by: configuration.torus.minorRadius)
        let position = configuration.torus.center
            + radial.value * radialScale.value
            + configuration.torus.axis * height.value
        let firstDerivative = radial.first * radialScale.value
            + radial.value * radialScale.first
            + configuration.torus.axis * height.first
        let secondDerivative = radial.second * radialScale.value
            + radial.first * (2.0 * radialScale.first)
            + radial.value * radialScale.second
            + configuration.torus.axis * height.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified sphere-torus component has a singular differential."
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
        guard surface == sphereSurface || surface == torusSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A sphere-torus pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        if surface == sphereSurface {
            return try sphereParameter(
                for: point,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let radius = configuration.sphere.radius + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.sphere.center.x - radius,
                y: configuration.sphere.center.y - radius,
                z: configuration.sphere.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.sphere.center.x + radius,
                y: configuration.sphere.center.y + radius,
                z: configuration.sphere.center.z + radius
            )
        )
    }

    private func sphereParameter(
        for point: Point3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let offset = point - configuration.sphere.center
        let axial = offset.dot(.unitZ)
        let horizontal = offset - Vector3D.unitZ * axial
        let poleThreshold = max(
            Double.ulpOfOne * configuration.sphere.radius * 4_096.0,
            tolerance.distance * 1.0e-6
        )
        guard horizontal.length <= poleThreshold else {
            let projection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
        let endpointTolerance = Self.endpointFractionTolerance(
            tolerance: tolerance
        )
        let direction: Vector3D
        if fraction <= endpointTolerance {
            direction = try differential(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            ).firstDerivative
        } else if fraction >= 1.0 - endpointTolerance {
            direction = -(try differential(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            ).firstDerivative)
        } else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: horizontal.length,
                tolerance: tolerance,
                message: "A pole-split sphere-torus pcurve reached a spherical pole away from a certified endpoint."
            )
        }
        let horizontalDirection = direction
            - Vector3D.unitZ * direction.dot(.unitZ)
        let normalized = try horizontalDirection.normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
        return SurfaceParameter(
            u: Self.normalizedAngle(atan2(
                normalized.dot(basis.v),
                normalized.dot(basis.u)
            )),
            v: axial >= 0.0 ? Double.pi * 0.5 : -Double.pi * 0.5
        )
    }

    private func angleDifferential(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> ScalarDifferential {
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
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let classificationTolerance = Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let lowerIsSimpleRoot = abs(
                configuration.discriminant.value(at: lowerAngle)
            ) <= classificationTolerance * 16.0
                && abs(configuration.discriminant.firstDerivative(at: lowerAngle))
                    > classificationTolerance
            let upperIsSimpleRoot = abs(
                configuration.discriminant.value(at: upperAngle)
            ) <= classificationTolerance * 16.0
                && abs(configuration.discriminant.firstDerivative(at: upperAngle))
                    > classificationTolerance
            let normalized: ScalarDifferential
            switch (lowerIsSimpleRoot, upperIsSimpleRoot) {
            case (true, true):
                let phase = Double.pi * fraction
                normalized = ScalarDifferential(
                    value: 0.5 - 0.5 * cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.5 * cos(phase)
                )
            case (true, false):
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: 1.0 - cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.25 * cos(phase)
                )
            case (false, true):
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: sin(phase),
                    first: Double.pi * 0.5 * cos(phase),
                    second: -Double.pi * Double.pi * 0.25 * sin(phase)
                )
            case (false, false):
                normalized = ScalarDifferential(
                    value: fraction,
                    first: 1.0,
                    second: 0.0
                )
            }
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * normalized.value,
                first: span * normalized.first,
                second: span * normalized.second
            )
        }
    }

    private func radialOffsetDifferential(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> ScalarDifferential {
        let value = configuration.radialOffset(at: angle.value)
        let angularFirst = -configuration.radialCosine * sin(angle.value)
            + configuration.radialSine * cos(angle.value)
        let angularSecond = -configuration.radialCosine * cos(angle.value)
            - configuration.radialSine * sin(angle.value)
        return ScalarDifferential(
            value: value,
            first: angularFirst * angle.first,
            second: angularSecond * angle.first * angle.first
                + angularFirst * angle.second
        )
    }

    private func radialDifferential(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> (
        value: Vector3D,
        first: Vector3D,
        second: Vector3D
    ) {
        let value = configuration.radialU * cos(angle.value)
            + configuration.radialV * sin(angle.value)
        let angularFirst = configuration.radialU * -sin(angle.value)
            + configuration.radialV * cos(angle.value)
        let angularSecond = -value
        return (
            value,
            angularFirst * angle.first,
            angularSecond * (angle.first * angle.first)
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
        case .negativeOpenAngularInterval:
            branchSign = -1.0
        case .positiveOpenAngularInterval:
            branchSign = 1.0
        }
        let endpointTolerance = Self.endpointFractionTolerance(
            tolerance: tolerance
        )
        let isLowerEndpoint = fraction <= endpointTolerance
        let isUpperEndpoint = fraction >= 1.0 - endpointTolerance
        let isCertifiedRootEndpoint: Bool
        switch componentKind {
        case .boundedAngularInterval:
            isCertifiedRootEndpoint = abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0)
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            isCertifiedRootEndpoint = isLowerEndpoint || isUpperEndpoint
        case .negativeFullBranch, .positiveFullBranch:
            isCertifiedRootEndpoint = false
        }
        if isCertifiedRootEndpoint,
           abs(discriminant.value) <= classificationTolerance * 32.0 {
            let squaredSlope = discriminant.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A sphere-torus boundary has no regular square-root continuation."
                )
            }
            let endpointDirection: Double
            switch componentKind {
            case .boundedAngularInterval:
                endpointDirection = cos(2.0 * Double.pi * fraction) < 0.0
                    ? -1.0
                    : 1.0
            case .negativeOpenAngularInterval,
                 .positiveOpenAngularInterval:
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
        guard discriminant.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -discriminant.value,
                tolerance: tolerance,
                message: "A sphere-torus evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(discriminant.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A sphere-torus square-root differential is singular at normalized fraction \(fraction) for \(componentKind.rawValue)."
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

    private static func endpointFractionTolerance(
        tolerance: ModelingTolerance
    ) -> Double {
        // Root-regularizing angular maps move by O(fraction squared), so values
        // within sqrt(ulp) of an endpoint can round to the endpoint exactly.
        max(tolerance.relative, 2.0 * sqrt(Double.ulpOfOne))
    }

    private static func makeConfiguration(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try sphereSurface.validate(tolerance: tolerance)
        try torusSurface.validate(tolerance: tolerance)
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(sphereSurface),
              case let .torus(sourceTorus) = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified sphere-torus curve requires one exact sphere and one exact torus."
            )
        }
        var axis = try sourceTorus.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        let torus = Torus(
            center: sourceTorus.center,
            axis: axis,
            majorRadius: sourceTorus.majorRadius,
            minorRadius: sourceTorus.minorRadius
        )
        let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
        let centerOffset = torus.center - sphere.center
        let radialCosine = centerOffset.dot(basis.u)
        let radialSine = centerOffset.dot(basis.v)
        let axialCoefficient = centerOffset.dot(axis)
        let discriminant = trigonometricPolynomial { angle in
            let radialOffset = radialCosine * cos(angle) + radialSine * sin(angle)
            let cosine = torus.majorRadius + radialOffset
            let value = (
                sphere.radius * sphere.radius
                    - centerOffset.dot(centerOffset)
                    - torus.majorRadius * torus.majorRadius
                    - 2.0 * torus.majorRadius * radialOffset
                    - torus.minorRadius * torus.minorRadius
            ) / (2.0 * torus.minorRadius)
            return cosine * cosine + axialCoefficient * axialCoefficient
                - value * value
        }
        return Configuration(
            sphere: sphere,
            torus: torus,
            radialU: basis.u,
            radialV: basis.v,
            centerOffset: centerOffset,
            radialCosine: radialCosine,
            radialSine: radialSine,
            axialCoefficient: axialCoefficient,
            discriminant: discriminant
        )
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
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.25,
                Double.ulpOfOne * 1_024.0
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: 1_024,
            tolerance: tolerance
        )
        var values = try solver.roots(
            coefficients: polynomial.tangentHalfAngleCoefficients
        ).map { normalizedAngle(2.0 * atan($0.value)) }
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            values.append(Double.pi)
        }
        values = values.map {
            refinedAngle(
                $0,
                polynomial: polynomial,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )
        }.filter {
            abs(polynomial.value(at: $0)) <= residualTolerance * 16.0
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

    private static func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let angles = [0.0] + (try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        ))
        let values = angles.map(polynomial.value)
        return maximum
            ? values.max() ?? polynomial.value(at: 0.0)
            : values.min() ?? polynomial.value(at: 0.0)
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

    private static func minimumAmplitude(
        configuration: Configuration,
        lowerAngle: Double,
        upperAngle: Double
    ) -> Double {
        let phase = atan2(configuration.radialSine, configuration.radialCosine)
        var candidates = [lowerAngle, upperAngle]
        for base in [phase, phase + Double.pi] {
            for turn in -2...3 {
                let angle = base + Double(turn) * 2.0 * Double.pi
                if angle >= lowerAngle, angle <= upperAngle {
                    candidates.append(angle)
                }
            }
        }
        return candidates.map { angle in
            hypot(
                configuration.torus.majorRadius
                    + configuration.radialOffset(at: angle),
                configuration.axialCoefficient
            )
        }.min() ?? .infinity
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 262_144.0
        let hasBoundaryRoots: Bool
        switch componentKind {
        case .boundedAngularInterval,
             .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            hasBoundaryRoots = true
        case .negativeFullBranch, .positiveFullBranch:
            hasBoundaryRoots = false
        }
        guard hasBoundaryRoots else {
            return machineBound
        }
        let classificationTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let lowerResidual = abs(configuration.discriminant.value(at: lowerAngle))
        let upperResidual = abs(configuration.discriminant.value(at: upperAngle))
        let rootResidual = max(
            lowerResidual <= classificationTolerance * 16.0 ? lowerResidual : 0.0,
            upperResidual <= classificationTolerance * 16.0 ? upperResidual : 0.0
        )
        let amplitude = max(
            minimumAmplitude(
                configuration: configuration,
                lowerAngle: lowerAngle,
                upperAngle: upperAngle
            ),
            tolerance.distance * 1.0e-6
        )
        let result = configuration.torus.minorRadius
            * sqrt(rootResidual) / amplitude + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Sphere-torus boundary roots do not certify the requested geometric tolerance."
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

    private static func refinedAngle(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let effectiveResidual = max(
            Double.ulpOfOne * polynomial.coefficientScale * 128.0,
            residualTolerance * 1.0e-8
        )
        for _ in 0..<128 {
            let value = polynomial.value(at: angle)
            if abs(value) <= effectiveResidual { break }
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

    private static func spherePoleContacts(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [PoleContact] {
        var result: [PoleContact] = []
        let branchTolerance = sqrt(classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        ))
        for sign in [-1.0, 1.0] {
            let pole = configuration.sphere.center
                + Vector3D.unitZ * (sign * configuration.sphere.radius)
            let offset = pole - configuration.torus.center
            let axial = offset.dot(configuration.torus.axis)
            let radial = offset - configuration.torus.axis * axial
            let radialDistance = radial.length
            guard radialDistance > tolerance.distance else { continue }
            let tubeRadial = radialDistance - configuration.torus.majorRadius
            let torusResidual = abs(
                hypot(tubeRadial, axial) - configuration.torus.minorRadius
            )
            guard torusResidual <= tolerance.distance else { continue }
            let radialDirection = radial / radialDistance
            let angle = normalizedAngle(atan2(
                radialDirection.dot(configuration.radialV),
                radialDirection.dot(configuration.radialU)
            ))
            let minorCosine = tubeRadial / configuration.torus.minorRadius
            let minorSine = axial / configuration.torus.minorRadius
            let cosineCoefficient = configuration.torus.majorRadius
                + configuration.centerOffset.dot(radialDirection)
            let signedRoot = cosineCoefficient * minorSine
                - configuration.axialCoefficient * minorCosine
            let branches: [Double]
            if signedRoot > branchTolerance {
                branches = [1.0]
            } else if signedRoot < -branchTolerance {
                branches = [-1.0]
            } else {
                branches = [-1.0, 1.0]
            }
            for branch in branches where result.contains(where: {
                $0.branch == branch
                    && angularDistance($0.angle, angle) <= tolerance.angle
            }) == false {
                result.append(PoleContact(
                    angle: angle,
                    branch: branch
                ))
            }
        }
        return result
    }

    private static func minimumDiscriminant(
        from lower: Double,
        to upper: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var candidateAngles = [lower, upper]
        let derivative = configuration.discriminant.derivativePolynomial
        let derivativeMagnitude = max(
            abs(derivative.cosine),
            abs(derivative.sine),
            abs(derivative.cosineDouble),
            abs(derivative.sineDouble)
        )
        if derivativeMagnitude > Double.ulpOfOne
            * configuration.discriminant.coefficientScale * 128.0 {
            let residualTolerance = classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            for angle in try roots(
                of: derivative,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            ) {
                appendPeriodicAngle(
                    angle,
                    from: lower,
                    to: upper,
                    result: &candidateAngles
                )
            }
        }
        return candidateAngles
            .map { configuration.discriminant.value(at: $0) }
            .min() ?? -.infinity
    }

    private static func appendPeriodicAngle(
        _ angle: Double,
        from lower: Double,
        to upper: Double,
        result: inout [Double]
    ) {
        let period = 2.0 * Double.pi
        let firstIndex = ceil((lower - angle) / period)
        let adjusted = angle + firstIndex * period
        if adjusted >= lower, adjusted <= upper {
            result.append(adjusted)
        }
    }

    private static func adjustedAngle(
        _ angle: Double,
        inside interval: ClosedRange<Double>
    ) -> Double {
        let period = 2.0 * Double.pi
        var adjusted = normalizedAngle(angle)
        while adjusted < interval.lowerBound {
            adjusted += period
        }
        while adjusted > interval.upperBound,
              adjusted - period >= interval.lowerBound {
            adjusted -= period
        }
        return adjusted
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
        case sphereSurface
        case torusSurface
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
                .sphereSurface,
                .torusSurface,
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
            sphereSurface: container.decode(Surface3D.self, forKey: .sphereSurface),
            torusSurface: container.decode(Surface3D.self, forKey: .torusSurface),
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
                debugDescription: "The sphere-torus residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sphereSurface, forKey: .sphereSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
