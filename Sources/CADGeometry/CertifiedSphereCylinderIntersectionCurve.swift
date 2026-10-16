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

public struct CertifiedSphereCylinderIntersectionCurve: Hashable, Sendable {
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

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let cylinder: Cylinder
        let axialCenter: Double
        let radicandCenter: Double
        let radicandCosine: Double
        let radicandSine: Double

        var characteristicLength: Double {
            max(
                (cylinder.origin - sphere.center).length,
                sphere.radius,
                cylinder.radius,
                1.0
            )
        }

        var radicandAmplitude: Double {
            hypot(radicandCosine, radicandSine)
        }

        func radicand(at angle: Double) -> Double {
            radicandCenter
                + radicandCosine * cos(angle)
                + radicandSine * sin(angle)
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            -radicandCosine * sin(angle) + radicandSine * cos(angle)
        }

        func radicandSecondDerivative(at angle: Double) -> Double {
            -radicandCosine * cos(angle) - radicandSine * sin(angle)
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
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
    }

    private enum OpenEndpointStructure: Equatable {
        case rootFree
        case lowerSimpleRoot
        case upperSimpleRoot
        case twoSimpleRoots
        case lowerDoubleRoot
        case upperDoubleRoot
        case twoDoubleRoots
    }

    public let sphereSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        self.sphereSurface = sphereSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
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

