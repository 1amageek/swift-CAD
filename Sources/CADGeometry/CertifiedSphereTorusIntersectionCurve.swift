import CADCore
import Synchronization
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

public struct CertifiedSphereTorusIntersectionCurve: Hashable, Sendable {
    public enum ComponentKind: String, Hashable, Sendable {
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

        func tangentHalfAngleCoefficients<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [Double] {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: Double.self))
            try execution.consumeWork(1)
            return [
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

        static func constant(_ value: Double) -> ScalarDifferential {
            ScalarDifferential(value: value, first: 0.0, second: 0.0)
        }

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

        func scaled(by scalar: Double) -> ScalarDifferential {
            multiplied(by: scalar)
        }




        func divided<A: ExactScalarAdmission & ~Copyable>(by other: ScalarDifferential, using execution: inout A) throws -> ScalarDifferential {
            try execution.checkpoint()
            let result = try dividedImplementation(by: other, using: &execution)
            try execution.checkpoint()
            return result
        }



        private func dividedImplementation<A: ExactScalarAdmission & ~Copyable>(by other: ScalarDifferential, using execution: inout A) throws -> ScalarDifferential {
            try execution.checkpoint()
            try execution.consumeWork(1)
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

    private struct DifferentialMagnitudeEnvelope {
        let value: Double
        let first: Double
        let second: Double
        let third: Double

        static func constant(_ value: Double) -> DifferentialMagnitudeEnvelope {
            DifferentialMagnitudeEnvelope(
                value: abs(value).nextUp,
                first: 0.0,
                second: 0.0,
                third: 0.0
            )
        }
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
    }

    private enum OpenEndpointStructure {
        case rootFree
        case lowerSimpleRoot
        case upperSimpleRoot
        case twoSimpleRoots
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(sphereSurface: sphereSurface, torusSurface: torusSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }


    public init(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        , using: &execution)
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        try validate(tolerance: tolerance, using: &execution)
            try execution.checkpoint()
    }

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try poleSplitNodes(sphereSurface: sphereSurface, torusSurface: torusSurface, tolerance: tolerance, using: &execution)
    }


    static func poleSplitNodes(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [(angle: Double, branch: Double)] {
        try execution.checkpoint()
        let result = try poleSplitNodesImplementation(sphereSurface: sphereSurface, torusSurface: torusSurface, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private static func poleSplitNodesImplementation(
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [(angle: Double, branch: Double)] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        return try (try CertifiedAnalyticCurveEvaluation.map(spherePoleContacts(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution), using: &execution) { element, execution in  (angle: element.angle, branch: element.branch)  })
    }

    private struct ValidationCacheKey: Hashable, Sendable {
        let curve: CertifiedSphereTorusIntersectionCurve
        let tolerance: ModelingTolerance
    }

    // Consumers query differential bounds per subdivision window, and each
    // query revalidates the same immutable curve with certified root
    // isolation; successful validations are memoized per process.
    private enum ValidationCache {
        static let storage = Mutex<[ValidationCacheKey: OriginalGeometryPreparationReceipt]>([:])
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
        try GeometryStructuralComparisonWork.charge(surface: sphereSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: torusSurface, using: &execution)
        try execution.checkpoint()
        try execution.consumeWork(1)

        let key = ValidationCacheKey(curve: self, tolerance: tolerance)
        if let receipt = ValidationCache.storage.withLock({ $0[key] }) {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
            }
            return
        }
        let prepared = try execution.withPreparationScope { execution in
            try validateUncached(tolerance: tolerance, using: &execution)
        }
        let receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: prepared.depth, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: (ValidationCacheKey, OriginalGeometryPreparationReceipt).self))
        ValidationCache.storage.withLock { cache in
            if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
            cache[key] = receipt
        }
    }

    private func validateUncached(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
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
                message: "A sphere-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        guard lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperAngle - lowerAngle)
        }
        let minimumAmplitude = (try Self.minimumAmplitude(
            configuration: configuration,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        , using: &execution))
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
        , using: &execution)
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution).contains { $0.branch == branch }
            let minimumDiscriminant = try Self.extremum(
                of: configuration.discriminant,
                maximum: false,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            , using: &execution)
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
            let intervals = (try Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminant,
                classificationTolerance: classificationTolerance
            , using: &execution))
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
            , using: &execution).contains { contact in
                let adjusted = (try Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                , using: &execution))
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
            let contacts = try (try CertifiedAnalyticCurveEvaluation.filter(Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution), using: &execution) { element, execution in  element.branch == branch  })
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
            let hasInteriorPole = try contacts.contains { contact in
                let adjusted = (try Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                , using: &execution))
                return adjusted > lowerAngle + tolerance.angle
                    && adjusted < upperAngle - tolerance.angle
            }
            let minimumDiscriminant = try Self.minimumDiscriminant(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
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
        , using: &execution)
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
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Double.self))
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            let sphereProjection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
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
        return try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution).position
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
        , using: &execution)
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
            angle: angle,
            fraction: clamped,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let minorCosine = try cosineCoefficient
            .multiplied(by: valueCoefficient)
            .subtracting(axial.multiplied(by: signedRoot))
            .divided(by: amplitudeSquared, using: &execution)
        let minorSine = try axial
            .multiplied(by: valueCoefficient)
            .adding(cosineCoefficient.multiplied(by: signedRoot))
            .divided(by: amplitudeSquared, using: &execution)

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
        , using: &execution)
        let source = CurveTaylorScalarJet.variable(clamped)
        let angle = angleTaylorJet(
            at: source,
            configuration: configuration,
            tolerance: tolerance
        )
        let radialOffset = angle.cosine().scaled(
            by: configuration.radialCosine
        ) + angle.sine().scaled(by: configuration.radialSine)
        let cosineCoefficient = radialOffset
            + CurveTaylorScalarJet(value: configuration.torus.majorRadius)
        let valueCoefficient = radialOffset.scaled(
            by: -configuration.torus.majorRadius
                / configuration.torus.minorRadius
        ) + CurveTaylorScalarJet(value: (
            configuration.sphere.radius * configuration.sphere.radius
                - configuration.centerOffset.dot(configuration.centerOffset)
                - configuration.torus.majorRadius
                    * configuration.torus.majorRadius
                - configuration.torus.minorRadius
                    * configuration.torus.minorRadius
        ) / (2.0 * configuration.torus.minorRadius))
        let axial = CurveTaylorScalarJet(
            value: configuration.axialCoefficient
        )
        let amplitudeSquared = cosineCoefficient * cosineCoefficient
            + axial * axial
        let amplitudeFloor = tolerance.distance * tolerance.distance * 1.0e-12
        guard amplitudeSquared.value > amplitudeFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sqrt(max(amplitudeSquared.value, 0.0)),
                tolerance: tolerance,
                message: "A sphere-torus third-order evaluator reached a singular tube-angle amplitude."
            )
        }
        let discriminant = amplitudeSquared
            - valueCoefficient * valueCoefficient
        let signedRoot = try signedSquareRootTaylorJet(
            discriminant,
            angle: angle,
            fraction: source,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let context = "Sphere-torus third derivative"
        let minorCosine = try (
            cosineCoefficient * valueCoefficient - axial * signedRoot
        ).divided(
            by: amplitudeSquared,
            tolerance: tolerance,
            diagnosticContext: context
        )
        let minorSine = try (
            axial * valueCoefficient + cosineCoefficient * signedRoot
        ).divided(
            by: amplitudeSquared,
            tolerance: tolerance,
            diagnosticContext: context
        )
        let radialScale = minorCosine.scaled(
            by: configuration.torus.minorRadius
        ) + CurveTaylorScalarJet(value: configuration.torus.majorRadius)
        let height = minorSine.scaled(by: configuration.torus.minorRadius)
        let radialU = angle.cosine() * radialScale
        let radialV = angle.sine() * radialScale
        let reconstructedFirst = configuration.radialU
                * radialU.firstDerivative
            + configuration.radialV * radialV.firstDerivative
            + configuration.torus.axis * height.firstDerivative
        let reconstructedSecond = configuration.radialU
                * radialU.secondDerivative
            + configuration.radialV * radialV.secondDerivative
            + configuration.torus.axis * height.secondDerivative
        let lower = try differential(
            atNormalizedFraction: clamped,
            tolerance: tolerance
        , using: &execution)
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
                message: "Sphere-torus Taylor differentiation disagrees with the certified lower-order differential."
            )
        }
        return configuration.radialU * radialU.thirdDerivative
            + configuration.radialV * radialV.thirdDerivative
            + configuration.torus.axis * height.thirdDerivative
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
        , using: &execution)
        if surface == sphereSurface {
            return try sphereParameter(
                for: point,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        return SurfaceParameter(u: projection.u, v: projection.v)
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
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
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

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try fullBranchSpatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }


    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try fullBranchSpatialDifferentialMagnitudeBoundsImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func fullBranchSpatialDifferentialMagnitudeBoundsImplementation(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            tolerance: tolerance
        , using: &execution)
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
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try spatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func spatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        if componentKind == .boundedAngularInterval {
            return try boundedBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            , using: &execution)
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            return try openBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            , using: &execution)
        }
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sphere-torus differential bounds require a certified component law."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let exactPeriod = 2.0 * Double.pi
        let period = exactPeriod.nextUp
        let lowerAngle = (
            max(lowerFraction, 0.0) * exactPeriod
        ).nextDown
        let upperAngle = (
            min(upperFraction, 1.0) * exactPeriod
        ).nextUp
        let minimumDiscriminant = (
            try Self.minimumDiscriminant(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) - arithmeticEnvelope
        ).nextDown
        guard minimumDiscriminant > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-torus differential certificate lost its positive discriminant lower bound."
            )
        }
        let minimumAmplitude = (
            (try Self.minimumAmplitude(
                configuration: configuration,
                lowerAngle: lowerAngle,
                upperAngle: upperAngle
            , using: &execution)) - tolerance.distance * 1.0e-6
        ).nextDown
        guard minimumAmplitude > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-torus differential certificate lost its tube-angle amplitude lower bound."
            )
        }

        let periodSquared = try upperProduct(
            period,
            period,
            tolerance: tolerance
        , using: &execution)
        let periodCubed = try upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        , using: &execution)
        let radialValue = Self.maximumAbsoluteHarmonic(
            constant: 0.0,
            cosine: configuration.radialCosine,
            sine: configuration.radialSine,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let radialAngularFirst = Self.maximumAbsoluteHarmonic(
            constant: 0.0,
            cosine: configuration.radialSine,
            sine: -configuration.radialCosine,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let radialOffset = DifferentialMagnitudeEnvelope(
            value: radialValue,
            first: try upperProduct(
                radialAngularFirst,
                period,
                tolerance: tolerance
            , using: &execution),
            second: try upperProduct(
                radialValue,
                periodSquared,
                tolerance: tolerance
            , using: &execution),
            third: try upperProduct(
                radialAngularFirst,
                periodCubed,
                tolerance: tolerance
            , using: &execution)
        )
        let discriminantAngularFirst = Self.maximumAbsolutePolynomial(
            configuration.discriminant.derivativePolynomial,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let discriminantAngularSecond = Self.maximumAbsolutePolynomial(
            configuration.discriminant.derivativePolynomial
                .derivativePolynomial,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let discriminantAngularThird = Self.maximumAbsolutePolynomial(
            configuration.discriminant.derivativePolynomial
                .derivativePolynomial.derivativePolynomial,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let discriminant = DifferentialMagnitudeEnvelope(
            value: Self.maximumAbsolutePolynomial(
                configuration.discriminant,
                lowerAngle: lowerAngle,
                upperAngle: upperAngle,
                tolerance: tolerance
            ),
            first: try upperProduct(
                discriminantAngularFirst,
                period,
                tolerance: tolerance
            , using: &execution),
            second: try upperProduct(
                discriminantAngularSecond,
                periodSquared,
                tolerance: tolerance
            , using: &execution),
            third: try upperProduct(
                discriminantAngularThird,
                periodCubed,
                tolerance: tolerance
            , using: &execution)
        )
        let rootLower = sqrt(minimumDiscriminant).nextDown
        guard rootLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-torus square-root lower bound collapsed."
            )
        }
        let rootSquaredLower = (
            rootLower * rootLower
        ).nextDown
        let rootCubedFactorLower = (
            (4.0 * rootSquaredLower).nextDown * rootLower
        ).nextDown
        let rootFifthLower = (
            rootSquaredLower * rootSquaredLower * rootLower
        ).nextDown
        guard rootCubedFactorLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-torus square-root cubic lower bound collapsed."
            )
        }
        let root = DifferentialMagnitudeEnvelope(
            value: sqrt(discriminant.value).nextUp,
            first: try upperQuotient(
                discriminant.first,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                upperQuotient(
                    discriminant.second,
                    (2.0 * rootLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                upperQuotient(
                    try upperProduct(
                        discriminant.first,
                        discriminant.first,
                        tolerance: tolerance
                    , using: &execution),
                    rootCubedFactorLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: try upperSum(
                upperQuotient(
                    discriminant.third,
                    (2.0 * rootLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                upperSum(
                    upperQuotient(
                        3.0 * discriminant.first * discriminant.second,
                        rootCubedFactorLower,
                        tolerance: tolerance
                    , using: &execution),
                    upperQuotient(
                        3.0 * discriminant.first * discriminant.first
                            * discriminant.first,
                        (8.0 * rootFifthLower).nextDown,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
        return try spatialBounds(
            angleFirst: period,
            angleSecond: 0.0,
            angleThird: 0.0,
            radialOffset: radialOffset,
            signedRoot: root,
            minimumAmplitude: minimumAmplitude,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    private func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let exactPeriod = 2.0 * Double.pi
        let period = exactPeriod.nextUp
        let phaseLower = (exactPeriod * lower).nextDown
        let phaseUpper = (exactPeriod * upper).nextUp
        let angleRange = (try Self.boundedAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        , using: &execution))
        let factor = try regularizedFactorBounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: angleRange.lower,
            requestedUpper: angleRange.upper,
            configuration: configuration,
            tolerance: tolerance,
            label: "Sphere-torus bounded branch"
        , using: &execution)
        let sineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5
        , using: &execution))
        let cosineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0
        , using: &execution))
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let periodSquared = try upperProduct(
            period,
            period,
            tolerance: tolerance
        , using: &execution)
        let periodCubed = try upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        , using: &execution)
        let angleFirst = try upperProduct(
            halfSpan,
            try upperProduct(
                period,
                sineMagnitude,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let angleSecond = try upperProduct(
            halfSpan,
            try upperProduct(
                periodSquared,
                cosineMagnitude,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let angleThird = try upperProduct(
            halfSpan,
            try upperProduct(
                periodCubed,
                sineMagnitude,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let distanceRoot = DifferentialMagnitudeEnvelope(
            value: try upperProduct(
                halfSpan,
                sineMagnitude,
                tolerance: tolerance
            , using: &execution),
            first: try upperProduct(
                halfSpan,
                try upperProduct(
                    period,
                    cosineMagnitude,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            second: try upperProduct(
                halfSpan,
                try upperProduct(
                    periodSquared,
                    sineMagnitude,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: try upperProduct(
                halfSpan,
                try upperProduct(
                    periodCubed,
                    cosineMagnitude,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
        let signedRoot = try regularizedSignedRootEnvelope(
            factor: factor,
            distanceRoot: distanceRoot,
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            tolerance: tolerance,
            label: "bounded sphere-torus"
        , using: &execution)
        return try spatialBoundsForAngleRange(
            lowerAngle: angleRange.lower,
            upperAngle: angleRange.upper,
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            signedRoot: signedRoot,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    private func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let lowerDifferential = angleDifferential(
            at: lower,
            configuration: configuration,
            tolerance: tolerance
        )
        let upperDifferential = angleDifferential(
            at: upper,
            configuration: configuration,
            tolerance: tolerance
        )
        let requestedLower = min(
            lowerDifferential.value,
            upperDifferential.value
        ).nextDown
        let requestedUpper = max(
            lowerDifferential.value,
            upperDifferential.value
        ).nextUp
        let structure = openEndpointStructure(
            configuration: configuration,
            tolerance: tolerance
        )
        let span = (upperAngle - lowerAngle).nextUp
        let angleBounds = (try openAngleDifferentialMagnitudeBounds(
            structure: structure,
            lowerFraction: lower,
            upperFraction: upper,
            span: span
        , using: &execution))
        let signedRoot: DifferentialMagnitudeEnvelope
        switch structure {
        case .rootFree:
            signedRoot = try rootFreeSignedRootEnvelope(
                requestedLower: requestedLower,
                requestedUpper: requestedUpper,
                angleFirst: angleBounds.first,
                angleSecond: angleBounds.second,
                angleThird: angleBounds.third,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let factor = try oneSidedRegularizedFactorBounds(
                rootAtLower: rootAtLower,
                requestedLower: requestedLower,
                requestedUpper: requestedUpper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let phaseScale = (Double.pi * 0.5).nextUp
            let distanceScale = sqrt(2.0 * span).nextUp
            let halfPhaseScale = (phaseScale * 0.5).nextUp
            signedRoot = try regularizedSignedRootEnvelope(
                factor: factor,
                distanceRoot: DifferentialMagnitudeEnvelope(
                    value: sqrt(span).nextUp,
                    first: try upperProduct(
                        distanceScale,
                        halfPhaseScale,
                        tolerance: tolerance
                    , using: &execution),
                    second: try upperProduct(
                        distanceScale,
                        try upperProduct(
                            halfPhaseScale,
                            halfPhaseScale,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    third: try upperProduct(
                        distanceScale,
                        pow(halfPhaseScale, 3.0),
                        tolerance: tolerance
                    , using: &execution)
                ),
                angleFirst: angleBounds.first,
                angleSecond: angleBounds.second,
                angleThird: angleBounds.third,
                tolerance: tolerance,
                label: "one-sided open sphere-torus"
            , using: &execution)
        case .twoSimpleRoots:
            let factor = try regularizedFactorBounds(
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                requestedLower: requestedLower,
                requestedUpper: requestedUpper,
                configuration: configuration,
                tolerance: tolerance,
                label: "Sphere-torus two-root open branch"
            , using: &execution)
            let halfSpan = (span * 0.5).nextUp
            let phaseScale = Double.pi.nextUp
            signedRoot = try regularizedSignedRootEnvelope(
                factor: factor,
                distanceRoot: DifferentialMagnitudeEnvelope(
                    value: halfSpan,
                    first: try upperProduct(
                        halfSpan,
                        phaseScale,
                        tolerance: tolerance
                    , using: &execution),
                    second: try upperProduct(
                        halfSpan,
                        try upperProduct(
                            phaseScale,
                            phaseScale,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    third: try upperProduct(
                        halfSpan,
                        pow(phaseScale, 3.0),
                        tolerance: tolerance
                    , using: &execution)
                ),
                angleFirst: angleBounds.first,
                angleSecond: angleBounds.second,
                angleThird: angleBounds.third,
                tolerance: tolerance,
                label: "two-root open sphere-torus"
            , using: &execution)
        }
        return try spatialBoundsForAngleRange(
            lowerAngle: requestedLower,
            upperAngle: requestedUpper,
            angleFirst: angleBounds.first,
            angleSecond: angleBounds.second,
            angleThird: angleBounds.third,
            signedRoot: signedRoot,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    private func openAngleDifferentialMagnitudeBounds<A: ExactScalarAdmission & ~Copyable>(
        structure: OpenEndpointStructure,
        lowerFraction: Double,
        upperFraction: Double,
        span: Double
    , using execution: inout A) throws -> (first: Double, second: Double, third: Double) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        switch structure {
        case .rootFree:
            return (span, 0.0, 0.0)
        case .lowerSimpleRoot, .upperSimpleRoot:
            let phaseScale = (Double.pi * 0.5).nextUp
            let phaseLower = phaseScale * lowerFraction
            let phaseUpper = phaseScale * upperFraction
            let sineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
                lower: phaseLower,
                upper: phaseUpper,
                phase: Double.pi * 0.5
            , using: &execution))
            let cosineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
                lower: phaseLower,
                upper: phaseUpper,
                phase: 0.0
            , using: &execution))
            let firstTrigonometricMagnitude = structure == .lowerSimpleRoot
                ? sineMagnitude
                : cosineMagnitude
            let secondTrigonometricMagnitude = structure == .lowerSimpleRoot
                ? cosineMagnitude
                : sineMagnitude
            return (
                (
                    span * phaseScale * firstTrigonometricMagnitude
                ).nextUp,
                (
                    span * phaseScale * phaseScale
                        * secondTrigonometricMagnitude
                ).nextUp,
                (
                    span * phaseScale * phaseScale * phaseScale
                        * firstTrigonometricMagnitude
                ).nextUp
            )
        case .twoSimpleRoots:
            let phaseScale = Double.pi.nextUp
            let phaseLower = phaseScale * lowerFraction
            let phaseUpper = phaseScale * upperFraction
            let sineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
                lower: phaseLower,
                upper: phaseUpper,
                phase: Double.pi * 0.5
            , using: &execution))
            let cosineMagnitude = (try Self.maximumAbsoluteTrigonometricValue(
                lower: phaseLower,
                upper: phaseUpper,
                phase: 0.0
            , using: &execution))
            let halfSpan = (span * 0.5).nextUp
            return (
                (halfSpan * phaseScale * sineMagnitude).nextUp,
                (
                    halfSpan * phaseScale * phaseScale
                        * cosineMagnitude
                ).nextUp,
                (
                    halfSpan * phaseScale * phaseScale * phaseScale
                        * sineMagnitude
                ).nextUp
            )
        }
    }

    private func oneSidedRegularizedFactorBounds(
        rootAtLower: Bool,
        requestedLower: Double,
        requestedUpper: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> EndpointRegularizedFactorBounder.Bounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let polynomial = configuration.discriminant
        let rootAngle = rootAtLower ? lowerAngle : upperAngle
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 131_072.0
        ).nextUp
        return try EndpointRegularizedFactorBounder().oneSidedBounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower,
            requestedUpper: requestedUpper,
            rootAtLower: rootAtLower,
            endpointValue: polynomial.value(at: rootAngle),
            endpointDerivative: polynomial.firstDerivative(at: rootAngle),
            firstDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial
                ),
            secondDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                ),
            thirdDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                        .derivativePolynomial
                ),
            fourthDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                        .derivativePolynomial.derivativePolynomial
                ),
            arithmeticEnvelope: arithmeticEnvelope,
            orientedValueRange: { rangeLower, rangeUpper, execution in
                try Self.discriminantRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope,
                    tolerance: tolerance
                , using: &execution)
            },
            tolerance: tolerance,
            label: "Sphere-torus one-sided open branch"
        , using: &execution)
    }

    private func rootFreeSignedRootEnvelope(
        requestedLower: Double,
        requestedUpper: Double,
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialMagnitudeEnvelope {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let range = try Self.discriminantRange(
            configuration: configuration,
            lower: requestedLower,
            upper: requestedUpper,
            arithmeticEnvelope: arithmeticEnvelope,
            tolerance: tolerance
        , using: &execution)
        guard range.lower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free open sphere-torus branch lost its positive discriminant margin."
            )
        }
        let polynomial = configuration.discriminant
        let firstByAngle = Self.maximumAbsolutePolynomial(
            polynomial.derivativePolynomial,
            lowerAngle: requestedLower,
            upperAngle: requestedUpper,
            tolerance: tolerance
        )
        let secondByAngle = Self.maximumAbsolutePolynomial(
            polynomial.derivativePolynomial.derivativePolynomial,
            lowerAngle: requestedLower,
            upperAngle: requestedUpper,
            tolerance: tolerance
        )
        let thirdByAngle = Self.maximumAbsolutePolynomial(
            polynomial.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            lowerAngle: requestedLower,
            upperAngle: requestedUpper,
            tolerance: tolerance
        )
        let discriminant = DifferentialMagnitudeEnvelope(
            value: max(abs(range.lower), abs(range.upper)).nextUp,
            first: try upperProduct(
                firstByAngle,
                angleFirst,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                try upperProduct(
                    secondByAngle,
                    try upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try upperProduct(
                    firstByAngle,
                    angleSecond,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: (
                thirdByAngle * angleFirst * angleFirst * angleFirst
                    + 3.0 * secondByAngle * angleFirst * angleSecond
                    + firstByAngle * angleThird
            ).nextUp
        )
        let rootLower = sqrt(range.lower).nextDown
        let rootCubedFactorLower = (
            4.0 * range.lower * rootLower
        ).nextDown
        let rootFifthLower = (
            range.lower * range.lower * rootLower
        ).nextDown
        guard rootLower > 0.0,
              rootCubedFactorLower > 0.0,
              rootFifthLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free open sphere-torus square-root margin collapsed."
            )
        }
        return DifferentialMagnitudeEnvelope(
            value: sqrt(discriminant.value).nextUp,
            first: try upperQuotient(
                discriminant.first,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                try upperQuotient(
                    discriminant.second,
                    (2.0 * rootLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                try upperQuotient(
                    try upperProduct(
                        discriminant.first,
                        discriminant.first,
                        tolerance: tolerance
                    , using: &execution),
                    rootCubedFactorLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: try upperSum(
                upperQuotient(
                    discriminant.third,
                    (2.0 * rootLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                upperSum(
                    upperQuotient(
                        3.0 * discriminant.first * discriminant.second,
                        rootCubedFactorLower,
                        tolerance: tolerance
                    , using: &execution),
                    upperQuotient(
                        3.0 * discriminant.first * discriminant.first
                            * discriminant.first,
                        (8.0 * rootFifthLower).nextDown,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
    }

    private func regularizedFactorBounds(
        componentLower: Double,
        componentUpper: Double,
        requestedLower: Double,
        requestedUpper: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        label: String
    , using execution: inout OriginalQueryExecution) throws -> EndpointRegularizedFactorBounder.Bounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let polynomial = configuration.discriminant
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 131_072.0
        ).nextUp
        return try EndpointRegularizedFactorBounder().bounds(
            componentLower: componentLower,
            componentUpper: componentUpper,
            requestedLower: requestedLower,
            requestedUpper: requestedUpper,
            lowerValue: polynomial.value(at: componentLower),
            upperValue: polynomial.value(at: componentUpper),
            lowerDerivative: polynomial.firstDerivative(at: componentLower),
            upperDerivative: polynomial.firstDerivative(at: componentUpper),
            firstDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial
                ),
            secondDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                ),
            thirdDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                        .derivativePolynomial
                ),
            fourthDerivativeMagnitudeUpperBound:
                Self.coefficientMagnitudeUpperBound(
                    polynomial.derivativePolynomial.derivativePolynomial
                        .derivativePolynomial.derivativePolynomial
                ),
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper, execution in
                try Self.discriminantRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope,
                    tolerance: tolerance
                , using: &execution)
            },
            tolerance: tolerance,
            label: label
        , using: &execution)
    }

    private func regularizedSignedRootEnvelope(
        factor: EndpointRegularizedFactorBounder.Bounds,
        distanceRoot: DifferentialMagnitudeEnvelope,
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        tolerance: ModelingTolerance,
        label: String
    , using execution: inout OriginalQueryExecution) throws -> DifferentialMagnitudeEnvelope {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A \(label) regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = try upperSum(
            try upperQuotient(
                factor.third,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                upperQuotient(
                    3.0 * factor.first * factor.second,
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                upperQuotient(
                    3.0 * factor.first * factor.first * factor.first,
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootByFraction = DifferentialMagnitudeEnvelope(
            value: rootUpper,
            first: try upperProduct(
                rootFirstByAngle,
                angleFirst,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                try upperProduct(
                    rootSecondByAngle,
                    try upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try upperProduct(
                    rootFirstByAngle,
                    angleSecond,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: (
                rootThirdByAngle * angleFirst * angleFirst * angleFirst
                    + 3.0 * rootSecondByAngle * angleFirst * angleSecond
                    + rootFirstByAngle * angleThird
            ).nextUp
        )
        return try multiplied(
            distanceRoot,
            rootByFraction,
            tolerance: tolerance
        , using: &execution)
    }

    private func spatialBoundsForAngleRange(
        lowerAngle: Double,
        upperAngle: Double,
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        signedRoot: DifferentialMagnitudeEnvelope,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let radialValue = Self.maximumAbsoluteHarmonic(
            constant: 0.0,
            cosine: configuration.radialCosine,
            sine: configuration.radialSine,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let radialAngularFirst = Self.maximumAbsoluteHarmonic(
            constant: 0.0,
            cosine: configuration.radialSine,
            sine: -configuration.radialCosine,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let angleFirstSquared = try upperProduct(
            angleFirst,
            angleFirst,
            tolerance: tolerance
        , using: &execution)
        let radialOffset = DifferentialMagnitudeEnvelope(
            value: radialValue,
            first: try upperProduct(
                radialAngularFirst,
                angleFirst,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                try upperProduct(
                    radialValue,
                    angleFirstSquared,
                    tolerance: tolerance
                , using: &execution),
                try upperProduct(
                    radialAngularFirst,
                    angleSecond,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: (
                radialAngularFirst * angleFirst * angleFirst * angleFirst
                    + 3.0 * radialValue * angleFirst * angleSecond
                    + radialAngularFirst * angleThird
            ).nextUp
        )
        let minimumAmplitude = (
            (try Self.minimumAmplitude(
                configuration: configuration,
                lowerAngle: lowerAngle,
                upperAngle: upperAngle
            , using: &execution)) - tolerance.distance * 1.0e-6
        ).nextDown
        guard minimumAmplitude > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A sphere-torus differential certificate lost its tube-angle amplitude lower bound."
            )
        }
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            radialOffset: radialOffset,
            signedRoot: signedRoot,
            minimumAmplitude: minimumAmplitude,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    private func spatialBounds(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        radialOffset: DifferentialMagnitudeEnvelope,
        signedRoot: DifferentialMagnitudeEnvelope,
        minimumAmplitude: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let cosineCoefficient = try adding(
            radialOffset,
            .constant(configuration.torus.majorRadius),
            tolerance: tolerance
        , using: &execution)
        let valueConstant = (
            configuration.sphere.radius * configuration.sphere.radius
                - configuration.centerOffset.dot(configuration.centerOffset)
                - configuration.torus.majorRadius
                    * configuration.torus.majorRadius
                - configuration.torus.minorRadius
                    * configuration.torus.minorRadius
        ) / (2.0 * configuration.torus.minorRadius)
        let valueCoefficient = try adding(
            scaled(
                radialOffset,
                by: -configuration.torus.majorRadius
                    / configuration.torus.minorRadius
            ),
            .constant(valueConstant),
            tolerance: tolerance
        , using: &execution)
        let axial = DifferentialMagnitudeEnvelope.constant(
            configuration.axialCoefficient
        )
        let amplitudeSquared = try adding(
            multiplied(
                cosineCoefficient,
                cosineCoefficient,
                tolerance: tolerance
            , using: &execution),
            multiplied(axial, axial, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        let minorCosineNumerator = try adding(
            multiplied(
                cosineCoefficient,
                valueCoefficient,
                tolerance: tolerance
            , using: &execution),
            multiplied(axial, signedRoot, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        let minorSineNumerator = try adding(
            multiplied(
                axial,
                valueCoefficient,
                tolerance: tolerance
            , using: &execution),
            multiplied(
                cosineCoefficient,
                signedRoot,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let amplitudeSquaredLower = (
            minimumAmplitude * minimumAmplitude
        ).nextDown
        guard amplitudeSquaredLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A sphere-torus amplitude-square lower bound collapsed."
            )
        }
        let inverseAmplitudeSquared = try reciprocal(
            amplitudeSquared,
            minimumValue: amplitudeSquaredLower,
            tolerance: tolerance
        , using: &execution)
        let minorCosine = try multiplied(
            minorCosineNumerator,
            inverseAmplitudeSquared,
            tolerance: tolerance
        , using: &execution)
        let minorSine = try multiplied(
            minorSineNumerator,
            inverseAmplitudeSquared,
            tolerance: tolerance
        , using: &execution)
        let radialScale = try adding(
            scaled(minorCosine, by: configuration.torus.minorRadius),
            .constant(configuration.torus.majorRadius),
            tolerance: tolerance
        , using: &execution)
        let height = scaled(
            minorSine,
            by: configuration.torus.minorRadius
        )
        let first = try upperSum(
            try upperProduct(
                angleFirst,
                radialScale.value,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                radialScale.first,
                height.first,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let radialSecond = try upperSum(
            try upperProduct(
                try upperSum(
                    try upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    angleSecond,
                    tolerance: tolerance
                , using: &execution),
                radialScale.value,
                tolerance: tolerance
            , using: &execution),
            try upperProduct(
                2.0 * angleFirst,
                radialScale.first,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let second = try upperSum(
            radialSecond,
            try upperSum(
                radialScale.second,
                height.second,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let directionSecond = (
            angleFirst * angleFirst + angleSecond
        ).nextUp
        let directionThird = (
            angleFirst * angleFirst * angleFirst
                + 3.0 * angleFirst * angleSecond
                + angleThird
        ).nextUp
        let radialThird = (
            directionThird * radialScale.value
                + 3.0 * directionSecond * radialScale.first
                + 3.0 * angleFirst * radialScale.second
                + radialScale.third
        ).nextUp
        let third = try upperSum(
            radialThird,
            height.third,
            tolerance: tolerance
        , using: &execution)
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func adding(
        _ first: DifferentialMagnitudeEnvelope,
        _ second: DifferentialMagnitudeEnvelope,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialMagnitudeEnvelope {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return DifferentialMagnitudeEnvelope(
            value: try upperSum(
                first.value,
                second.value,
                tolerance: tolerance
            , using: &execution),
            first: try upperSum(
                first.first,
                second.first,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                first.second,
                second.second,
                tolerance: tolerance
            , using: &execution),
            third: try upperSum(
                first.third,
                second.third,
                tolerance: tolerance
            , using: &execution)
        )
    }

    private func multiplied(
        _ first: DifferentialMagnitudeEnvelope,
        _ second: DifferentialMagnitudeEnvelope,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialMagnitudeEnvelope {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return DifferentialMagnitudeEnvelope(
            value: try upperProduct(
                first.value,
                second.value,
                tolerance: tolerance
            , using: &execution),
            first: try upperSum(
                upperProduct(
                    first.first,
                    second.value,
                    tolerance: tolerance
                , using: &execution),
                upperProduct(
                    first.value,
                    second.first,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                upperProduct(
                    first.second,
                    second.value,
                    tolerance: tolerance
                , using: &execution),
                upperSum(
                    upperProduct(
                        2.0 * first.first,
                        second.first,
                        tolerance: tolerance
                    , using: &execution),
                    upperProduct(
                        first.value,
                        second.second,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: try upperSum(
                upperProduct(
                    first.third,
                    second.value,
                    tolerance: tolerance
                , using: &execution),
                upperSum(
                    upperProduct(
                        3.0 * first.second,
                        second.first,
                        tolerance: tolerance
                    , using: &execution),
                    upperSum(
                        upperProduct(
                            3.0 * first.first,
                            second.second,
                            tolerance: tolerance
                        , using: &execution),
                        upperProduct(
                            first.value,
                            second.third,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
    }

    private func scaled(
        _ value: DifferentialMagnitudeEnvelope,
        by scalar: Double
    ) -> DifferentialMagnitudeEnvelope {
        let magnitude = abs(scalar).nextUp
        return DifferentialMagnitudeEnvelope(
            value: (value.value * magnitude).nextUp,
            first: (value.first * magnitude).nextUp,
            second: (value.second * magnitude).nextUp,
            third: (value.third * magnitude).nextUp
        )
    }

    private func reciprocal(
        _ value: DifferentialMagnitudeEnvelope,
        minimumValue: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialMagnitudeEnvelope {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let squaredLower = (minimumValue * minimumValue).nextDown
        let cubedLower = (squaredLower * minimumValue).nextDown
        let fourthLower = (cubedLower * minimumValue).nextDown
        guard squaredLower > 0.0,
              cubedLower > 0.0,
              fourthLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus reciprocal differential lower bound collapsed."
            )
        }
        return DifferentialMagnitudeEnvelope(
            value: try upperQuotient(
                1.0,
                minimumValue,
                tolerance: tolerance
            , using: &execution),
            first: try upperQuotient(
                value.first,
                squaredLower,
                tolerance: tolerance
            , using: &execution),
            second: try upperSum(
                upperQuotient(
                    try upperProduct(
                        2.0 * value.first,
                        value.first,
                        tolerance: tolerance
                    , using: &execution),
                    cubedLower,
                    tolerance: tolerance
                , using: &execution),
                upperQuotient(
                    value.second,
                    squaredLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            third: try upperSum(
                upperQuotient(
                    try upperProduct(
                        6.0 * value.first,
                        try upperProduct(
                            value.first,
                            value.first,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    fourthLower,
                    tolerance: tolerance
                , using: &execution),
                try upperSum(
                    upperQuotient(
                        try upperProduct(
                            6.0 * value.first,
                            value.second,
                            tolerance: tolerance
                        , using: &execution),
                        cubedLower,
                        tolerance: tolerance
                    , using: &execution),
                    upperQuotient(
                        value.third,
                        squaredLower,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
    }

    private func upperProduct<A: ExactScalarAdmission & ~Copyable>(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification received a negative or non-finite factor."
            )
        }
        let result = (first * second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperQuotient<A: ExactScalarAdmission & ~Copyable>(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard numerator.isFinite,
              denominator.isFinite,
              numerator >= 0.0,
              denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification received a non-positive divisor."
            )
        }
        let result = (numerator / denominator).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperSum<A: ExactScalarAdmission & ~Copyable>(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification received a negative or non-finite summand."
            )
        }
        let result = (first + second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-torus differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func resourceFailure(
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

    private func sphereParameter(
        for point: Point3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)
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
            , using: &execution).firstDerivative
        } else if fraction >= 1.0 - endpointTolerance {
            direction = -(try differential(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            , using: &execution).firstDerivative)
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

    private func angleTaylorJet(
        at fraction: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance
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
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let classificationTolerance = Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let lowerIsSimpleRoot = abs(
                configuration.discriminant.value(at: lowerAngle)
            ) <= classificationTolerance * 16.0
                && abs(
                    configuration.discriminant.firstDerivative(
                        at: lowerAngle
                    )
                ) > classificationTolerance
            let upperIsSimpleRoot = abs(
                configuration.discriminant.value(at: upperAngle)
            ) <= classificationTolerance * 16.0
                && abs(
                    configuration.discriminant.firstDerivative(
                        at: upperAngle
                    )
                ) > classificationTolerance
            let normalized: CurveTaylorScalarJet
            switch (lowerIsSimpleRoot, upperIsSimpleRoot) {
            case (true, true):
                normalized = CurveTaylorScalarJet(value: 0.5)
                    - fraction.scaled(by: Double.pi).cosine()
                        .scaled(by: 0.5)
            case (true, false):
                normalized = CurveTaylorScalarJet(value: 1.0)
                    - fraction.scaled(by: Double.pi * 0.5).cosine()
            case (false, true):
                normalized = fraction.scaled(
                    by: Double.pi * 0.5
                ).sine()
            case (false, false):
                normalized = fraction
            }
            return CurveTaylorScalarJet(value: lowerAngle)
                + normalized.scaled(by: upperAngle - lowerAngle)
        }
    }

    private func signedSquareRootTaylorJet(
        _ discriminant: CurveTaylorScalarJet,
        angle: CurveTaylorScalarJet,
        fraction: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Sphere-torus third derivative"
        let branchSign: Double
        switch componentKind {
        case .negativeFullBranch, .negativeOpenAngularInterval:
            branchSign = -1.0
        case .positiveFullBranch, .positiveOpenAngularInterval,
             .boundedAngularInterval:
            branchSign = 1.0
        }
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedDiscriminantFactorTaylorJet(
                angle: angle,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let distanceRoot = fraction.scaled(
                by: 2.0 * Double.pi
            ).sine().scaled(by: (upperAngle - lowerAngle) * 0.5)
            return try regularizedSquareRootTaylorJet(
                factor: factor,
                distanceRoot: distanceRoot,
                branchSign: 1.0,
                tolerance: tolerance,
                diagnosticContext: context
            , using: &execution)
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            )
            if structure != .rootFree {
                return try openRegularizedSquareRootTaylorJet(
                    structure: structure,
                    angle: angle,
                    fraction: fraction,
                    branchSign: branchSign,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
            }
        }
        return try discriminant.squareRoot(
            tolerance: tolerance,
            diagnosticContext: context
        ).scaled(by: branchSign).validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
    }

    private func openRegularizedSquareRootTaylorJet(
        structure: OpenEndpointStructure,
        angle: CurveTaylorScalarJet,
        fraction: CurveTaylorScalarJet,
        branchSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let factor: CurveTaylorScalarJet
        let distanceRoot: CurveTaylorScalarJet
        switch structure {
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let dividedDifference = try Self
                .trigonometricDividedDifferenceTaylorJet(
                    configuration.discriminant,
                    value: angle,
                    endpoint: rootAtLower ? lowerAngle : upperAngle,
                    tolerance: tolerance
                , using: &execution)
            factor = rootAtLower
                ? dividedDifference
                : -dividedDifference
            let phase = fraction.scaled(by: Double.pi * 0.5)
            let argument = rootAtLower
                ? phase.scaled(by: 0.5)
                : CurveTaylorScalarJet(value: Double.pi * 0.25)
                    - phase.scaled(by: 0.5)
            distanceRoot = argument.sine().scaled(
                by: sqrt(2.0 * (upperAngle - lowerAngle))
            )
        case .twoSimpleRoots:
            factor = try regularizedDiscriminantFactorTaylorJet(
                angle: angle,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            distanceRoot = fraction.scaled(by: Double.pi).sine()
                .scaled(by: (upperAngle - lowerAngle) * 0.5)
        case .rootFree:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A root-free sphere-torus graph edge does not use endpoint regularization."
            )
        }
        return try regularizedSquareRootTaylorJet(
            factor: factor,
            distanceRoot: distanceRoot,
            branchSign: branchSign,
            tolerance: tolerance,
            diagnosticContext: "Open sphere-torus third derivative"
        , using: &execution)
    }

    private func regularizedSquareRootTaylorJet(
        factor: CurveTaylorScalarJet,
        distanceRoot: CurveTaylorScalarJet,
        branchSign: Double,
        tolerance: ModelingTolerance,
        diagnosticContext: String
    , using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try (
            distanceRoot * factor.squareRoot(
                tolerance: tolerance,
                diagnosticContext: diagnosticContext
            )
        ).scaled(by: branchSign).validated(
            tolerance: tolerance,
            diagnosticContext: diagnosticContext
        )
    }

    private func regularizedDiscriminantFactorTaylorJet(
        angle: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let span = upperAngle - lowerAngle
        let usesLowerEndpoint = angle.value - lowerAngle
            <= upperAngle - angle.value
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = try Self.trigonometricDividedDifferenceTaylorJet(
            configuration.discriminant,
            value: angle,
            endpoint: endpoint,
            tolerance: tolerance
        , using: &execution)
        let lowerValue = configuration.discriminant.value(at: lowerAngle)
        let upperValue = configuration.discriminant.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let numerator = usesLowerEndpoint
            ? dividedDifference
                + CurveTaylorScalarJet(value: -correctionSlope)
            : CurveTaylorScalarJet(value: correctionSlope)
                - dividedDifference
        let denominator = usesLowerEndpoint
            ? CurveTaylorScalarJet(value: upperAngle) - angle
            : angle - CurveTaylorScalarJet(value: lowerAngle)
        return try numerator.divided(
            by: denominator,
            tolerance: tolerance,
            diagnosticContext: "Sphere-torus regularized discriminant"
        ).validated(
            tolerance: tolerance,
            diagnosticContext: "Sphere-torus regularized discriminant"
        )
    }

    private static func trigonometricDividedDifferenceTaylorJet(
        _ polynomial: TrigonometricPolynomial,
        value: CurveTaylorScalarJet,
        endpoint: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Sphere-torus trigonometric divided difference"
        var result = CurveTaylorScalarJet(value: 0.0)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: (order: Double, cosine: Double, sine: Double).self))
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
            try execution.consumeWork(1)
            let halfOrder = harmonic.order * 0.5
            let difference = (
                value - CurveTaylorScalarJet(value: endpoint)
            ).scaled(by: halfOrder)
            let midpoint = (
                value + CurveTaylorScalarJet(value: endpoint)
            ).scaled(by: halfOrder)
            let sinc = try difference.sinc(
                tolerance: tolerance,
                diagnosticContext: context
            )
            let amplitude = midpoint.sine().scaled(
                by: -harmonic.cosine
            ) + midpoint.cosine().scaled(by: harmonic.sine)
            result = result
                + (sinc * amplitude).scaled(by: harmonic.order)
        }
        return try result.validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
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
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedDiscriminantFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            return try regularizedSquareRootDifferential(
                factor: factor,
                distanceRoot: ScalarDifferential(
                    value: (upperAngle - lowerAngle) * 0.5
                        * sin(2.0 * Double.pi * fraction),
                    first: (upperAngle - lowerAngle) * Double.pi
                        * cos(2.0 * Double.pi * fraction),
                    second: -2.0 * (upperAngle - lowerAngle)
                        * Double.pi * Double.pi
                        * sin(2.0 * Double.pi * fraction)
                ),
                angle: angle,
                branchSign: 1.0,
                tolerance: tolerance,
                label: "bounded sphere-torus"
            , using: &execution)
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            )
            if structure != .rootFree {
                return try openRegularizedSquareRootDifferential(
                    structure: structure,
                    angle: angle,
                    fraction: fraction,
                    branchSign: branchSign,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
            }
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

    private func openRegularizedSquareRootDifferential(
        structure: OpenEndpointStructure,
        angle: ScalarDifferential,
        fraction: Double,
        branchSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let factor: ScalarDifferential
        let distanceRoot: ScalarDifferential
        switch structure {
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let dividedDifference = (try Self.trigonometricDividedDifference(
                configuration.discriminant,
                value: angle.value,
                endpoint: rootAtLower ? lowerAngle : upperAngle
            , using: &execution))
            factor = rootAtLower
                ? dividedDifference
                : dividedDifference.scaled(by: -1.0)
            let phaseScale = Double.pi * 0.5
            let phase = phaseScale * fraction
            let halfPhaseScale = phaseScale * 0.5
            let argument = rootAtLower
                ? phase * 0.5
                : Double.pi * 0.25 - phase * 0.5
            let derivativeSign = rootAtLower ? 1.0 : -1.0
            let scale = sqrt(2.0 * (upperAngle - lowerAngle))
            distanceRoot = ScalarDifferential(
                value: scale * sin(argument),
                first: derivativeSign * scale * halfPhaseScale
                    * cos(argument),
                second: -scale * halfPhaseScale * halfPhaseScale
                    * sin(argument)
            )
        case .twoSimpleRoots:
            factor = try regularizedDiscriminantFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let phase = Double.pi * fraction
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            distanceRoot = ScalarDifferential(
                value: halfSpan * sin(phase),
                first: halfSpan * Double.pi * cos(phase),
                second: -halfSpan * Double.pi * Double.pi * sin(phase)
            )
        case .rootFree:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A root-free sphere-torus graph edge does not use endpoint regularization."
            )
        }
        return try regularizedSquareRootDifferential(
            factor: factor,
            distanceRoot: distanceRoot,
            angle: angle,
            branchSign: branchSign,
            tolerance: tolerance,
            label: "open sphere-torus"
        , using: &execution)
    }

    private func regularizedSquareRootDifferential(
        factor: ScalarDifferential,
        distanceRoot: ScalarDifferential,
        angle: ScalarDifferential,
        branchSign: Double,
        tolerance: ModelingTolerance,
        label: String
    , using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard factor.value > 0.0, factor.value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: factor.value,
                tolerance: tolerance,
                message: "A \(label) component lost its positive regularized discriminant factor."
            )
        }
        let root = sqrt(factor.value)
        let rootByAngle = ScalarDifferential(
            value: root,
            first: factor.first / (2.0 * root),
            second: factor.second / (2.0 * root)
                - factor.first * factor.first
                    / (4.0 * root * root * root)
        )
        let rootByFraction = ScalarDifferential(
            value: rootByAngle.value,
            first: rootByAngle.first * angle.first,
            second: rootByAngle.second * angle.first * angle.first
                + rootByAngle.first * angle.second
        )
        let result = distanceRoot
            .multiplied(by: rootByFraction)
            .scaled(by: branchSign)
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A \(label) regularized square-root differential exceeded finite arithmetic."
            )
        }
        return result
    }

    private func regularizedDiscriminantFactorDifferential(
        at angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
                message: "A sphere-torus regularized factor was evaluated outside its certified angular component."
            )
        }
        let polynomial = configuration.discriminant
        let lowerValue = polynomial.value(at: lowerAngle)
        let upperValue = polynomial.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = (try Self.trigonometricDividedDifference(
            polynomial,
            value: angle,
            endpoint: endpoint
        , using: &execution))
        let numerator = usesLowerEndpoint
            ? dividedDifference.adding(.constant(-correctionSlope))
            : ScalarDifferential.constant(correctionSlope)
                .subtracting(dividedDifference)
        let denominator = usesLowerEndpoint
            ? ScalarDifferential(
                value: upperAngle - angle,
                first: -1.0,
                second: 0.0
            )
            : ScalarDifferential(
                value: angle - lowerAngle,
                first: 1.0,
                second: 0.0
            )
        return try numerator.divided(by: denominator, using: &execution)
    }

    private static func trigonometricDividedDifference<A: ExactScalarAdmission & ~Copyable>(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    , using execution: inout A) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result = ScalarDifferential.constant(0.0)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: (order: Double, cosine: Double, sine: Double).self))
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
            try execution.consumeWork(1)
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
                )
            )
            result = result.adding(
                sinc.multiplied(by: amplitude).scaled(by: harmonic.order)
            )
        }
        return result
    }

    private static func sincDifferential(
        at value: Double,
        derivativeScale: Double
    ) -> ScalarDifferential {
        let absolute = abs(value)
        if absolute <= 0.25 {
            let squared = value * value
            let fourth = squared * squared
            let sixth = fourth * squared
            let eighth = fourth * fourth
            return ScalarDifferential(
                value: 1.0 - squared / 6.0 + fourth / 120.0
                    - sixth / 5_040.0 + eighth / 362_880.0,
                first: derivativeScale * (
                    -value / 3.0 + value * squared / 30.0
                        - value * fourth / 840.0
                        + value * sixth / 45_360.0
                ),
                second: derivativeScale * derivativeScale * (
                    -1.0 / 3.0 + squared / 10.0
                        - fourth / 168.0 + sixth / 6_480.0
                )
            )
        }
        let inverse = 1.0 / value
        let inverseSquared = inverse * inverse
        let inverseCubed = inverseSquared * inverse
        return ScalarDifferential(
            value: sin(value) * inverse,
            first: derivativeScale * (
                cos(value) * inverse - sin(value) * inverseSquared
            ),
            second: derivativeScale * derivativeScale * (
                -sin(value) * inverse
                    - 2.0 * cos(value) * inverseSquared
                    + 2.0 * sin(value) * inverseCubed
            )
        )
    }

    private func openEndpointStructure(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> OpenEndpointStructure {
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let lowerIsRoot = abs(
            configuration.discriminant.value(at: lowerAngle)
        ) <= classificationTolerance * 16.0
        let upperIsRoot = abs(
            configuration.discriminant.value(at: upperAngle)
        ) <= classificationTolerance * 16.0
        if lowerIsRoot == false, upperIsRoot == false {
            return .rootFree
        }
        if lowerIsRoot, upperIsRoot == false {
            return .lowerSimpleRoot
        }
        if lowerIsRoot == false, upperIsRoot {
            return .upperSimpleRoot
        }
        return .twoSimpleRoots
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
    , using execution: inout OriginalQueryExecution) throws -> Configuration {
        try GeometryStructuralComparisonWork.charge(surface: sphereSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: torusSurface, using: &execution)
        try execution.checkpoint()
        try execution.consumeWork(1)
        try sphereSurface.validate(tolerance: tolerance, using: &execution)
        try torusSurface.validate(tolerance: tolerance, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.25,
                Double.ulpOfOne * 1_024.0
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: 1_024,
            tolerance: tolerance
        )
        var values = try (try CertifiedAnalyticCurveEvaluation.map(solver.roots(
            coefficients: try polynomial.tangentHalfAngleCoefficients(using: &execution)
        , using: &execution), using: &execution) { element, execution in  normalizedAngle(2.0 * atan(element.value))  })
        var valuesCapacity = values.count
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            try CertifiedAnalyticCurveEvaluation.append(Double.pi, to: &values, using: &execution, capacity: &valuesCapacity)
        }
        values = (try CertifiedAnalyticCurveEvaluation.sorted((try CertifiedAnalyticCurveEvaluation.filter((try CertifiedAnalyticCurveEvaluation.map(values, using: &execution) { element, execution in 
            (try refinedAngle(
                element,
                polynomial: polynomial,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            , using: &execution))
         }), using: &execution) { element, execution in 
            abs(polynomial.value(at: element)) <= residualTolerance * 16.0
         }), using: &execution))
        var result: [Double] = []
        var resultCapacity = result.count
        for value in values where result.last.map({
            angularDistance($0, value) <= tolerance.angle
        }) != true {
            try execution.consumeWork(1)
            try CertifiedAnalyticCurveEvaluation.append(value, to: &result, using: &execution, capacity: &resultCapacity)
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
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let stationaryAngles = try roots(
            of: polynomial.derivativePolynomial, residualTolerance: residualTolerance,
            tolerance: tolerance, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(
            count: try exactScalarCount(stationaryAngles.count, 1), of: Double.self))
        let angles = [0.0] + stationaryAngles
        let values = (try CertifiedAnalyticCurveEvaluation.map(angles, using: &execution) { element, _ in polynomial.value(at: element) })
        return maximum
            ? values.max() ?? polynomial.value(at: 0.0)
            : values.min() ?? polynomial.value(at: 0.0)
    }

    private static func validIntervals<A: ExactScalarAdmission & ~Copyable>(
        boundaries: [Double],
        polynomial: TrigonometricPolynomial,
        classificationTolerance: Double
    , using execution: inout A) throws -> [(lower: Double, upper: Double)] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard boundaries.isEmpty == false else { return [] }
        return (try CertifiedAnalyticCurveEvaluation.compactMap(boundaries.indices, using: &execution) { index, execution in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return polynomial.value(at: lower + (upper - lower) * 0.5)
                > classificationTolerance
                ? (lower, upper)
                : nil
         })
    }

    private static func minimumAmplitude<A: ExactScalarAdmission & ~Copyable>(
        configuration: Configuration,
        lowerAngle: Double,
        upperAngle: Double
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let phase = atan2(configuration.radialSine, configuration.radialCosine)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        var candidates = [lowerAngle, upperAngle]
        var candidatesCapacity = candidates.count
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        for base in [phase, phase + Double.pi] {
            try execution.consumeWork(1)
            for turn in -2...3 {
                try execution.consumeWork(1)
                let angle = base + Double(turn) * 2.0 * Double.pi
                if angle >= lowerAngle, angle <= upperAngle {
                    try CertifiedAnalyticCurveEvaluation.append(angle, to: &candidates, using: &execution, capacity: &candidatesCapacity)
                }
            }
        }
        return (try CertifiedAnalyticCurveEvaluation.map(candidates, using: &execution) { angle, execution in
            hypot(
                configuration.torus.majorRadius
                    + configuration.radialOffset(at: angle),
                configuration.axialCoefficient
            )
         }).min() ?? .infinity
    }

    private static func boundedAngleRange<A: ExactScalarAdmission & ~Copyable>(
        phaseLower: Double,
        phaseUpper: Double,
        lowerAngle: Double,
        upperAngle: Double
    , using execution: inout A) throws -> (lower: Double, upper: Double) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        var values = [
            midpoint - halfSpan * cos(phaseLower),
            midpoint - halfSpan * cos(phaseUpper),
        ]
        var valuesCapacity = values.count
        for index in 0...2 {
            try execution.consumeWork(1)
            let phase = Double(index) * Double.pi
            if phase > phaseLower, phase < phaseUpper {
                try CertifiedAnalyticCurveEvaluation.append(midpoint - halfSpan * cos(phase), to: &values, using: &execution, capacity: &valuesCapacity)
            }
        }
        return (
            max(lowerAngle, values.min() ?? lowerAngle).nextDown,
            min(upperAngle, values.max() ?? upperAngle).nextUp
        )
    }

    private static func maximumAbsoluteTrigonometricValue<A: ExactScalarAdmission & ~Copyable>(
        lower: Double,
        upper: Double,
        phase: Double
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result = max(
            abs(cos(lower - phase)),
            abs(cos(upper - phase))
        )
        for index in -2...4 {
            try execution.consumeWork(1)
            let extremum = phase + Double(index) * Double.pi
            if extremum > lower, extremum < upper {
                result = 1.0
            }
        }
        return result.nextUp
    }

    private static func discriminantRange(
        configuration: Configuration,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        var candidateAngles = [lower, upper]
        var candidateAnglesCapacity = candidateAngles.count
        let derivative = configuration.discriminant.derivativePolynomial
        let derivativeMagnitude = coefficientMagnitudeUpperBound(derivative)
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
            , using: &execution) {
                try execution.consumeWork(1)
                (try appendPeriodicAngle(
                    angle,
                    from: lower,
                    to: upper,
                    result: &candidateAngles, capacity: &candidateAnglesCapacity
                , using: &execution))
            }
        }
        let values = (try CertifiedAnalyticCurveEvaluation.map(candidateAngles, using: &execution) { element, _ in configuration.discriminant.value(at: element) })
        return (
            ((values.min() ?? -.infinity) - arithmeticEnvelope).nextDown,
            ((values.max() ?? .infinity) + arithmeticEnvelope).nextUp
        )
    }

    private static func maximumAbsoluteHarmonic(
        constant: Double,
        cosine: Double,
        sine: Double,
        lowerAngle: Double,
        upperAngle: Double
    ) -> Double {
        let amplitude = hypot(cosine, sine).nextUp
        let globalBound = (abs(constant) + amplitude).nextUp
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfWidth = ((upperAngle - lowerAngle) * 0.5).nextUp
        let coefficientScale = max(
            abs(constant),
            abs(cosine),
            abs(sine),
            1.0
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne * coefficientScale * 64.0
        ).nextUp
        let midpointBound = (
            abs(
                constant
                    + cosine * cos(midpoint)
                    + sine * sin(midpoint)
            ) + arithmeticEnvelope
        ).nextUp
        let localBound = (
            midpointBound + (amplitude * halfWidth).nextUp
        ).nextUp
        return min(globalBound, localBound).nextUp
    }

    private static func maximumAbsolutePolynomial(
        _ polynomial: TrigonometricPolynomial,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        let derivative = polynomial.derivativePolynomial
        let globalValueBound = coefficientMagnitudeUpperBound(polynomial)
        let globalDerivativeBound = coefficientMagnitudeUpperBound(derivative)
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfWidth = ((upperAngle - lowerAngle) * 0.5).nextUp
        let arithmeticEnvelope = max(
            Double.ulpOfOne * polynomial.coefficientScale * 64.0,
            tolerance.relative * polynomial.coefficientScale * 1.0e-9
        )
        let midpointBound = (
            abs(polynomial.value(at: midpoint)) + arithmeticEnvelope
        ).nextUp
        let localBound = (
            midpointBound
                + (globalDerivativeBound * halfWidth).nextUp
        ).nextUp
        return min(globalValueBound, localBound).nextUp
    }

    private static func coefficientMagnitudeUpperBound(
        _ polynomial: TrigonometricPolynomial
    ) -> Double {
        var result = abs(polynomial.constant).nextUp
        result = (result + abs(polynomial.cosine)).nextUp
        result = (result + abs(polynomial.sine)).nextUp
        result = (result + abs(polynomial.cosineDouble)).nextUp
        return (result + abs(polynomial.sineDouble)).nextUp
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            (try minimumAmplitude(
                configuration: configuration,
                lowerAngle: lowerAngle,
                upperAngle: upperAngle
            , using: &execution)),
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

    private static func refinedAngle<A: ExactScalarAdmission & ~Copyable>(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var angle = normalizedAngle(initial)
        let effectiveResidual = max(
            Double.ulpOfOne * polynomial.coefficientScale * 128.0,
            residualTolerance * 1.0e-8
        )
        for _ in 0..<128 {
            try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> [PoleContact] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result: [PoleContact] = []
        var resultCapacity = result.count
        let branchTolerance = sqrt(classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        ))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        for sign in [-1.0, 1.0] {
            try execution.consumeWork(1)
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
                try execution.consumeWork(1)
                try CertifiedAnalyticCurveEvaluation.append(PoleContact(
                    angle: angle,
                    branch: branch
                ), to: &result, using: &execution, capacity: &resultCapacity)
            }
        }
        return result
    }

    private static func minimumDiscriminant(
        from lower: Double,
        to upper: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        var candidateAngles = [lower, upper]
        var candidateAnglesCapacity = candidateAngles.count
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
            , using: &execution) {
                try execution.consumeWork(1)
                (try appendPeriodicAngle(
                    angle,
                    from: lower,
                    to: upper,
                    result: &candidateAngles, capacity: &candidateAnglesCapacity
                , using: &execution))
            }
        }
        return try CertifiedAnalyticCurveEvaluation.map(candidateAngles, using: &execution) { angle, _ in configuration.discriminant.value(at: angle) }
            .min() ?? -.infinity
    }

    private static func appendPeriodicAngle<A: ExactScalarAdmission & ~Copyable>(
        _ angle: Double,
        from lower: Double,
        to upper: Double,
        result: inout [Double], capacity: inout Int
    , using execution: inout A) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let firstIndex = ceil((lower - angle) / period)
        let adjusted = angle + firstIndex * period
        if adjusted >= lower, adjusted <= upper {
            try CertifiedAnalyticCurveEvaluation.append(adjusted, to: &result, using: &execution, capacity: &capacity)
        }
    }

    private static func adjustedAngle<A: ExactScalarAdmission & ~Copyable>(
        _ angle: Double,
        inside interval: ClosedRange<Double>
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        var adjusted = normalizedAngle(angle)
        while adjusted < interval.lowerBound {
            try execution.consumeWork(1)
            adjusted += period
        }
        while adjusted > interval.upperBound,
              adjusted - period >= interval.lowerBound {
            try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case sphereSurface
        case torusSurface
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
        , using: &execution)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)

        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sphereSurface, forKey: .sphereSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedSphereTorusIntersectionCurve: Codable {}
extension CertifiedSphereTorusIntersectionCurve.ComponentKind: Codable {}
#endif
