import CADCore
import Foundation

public struct CertifiedSphereCylinderIntersectionCurve: Codable, Hashable, Sendable {
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
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
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
        tolerance: ModelingTolerance
    ) throws {
        self.sphereSurface = sphereSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
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

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
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
                message: "A sphere-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
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
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            ).contains { $0.branch == branch }
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
                    message: "A bounded sphere-cylinder component is not a complete simple-root interval."
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
                    message: "An open sphere-cylinder branch is not one complete nonnegative interval between consecutive certified graph nodes."
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
                message: "A sphere-cylinder curve exceeded its certified geometric residual."
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
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
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
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(
            at: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let angularFirst = configuration.radicandFirstDerivative(at: angle.value)
        let radicand = ScalarDifferential(
            value: configuration.radicand(at: angle.value),
            first: angularFirst * angle.first,
            second: configuration.radicandSecondDerivative(at: angle.value)
                * angle.first * angle.first + angularFirst * angle.second
        )
        let root = try signedSquareRootDifferential(
            radicand,
            fraction: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let height = ScalarDifferential(
            value: -configuration.axialCenter + root.value,
            first: root.first,
            second: root.second
        )
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

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
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
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
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

    private func sphereParameter(
        for point: Point3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
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
        let endpointTolerance = max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
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
        }
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

    private static func makeConfiguration(
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try sphereSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
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
            tolerance: tolerance
        )
        let centerOffset = cylinder.origin - sphere.center
        let axialCenter = centerOffset.dot(cylinder.axis)
        let radialCenterOffset = centerOffset - cylinder.axis * axialCenter
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
        tolerance: ModelingTolerance
    ) throws -> Cylinder {
        var axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        let originVector = cylinder.origin - .origin
        let origin = cylinder.origin + axis * -originVector.dot(axis)
        return Cylinder(origin: origin, axis: axis, radius: cylinder.radius)
    }

    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
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
        let values = [
            normalizedAngle(phase - offset),
            normalizedAngle(phase + offset),
        ].map { refinedBoundaryAngle(
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
        let result = sqrt(rootResidual) + machineBound
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

    private static func spherePoleContacts(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [PoleContact] {
        var result: [PoleContact] = []
        for sign in [-1.0, 1.0] {
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
        var values = [
            configuration.radicand(at: lower),
            configuration.radicand(at: upper),
        ]
        let phase = atan2(
            configuration.radicandSine,
            configuration.radicandCosine
        )
        for critical in [phase, phase + Double.pi] {
            let firstIndex = ceil(
                (lower - critical) / (2.0 * Double.pi)
            )
            let adjusted = critical + firstIndex * 2.0 * Double.pi
            if adjusted >= lower, adjusted <= upper {
                values.append(configuration.radicand(at: adjusted))
            }
        }
        return values.min() ?? -.infinity
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
        )
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

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sphereSurface, forKey: .sphereSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