    private static func poleSplitNodesImplementation(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [(angle: Double, branch: Double)] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let contacts = try spherePoleContacts(configuration: configuration, tolerance: tolerance, using: &execution)
        return try CertifiedAnalyticCurveEvaluation.map(contacts, using: &execution) { value, _ in
            (angle: value.angle, branch: value.branch)
        }
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
                message: "A sphere-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
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
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance,
                using: &execution).contains { try execution.consumeWork(1); return $0.branch == branch }
            let minimumRadicand = configuration.radicandCenter
                - configuration.radicandAmplitude
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  hasSpherePoleContact == false,
                  minimumRadicand > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumRadicand,
                    tolerance: tolerance,
                    message: "A full sphere-cylinder branch requires a positive root-free, sphere-pole-free radicand domain."
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
                    message: "A bounded sphere-cylinder component is not a complete simple-root interval."
                )
            }
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let branch = componentKind == .negativeOpenAngularInterval ? -1.0 : 1.0
            let allContacts = try Self.spherePoleContacts(configuration: configuration, tolerance: tolerance, using: &execution)
            var contacts: [PoleContact] = []
            try CertifiedAnalyticCurveEvaluation.reserveCapacity(allContacts.count, in: &contacts, using: &execution)
            for contact in allContacts { try execution.consumeWork(1); if contact.branch == branch { contacts.append(contact) } }
            let lowerIsPole = try contacts.contains {
                try execution.consumeWork(1)
                return Self.angularDistance($0.angle, lowerAngle) <= tolerance.angle
            }
            let upperIsPole = try contacts.contains {
                try execution.consumeWork(1)
                return Self.angularDistance($0.angle, upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerIsRoot = lowerResidual <= classificationTolerance * 16.0
            let upperIsRoot = upperResidual <= classificationTolerance * 16.0
            let hasInteriorPole = try contacts.contains { contact in
                try execution.consumeWork(1)
                let adjusted = try Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle,
                    using: &execution)
                return adjusted > lowerAngle + tolerance.angle
                    && adjusted < upperAngle - tolerance.angle
            }
            let minimumRadicand = try Self.minimumRadicand(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration,
                using: &execution)
            guard lowerIsPole || lowerIsRoot,
                  upperIsPole || upperIsRoot,
                  hasInteriorPole == false,
                  minimumRadicand >= -classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(
                        max(lowerResidual, upperResidual),
                        max(0.0, -minimumRadicand)
                    ),
                    tolerance: tolerance,
                    message: "An open sphere-cylinder branch is not one complete nonnegative interval between consecutive certified graph nodes."
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
                message: "A sphere-cylinder curve exceeded its certified geometric residual."
            )
        }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance,
                using: &execution)
            let sphereProjection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance,
                using: &execution)
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance,
                using: &execution)
            let residual = max(sphereProjection.residual, cylinderProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A sphere-cylinder curve failed its algebraic reconstruction check."
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
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let angle = try angleDifferential(
            at: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let angularFirst = configuration.radicandFirstDerivative(at: angle.value)
        let radicand = ScalarDifferential(
            value: configuration.radicand(at: angle.value),
            first: angularFirst * angle.first,
            second: configuration.radicandSecondDerivative(at: angle.value)
                * angle.first * angle.first + angularFirst * angle.second
        )
        let root = try signedSquareRootDifferential(
            radicand,
            angle: angle.value,
            fraction: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let height = ScalarDifferential(
            value: -configuration.axialCenter + root.value,
            first: root.first,
            second: root.second
        )
        let geometry = try configuration.cylinder.surface.differentialGeometry(
            u: angle.value,
            v: height.value,
            tolerance: tolerance,
            using: &execution)
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
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified sphere-cylinder component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: geometry.position,
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
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let source = CurveTaylorScalarJet.variable(clamped)
        let angle = try angleTaylorJet(
            at: source,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let root = try signedSquareRootTaylorJet(
            angle: angle,
            fraction: source,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let height = CurveTaylorScalarJet(value: -configuration.axialCenter)
            + root
        let surface = try cylinderSurface.parameterDerivativesThroughThirdOrder(
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
                message: "Sphere-cylinder Taylor differentiation disagrees with the certified lower-order differential."
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
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: sphereSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: cylinderSurface, using: &execution)
        guard surface == sphereSurface || surface == cylinderSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A sphere-cylinder pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            using: &execution)
        if surface == sphereSurface {
            return try sphereParameter(
                for: point,
                atNormalizedFraction: fraction,
                tolerance: tolerance,
                using: &execution)
        }
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
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let height = abs(configuration.axialCenter)
            + sqrt(max(
                configuration.radicandCenter + configuration.radicandAmplitude,
                0.0
            ))
        let radius = configuration.cylinder.radius + height + tolerance.distance
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

    private func fullBranchSpatialDifferentialMagnitudeBoundsImplementation(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Root-free sphere-cylinder differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let amplitude = configuration.radicandAmplitude.nextUp
        let minimumRadicand = (
            configuration.radicandCenter - amplitude - arithmeticEnvelope
        ).nextDown
        guard minimumRadicand > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cylinder differential certificate lost its positive radicand lower bound."
            )
        }
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try upperProduct(
            period,
            period,
            tolerance: tolerance,
            using: &execution)
        let periodCubed = try upperProduct(
            periodSquared,
            period,
            tolerance: tolerance,
            using: &execution)
        let radicandFirst = try upperProduct(
            amplitude,
            period,
            tolerance: tolerance,
            using: &execution)
        let radicandSecond = try upperProduct(
            amplitude,
            periodSquared,
            tolerance: tolerance,
            using: &execution)
        let radicandThird = try upperProduct(
            amplitude,
            periodCubed,
            tolerance: tolerance,
            using: &execution)
        let rootLower = sqrt(minimumRadicand).nextDown
        guard rootLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cylinder square-root lower bound collapsed."
            )
        }
        let rootFirst = try upperQuotient(
            radicandFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance,
            using: &execution)
        let rootCubedLower = (
            (rootLower * rootLower).nextDown * rootLower
        ).nextDown
        let rootSecond = try upperSum(
            try upperQuotient(
                radicandSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance,
                using: &execution),
            try upperQuotient(
                try upperProduct(
                    radicandFirst,
                    radicandFirst,
                    tolerance: tolerance,
                    using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance,
                using: &execution),
            tolerance: tolerance,
            using: &execution)
        let rootFifthLower = (
            rootCubedLower * rootLower * rootLower
        ).nextDown
        let rootThird = try upperSum(
            try upperQuotient(
                radicandThird,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance,
                using: &execution),
            try upperSum(
                try upperQuotient(
                    try upperProduct(
                        3.0,
                        try upperProduct(
                            radicandFirst,
                            radicandSecond,
                            tolerance: tolerance,
                            using: &execution),
                        tolerance: tolerance,
                        using: &execution),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance,
                    using: &execution),
                try upperQuotient(
                    try upperProduct(
                        3.0,
                        try upperProduct(
                            radicandFirst,
                            try upperProduct(
                                radicandFirst,
                                radicandFirst,
                                tolerance: tolerance,
                                using: &execution),
                            tolerance: tolerance,
                            using: &execution),
                        tolerance: tolerance,
                        using: &execution),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance,
                    using: &execution),
                tolerance: tolerance,
                using: &execution),
            tolerance: tolerance,
            using: &execution)
        let angularFirst = try upperProduct(
            configuration.cylinder.radius,
            period,
            tolerance: tolerance,
            using: &execution)
        let angularSecond = try upperProduct(
            configuration.cylinder.radius,
            periodSquared,
            tolerance: tolerance,
            using: &execution)
        let angularThird = try upperProduct(
            configuration.cylinder.radius,
            periodCubed,
            tolerance: tolerance,
            using: &execution)
        let first = hypot(angularFirst, rootFirst).nextUp
        let second = hypot(angularSecond, rootSecond).nextUp
        let third = hypot(angularThird, rootThird).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func boundedBranchSpatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
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
        guard componentKind == .boundedAngularInterval else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded sphere-cylinder differential bounds require a complete simple-root interval."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength
                * 131_072.0
        ).nextUp
        let phaseLower = 2.0 * Double.pi
            * max(lowerFraction, 0.0)
        let phaseUpper = 2.0 * Double.pi
            * min(upperFraction, 1.0)
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let amplitude = configuration.radicandAmplitude.nextUp
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: lowerAngle,
            requestedUpper: upperAngle,
            lowerValue: configuration.radicand(at: lowerAngle),
            upperValue: configuration.radicand(at: upperAngle),
            lowerDerivative: configuration.radicandFirstDerivative(
                at: lowerAngle
            ),
            upperDerivative: configuration.radicandFirstDerivative(
                at: upperAngle
            ),
            firstDerivativeMagnitudeUpperBound: amplitude,
            secondDerivativeMagnitudeUpperBound: amplitude,
            thirdDerivativeMagnitudeUpperBound: amplitude,
            fourthDerivativeMagnitudeUpperBound: amplitude,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { lower, upper, execution in
                (
                    try Self.minimumRadicand(
                        from: lower,
                        to: upper,
                        configuration: configuration,
                        using: &execution).nextDown,
                    (
                        configuration.radicandCenter
                            + configuration.radicandAmplitude
                    ).nextUp
                )
            },
            tolerance: tolerance,
            label: "Sphere-cylinder bounded branch",
            using: &execution)
        let rootBounds = try factorSquareRootBounds(
            lower: factor.lower,
            upper: factor.upper,
            first: factor.first,
            second: factor.second,
            third: factor.third,
            tolerance: tolerance,
            using: &execution)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = (period * period).nextUp
        let periodCubed = (periodSquared * period).nextUp
        let sineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5,
            using: &execution)
        let cosineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0,
            using: &execution)
        let angleFirst = (
            halfSpan * period * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * periodSquared * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * periodCubed * sineMagnitude
        ).nextUp
        let transverseFirst = (
            halfSpan * (
                period * cosineMagnitude * rootBounds.value
                    + sineMagnitude * rootBounds.first * angleFirst
            )
        ).nextUp
        let transverseSecond = (
            halfSpan * (
                periodSquared * sineMagnitude * rootBounds.value
                    + 2.0 * period * cosineMagnitude
                        * rootBounds.first * angleFirst
                    + sineMagnitude * (
                        rootBounds.second * angleFirst * angleFirst
                            + rootBounds.first * angleSecond
                    )
            )
        ).nextUp
        let rootByFractionFirst = (
            rootBounds.first * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootBounds.second * angleFirst * angleFirst
                + rootBounds.first * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootBounds.third * angleFirst * angleFirst * angleFirst
                + 3.0 * rootBounds.second * angleFirst * angleSecond
                + rootBounds.first * angleThird
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
        let transverseThird = (
            prefixThird * rootBounds.value
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixValue * rootByFractionThird
        ).nextUp
        let radialFirst = (
            configuration.cylinder.radius * angleFirst
        ).nextUp
        let radialSecond = (
            configuration.cylinder.radius
                * hypot(angleFirst * angleFirst, angleSecond)
        ).nextUp
        let radialThird = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let first = hypot(radialFirst, transverseFirst).nextUp
        let second = hypot(radialSecond, transverseSecond).nextUp
        let third = hypot(radialThird, transverseThird).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Bounded sphere-cylinder spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func openBranchSpatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard componentKind == .negativeOpenAngularInterval
                || componentKind == .positiveOpenAngularInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Open sphere-cylinder differential bounds require a valid pole-split source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let structure = try openEndpointStructure(
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        switch structure {
        case .rootFree:
            return try rootFreeOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
        case .twoSimpleRoots:
            return try twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
        case .lowerSimpleRoot, .upperSimpleRoot,
             .lowerDoubleRoot, .upperDoubleRoot:
            return try oneSidedOpenSpatialDifferentialMagnitudeBounds(
                structure: structure,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
        case .twoDoubleRoots:
            return try twoDoubleRootOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
        }
    }

    private func rootFreeOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let span = (upperAngle - lowerAngle).nextUp
        let angleLower = lowerAngle
            + (upperAngle - lowerAngle) * lowerFraction
        let angleUpper = lowerAngle
            + (upperAngle - lowerAngle) * upperFraction
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength
                * 131_072.0
        ).nextUp
        let minimumRadicand = (
            try Self.minimumRadicand(
                from: angleLower,
                to: angleUpper,
                configuration: configuration,
                using: &execution) - arithmeticEnvelope
        ).nextDown
        guard minimumRadicand > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free pole-split sphere-cylinder differential certificate lost its positive radicand margin."
            )
        }
        let amplitude = configuration.radicandAmplitude.nextUp
        let rootLower = sqrt(minimumRadicand).nextDown
        let rootFirstByAngle = (
            amplitude / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (
            minimumRadicand * rootLower
        ).nextDown
        let rootSecondByAngle = (
            amplitude / (2.0 * rootLower).nextDown
                + amplitude * amplitude
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let rootFifthLower = (
            minimumRadicand * minimumRadicand * rootLower
        ).nextDown
        let rootThirdByAngle = (
            amplitude / (2.0 * rootLower).nextDown
                + 3.0 * amplitude * amplitude
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * amplitude * amplitude * amplitude
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let axialFirst = (rootFirstByAngle * span).nextUp
        let axialSecond = (
            rootSecondByAngle * span * span
        ).nextUp
        let axialThird = (
            rootThirdByAngle * span * span * span
        ).nextUp
        return try spatialBounds(
            angleFirst: span,
            angleSecond: 0.0,
            angleThird: 0.0,
            axialFirst: axialFirst,
            axialSecond: axialSecond,
            axialThird: axialThird,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
    }

    private func twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength
                * 131_072.0
        ).nextUp
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let span = (upperAngle - lowerAngle).nextUp
        let requestedLower = lowerAngle + span * (
            0.5 - 0.5 * cos(Double.pi * lowerFraction)
        )
        let requestedUpper = lowerAngle + span * (
            0.5 - 0.5 * cos(Double.pi * upperFraction)
        )
        let amplitude = configuration.radicandAmplitude.nextUp
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower.nextDown,
            requestedUpper: requestedUpper.nextUp,
            lowerValue: configuration.radicand(at: lowerAngle),
            upperValue: configuration.radicand(at: upperAngle),
            lowerDerivative: configuration.radicandFirstDerivative(
                at: lowerAngle
            ),
            upperDerivative: configuration.radicandFirstDerivative(
                at: upperAngle
            ),
            firstDerivativeMagnitudeUpperBound: amplitude,
            secondDerivativeMagnitudeUpperBound: amplitude,
            thirdDerivativeMagnitudeUpperBound: amplitude,
            fourthDerivativeMagnitudeUpperBound: amplitude,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { lower, upper, execution in
                (
                    try Self.minimumRadicand(
                        from: lower,
                        to: upper,
                        configuration: configuration,
                        using: &execution).nextDown,
                    (
                        configuration.radicandCenter
                            + configuration.radicandAmplitude
                    ).nextUp
                )
            },
            tolerance: tolerance,
            label: "Sphere-cylinder two-simple-root open branch",
            using: &execution)
        let rootBounds = try factorSquareRootBounds(
            lower: factor.lower,
            upper: factor.upper,
            first: factor.first,
            second: factor.second,
            third: factor.third,
            tolerance: tolerance,
            using: &execution)
        let phaseLower = Double.pi * lowerFraction
        let phaseUpper = Double.pi * upperFraction
        let sineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5,
            using: &execution)
        let cosineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0,
            using: &execution)
        let angleFirst = (
            halfSpan * Double.pi * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * Double.pi * Double.pi * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * pow(Double.pi, 3.0) * sineMagnitude
        ).nextUp
        let axialFirst = (
            halfSpan * (
                Double.pi * cosineMagnitude * rootBounds.value
                    + sineMagnitude * rootBounds.first * angleFirst
            )
        ).nextUp
        let axialSecond = (
            halfSpan * (
                Double.pi * Double.pi
                    * sineMagnitude * rootBounds.value
                    + 2.0 * Double.pi * cosineMagnitude
                        * rootBounds.first * angleFirst
                    + sineMagnitude * (
                        rootBounds.second * angleFirst * angleFirst
                            + rootBounds.first * angleSecond
                    )
            )
        ).nextUp
        let rootByFractionFirst = (
            rootBounds.first * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootBounds.second * angleFirst * angleFirst
                + rootBounds.first * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootBounds.third * angleFirst * angleFirst * angleFirst
                + 3.0 * rootBounds.second * angleFirst * angleSecond
                + rootBounds.first * angleThird
        ).nextUp
        let prefixValue = (halfSpan * sineMagnitude).nextUp
        let prefixFirst = (
            halfSpan * Double.pi * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * Double.pi * Double.pi * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * pow(Double.pi, 3.0) * cosineMagnitude
        ).nextUp
        let axialThird = (
            prefixThird * rootBounds.value
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixValue * rootByFractionThird
        ).nextUp
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            axialFirst: axialFirst,
            axialSecond: axialSecond,
            axialThird: axialThird,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
    }

    private func oneSidedOpenSpatialDifferentialMagnitudeBounds(
        structure: OpenEndpointStructure,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let lowerAngleGeometry = try angleDifferential(
            at: lowerFraction,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let upperAngleGeometry = try angleDifferential(
            at: upperFraction,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let requestedLowerAngle = min(
            lowerAngleGeometry.value,
            upperAngleGeometry.value
        ).nextDown
        let requestedUpperAngle = max(
            lowerAngleGeometry.value,
            upperAngleGeometry.value
        ).nextUp
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength
                * 131_072.0
        ).nextUp
        let amplitude = configuration.radicandAmplitude.nextUp
        let span = (upperAngle - lowerAngle).nextUp
        let factor: EndpointRegularizedFactorBounder.Bounds
        let angleFirst: Double
        let angleSecond: Double
        let angleThird: Double
        let prefixValue: Double
        let prefixFirst: Double
        let prefixSecond: Double
        let prefixThird: Double

        switch structure {
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let endpoint = rootAtLower ? lowerAngle : upperAngle
            factor = try EndpointRegularizedFactorBounder().oneSidedBounds(
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                requestedLower: requestedLowerAngle,
                requestedUpper: requestedUpperAngle,
                rootAtLower: rootAtLower,
                endpointValue: configuration.radicand(at: endpoint),
                endpointDerivative:
                    configuration.radicandFirstDerivative(at: endpoint),
                firstDerivativeMagnitudeUpperBound: amplitude,
                secondDerivativeMagnitudeUpperBound: amplitude,
                thirdDerivativeMagnitudeUpperBound: amplitude,
                fourthDerivativeMagnitudeUpperBound: amplitude,
                arithmeticEnvelope: arithmeticEnvelope,
                orientedValueRange: { lower, upper, execution in
                    (
                        try Self.minimumRadicand(
                            from: lower,
                            to: upper,
                            configuration: configuration,
                            using: &execution).nextDown,
                        (
                            configuration.radicandCenter
                                + configuration.radicandAmplitude
                        ).nextUp
                    )
                },
                tolerance: tolerance,
                label: "Sphere-cylinder one-sided simple-root branch",
                using: &execution)
            let angularRate = Double.pi * 0.5
            let angularPhaseLower = angularRate * lowerFraction
            let angularPhaseUpper = angularRate * upperFraction
            let firstMagnitude = try Self.maximumAbsoluteTrigonometricValue(
                lower: angularPhaseLower,
                upper: angularPhaseUpper,
                phase: rootAtLower ? Double.pi * 0.5 : 0.0,
                using: &execution)
            let secondMagnitude = try Self.maximumAbsoluteTrigonometricValue(
                lower: angularPhaseLower,
                upper: angularPhaseUpper,
                phase: rootAtLower ? 0.0 : Double.pi * 0.5,
                using: &execution)
            angleFirst = (span * angularRate * firstMagnitude).nextUp
            angleSecond = (
                span * angularRate * angularRate * secondMagnitude
            ).nextUp
            angleThird = (
                span * pow(angularRate, 3.0) * firstMagnitude
            ).nextUp

            let prefixScale = sqrt(2.0 * span).nextUp
            let prefixRate = Double.pi * 0.25
            let prefixPhaseLower = rootAtLower
                ? prefixRate * lowerFraction
                : prefixRate * (1.0 - upperFraction)
            let prefixPhaseUpper = rootAtLower
                ? prefixRate * upperFraction
                : prefixRate * (1.0 - lowerFraction)
            let sineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
                lower: prefixPhaseLower,
                upper: prefixPhaseUpper,
                phase: Double.pi * 0.5,
                using: &execution)
            let cosineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
                lower: prefixPhaseLower,
                upper: prefixPhaseUpper,
                phase: 0.0,
                using: &execution)
            prefixValue = (prefixScale * sineMagnitude).nextUp
            prefixFirst = (
                prefixScale * prefixRate * cosineMagnitude
            ).nextUp
            prefixSecond = (
                prefixScale * prefixRate * prefixRate * sineMagnitude
            ).nextUp
            prefixThird = (
                prefixScale * pow(prefixRate, 3.0) * cosineMagnitude
            ).nextUp

        case .lowerDoubleRoot, .upperDoubleRoot:
            let rootAtLower = structure == .lowerDoubleRoot
            let endpoint = rootAtLower ? lowerAngle : upperAngle
            factor = try EndpointRegularizedFactorBounder()
                .oneSidedDoubleRootBounds(
                    componentLower: lowerAngle,
                    componentUpper: upperAngle,
                    requestedLower: requestedLowerAngle,
                    requestedUpper: requestedUpperAngle,
                    rootAtLower: rootAtLower,
                    endpointValue: configuration.radicand(at: endpoint),
                    endpointDerivative:
                        configuration.radicandFirstDerivative(at: endpoint),
                    endpointSecondDerivative:
                        configuration.radicandSecondDerivative(at: endpoint),
                    firstDerivativeMagnitudeUpperBound: amplitude,
                    secondDerivativeMagnitudeUpperBound: amplitude,
                    thirdDerivativeMagnitudeUpperBound: amplitude,
                    fourthDerivativeMagnitudeUpperBound: amplitude,
                    fifthDerivativeMagnitudeUpperBound: amplitude,
                    arithmeticEnvelope: arithmeticEnvelope,
                    valueRange: { lower, upper, execution in
                        (
                            try Self.minimumRadicand(
                                from: lower,
                                to: upper,
                                configuration: configuration,
                                using: &execution).nextDown,
                            (
                                configuration.radicandCenter
                                    + configuration.radicandAmplitude
                            ).nextUp
                        )
                    },
                    tolerance: tolerance,
                    label: "Sphere-cylinder one-sided double-root branch",
                    using: &execution)
            let maximumDistance = max(
                abs(requestedLowerAngle - endpoint),
                abs(requestedUpperAngle - endpoint)
            ).nextUp
            angleFirst = span
            angleSecond = 0.0
            angleThird = 0.0
            prefixValue = maximumDistance
            prefixFirst = span
            prefixSecond = 0.0
            prefixThird = 0.0

        case .rootFree, .twoSimpleRoots, .twoDoubleRoots:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A non-one-sided sphere-cylinder endpoint structure reached the one-sided differential bounder."
            )
        }

        let rootBounds = try factorSquareRootBounds(
            lower: factor.lower,
            upper: factor.upper,
            first: factor.first,
            second: factor.second,
            third: factor.third,
            tolerance: tolerance,
            using: &execution)
        let rootByFractionFirst = (
            rootBounds.first * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootBounds.second * angleFirst * angleFirst
                + rootBounds.first * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootBounds.third * angleFirst * angleFirst * angleFirst
                + 3.0 * rootBounds.second * angleFirst * angleSecond
                + rootBounds.first * angleThird
        ).nextUp
        let axialFirst = (
            prefixFirst * rootBounds.value
                + prefixValue * rootByFractionFirst
        ).nextUp
        let axialSecond = (
            prefixSecond * rootBounds.value
                + 2.0 * prefixFirst * rootByFractionFirst
                + prefixValue * rootByFractionSecond
        ).nextUp
        let axialThird = (
            prefixThird * rootBounds.value
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixValue * rootByFractionThird
        ).nextUp
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            axialFirst: axialFirst,
            axialSecond: axialSecond,
            axialThird: axialThird,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
    }
    private func twoDoubleRootOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let phaseLower = Double.pi * lowerFraction
        let phaseUpper = Double.pi * upperFraction
        let sineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5,
            using: &execution)
        let cosineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0,
            using: &execution)
        let axialScale = sqrt(
            2.0 * configuration.radicandAmplitude.nextUp
        ).nextUp
        let axialFirst = (
            axialScale * Double.pi * cosineMagnitude
        ).nextUp
        let axialSecond = (
            axialScale * Double.pi * Double.pi * sineMagnitude
        ).nextUp
        let axialThird = (
            axialScale * pow(Double.pi, 3.0) * cosineMagnitude
        ).nextUp
        return try spatialBounds(
            angleFirst: (upperAngle - lowerAngle).nextUp,
            angleSecond: 0.0,
            angleThird: 0.0,
            axialFirst: axialFirst,
            axialSecond: axialSecond,
            axialThird: axialThird,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
    }

    private func factorSquareRootBounds(
        lower: Double,
        upper: Double,
        first: Double,
        second: Double,
        third: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (
        value: Double,
        first: Double,
        second: Double,
        third: Double
    ) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let rootLower = sqrt(lower).nextDown
        let rootUpper = sqrt(upper).nextUp
        guard rootLower > 0.0,
              rootUpper.isFinite,
              first.isFinite,
              second.isFinite,
              third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A sphere-cylinder regularized square-root factor lost its positive finite margin."
            )
        }
        let rootFirst = (
            first / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (lower * rootLower).nextDown
        let rootSecond = (
            second / (2.0 * rootLower).nextDown
                + first * first
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let rootFifthLower = (lower * lower * rootLower).nextDown
        let rootThird = (
            third / (2.0 * rootLower).nextDown
                + 3.0 * first * second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * first * first * first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        return (rootUpper, rootFirst, rootSecond, rootThird)
    }

    private func spatialBounds(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        axialFirst: Double,
        axialSecond: Double,
        axialThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let radialFirst = (
            configuration.cylinder.radius * angleFirst
        ).nextUp
        let radialSecond = (
            configuration.cylinder.radius
                * hypot(angleFirst * angleFirst, angleSecond)
        ).nextUp
        let radialThird = (
            configuration.cylinder.radius * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let first = hypot(radialFirst, axialFirst).nextUp
        let second = hypot(radialSecond, axialSecond).nextUp
        let third = hypot(radialThird, axialThird).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func sphereParameter(
        for point: Point3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance,
            using: &execution)
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
                tolerance: tolerance,
                using: &execution)
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
        let endpointTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let direction: Vector3D
        if fraction <= endpointTolerance {
            direction = try differential(
                atNormalizedFraction: 0.0,
                tolerance: tolerance,
                using: &execution).firstDerivative
        } else if fraction >= 1.0 - endpointTolerance {
            direction = -(try differential(
                atNormalizedFraction: 1.0,
                tolerance: tolerance,
                using: &execution).firstDerivative)
        } else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: horizontal.length,
                tolerance: tolerance,
                message: "A pole-split sphere-cylinder pcurve reached a spherical pole away from a certified endpoint."
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

    private func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification received a negative or non-finite factor."
            )
        }
        let result = (first * second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperQuotient(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard numerator.isFinite,
              denominator.isFinite,
              numerator >= 0.0,
              denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification received a non-positive divisor."
            )
        }
        let result = (numerator / denominator).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperSum(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification received a negative or non-finite summand."
            )
        }
        let result = (first + second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cylinder differential certification exceeded finite arithmetic."
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

    private func angleDifferential(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            let structure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let normalized: ScalarDifferential
            switch structure {
            case .twoSimpleRoots:
                let phase = Double.pi * fraction
                normalized = ScalarDifferential(
                    value: 0.5 - 0.5 * cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.5 * cos(phase)
                )
            case .lowerSimpleRoot:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: 1.0 - cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.25 * cos(phase)
                )
            case .upperSimpleRoot:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: sin(phase),
                    first: Double.pi * 0.5 * cos(phase),
                    second: -Double.pi * Double.pi * 0.25 * sin(phase)
                )
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            let structure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let normalized: CurveTaylorScalarJet
            switch structure {
            case .twoSimpleRoots:
                normalized = CurveTaylorScalarJet(value: 0.5)
                    - fraction.scaled(by: Double.pi).cosine().scaled(by: 0.5)
            case .lowerSimpleRoot:
                normalized = CurveTaylorScalarJet(value: 1.0)
                    - fraction.scaled(by: Double.pi * 0.5).cosine()
            case .upperSimpleRoot:
                normalized = fraction.scaled(by: Double.pi * 0.5).sine()
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                normalized = fraction
            }
            return CurveTaylorScalarJet(value: lowerAngle)
                + normalized.scaled(by: upperAngle - lowerAngle)
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
        let context = "Sphere-cylinder third derivative"
        let branchSign: Double
        switch componentKind {
        case .negativeFullBranch, .negativeOpenAngularInterval:
            branchSign = -1.0
        case .positiveFullBranch, .positiveOpenAngularInterval,
             .boundedAngularInterval:
            branchSign = 1.0
        }
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedRadicandFactorTaylorJet(
                angle: angle,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let prefix = fraction.scaled(by: 2.0 * Double.pi).sine()
                .scaled(by: (upperAngle - lowerAngle) * 0.5)
            return try (prefix * factor.squareRoot(
                tolerance: tolerance,
                diagnosticContext: context
            )).validated(tolerance: tolerance, diagnosticContext: context)
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            switch structure {
            case .rootFree:
                break
            case .twoDoubleRoots:
                return fraction.scaled(by: Double.pi).sine().scaled(
                    by: branchSign * sqrt(2.0 * configuration.radicandAmplitude)
                )
            case .twoSimpleRoots, .lowerSimpleRoot, .upperSimpleRoot,
                 .lowerDoubleRoot, .upperDoubleRoot:
                let factor: CurveTaylorScalarJet
                let prefix: CurveTaylorScalarJet
                switch structure {
                case .twoSimpleRoots:
                    factor = try regularizedRadicandFactorTaylorJet(
                        angle: angle,
                        configuration: configuration,
                        tolerance: tolerance,
                        using: &execution)
                    prefix = fraction.scaled(by: Double.pi).sine()
                        .scaled(by: (upperAngle - lowerAngle) * 0.5)
                case .lowerSimpleRoot:
                    factor = try simpleRootFactorTaylorJet(
                        angle: angle,
                        endpoint: lowerAngle,
                        isLowerRoot: true,
                        configuration: configuration,
                        tolerance: tolerance,
                        using: &execution)
                    prefix = fraction.scaled(by: Double.pi * 0.25).sine()
                        .scaled(by: sqrt(2.0 * (upperAngle - lowerAngle)))
                case .upperSimpleRoot:
                    factor = try simpleRootFactorTaylorJet(
                        angle: angle,
                        endpoint: upperAngle,
                        isLowerRoot: false,
                        configuration: configuration,
                        tolerance: tolerance,
                        using: &execution)
                    prefix = (
                        CurveTaylorScalarJet(value: 1.0) - fraction
                    ).scaled(by: Double.pi * 0.25).sine()
                        .scaled(by: sqrt(2.0 * (upperAngle - lowerAngle)))
                case .lowerDoubleRoot:
                    factor = try doubleRootFactorTaylorJet(
                        angle: angle,
                        endpoint: lowerAngle,
                        isLowerRoot: true,
                        configuration: configuration,
                        tolerance: tolerance,
                        using: &execution)
                    prefix = fraction.scaled(by: upperAngle - lowerAngle)
                case .upperDoubleRoot:
                    factor = try doubleRootFactorTaylorJet(
                        angle: angle,
                        endpoint: upperAngle,
                        isLowerRoot: false,
                        configuration: configuration,
                        tolerance: tolerance,
                        using: &execution)
                    prefix = (CurveTaylorScalarJet(value: 1.0) - fraction)
                        .scaled(by: upperAngle - lowerAngle)
                case .rootFree, .twoDoubleRoots:
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "An incompatible sphere-cylinder endpoint structure reached Taylor regularization."
                    )
                }
                return try (
                    prefix * factor.squareRoot(
                        tolerance: tolerance,
                        diagnosticContext: context
                    )
                ).scaled(by: branchSign).validated(
                    tolerance: tolerance,
                    diagnosticContext: context
                )
            }
        }
        let radicand = CurveTaylorScalarJet(value: configuration.radicandCenter)
            + angle.cosine().scaled(by: configuration.radicandCosine)
            + angle.sine().scaled(by: configuration.radicandSine)
        return try radicand.squareRoot(
            tolerance: tolerance,
            diagnosticContext: context
        ).scaled(by: branchSign).validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
    }

    private func regularizedRadicandFactorTaylorJet(
        angle: CurveTaylorScalarJet,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Sphere-cylinder regularized radicand"
        let lower = (angle - CurveTaylorScalarJet(value: lowerAngle))
            .scaled(by: 0.5)
        let upper = (CurveTaylorScalarJet(value: upperAngle) - angle)
            .scaled(by: 0.5)
        return try (
            lower.sinc(tolerance: tolerance, diagnosticContext: context)
                * upper.sinc(tolerance: tolerance, diagnosticContext: context)
        ).scaled(by: configuration.radicandAmplitude * 0.5).validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
    }

    private func simpleRootFactorTaylorJet(
        angle: CurveTaylorScalarJet,
        endpoint: Double,
        isLowerRoot: Bool,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Sphere-cylinder simple-root factor"
        let phase = atan2(
            configuration.radicandSine,
            configuration.radicandCosine
        )
        let midpoint = (
            angle + CurveTaylorScalarJet(value: endpoint)
        ).scaled(by: 0.5) - CurveTaylorScalarJet(value: phase)
        let amplitude = midpoint.sine().scaled(by: isLowerRoot ? -1.0 : 1.0)
        let distance = isLowerRoot
            ? angle - CurveTaylorScalarJet(value: endpoint)
            : CurveTaylorScalarJet(value: endpoint) - angle
        return try (
            amplitude * distance.scaled(by: 0.5).sinc(
                tolerance: tolerance,
                diagnosticContext: context
            )
        ).scaled(by: configuration.radicandAmplitude).validated(
            tolerance: tolerance,
            diagnosticContext: context
        )
    }

    private func doubleRootFactorTaylorJet(
        angle: CurveTaylorScalarJet,
        endpoint: Double,
        isLowerRoot: Bool,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveTaylorScalarJet {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let context = "Sphere-cylinder double-root factor"
        let distance = isLowerRoot
            ? angle - CurveTaylorScalarJet(value: endpoint)
            : CurveTaylorScalarJet(value: endpoint) - angle
        let sinc = try distance.scaled(by: 0.5).sinc(
            tolerance: tolerance,
            diagnosticContext: context
        )
        return try (sinc * sinc).scaled(
            by: configuration.radicandAmplitude * 0.5
        ).validated(tolerance: tolerance, diagnosticContext: context)
    }

    private func openEndpointStructure(
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OpenEndpointStructure {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try Self.openEndpointStructure(
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
    }

    private static func openEndpointStructure(
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OpenEndpointStructure {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let residualLimit = classificationTolerance * 16.0
        let lowerResidual = abs(configuration.radicand(at: lowerAngle))
        let upperResidual = abs(configuration.radicand(at: upperAngle))
        let lowerDerivative = abs(
            configuration.radicandFirstDerivative(at: lowerAngle)
        )
        let upperDerivative = abs(
            configuration.radicandFirstDerivative(at: upperAngle)
        )
        let lowerIsRoot = lowerResidual <= residualLimit
        let upperIsRoot = upperResidual <= residualLimit
        let lowerIsSimple = lowerIsRoot
            && lowerDerivative > classificationTolerance
        let upperIsSimple = upperIsRoot
            && upperDerivative > classificationTolerance
        let lowerIsDouble = lowerIsRoot
            && lowerIsSimple == false
            && configuration.radicandSecondDerivative(at: lowerAngle)
                > classificationTolerance
        let upperIsDouble = upperIsRoot
            && upperIsSimple == false
            && configuration.radicandSecondDerivative(at: upperAngle)
                > classificationTolerance
        switch (
            lowerIsSimple,
            upperIsSimple,
            lowerIsDouble,
            upperIsDouble
        ) {
        case (false, false, false, false):
            return .rootFree
        case (true, false, false, false):
            return .lowerSimpleRoot
        case (false, true, false, false):
            return .upperSimpleRoot
        case (true, true, false, false):
            return .twoSimpleRoots
        case (false, false, true, false):
            return .lowerDoubleRoot
        case (false, false, false, true):
            return .upperDoubleRoot
        case (false, false, true, true):
            return .twoDoubleRoots
        default:
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: max(lowerResidual, upperResidual),
                tolerance: tolerance,
                message: "A pole-split sphere-cylinder component has an inconsistent endpoint root multiplicity."
            )
        }
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        angle: Double,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let algebraicTolerance = Self.classificationTolerance(
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
            let factor = try regularizedRadicandFactorDifferential(
                at: angle,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            guard factor.value > 0.0, factor.value.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "A bounded sphere-cylinder component lost its positive regularized radicand factor."
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
            let angleDifferential = try self.angleDifferential(
                at: fraction,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let rootByFraction = ScalarDifferential(
                value: rootByAngle.value,
                first: rootByAngle.first * angleDifferential.first,
                second: rootByAngle.second
                        * angleDifferential.first * angleDifferential.first
                    + rootByAngle.first * angleDifferential.second
            )
            let phase = 2.0 * Double.pi * fraction
            let sine = ScalarDifferential(
                value: sin(phase),
                first: 2.0 * Double.pi * cos(phase),
                second: -4.0 * Double.pi * Double.pi * sin(phase)
            )
            let result = Self.product(
                sine,
                rootByFraction
            ).scaled(by: (upperAngle - lowerAngle) * 0.5)
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded sphere-cylinder regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            if structure != .rootFree {
                return try openRegularizedSquareRootDifferential(
                    structure: structure,
                    angle: angle,
                    fraction: fraction,
                    branchSign: branchSign,
                    configuration: configuration,
                    tolerance: tolerance,
                    using: &execution)
            }
        }
        let endpointTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
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
           abs(radicand.value) <= algebraicTolerance * 32.0 {
            let squaredSlope = radicand.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A sphere-cylinder radicand endpoint has no regular square-root continuation."
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
        guard radicand.value >= -algebraicTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -radicand.value,
                tolerance: tolerance,
                message: "A sphere-cylinder evaluator left its certified non-negative radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A sphere-cylinder square-root differential is singular."
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

    private func openRegularizedSquareRootDifferential(
        structure: OpenEndpointStructure,
        angle: Double,
        fraction: Double,
        branchSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        if structure == .twoDoubleRoots {
            let phase = Double.pi * fraction
            let magnitude = sqrt(
                2.0 * configuration.radicandAmplitude
            )
            return ScalarDifferential(
                value: branchSign * magnitude * sin(phase),
                first: branchSign * magnitude
                    * Double.pi * cos(phase),
                second: -branchSign * magnitude
                    * Double.pi * Double.pi * sin(phase)
            )
        }
        let factor: ScalarDifferential
        let prefix: ScalarDifferential
        switch structure {
        case .rootFree, .twoDoubleRoots:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A root-free or doubly closed sphere-cylinder branch does not use a one-sided endpoint factor."
            )
        case .twoSimpleRoots:
            factor = try regularizedRadicandFactorDifferential(
                at: angle,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let phase = Double.pi * fraction
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            prefix = ScalarDifferential(
                value: halfSpan * sin(phase),
                first: halfSpan * Double.pi * cos(phase),
                second: -halfSpan * Double.pi * Double.pi
                    * sin(phase)
            )
        case .lowerSimpleRoot:
            factor = try simpleRootFactorDifferential(
                at: angle,
                endpoint: lowerAngle,
                isLowerRoot: true,
                configuration: configuration
            , using: &execution)
            let phase = Double.pi * fraction * 0.25
            let scale = sqrt(
                2.0 * (upperAngle - lowerAngle)
            )
            prefix = ScalarDifferential(
                value: scale * sin(phase),
                first: scale * Double.pi * 0.25 * cos(phase),
                second: -scale * Double.pi * Double.pi
                    * 0.0625 * sin(phase)
            )
        case .upperSimpleRoot:
            factor = try simpleRootFactorDifferential(
                at: angle,
                endpoint: upperAngle,
                isLowerRoot: false,
                configuration: configuration
            , using: &execution)
            let phase = Double.pi * (1.0 - fraction) * 0.25
            let scale = sqrt(
                2.0 * (upperAngle - lowerAngle)
            )
            prefix = ScalarDifferential(
                value: scale * sin(phase),
                first: -scale * Double.pi * 0.25 * cos(phase),
                second: -scale * Double.pi * Double.pi
                    * 0.0625 * sin(phase)
            )
        case .lowerDoubleRoot:
            factor = try doubleRootFactorDifferential(
                at: angle,
                endpoint: lowerAngle,
                isLowerRoot: true,
                configuration: configuration
            , using: &execution)
            prefix = ScalarDifferential(
                value: (upperAngle - lowerAngle) * fraction,
                first: upperAngle - lowerAngle,
                second: 0.0
            )
        case .upperDoubleRoot:
            factor = try doubleRootFactorDifferential(
                at: angle,
                endpoint: upperAngle,
                isLowerRoot: false,
                configuration: configuration
            , using: &execution)
            prefix = ScalarDifferential(
                value: (upperAngle - lowerAngle) * (1.0 - fraction),
                first: -(upperAngle - lowerAngle),
                second: 0.0
            )
        }
        guard factor.value > 0.0, factor.value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: factor.value,
                tolerance: tolerance,
                message: "A pole-split sphere-cylinder component lost its positive regularized radicand factor."
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
        let angleDifferential = try self.angleDifferential(
            at: fraction,
            configuration: configuration,
            tolerance: tolerance,
            using: &execution)
        let rootByFraction = ScalarDifferential(
            value: rootByAngle.value,
            first: rootByAngle.first * angleDifferential.first,
            second: rootByAngle.second
                    * angleDifferential.first * angleDifferential.first
                + rootByAngle.first * angleDifferential.second
        )
        let result = Self.product(
            prefix,
            rootByFraction
        ).scaled(by: branchSign)
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A pole-split sphere-cylinder regularized square-root differential exceeded finite arithmetic."
            )
        }
        return result
    }

    private func simpleRootFactorDifferential(
        at angle: Double,
        endpoint: Double,
        isLowerRoot: Bool,
        configuration: Configuration,
        using execution: inout OriginalQueryExecution
    ) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let phase = atan2(
            configuration.radicandSine,
            configuration.radicandCosine
        )
        let midpoint = (angle + endpoint) * 0.5 - phase
        let amplitude = ScalarDifferential(
            value: isLowerRoot ? -sin(midpoint) : sin(midpoint),
            first: (isLowerRoot ? -0.5 : 0.5) * cos(midpoint),
            second: (isLowerRoot ? 0.25 : -0.25)
                * sin(midpoint)
        )
        let distance = isLowerRoot
            ? angle - endpoint
            : endpoint - angle
        let sinc = try Self.sincDifferential(
            at: distance * 0.5,
            derivativeScale: isLowerRoot ? 0.5 : -0.5,
            using: &execution)
        return Self.product(
            amplitude,
            sinc
        ).scaled(by: configuration.radicandAmplitude)
    }

    private func doubleRootFactorDifferential(
        at angle: Double,
        endpoint: Double,
        isLowerRoot: Bool,
        configuration: Configuration,
        using execution: inout OriginalQueryExecution
    ) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let distance = isLowerRoot
            ? angle - endpoint
            : endpoint - angle
        let sinc = try Self.sincDifferential(
            at: distance * 0.5,
            derivativeScale: isLowerRoot ? 0.5 : -0.5,
            using: &execution)
        return Self.product(
            sinc,
            sinc
        ).scaled(by: configuration.radicandAmplitude * 0.5)
    }

    private func regularizedRadicandFactorDifferential(
        at angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
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
                message: "A bounded sphere-cylinder regularized factor was evaluated outside its certified angular component."
            )
        }
        let lowerSinc = try Self.sincDifferential(
            at: lowerDistance * 0.5,
            derivativeScale: 0.5,
            using: &execution)
        let upperSinc = try Self.sincDifferential(
            at: upperDistance * 0.5,
            derivativeScale: -0.5,
            using: &execution)
        return Self.product(
            lowerSinc,
            upperSinc
        ).scaled(
            by: configuration.radicandAmplitude * 0.5
        )
    }

    private static func sincDifferential(
        at value: Double,
        derivativeScale: Double,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let valueResult: Double
        let firstByValue: Double
        let secondByValue: Double
        if abs(value) <= 0.25 {
            var accumulatedValue = 0.0
            var accumulatedFirst = 0.0
            var accumulatedSecond = 0.0
            var coefficient = 1.0
            for index in 0...12 {
                try execution.consumeWork(1)
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
                coefficient /= -Double(
                    (2 * index + 2) * (2 * index + 3)
                )
            }
            valueResult = accumulatedValue
            firstByValue = accumulatedFirst
            secondByValue = accumulatedSecond
        } else {
            let sine = sin(value)
            let cosine = cos(value)
            let squared = value * value
            valueResult = sine / value
            firstByValue = (value * cosine - sine) / squared
            secondByValue = -sine / value
                - 2.0 * cosine / squared
                + 2.0 * sine / (squared * value)
        }
        return ScalarDifferential(
            value: valueResult,
            first: firstByValue * derivativeScale,
            second: secondByValue * derivativeScale * derivativeScale
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

    private static func makeConfiguration(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try sphereSurface.validate(tolerance: tolerance, using: &execution)
        try cylinderSurface.validate(tolerance: tolerance, using: &execution)
        // Canonicalization may traverse the retained offset source chain.
        try GeometryStructuralComparisonWork.charge(surface: sphereSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: cylinderSurface, using: &execution)
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(sphereSurface),
              case let .cylinder(cylinderCanonical) = CanonicalAnalyticSurface(cylinderSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified sphere-cylinder curve requires exact sphere and cylinder surfaces."
            )
        }
        let cylinder = try canonicalCylinder(
            cylinderCanonical,
            tolerance: tolerance,
            using: &execution)
        let centerOffset = cylinder.origin - sphere.center
        let axialCenter = centerOffset.dot(cylinder.axis)
        let radialCenterOffset = centerOffset - cylinder.axis * axialCenter
        let zeroPoint = try cylinder.surface.point(
            u: 0.0,
            v: 0.0,
            tolerance: tolerance,
            using: &execution)
        let quarterPoint = try cylinder.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance,
            using: &execution)
        return Configuration(
            sphere: sphere,
            cylinder: cylinder,
            axialCenter: axialCenter,
            radicandCenter: sphere.radius * sphere.radius
                - radialCenterOffset.dot(radialCenterOffset)
                - cylinder.radius * cylinder.radius,
            radicandCosine: -2.0 * radialCenterOffset.dot(
                zeroPoint - cylinder.origin
            ),
            radicandSine: -2.0 * radialCenterOffset.dot(
                quarterPoint - cylinder.origin
            )
        )
    }

    private static func canonicalCylinder(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Cylinder {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
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
        let amplitude = configuration.radicandAmplitude
        let numericalThreshold = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard amplitude > numericalThreshold else { return [] }
        let ratio = -configuration.radicandCenter / amplitude
        let ratioTolerance = numericalThreshold / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let phase = atan2(configuration.radicandSine, configuration.radicandCosine)
        let offset = acos(min(max(ratio, -1.0), 1.0))
        let candidates = try CertifiedAnalyticCurveEvaluation.values(normalizedAngle(phase - offset),
            normalizedAngle(phase + offset), using: &execution)
        let refined = try CertifiedAnalyticCurveEvaluation.map(candidates, using: &execution) { value, execution in
            try refinedBoundaryAngle(value, configuration: configuration, tolerance: tolerance, using: &execution)
        }
        let values = try CertifiedAnalyticCurveEvaluation.sorted(refined, using: &execution)
        var result: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(values.count, in: &result, using: &execution)
        for value in values {
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
        let lowerResidual = abs(configuration.radicand(at: lowerAngle))
        let upperResidual = abs(configuration.radicand(at: upperAngle))
        let rootResidual = max(
            lowerResidual <= classificationTolerance * 16.0 ? lowerResidual : 0.0,
            upperResidual <= classificationTolerance * 16.0 ? upperResidual : 0.0
        )
        let regularizationResidual: Double
        if componentKind == .boundedAngularInterval {
            let midpoint = lowerAngle
                + (upperAngle - lowerAngle) * 0.5
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            let period = 2.0 * Double.pi
            let phase = atan2(
                configuration.radicandSine,
                configuration.radicandCosine
            )
            let unwrappedPhase = phase
                + round((midpoint - phase) / period) * period
            let radicandMachineBound = Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0
            regularizationResidual = (
                abs(
                    configuration.radicandCenter
                        + configuration.radicandAmplitude * cos(halfSpan)
                )
                    + configuration.radicandAmplitude
                        * abs(unwrappedPhase - midpoint)
                    + radicandMachineBound
            ).nextUp
        } else if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = try openEndpointStructure(
                lowerAngle: lowerAngle,
                upperAngle: upperAngle,
                configuration: configuration,
                tolerance: tolerance,
                using: &execution)
            let radicandMachineBound = Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0
            switch structure {
            case .twoSimpleRoots:
                let midpoint = lowerAngle
                    + (upperAngle - lowerAngle) * 0.5
                let halfSpan = (upperAngle - lowerAngle) * 0.5
                let period = 2.0 * Double.pi
                let phase = atan2(
                    configuration.radicandSine,
                    configuration.radicandCosine
                )
                let unwrappedPhase = phase
                    + round((midpoint - phase) / period) * period
                regularizationResidual = (
                    abs(
                        configuration.radicandCenter
                            + configuration.radicandAmplitude
                                * cos(halfSpan)
                    )
                        + configuration.radicandAmplitude
                            * abs(unwrappedPhase - midpoint)
                        + radicandMachineBound
                ).nextUp
            case .lowerSimpleRoot, .lowerDoubleRoot, .twoDoubleRoots:
                let endpoint = lowerAngle
                let period = 2.0 * Double.pi
                let phase = atan2(
                    configuration.radicandSine,
                    configuration.radicandCosine
                )
                let targetPhase = endpoint - Double.pi
                let unwrappedPhase = phase
                    + round((targetPhase - phase) / period) * period
                let phaseResidual = structure == .lowerSimpleRoot
                    ? 0.0
                    : configuration.radicandAmplitude
                        * abs(unwrappedPhase - targetPhase)
                regularizationResidual = (
                    rootResidual
                        + phaseResidual
                        + radicandMachineBound
                ).nextUp
            case .upperSimpleRoot, .upperDoubleRoot:
                let endpoint = upperAngle
                let period = 2.0 * Double.pi
                let phase = atan2(
                    configuration.radicandSine,
                    configuration.radicandCosine
                )
                let targetPhase = endpoint - Double.pi
                let unwrappedPhase = phase
                    + round((targetPhase - phase) / period) * period
                let phaseResidual = structure == .upperSimpleRoot
                    ? 0.0
                    : configuration.radicandAmplitude
                        * abs(unwrappedPhase - targetPhase)
                regularizationResidual = (
                    rootResidual
                        + phaseResidual
                        + radicandMachineBound
                ).nextUp
            case .rootFree:
                regularizationResidual = 0.0
            }
        } else {
            regularizationResidual = 0.0
        }
        let result = sqrt(
            max(rootResidual, regularizationResidual)
        ) + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Sphere-cylinder boundary roots do not certify the requested geometric tolerance."
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

    private static func spherePoleContacts(
        configuration: Configuration,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [PoleContact] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result: [PoleContact] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(4, in: &result, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
        for sign in [-1.0, 1.0] {
            try execution.consumeWork(1)
            let pole = configuration.sphere.center
                + Vector3D.unitZ * (sign * configuration.sphere.radius)
            let offset = pole - configuration.cylinder.origin
            let height = offset.dot(configuration.cylinder.axis)
            let radial = offset - configuration.cylinder.axis * height
            guard abs(radial.length - configuration.cylinder.radius)
                <= tolerance.distance else {
                continue
            }
            let basis = try analyticOrthonormalBasis(
                configuration.cylinder.axis,
                tolerance: tolerance
            )
            let angle = normalizedAngle(atan2(
                radial.dot(basis.v),
                radial.dot(basis.u)
            ))
            let signedRoot = height + configuration.axialCenter
            let branches: [Double]
            if signedRoot > tolerance.distance {
                branches = try CertifiedAnalyticCurveEvaluation.values(1.0, using: &execution)
            } else if signedRoot < -tolerance.distance {
                branches = try CertifiedAnalyticCurveEvaluation.values(-1.0, using: &execution)
            } else {
                branches = try CertifiedAnalyticCurveEvaluation.values(-1.0, 1.0, using: &execution)
            }
            for branch in branches {
                try execution.consumeWork(1)
                try execution.consumeWork(result.count)
                if result.contains(where: {
                $0.branch == branch
                    && angularDistance($0.angle, angle) <= tolerance.angle
                }) { continue }
                result.append(PoleContact(
                    angle: angle,
                    branch: branch
                ))
            }
        }
        return result
    }

    private static func minimumRadicand(
        from lower: Double,
        to upper: Double,
        configuration: Configuration,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var values: [Double] = []
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(4, in: &values, using: &execution)
        values.append(configuration.radicand(at: lower)); values.append(configuration.radicand(at: upper))
        let phase = atan2(
            configuration.radicandSine,
            configuration.radicandCosine
        )
        try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
        for critical in [phase, phase + Double.pi] {
            try execution.consumeWork(1)
            let firstIndex = ceil(
                (lower - critical) / (2.0 * Double.pi)
            )
            let adjusted = critical + firstIndex * 2.0 * Double.pi
            if adjusted >= lower, adjusted <= upper {
                values.append(configuration.radicand(at: adjusted))
            }
        }
        try execution.consumeWork(values.count)
        return values.min() ?? -.infinity
    }

    private static func maximumAbsoluteTrigonometricValue(
        lower: Double,
        upper: Double,
        phase: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
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
                break
            }
        }
        return result.nextUp
    }

    private static func adjustedAngle(
        _ angle: Double,
        inside interval: ClosedRange<Double>,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        var adjusted = normalizedAngle(angle)
        while adjusted < interval.lowerBound - period * 0.5 {
            try execution.consumeWork(1)
            let next = adjusted + period
            guard next > adjusted else { throw GeometryConversionError.resourceLimitExceeded("Certified angular normalization cannot advance at binary64 resolution.") }
            adjusted = next
        }
        while adjusted > interval.upperBound + period * 0.5 {
            try execution.consumeWork(1)
            let next = adjusted - period
            guard next < adjusted else { throw GeometryConversionError.resourceLimitExceeded("Certified angular normalization cannot advance at binary64 resolution.") }
            adjusted = next
        }
        if adjusted < interval.lowerBound {
            let next = adjusted + period
            guard next > adjusted else { throw GeometryConversionError.resourceLimitExceeded("Certified angular normalization cannot advance at binary64 resolution.") }
            adjusted = next
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


    static func poleSplitNodes(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try Self.poleSplitNodes(sphereSurface: sphereSurface, cylinderSurface: cylinderSurface, tolerance: tolerance, using: &execution)
    }

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [(angle: Double, branch: Double)] {
        try execution.checkpoint()
        let result = try Self.poleSplitNodesImplementation(sphereSurface: sphereSurface, cylinderSurface: cylinderSurface, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
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

    func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundedBranchSpatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try boundedBranchSpatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try openBranchSpatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try openBranchSpatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    public init(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(sphereSurface: sphereSurface, cylinderSurface: cylinderSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case sphereSurface
        case cylinderSurface
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
            sphereSurface: container.decode(Surface3D.self, forKey: .sphereSurface),
            cylinderSurface: container.decode(
                Surface3D.self,
                forKey: .cylinderSurface
            ),
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
                debugDescription: "The sphere-cylinder residual certificate does not match the reconstructed source surfaces."
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
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedSphereCylinderIntersectionCurve: Codable {}
extension CertifiedSphereCylinderIntersectionCurve.ComponentKind: Codable {}
#endif
