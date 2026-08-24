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

    private enum OpenEndpointStructure: Equatable {
        case rootFree
        case lowerSimpleRoot
        case upperSimpleRoot
        case twoSimpleRoots
        case lowerDoubleRoot
        case upperDoubleRoot
        case twoDoubleRoots
        case lowerSimpleUpperDouble
        case lowerDoubleUpperSimple
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

        var firstDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 2.0 * abs(cosineDouble)
                    + 2.0 * abs(sineDouble)
            ).nextUp
        }

        var absoluteUpperBound: Double {
            (
                abs(constant)
                    + abs(cosine)
                    + abs(sine)
                    + abs(cosineDouble)
                    + abs(sineDouble)
            ).nextUp
        }

        var secondDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 4.0 * abs(cosineDouble)
                    + 4.0 * abs(sineDouble)
            ).nextUp
        }

        var thirdDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 8.0 * abs(cosineDouble)
                    + 8.0 * abs(sineDouble)
            ).nextUp
        }

        var fourthDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 16.0 * abs(cosineDouble)
                    + 16.0 * abs(sineDouble)
            ).nextUp
        }

        var fifthDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 32.0 * abs(cosineDouble)
                    + 32.0 * abs(sineDouble)
            ).nextUp
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }

        func derivative(at angle: Double) -> Double {
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
            let phase = Double(order) * Double.pi * 0.5
            return cosine * cos(angle + phase)
                + sine * sin(angle + phase)
                + pow(2.0, Double(order)) * (
                cosineDouble * cos(2.0 * angle + phase)
                    + sineDouble * sin(2.0 * angle + phase)
            )
        }
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

        var radicandPolynomial: TrigonometricPolynomial {
            let cosine = slope * radialCosine
            let sine = slope * radialSine
            return TrigonometricPolynomial(
                constant: axialCenter * axialCenter
                    + (cosine * cosine + sine * sine) * 0.5
                    - quadraticA * quadraticC,
                cosine: 2.0 * axialCenter * cosine,
                sine: 2.0 * axialCenter * sine,
                cosineDouble: (cosine * cosine - sine * sine) * 0.5,
                sineDouble: cosine * sine
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
        let third: Double

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
            let endpointStructure = openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            )
            guard endpointStructure != .twoDoubleRoots,
                  endpointStructure != .lowerSimpleUpperDouble,
                  endpointStructure != .lowerDoubleUpperSimple else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "A regular sphere-cone pole-split graph edge cannot combine endpoint root multiplicities."
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
        let radialThird = -radialFirst
        let generator = configuration.cone.axis * cosine + radial * sine
        let generatorFirst = radialFirst * sine
        let generatorSecond = radialSecond * sine
        let generatorThird = radialThird * sine
        let composedGeneratorFirst = generatorFirst * angle.first
        let composedGeneratorSecond = generatorSecond
                * (angle.first * angle.first)
            + generatorFirst * angle.second
        let composedGeneratorThird = generatorThird
                * (angle.first * angle.first * angle.first)
            + generatorSecond * (3.0 * angle.first * angle.second)
            + generatorFirst * angle.third
        let position = configuration.cone.apex + generator * slant.value
        let firstDerivative = composedGeneratorFirst * slant.value
            + generator * slant.first
        let secondDerivative = composedGeneratorSecond * slant.value
            + composedGeneratorFirst * (2.0 * slant.first)
            + generator * slant.second
        let thirdDerivative = composedGeneratorThird * slant.value
            + composedGeneratorSecond * (3.0 * slant.first)
            + composedGeneratorFirst * (3.0 * slant.second)
            + generator * slant.third
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified sphere-cone component has a singular differential."
            )
        }
        guard thirdDerivative.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A certified sphere-cone third differential exceeded finite arithmetic."
            )
        }
        return ThirdOrderDifferentialGeometry(
            position: position,
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
                message: "Root-free sphere-cone differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let arithmeticEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let minimumRadicand = (
            Self.minimumRadicand(configuration: configuration)
                - arithmeticEnvelope
        ).nextDown
        guard minimumRadicand > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone differential certificate lost its positive radicand lower bound."
            )
        }

        let amplitude = configuration.radialAmplitude.nextUp
        let harmonicMagnitude = try upperProduct(
            abs(configuration.slope),
            amplitude,
            tolerance: tolerance
        )
        let halfLinearMagnitude = try upperSum(
            abs(configuration.axialCenter),
            harmonicMagnitude,
            tolerance: tolerance
        )
        let radicandConstantMagnitude = try upperProduct(
            configuration.quadraticA,
            abs(configuration.quadraticC),
            tolerance: tolerance
        )
        let maximumRadicand = try upperSum(
            try upperProduct(
                halfLinearMagnitude,
                halfLinearMagnitude,
                tolerance: tolerance
            ),
            radicandConstantMagnitude,
            tolerance: tolerance
        )
        let radicandFirst = try upperProduct(
            2.0,
            try upperProduct(
                halfLinearMagnitude,
                harmonicMagnitude,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let radicandSecond = try upperProduct(
            2.0,
            try upperSum(
                try upperProduct(
                    harmonicMagnitude,
                    harmonicMagnitude,
                    tolerance: tolerance
                ),
                try upperProduct(
                    halfLinearMagnitude,
                    harmonicMagnitude,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let radicandThird = (
            2.0 * (
                3.0 * harmonicMagnitude * harmonicMagnitude
                    + halfLinearMagnitude * harmonicMagnitude
            )
        ).nextUp
        let rootLower = sqrt(minimumRadicand).nextDown
        let rootUpper = sqrt(maximumRadicand).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone square-root certificate lost its finite positive margin."
            )
        }
        let rootFirst = try upperQuotient(
            radicandFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (
            (rootLower * rootLower).nextDown * rootLower
        ).nextDown
        let rootSecond = try upperSum(
            try upperQuotient(
                radicandSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
                    radicandFirst,
                    radicandFirst,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootFifthLower = (
            minimumRadicand * minimumRadicand * rootLower
        ).nextDown
        let rootThird = (
            radicandThird / (2.0 * rootLower).nextDown
                + 3.0 * radicandFirst * radicandSecond
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * radicandFirst * radicandFirst * radicandFirst
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp

        let rawDenominator = configuration.quadraticA
            * cos(configuration.cone.halfAngle)
        let denominatorEnvelope = max(
            Double.ulpOfOne * abs(rawDenominator) * 4_096.0,
            tolerance.relative * abs(rawDenominator) * 1.0e-6
        )
        let denominatorLower = (
            abs(rawDenominator) - denominatorEnvelope
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone slant denominator lost its positive margin."
            )
        }
        let slantMagnitude = try upperQuotient(
            try upperSum(
                halfLinearMagnitude,
                rootUpper,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootFirst,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantSecond = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootSecond,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantThird = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootThird,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )

        let sine = sin(configuration.cone.halfAngle).nextUp
        let angularFirst = hypot(
            try upperProduct(
                sine,
                slantMagnitude,
                tolerance: tolerance
            ),
            slantFirst
        ).nextUp
        let angularSecond = try upperSum(
            try upperProduct(
                sine,
                slantMagnitude,
                tolerance: tolerance
            ),
            try upperSum(
                try upperProduct(
                    2.0 * sine,
                    slantFirst,
                    tolerance: tolerance
                ),
                slantSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let angularThird = (
            sine * slantMagnitude
                + 3.0 * sine * slantFirst
                + 3.0 * sine * slantSecond
                + slantThird
        ).nextUp
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
                message: "Bounded sphere-cone differential bounds require a valid complete simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
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
            lowerValue: radicand.value(at: lowerAngle),
            upperValue: radicand.value(at: upperAngle),
            lowerDerivative: radicand.derivative(at: lowerAngle),
            upperDerivative: radicand.derivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                )
            },
            tolerance: tolerance,
            label: "Sphere-cone bounded branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A bounded sphere-cone regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
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
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
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
        let signedRootMagnitude = (
            halfSpan * sineMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            halfSpan * (
                period * cosineMagnitude * rootUpper
                    + sineMagnitude * rootFirstByAngle * angleFirst
            )
        ).nextUp
        let signedRootSecond = (
            halfSpan * (
                periodSquared * sineMagnitude * rootUpper
                    + 2.0 * period * cosineMagnitude
                        * rootFirstByAngle * angleFirst
                    + sineMagnitude * (
                        rootSecondByAngle * angleFirst * angleFirst
                            + rootFirstByAngle * angleSecond
                    )
            )
        ).nextUp
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
        let harmonicMagnitude = (
            abs(configuration.slope) * configuration.radialAmplitude
        ).nextUp
        let halfLinearMagnitude = (
            abs(configuration.axialCenter) + harmonicMagnitude
        ).nextUp
        let halfLinearFirst = (
            harmonicMagnitude * angleFirst
        ).nextUp
        let halfLinearSecond = (
            harmonicMagnitude
                * (angleFirst * angleFirst + angleSecond)
        ).nextUp
        let halfLinearThird = (
            harmonicMagnitude * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        )
        let slantMagnitude = try upperQuotient(
            try upperSum(
                halfLinearMagnitude,
                signedRootMagnitude,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try upperQuotient(
            try upperSum(
                halfLinearFirst,
                signedRootFirst,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantSecond = try upperQuotient(
            try upperSum(
                halfLinearSecond,
                signedRootSecond,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        let slantThird = try upperQuotient(
            try upperSum(
                halfLinearThird,
                signedRootThird,
                tolerance: tolerance
            ),
            denominatorLower,
            tolerance: tolerance
        )
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            slantMagnitude: slantMagnitude,
            slantFirst: slantFirst,
            slantSecond: slantSecond,
            slantThird: slantThird,
            configuration: configuration,
            tolerance: tolerance
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
                message: "Apex-reduced sphere-cone differential bounds require a certified apex-contact component."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let angleFirst = (upperAngle - lowerAngle).nextUp
        let harmonicMagnitude = (
            abs(configuration.slope) * configuration.radialAmplitude
        ).nextUp
        let halfLinearMagnitude = (
            abs(configuration.axialCenter) + harmonicMagnitude
        ).nextUp
        let halfLinearFirst = (
            harmonicMagnitude * angleFirst
        ).nextUp
        let halfLinearSecond = (
            harmonicMagnitude * angleFirst * angleFirst
        ).nextUp
        let halfLinearThird = (
            harmonicMagnitude * angleFirst * angleFirst * angleFirst
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        )
        let scale = try upperQuotient(
            2.0,
            denominatorLower,
            tolerance: tolerance
        )
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: 0.0,
            angleThird: 0.0,
            slantMagnitude: try upperProduct(
                scale,
                halfLinearMagnitude,
                tolerance: tolerance
            ),
            slantFirst: try upperProduct(
                scale,
                halfLinearFirst,
                tolerance: tolerance
            ),
            slantSecond: try upperProduct(
                scale,
                halfLinearSecond,
                tolerance: tolerance
            ),
            slantThird: try upperProduct(
                scale,
                halfLinearThird,
                tolerance: tolerance
            ),
            configuration: configuration,
            tolerance: tolerance
        )
    }

    func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
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
                message: "Open sphere-cone differential bounds require a valid certified graph-edge source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        switch openEndpointStructure(
            configuration: configuration,
            tolerance: tolerance
        ) {
        case .rootFree:
            return try rootFreeOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .lowerSimpleRoot:
            return try oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: true,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .upperSimpleRoot:
            return try oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: false,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .twoSimpleRoots:
            return try twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .lowerDoubleRoot:
            return try oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: true,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .upperDoubleRoot:
            return try oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: false,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .twoDoubleRoots, .lowerSimpleUpperDouble,
             .lowerDoubleUpperSimple:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A validated regular sphere-cone open branch reached an inconsistent endpoint-root structure."
            )
        }
    }

    private func rootFreeOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let span = (upperAngle - lowerAngle).nextUp
        let requestedLower = lowerAngle + span * lowerFraction
        let requestedUpper = lowerAngle + span * upperFraction
        let envelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let minimum = (
            Self.minimumRadicand(
                from: requestedLower,
                to: requestedUpper,
                configuration: configuration
            ) - envelope
        ).nextDown
        let radicand = configuration.radicandPolynomial
        let maximum = (
            radicand.absoluteUpperBound + envelope
        ).nextUp
        guard minimum > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free open sphere-cone differential certificate lost its positive radicand margin."
            )
        }
        let rootLower = sqrt(minimum).nextDown
        let rootUpper = sqrt(maximum).nextUp
        let rootFirstByAngle = try upperQuotient(
            radicand.firstDerivativeAbsoluteUpperBound,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (minimum * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                radicand.secondDerivativeAbsoluteUpperBound,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
                    radicand.firstDerivativeAbsoluteUpperBound,
                    radicand.firstDerivativeAbsoluteUpperBound,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootFifthLower = (
            minimum * minimum * rootLower
        ).nextDown
        let rootThirdByAngle = (
            radicand.thirdDerivativeAbsoluteUpperBound
                    / (2.0 * rootLower).nextDown
                + 3.0 * radicand.firstDerivativeAbsoluteUpperBound
                    * radicand.secondDerivativeAbsoluteUpperBound
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * pow(
                    radicand.firstDerivativeAbsoluteUpperBound,
                    3.0
                ) / (8.0 * rootFifthLower).nextDown
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: span,
            angleSecond: 0.0,
            angleThird: 0.0,
            rootMagnitude: rootUpper,
            rootFirst: try upperProduct(
                rootFirstByAngle,
                span,
                tolerance: tolerance
            ),
            rootSecond: try upperProduct(
                rootSecondByAngle,
                try upperProduct(span, span, tolerance: tolerance),
                tolerance: tolerance
            ),
            rootThird: (
                rootThirdByAngle * span * span * span
            ).nextUp,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
        rootAtLower: Bool,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let span = (upperAngle - lowerAngle).nextUp
        let requestedLower = lowerAngle + span * lowerFraction
        let requestedUpper = lowerAngle + span * upperFraction
        let rootAngle = rootAtLower ? lowerAngle : upperAngle
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let factor = try EndpointRegularizedFactorBounder()
            .oneSidedDoubleRootBounds(
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                requestedLower: requestedLower.nextDown,
                requestedUpper: requestedUpper.nextUp,
                rootAtLower: rootAtLower,
                endpointValue: radicand.value(at: rootAngle),
                endpointDerivative: radicand.derivative(at: rootAngle),
                endpointSecondDerivative: radicand.secondDerivative(
                    at: rootAngle
                ),
                firstDerivativeMagnitudeUpperBound:
                    radicand.firstDerivativeAbsoluteUpperBound,
                secondDerivativeMagnitudeUpperBound:
                    radicand.secondDerivativeAbsoluteUpperBound,
                thirdDerivativeMagnitudeUpperBound:
                    radicand.thirdDerivativeAbsoluteUpperBound,
                fourthDerivativeMagnitudeUpperBound:
                    radicand.fourthDerivativeAbsoluteUpperBound,
                fifthDerivativeMagnitudeUpperBound:
                    radicand.fifthDerivativeAbsoluteUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                valueRange: { rangeLower, rangeUpper in
                    Self.radicandRange(
                        configuration: configuration,
                        lower: rangeLower,
                        upper: rangeUpper,
                        arithmeticEnvelope: arithmeticEnvelope
                    )
                },
                tolerance: tolerance,
                label: "Sphere-cone double-root open branch"
            )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A double-root sphere-cone regularized factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
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
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let distanceMagnitude = span
        let signedRootMagnitude = (
            distanceMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            span * rootUpper
                + distanceMagnitude * rootFirstByAngle * span
        ).nextUp
        let signedRootSecond = (
            2.0 * span * rootFirstByAngle * span
                + distanceMagnitude * rootSecondByAngle * span * span
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * span * span
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * span * span * span
        ).nextUp
        let signedRootThird = (
            3.0 * span * rootByFractionSecond
                + distanceMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: span,
            angleSecond: 0.0,
            angleThird: 0.0,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
        rootAtLower: Bool,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let lowerDifferential = angleDifferential(
            at: lowerFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let upperDifferential = angleDifferential(
            at: upperFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let requestedLower = min(
            lowerDifferential.value,
            upperDifferential.value
        )
        let requestedUpper = max(
            lowerDifferential.value,
            upperDifferential.value
        )
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let rootAngle = rootAtLower ? lowerAngle : upperAngle
        let factor = try EndpointRegularizedFactorBounder().oneSidedBounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower.nextDown,
            requestedUpper: requestedUpper.nextUp,
            rootAtLower: rootAtLower,
            endpointValue: radicand.value(at: rootAngle),
            endpointDerivative: radicand.derivative(at: rootAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            orientedValueRange: { rangeLower, rangeUpper in
                let range = Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                )
                return range
            },
            tolerance: tolerance,
            label: "Sphere-cone one-sided open branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A one-sided sphere-cone regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
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
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let phaseScale = (Double.pi * 0.5).nextUp
        let phaseLower = phaseScale * lowerFraction
        let phaseUpper = phaseScale * upperFraction
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
        let span = (upperAngle - lowerAngle).nextUp
        let angleFirst = rootAtLower
            ? (span * phaseScale * sineMagnitude).nextUp
            : (span * phaseScale * cosineMagnitude).nextUp
        let angleSecond = rootAtLower
            ? (span * phaseScale * phaseScale * cosineMagnitude).nextUp
            : (span * phaseScale * phaseScale * sineMagnitude).nextUp
        let angleThird = rootAtLower
            ? (span * pow(phaseScale, 3.0) * sineMagnitude).nextUp
            : (span * pow(phaseScale, 3.0) * cosineMagnitude).nextUp
        let distanceRootScale = sqrt(2.0 * span).nextUp
        let distanceRootMagnitude = sqrt(span).nextUp
        let halfPhaseScale = (phaseScale * 0.5).nextUp
        let distanceRootFirst = (
            distanceRootScale * halfPhaseScale
        ).nextUp
        let distanceRootSecond = (
            distanceRootScale * halfPhaseScale * halfPhaseScale
        ).nextUp
        let distanceRootThird = (
            distanceRootScale * pow(halfPhaseScale, 3.0)
        ).nextUp
        let signedRootMagnitude = (
            distanceRootMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            distanceRootFirst * rootUpper
                + distanceRootMagnitude
                    * rootFirstByAngle * angleFirst
        ).nextUp
        let signedRootSecond = (
            distanceRootSecond * rootUpper
                + 2.0 * distanceRootFirst
                    * rootFirstByAngle * angleFirst
                + distanceRootMagnitude * (
                    rootSecondByAngle * angleFirst * angleFirst
                        + rootFirstByAngle * angleSecond
                )
        ).nextUp
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
        let signedRootThird = (
            distanceRootThird * rootUpper
                + 3.0 * distanceRootSecond * rootByFractionFirst
                + 3.0 * distanceRootFirst * rootByFractionSecond
                + distanceRootMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let requestedLower = angleDifferential(
            at: lowerFraction,
            configuration: configuration,
            tolerance: tolerance
        ).value
        let requestedUpper = angleDifferential(
            at: upperFraction,
            configuration: configuration,
            tolerance: tolerance
        ).value
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower.nextDown,
            requestedUpper: requestedUpper.nextUp,
            lowerValue: radicand.value(at: lowerAngle),
            upperValue: radicand.value(at: upperAngle),
            lowerDerivative: radicand.derivative(at: lowerAngle),
            upperDerivative: radicand.derivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                )
            },
            tolerance: tolerance,
            label: "Sphere-cone two-root open branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A two-root open sphere-cone regularized factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            try upperQuotient(
                try upperProduct(
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
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let phaseScale = Double.pi.nextUp
        let phaseLower = phaseScale * lowerFraction
        let phaseUpper = phaseScale * upperFraction
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
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let angleFirst = (
            halfSpan * phaseScale * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * phaseScale * phaseScale * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * pow(phaseScale, 3.0) * sineMagnitude
        ).nextUp
        let signedRootMagnitude = (
            halfSpan * sineMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            halfSpan * (
                phaseScale * cosineMagnitude * rootUpper
                    + sineMagnitude * rootFirstByAngle * angleFirst
            )
        ).nextUp
        let signedRootSecond = (
            halfSpan * (
                phaseScale * phaseScale * sineMagnitude * rootUpper
                    + 2.0 * phaseScale * cosineMagnitude
                        * rootFirstByAngle * angleFirst
                    + sineMagnitude * (
                        rootSecondByAngle * angleFirst * angleFirst
                            + rootFirstByAngle * angleSecond
                    )
            )
        ).nextUp
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
            halfSpan * phaseScale * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * phaseScale * phaseScale * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * pow(phaseScale, 3.0) * cosineMagnitude
        ).nextUp
        let signedRootThird = (
            prefixThird * rootUpper
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    func normalizedFractionCandidates(
        forConeAngle angle: Double,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let normalized = Self.normalizedAngle(angle)
            let fraction = normalized / period
            return normalized == 0.0 ? [0.0, 1.0] : [fraction]
        case .boundedAngularInterval:
            let adjusted = Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            )
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            let normalized = min(
                max((adjusted - lowerAngle) / (upperAngle - lowerAngle), 0.0),
                1.0
            )
            let phase = acos(1.0 - 2.0 * normalized)
            let fraction = phase / period
            return [fraction, 1.0 - fraction]
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let adjusted = Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            )
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            let normalized = min(
                max((adjusted - lowerAngle) / (upperAngle - lowerAngle), 0.0),
                1.0
            )
            let configuration = try Self.makeConfiguration(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            )
            switch openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            ) {
            case .twoSimpleRoots:
                return [acos(1.0 - 2.0 * normalized) / Double.pi]
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                return [acos(1.0 - normalized) / (Double.pi * 0.5)]
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                return [asin(normalized) / (Double.pi * 0.5)]
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                return [normalized]
            }
        case .apexReducedAngularInterval:
            let adjusted = Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            )
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            return [(adjusted - lowerAngle) / (upperAngle - lowerAngle)]
        }
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

    private func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a negative or non-finite factor."
            )
        }
        let result = (first * second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperQuotient(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard numerator.isFinite,
              denominator.isFinite,
              numerator >= 0.0,
              denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a non-positive divisor."
            )
        }
        let result = (numerator / denominator).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func upperSum(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a negative or non-finite summand."
            )
        }
        let result = (first + second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func slantDenominatorLowerBound(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let raw = abs(
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        let envelope = max(
            Double.ulpOfOne * raw * 4_096.0,
            tolerance.relative * raw * 1.0e-6
        )
        let result = (raw - envelope).nextDown
        guard result > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A sphere-cone slant denominator lost its positive margin."
            )
        }
        return result
    }

    private func spatialBounds(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        slantMagnitude: Double,
        slantFirst: Double,
        slantSecond: Double,
        slantThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let sine = sin(configuration.cone.halfAngle).nextUp
        let first = try upperSum(
            try upperProduct(
                try upperProduct(
                    sine,
                    angleFirst,
                    tolerance: tolerance
                ),
                slantMagnitude,
                tolerance: tolerance
            ),
            slantFirst,
            tolerance: tolerance
        )
        let generatorSecond = try upperProduct(
            sine,
            try upperSum(
                try upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let second = try upperSum(
            try upperProduct(
                generatorSecond,
                slantMagnitude,
                tolerance: tolerance
            ),
            try upperSum(
                try upperProduct(
                    try upperProduct(
                        2.0 * sine,
                        angleFirst,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                slantSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let generatorThird = (
            sine * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let third = (
            generatorThird * slantMagnitude
                + 3.0 * generatorSecond * slantFirst
                + 3.0 * sine * angleFirst * slantSecond
                + slantThird
        ).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    private func spatialBoundsFromSignedRoot(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        rootMagnitude: Double,
        rootFirst: Double,
        rootSecond: Double,
        rootThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let harmonicMagnitude = try upperProduct(
            abs(configuration.slope),
            configuration.radialAmplitude.nextUp,
            tolerance: tolerance
        )
        let halfLinearMagnitude = try upperSum(
            abs(configuration.axialCenter),
            harmonicMagnitude,
            tolerance: tolerance
        )
        let halfLinearFirst = try upperProduct(
            harmonicMagnitude,
            angleFirst,
            tolerance: tolerance
        )
        let halfLinearSecond = try upperProduct(
            harmonicMagnitude,
            try upperSum(
                try upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfLinearThird = (
            harmonicMagnitude * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        )
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            slantMagnitude: try upperQuotient(
                try upperSum(
                    halfLinearMagnitude,
                    rootMagnitude,
                    tolerance: tolerance
                ),
                denominatorLower,
                tolerance: tolerance
            ),
            slantFirst: try upperQuotient(
                try upperSum(
                    halfLinearFirst,
                    rootFirst,
                    tolerance: tolerance
                ),
                denominatorLower,
                tolerance: tolerance
            ),
            slantSecond: try upperQuotient(
                try upperSum(
                    halfLinearSecond,
                    rootSecond,
                    tolerance: tolerance
                ),
                denominatorLower,
                tolerance: tolerance
            ),
            slantThird: try upperQuotient(
                try upperSum(
                    halfLinearThird,
                    rootThird,
                    tolerance: tolerance
                ),
                denominatorLower,
                tolerance: tolerance
            ),
            configuration: configuration,
            tolerance: tolerance
        )
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

    private func openEndpointStructure(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> OpenEndpointStructure {
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let lowerIsRoot = abs(configuration.radicand(at: lowerAngle))
            <= classificationTolerance * 16.0
        let upperIsRoot = abs(configuration.radicand(at: upperAngle))
            <= classificationTolerance * 16.0
        let lowerIsSimple = lowerIsRoot
            && abs(configuration.radicandFirstDerivative(at: lowerAngle))
                > classificationTolerance
        let upperIsSimple = upperIsRoot
            && abs(configuration.radicandFirstDerivative(at: upperAngle))
                > classificationTolerance
        if lowerIsRoot == false, upperIsRoot == false {
            return .rootFree
        }
        if lowerIsRoot, upperIsRoot == false {
            return lowerIsSimple ? .lowerSimpleRoot : .lowerDoubleRoot
        }
        if lowerIsRoot == false, upperIsRoot {
            return upperIsSimple ? .upperSimpleRoot : .upperDoubleRoot
        }
        if lowerIsSimple, upperIsSimple {
            return .twoSimpleRoots
        }
        if lowerIsSimple {
            return .lowerSimpleUpperDouble
        }
        if upperIsSimple {
            return .lowerDoubleUpperSimple
        }
        return .twoDoubleRoots
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
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let normalized: ScalarDifferential
            switch openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            ) {
            case .twoSimpleRoots:
                let phase = Double.pi * fraction
                normalized = ScalarDifferential(
                    value: 0.5 - 0.5 * cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.5 * cos(phase),
                    third: -pow(Double.pi, 3.0) * 0.5 * sin(phase)
                )
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: 1.0 - cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.25 * cos(phase),
                    third: -pow(Double.pi * 0.5, 3.0) * sin(phase)
                )
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: sin(phase),
                    first: Double.pi * 0.5 * cos(phase),
                    second: -Double.pi * Double.pi * 0.25 * sin(phase),
                    third: -pow(Double.pi * 0.5, 3.0) * cos(phase)
                )
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                normalized = ScalarDifferential(
                    value: fraction,
                    first: 1.0,
                    second: 0.0,
                    third: 0.0
                )
            }
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * normalized.value,
                first: span * normalized.first,
                second: span * normalized.second,
                third: span * normalized.third
            )
        case .apexReducedAngularInterval:
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0,
                third: 0.0
            )
        }
    }

    private func angleFourthDerivative(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch,
             .apexReducedAngularInterval:
            return 0.0
        case .boundedAngularInterval:
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            return -halfSpan * pow(period, 4.0) * cos(period * fraction)
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let normalizedFourth: Double
            switch openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            ) {
            case .twoSimpleRoots:
                normalizedFourth = -0.5 * pow(Double.pi, 4.0)
                    * cos(Double.pi * fraction)
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                let scale = Double.pi * 0.5
                normalizedFourth = -pow(scale, 4.0)
                    * cos(scale * fraction)
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                let scale = Double.pi * 0.5
                normalizedFourth = pow(scale, 4.0)
                    * sin(scale * fraction)
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                normalizedFourth = 0.0
            }
            return (upperAngle - lowerAngle) * normalizedFourth
        }
    }

    private func radicandFourthDerivative(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let polynomial = configuration.radicandPolynomial
        let firstAngular = polynomial.derivative(at: angle.value)
        let secondAngular = polynomial.secondDerivative(at: angle.value)
        let thirdAngular = polynomial.thirdDerivative(at: angle.value)
        let fourthAngular = polynomial.derivative(order: 4, at: angle.value)
        let angleFourth = angleFourthDerivative(
            at: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        return fourthAngular * pow(angle.first, 4.0)
            + 6.0 * thirdAngular * angle.first * angle.first * angle.second
            + 3.0 * secondAngular * angle.second * angle.second
            + 4.0 * secondAngular * angle.first * angle.third
            + firstAngular * angleFourth
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
        let halfLinearAngularSecond = configuration.halfLinearSecondDerivative(
            at: angle.value
        )
        let halfLinear = ScalarDifferential(
            value: configuration.halfLinear(at: angle.value),
            first: halfLinearAngularFirst * angle.first,
            second: halfLinearAngularSecond * angle.first * angle.first
                + halfLinearAngularFirst * angle.second,
            third: -halfLinearAngularFirst
                    * angle.first * angle.first * angle.first
                + 3.0 * halfLinearAngularSecond * angle.first * angle.second
                + halfLinearAngularFirst * angle.third
        )
        let inverseQuadraticCosine = 1.0 / (
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        if componentKind == .apexReducedAngularInterval {
            let scale = 2.0 * inverseQuadraticCosine
            return ScalarDifferential(
                value: halfLinear.value * scale,
                first: halfLinear.first * scale,
                second: halfLinear.second * scale,
                third: halfLinear.third * scale
            )
        }
        let radicand = ScalarDifferential(
            value: halfLinear.value * halfLinear.value
                - configuration.quadraticA * configuration.quadraticC,
            first: 2.0 * halfLinear.value * halfLinear.first,
            second: 2.0 * (
                halfLinear.first * halfLinear.first
                    + halfLinear.value * halfLinear.second
            ),
            third: 2.0 * (
                3.0 * halfLinear.first * halfLinear.second
                    + halfLinear.value * halfLinear.third
            )
        )
        let root = try signedSquareRootDifferential(
            radicand,
            angle: angle,
            fraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        return ScalarDifferential(
            value: (halfLinear.value + root.value) * inverseQuadraticCosine,
            first: (halfLinear.first + root.first) * inverseQuadraticCosine,
            second: (halfLinear.second + root.second) * inverseQuadraticCosine,
            third: (halfLinear.third + root.third) * inverseQuadraticCosine
        )
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        angle: ScalarDifferential,
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
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedRadicandFactorDifferential(
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
                    message: "A bounded sphere-cone component lost its positive regularized radicand factor."
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
                        / (4.0 * root * root * root)
                    + 3.0 * factor.first * factor.first * factor.first
                        / (8.0 * pow(root, 5.0))
            )
            let rootByFraction = ScalarDifferential(
                value: rootByAngle.value,
                first: rootByAngle.first * angle.first,
                second: rootByAngle.second * angle.first * angle.first
                    + rootByAngle.first * angle.second,
                third: rootByAngle.third
                        * angle.first * angle.first * angle.first
                    + 3.0 * rootByAngle.second * angle.first * angle.second
                    + rootByAngle.first * angle.third
            )
            let phase = 2.0 * Double.pi * fraction
            let sine = ScalarDifferential(
                value: sin(phase),
                first: 2.0 * Double.pi * cos(phase),
                second: -4.0 * Double.pi * Double.pi * sin(phase),
                third: -8.0 * pow(Double.pi, 3.0) * cos(phase)
            )
            let result = Self.product(
                sine,
                rootByFraction
            ).scaled(by: (upperAngle - lowerAngle) * 0.5)
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded sphere-cone regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            )
            switch structure {
            case .lowerSimpleRoot, .upperSimpleRoot, .twoSimpleRoots,
                 .lowerDoubleRoot, .upperDoubleRoot:
                return try openRegularizedSquareRootDifferential(
                    structure: structure,
                    angle: angle,
                    fraction: fraction,
                    branchSign: branchSign,
                    configuration: configuration,
                    tolerance: tolerance
                )
            case .rootFree, .twoDoubleRoots, .lowerSimpleUpperDouble,
                 .lowerDoubleUpperSimple:
                break
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
            let signedFirst = signedEndpointDirection * sqrt(squaredSlope)
            let second = radicand.third / (6.0 * signedFirst)
            let fourth = radicandFourthDerivative(
                angle: angle,
                fraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            )
            let third = (fourth - 6.0 * second * second)
                / (8.0 * signedFirst)
            return ScalarDifferential(
                value: 0.0,
                first: signedFirst,
                second: second,
                third: third
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
                    / (4.0 * signedValue * signedValue * signedValue),
            third: radicand.third / (2.0 * signedValue)
                - 3.0 * radicand.first * radicand.second
                    / (4.0 * signedValue * signedValue * signedValue)
                + 3.0 * radicand.first * radicand.first * radicand.first
                    / (8.0 * pow(signedValue, 5.0))
        )
    }

    private func openRegularizedSquareRootDifferential(
        structure: OpenEndpointStructure,
        angle: ScalarDifferential,
        fraction: Double,
        branchSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let factor: ScalarDifferential
        let distanceRoot: ScalarDifferential
        switch structure {
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let dividedDifference = Self.trigonometricDividedDifference(
                configuration.radicandPolynomial,
                value: angle.value,
                endpoint: rootAtLower ? lowerAngle : upperAngle
            )
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
                    * sin(argument),
                third: -scale * pow(
                    derivativeSign * halfPhaseScale,
                    3.0
                ) * cos(argument)
            )
        case .twoSimpleRoots:
            factor = try regularizedRadicandFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            )
            let phase = Double.pi * fraction
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            distanceRoot = ScalarDifferential(
                value: halfSpan * sin(phase),
                first: halfSpan * Double.pi * cos(phase),
                second: -halfSpan * Double.pi * Double.pi * sin(phase),
                third: -halfSpan * pow(Double.pi, 3.0) * cos(phase)
            )
        case .lowerDoubleRoot, .upperDoubleRoot:
            let rootAtLower = structure == .lowerDoubleRoot
            factor = Self.trigonometricSecondDividedDifference(
                configuration.radicandPolynomial,
                value: angle.value,
                endpoint: rootAtLower ? lowerAngle : upperAngle
            )
            let span = upperAngle - lowerAngle
            distanceRoot = ScalarDifferential(
                value: rootAtLower
                    ? span * fraction
                    : span * (1.0 - fraction),
                first: rootAtLower ? span : -span,
                second: 0.0,
                third: 0.0
            )
        case .rootFree, .twoDoubleRoots, .lowerSimpleUpperDouble,
             .lowerDoubleUpperSimple:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested sphere-cone endpoint structure does not use simple-root regularization."
            )
        }
        guard factor.value > 0.0, factor.value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: factor.value,
                tolerance: tolerance,
                message: "An open sphere-cone component lost its positive regularized radicand factor."
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
                    / (4.0 * root * root * root)
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * pow(root, 5.0))
        )
        let rootByFraction = ScalarDifferential(
            value: rootByAngle.value,
            first: rootByAngle.first * angle.first,
            second: rootByAngle.second * angle.first * angle.first
                + rootByAngle.first * angle.second,
            third: rootByAngle.third
                    * angle.first * angle.first * angle.first
                + 3.0 * rootByAngle.second * angle.first * angle.second
                + rootByAngle.first * angle.third
        )
        let result = Self.product(
            distanceRoot,
            rootByFraction
        ).scaled(by: branchSign)
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite,
              result.third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "An open sphere-cone regularized square-root differential exceeded finite arithmetic."
            )
        }
        return result
    }

    private func regularizedRadicandFactorDifferential(
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
                message: "A bounded sphere-cone regularized factor was evaluated outside its certified angular component."
            )
        }
        let radicand = configuration.radicandPolynomial
        let lowerValue = radicand.value(at: lowerAngle)
        let upperValue = radicand.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = Self.trigonometricDividedDifference(
            radicand,
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
        return try Self.quotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded sphere-cone regularized factor lost its opposite-endpoint denominator."
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
                third: -halfOrder * halfOrder * halfOrder * (
                    -harmonic.cosine * cos(midpoint)
                        - harmonic.sine * sin(midpoint)
                )
            )
            result = result.adding(
                product(sinc, amplitude).scaled(by: harmonic.order)
            )
        }
        return result
    }

    private static func trigonometricSecondDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ) -> ScalarDifferential {
        let difference = value - endpoint
        if abs(difference) <= 0.25 {
            var result = 0.0
            var first = 0.0
            var second = 0.0
            var third = 0.0
            var factorial = 1.0
            for order in 1...24 {
                factorial *= Double(order)
                guard order >= 2 else { continue }
                let coefficient = polynomial.derivative(
                    order: order,
                    at: endpoint
                ) / factorial
                let exponent = order - 2
                result += coefficient * pow(
                    difference,
                    Double(exponent)
                )
                if exponent > 0 {
                    first += coefficient * Double(exponent)
                        * pow(difference, Double(exponent - 1))
                }
                if exponent > 1 {
                    second += coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(difference, Double(exponent - 2))
                }
                if exponent > 2 {
                    third += coefficient
                        * Double(exponent * (exponent - 1) * (exponent - 2))
                        * pow(difference, Double(exponent - 3))
                }
            }
            return ScalarDifferential(
                value: result,
                first: first,
                second: second,
                third: third
            )
        }
        let endpointValue = polynomial.value(at: endpoint)
        let endpointFirst = polynomial.derivative(at: endpoint)
        let numerator = polynomial.value(at: value)
            - endpointValue - endpointFirst * difference
        let numeratorFirst = polynomial.derivative(at: value)
            - endpointFirst
        let numeratorSecond = polynomial.secondDerivative(at: value)
        let numeratorThird = polynomial.thirdDerivative(at: value)
        let squared = difference * difference
        let cubed = squared * difference
        let fourth = squared * squared
        let fifth = fourth * difference
        return ScalarDifferential(
            value: numerator / squared,
            first: numeratorFirst / squared - 2.0 * numerator / cubed,
            second: numeratorSecond / squared
                - 4.0 * numeratorFirst / cubed
                + 6.0 * numerator / fourth,
            third: numeratorThird / squared
                - 6.0 * numeratorSecond / cubed
                + 18.0 * numeratorFirst / fourth
                - 24.0 * numerator / fifth
        )
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
            third: thirdByValue * derivativeScale * derivativeScale
                * derivativeScale
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

    private static func quotient(
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
        let inverseThird = -6.0 * denominator.first * denominator.first
                * denominator.first * pow(inverse, 4.0)
            + 6.0 * denominator.first * denominator.second
                * inverse * inverse * inverse
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

    private static func radicandRange(
        configuration: Configuration,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double
    ) -> (lower: Double, upper: Double) {
        let rawAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        let amplitudeLower = max(0.0, rawAmplitude.nextDown)
        let amplitudeUpper = rawAmplitude.nextUp
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        var cosineValues = [
            cos(lower - phase),
            cos(upper - phase),
        ]
        let firstExtremum = Int(
            floor((lower - phase) / Double.pi)
        ) - 1
        let lastExtremum = Int(
            ceil((upper - phase) / Double.pi)
        ) + 1
        for index in firstExtremum...lastExtremum {
            let angle = phase + Double(index) * Double.pi
            if angle > lower, angle < upper {
                cosineValues.append(index.isMultiple(of: 2) ? 1.0 : -1.0)
            }
        }
        let cosineLower = cosineValues.min() ?? -1.0
        let cosineUpper = cosineValues.max() ?? 1.0
        let harmonicLower = (
            (cosineLower >= 0.0 ? amplitudeLower : amplitudeUpper)
                * cosineLower
        ).nextDown
        let harmonicUpper = (
            (cosineUpper >= 0.0 ? amplitudeUpper : amplitudeLower)
                * cosineUpper
        ).nextUp
        let linearLower = (
            configuration.axialCenter + harmonicLower
        ).nextDown
        let linearUpper = (
            configuration.axialCenter + harmonicUpper
        ).nextUp
        let squareLower: Double
        if linearLower <= 0.0, linearUpper >= 0.0 {
            squareLower = 0.0
        } else {
            squareLower = min(
                linearLower * linearLower,
                linearUpper * linearUpper
            ).nextDown
        }
        let squareUpper = max(
            linearLower * linearLower,
            linearUpper * linearUpper
        ).nextUp
        let product = (
            configuration.quadraticA * configuration.quadraticC
        )
        return (
            (squareLower - product - arithmeticEnvelope).nextDown,
            (squareUpper - product + arithmeticEnvelope).nextUp
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
