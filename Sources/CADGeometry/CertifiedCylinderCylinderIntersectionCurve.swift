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

        func radicand(at angle: Double) -> Double {
            let distance = signedDistance(at: angle)
            return reference.radius * reference.radius - distance * distance
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            -2.0 * signedDistance(at: angle)
                * signedDistanceFirstDerivative(at: angle)
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
        let radicand = ScalarDifferential(
            value: (configuration.reference.radius * configuration.reference.radius
                - signedDistance.value * signedDistance.value)
                * inverseProjectedAxisSquaredLength,
            first: -2.0 * signedDistance.value * signedDistance.first
                * inverseProjectedAxisSquaredLength,
            second: -2.0 * (
                signedDistance.first * signedDistance.first
                    + signedDistance.value * signedDistance.second
            ) * inverseProjectedAxisSquaredLength
        )
        let signedRoot = try signedSquareRootDifferential(
            radicand,
            fraction: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance
        )
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

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        fraction: Double,
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
            branchSign = sin(2.0 * Double.pi * fraction) < 0.0 ? -1.0 : 1.0
        }
        if componentKind == .boundedAngularInterval,
           abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0),
           abs(radicand.value) <= algebraicTolerance * 32.0 {
            let squaredSlope = radicand.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A cylinder-cylinder radicand endpoint has no regular square-root continuation."
                )
            }
            let isUpper = cos(2.0 * Double.pi * fraction) < 0.0
            return ScalarDifferential(
                value: 0.0,
                first: (isUpper ? -1.0 : 1.0) * sqrt(squaredSlope),
                second: 0.0
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
