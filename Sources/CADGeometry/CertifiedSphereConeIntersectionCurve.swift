import CADCore
import Foundation

public struct CertifiedSphereConeIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case negativeOpenAngularInterval
        case positiveOpenAngularInterval
        case apexReducedAngularInterval
    }

    enum ApexContactTopology {
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

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let cone: Cone
        let axialCenter: Double
        let radialCosine: Double
        let radialSine: Double
        let quadraticA: Double
        let quadraticC: Double

        var radialAmplitude: Double {
            hypot(radialCosine, radialSine)
        }

        var slope: Double {
            tan(cone.halfAngle)
        }

        var characteristicLength: Double {
            max(
                (sphere.center - cone.apex).length,
                sphere.radius,
                1.0
            )
        }

        func halfLinear(at angle: Double) -> Double {
            axialCenter + slope * (
                radialCosine * cos(angle) + radialSine * sin(angle)
            )
        }

        func halfLinearFirstDerivative(at angle: Double) -> Double {
            slope * (-radialCosine * sin(angle) + radialSine * cos(angle))
        }

        func halfLinearSecondDerivative(at angle: Double) -> Double {
            slope * (-radialCosine * cos(angle) - radialSine * sin(angle))
        }

        func radicand(at angle: Double) -> Double {
            let linear = halfLinear(at: angle)
            return linear * linear - quadraticA * quadraticC
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            2.0 * halfLinear(at: angle)
                * halfLinearFirstDerivative(at: angle)
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
    }

    public let sphereSurface: Surface3D
    public let coneSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.sphereSurface = sphereSurface
        self.coneSurface = coneSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
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
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        try rejectConeApexContact(
            configuration: configuration,
            tolerance: tolerance
        )
        return try spherePoleContacts(
            configuration: configuration,
            tolerance: tolerance
        ).map { (angle: $0.angle, branch: $0.branch) }
    }

    static func apexContactTopology(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ApexContactTopology? {
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let residualBound = apexReductionResidualUpperBound(
            configuration: configuration
        )
        guard residualBound <= tolerance.distance else {
            return nil
        }
        let boundaries = apexBoundaryAngles(
            configuration: configuration,
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
                message: "A sphere-cone curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        if componentKind != .apexReducedAngularInterval {
            try Self.rejectConeApexContact(
                configuration: configuration,
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
        let boundaries = Self.boundaryAngles(
            configuration: configuration,
            tolerance: tolerance
        )
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            ).contains { $0.branch == branch }
            let minimumRadicand = Self.minimumRadicand(configuration: configuration)
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
                    message: "A full sphere-cone branch requires a positive root-free, sphere-pole-free radicand domain."
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
                    message: "A bounded sphere-cone component is not a complete simple-root interval."
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
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerIsRoot = lowerResidual <= classificationTolerance * 16.0
            let upperIsRoot = upperResidual <= classificationTolerance * 16.0
            let hasInteriorPole = contacts.contains { contact in
                let adjusted = Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                )
                return adjusted > lowerAngle + tolerance.angle
                    && adjusted < upperAngle - tolerance.angle
            }
            let minimumRadicand = Self.minimumRadicand(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration
            )
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
                    message: "An open sphere-cone branch is not one complete nonnegative interval between consecutive certified graph nodes."
                )
            }
        case .apexReducedAngularInterval:
            guard let topology = try Self.apexContactTopology(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: Self.apexReductionResidualUpperBound(
                        configuration: configuration
                    ),
                    tolerance: tolerance,
                    message: "An apex-reduced sphere-cone component requires a certified cone-apex contact."
                )
            }
            let matchesTopology: Bool
            switch topology {
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
                    message: "An apex-reduced sphere-cone component must cover one complete non-apex root interval."
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
                message: "A sphere-cone curve exceeded its certified geometric residual."
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
            let coneProjection = try coneSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(sphereProjection.residual, coneProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A sphere-cone curve failed its algebraic reconstruction check."
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
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(
            at: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let slant = try slantDifferential(
            angle: angle,
            fraction: normalizedFraction,
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
                message: "A certified sphere-cone curve reaches the cone apex."
            )
        }
        let basis = try analyticOrthonormalBasis(
            configuration.cone.axis,
            tolerance: tolerance
        )
        let cosine = cos(configuration.cone.halfAngle)
        let sine = sin(configuration.cone.halfAngle)
        let radial = basis.u * cos(angle.value) + basis.v * sin(angle.value)
        let radialFirst = -basis.u * sin(angle.value) + basis.v * cos(angle.value)
        let radialSecond = -radial
        let generator = configuration.cone.axis * cosine + radial * sine
        let generatorFirst = radialFirst * sine
        let generatorSecond = radialSecond * sine
        let position = configuration.cone.apex + generator * slant.value
        let firstDerivative = generatorFirst * (angle.first * slant.value)
            + generator * slant.first
        let secondDerivative = generatorSecond
                * (angle.first * angle.first * slant.value)
            + generatorFirst
                * (angle.second * slant.value + 2.0 * angle.first * slant.first)
            + generator * slant.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified sphere-cone component has a singular differential."
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
        guard surface == sphereSurface || surface == coneSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A sphere-cone pcurve was requested on an unrelated surface."
            )
        }
        if surface == coneSurface {
            let normalizedFraction = min(max(fraction, 0.0), 1.0)
            let configuration = try Self.makeConfiguration(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            )
            let angle = angleDifferential(
                at: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            let slant = try slantDifferential(
                angle: angle,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            return SurfaceParameter(u: angle.value, v: slant.value)
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
        throw KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "A sphere-cone pcurve was requested on an unrelated surface."
        )
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
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
            coneSurface: coneSurface,
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
                message: "A pole-split sphere-cone pcurve reached a spherical pole away from a certified endpoint."
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
            let lowerIsSimpleRoot = abs(configuration.radicand(at: lowerAngle))
                    <= classificationTolerance * 16.0
                && abs(configuration.radicandFirstDerivative(at: lowerAngle))
                    > classificationTolerance
            let upperIsSimpleRoot = abs(configuration.radicand(at: upperAngle))
                    <= classificationTolerance * 16.0
                && abs(configuration.radicandFirstDerivative(at: upperAngle))
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
        case .apexReducedAngularInterval:
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0
            )
        }
    }

    private func slantDifferential(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let halfLinearAngularFirst = configuration.halfLinearFirstDerivative(
            at: angle.value
        )
        let halfLinear = ScalarDifferential(
            value: configuration.halfLinear(at: angle.value),
            first: halfLinearAngularFirst * angle.first,
            second: configuration.halfLinearSecondDerivative(at: angle.value)
                * angle.first * angle.first + halfLinearAngularFirst * angle.second
        )
        let inverseQuadraticCosine = 1.0 / (
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        if componentKind == .apexReducedAngularInterval {
            let scale = 2.0 * inverseQuadraticCosine
            return ScalarDifferential(
                value: halfLinear.value * scale,
                first: halfLinear.first * scale,
                second: halfLinear.second * scale
            )
        }
        let radicand = ScalarDifferential(
            value: halfLinear.value * halfLinear.value
                - configuration.quadraticA * configuration.quadraticC,
            first: 2.0 * halfLinear.value * halfLinear.first,
            second: 2.0 * (
                halfLinear.first * halfLinear.first
                    + halfLinear.value * halfLinear.second
            )
        )
        let root = try signedSquareRootDifferential(
            radicand,
            fraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        return ScalarDifferential(
            value: (halfLinear.value + root.value) * inverseQuadraticCosine,
            first: (halfLinear.first + root.first) * inverseQuadraticCosine,
            second: (halfLinear.second + root.second) * inverseQuadraticCosine
        )
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
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
        case .apexReducedAngularInterval:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An apex-reduced sphere-cone component does not use a square-root branch."
            )
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
        case .apexReducedAngularInterval:
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
                    message: "A sphere-cone radicand endpoint has no regular square-root continuation."
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
            case .apexReducedAngularInterval:
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
                message: "A sphere-cone evaluator left its certified non-negative radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A sphere-cone square-root differential is singular at normalized fraction \(fraction) for \(componentKind.rawValue)."
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

    private static func endpointFractionTolerance(
        tolerance: ModelingTolerance
    ) -> Double {
        // Root-regularizing angular maps move by O(fraction squared), so values
        // within sqrt(ulp) of an endpoint can round to the endpoint exactly.
        max(tolerance.relative, 2.0 * sqrt(Double.ulpOfOne))
    }

    private static func makeConfiguration(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try sphereSurface.validate(tolerance: tolerance)
        try coneSurface.validate(tolerance: tolerance)
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(sphereSurface),
              case let .cone(coneCanonical) = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified sphere-cone curve requires exact sphere and cone surfaces."
            )
        }
        let cone = try canonicalCone(coneCanonical, tolerance: tolerance)
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter
        let zeroPoint = try cone.surface.point(
            u: 0.0,
            v: 1.0,
            tolerance: tolerance
        )
        let quarterPoint = try cone.surface.point(
            u: Double.pi * 0.5,
            v: 1.0,
            tolerance: tolerance
        )
        let axialStep = cone.axis * cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let zeroRadial = (zeroPoint - cone.apex - axialStep) / sine
        let quarterRadial = (quarterPoint - cone.apex - axialStep) / sine
        let slope = tan(cone.halfAngle)
        return Configuration(
            sphere: sphere,
            cone: cone,
            axialCenter: axialCenter,
            radialCosine: radialCenter.dot(zeroRadial),
            radialSine: radialCenter.dot(quarterRadial),
            quadraticA: 1.0 + slope * slope,
            quadraticC: centerOffset.dot(centerOffset)
                - sphere.radius * sphere.radius
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

    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let product = configuration.quadraticA * configuration.quadraticC
        let numericalThreshold = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard product >= -numericalThreshold else { return [] }
        let root = sqrt(max(0.0, product))
        let linearThreshold = sqrt(numericalThreshold)
        let targets = root <= linearThreshold
            ? [0.0]
            : [root, -root]
        let harmonicAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        guard harmonicAmplitude > tolerance.distance else { return [] }
        let phase = atan2(configuration.radialSine, configuration.radialCosine)
        var values: [Double] = []
        for target in targets {
            let ratio = (target - configuration.axialCenter) / harmonicAmplitude
            let ratioTolerance = linearThreshold / harmonicAmplitude
            guard ratio >= -1.0 - ratioTolerance,
                  ratio <= 1.0 + ratioTolerance else {
                continue
            }
            let offset = acos(min(max(ratio, -1.0), 1.0))
            values.append(normalizedAngle(phase - offset))
            values.append(normalizedAngle(phase + offset))
        }
        values = values.map { refinedBoundaryAngle(
            $0,
            configuration: configuration,
            tolerance: tolerance
        ) }.sorted()
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
        let lower = configuration.axialCenter
            - abs(configuration.slope) * configuration.radialAmplitude
        let upper = configuration.axialCenter
            + abs(configuration.slope) * configuration.radialAmplitude
        let minimumAbsoluteLinear: Double
        if lower <= 0.0, upper >= 0.0 {
            minimumAbsoluteLinear = 0.0
        } else {
            minimumAbsoluteLinear = min(abs(lower), abs(upper))
        }
        return minimumAbsoluteLinear * minimumAbsoluteLinear
            - configuration.quadraticA * configuration.quadraticC
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
                    message: "A sphere-cone apex reduction exceeded the requested geometric tolerance."
                )
            }
            return result
        }
        let hasBoundaryRoots: Bool
        switch componentKind {
        case .boundedAngularInterval,
             .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            hasBoundaryRoots = true
        case .negativeFullBranch, .positiveFullBranch:
            hasBoundaryRoots = false
        case .apexReducedAngularInterval:
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
        let denominator = abs(
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        let result = sqrt(rootResidual) / denominator + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Sphere-cone boundary roots do not certify the requested geometric tolerance."
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

    private static func apexReductionResidualUpperBound(
        configuration: Configuration
    ) -> Double {
        abs(configuration.quadraticC) / configuration.sphere.radius
    }

    private static func apexBoundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let harmonicAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        guard harmonicAmplitude > tolerance.distance else {
            return []
        }
        let ratio = -configuration.axialCenter / harmonicAmplitude
        let ratioTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        ).squareRoot() / harmonicAmplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        let offset = acos(min(max(ratio, -1.0), 1.0))
        let candidates = [
            normalizedAngle(phase - offset),
            normalizedAngle(phase + offset),
        ].map {
            refinedApexBoundaryAngle(
                $0,
                configuration: configuration,
                tolerance: tolerance
            )
        }.sorted()
        var result: [Double] = []
        for candidate in candidates where result.contains(where: {
            angularDistance($0, candidate) <= tolerance.angle
        }) == false {
            result.append(candidate)
        }
        return result
    }

    private static func refinedApexBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let proofTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 128.0
        for _ in 0..<64 {
            let value = configuration.halfLinear(at: angle)
            if abs(value) <= proofTolerance {
                break
            }
            let derivative = configuration.halfLinearFirstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else {
                break
            }
            angle = normalizedAngle(angle - step)
        }
        return angle
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

    private static func rejectConeApexContact(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws {
        let apexResidual = abs(
            (configuration.sphere.center - configuration.cone.apex).length
                - configuration.sphere.radius
        )
        if apexResidual <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "Sphere-cone intersection passes through the cone's singular apex parameter."
            )
        }
    }

    private static func spherePoleContacts(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [PoleContact] {
        var result: [PoleContact] = []
        let cosine = cos(configuration.cone.halfAngle)
        let sine = sin(configuration.cone.halfAngle)
        let basis = try analyticOrthonormalBasis(
            configuration.cone.axis,
            tolerance: tolerance
        )
        for sign in [-1.0, 1.0] {
            let pole = configuration.sphere.center
                + Vector3D.unitZ * (sign * configuration.sphere.radius)
            let offset = pole - configuration.cone.apex
            let axialDistance = offset.dot(configuration.cone.axis)
            let radial = offset - configuration.cone.axis * axialDistance
            let slant = axialDistance / cosine
            let expectedRadialDistance = abs(slant) * sine
            guard abs(radial.length - expectedRadialDistance)
                <= tolerance.distance else {
                continue
            }
            guard abs(slant) > tolerance.distance else {
                continue
            }
            let signedRadial = radial / (slant * sine)
            let angle = normalizedAngle(atan2(
                signedRadial.dot(basis.v),
                signedRadial.dot(basis.u)
            ))
            let signedRoot = configuration.quadraticA * cosine * slant
                - configuration.halfLinear(at: angle)
            let branches: [Double]
            if signedRoot > tolerance.distance {
                branches = [1.0]
            } else if signedRoot < -tolerance.distance {
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

    private static func minimumRadicand(
        from lower: Double,
        to upper: Double,
        configuration: Configuration
    ) -> Double {
        var candidateAngles = [lower, upper]
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        appendPeriodicAngle(
            phase,
            from: lower,
            to: upper,
            result: &candidateAngles
        )
        appendPeriodicAngle(
            phase + Double.pi,
            from: lower,
            to: upper,
            result: &candidateAngles
        )
        let harmonicAmplitude = configuration.slope
            * configuration.radialAmplitude
        if abs(harmonicAmplitude) > Double.leastNonzeroMagnitude {
            let ratio = -configuration.axialCenter / harmonicAmplitude
            if ratio >= -1.0, ratio <= 1.0 {
                let offset = acos(ratio)
                appendPeriodicAngle(
                    phase - offset,
                    from: lower,
                    to: upper,
                    result: &candidateAngles
                )
                appendPeriodicAngle(
                    phase + offset,
                    from: lower,
                    to: upper,
                    result: &candidateAngles
                )
            }
        }
        return candidateAngles
            .map { configuration.radicand(at: $0) }
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
        while adjusted < interval.lowerBound - period * 0.5 {
            adjusted += period
        }
        while adjusted > interval.upperBound + period * 0.5 {
            adjusted -= period
        }
        if adjusted < interval.lowerBound {
            adjusted += period
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
        case coneSurface
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
                .coneSurface,
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
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
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
                debugDescription: "The sphere-cone residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sphereSurface, forKey: .sphereSurface)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
