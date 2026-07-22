import CADCore
import Foundation

public struct CertifiedParallelTorusCylinderIntersectionCurve: Codable, Hashable, Sendable {
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

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
        let radialU: Vector3D
        let radialV: Vector3D
    }

    private struct Configuration {
        let torus: Torus
        let cylinder: Cylinder
        let radialSquaredCenter: Double
        let radialSquaredCosine: Double
        let radialSquaredSine: Double

        var characteristicLength: Double {
            max(
                torus.majorRadius + torus.minorRadius,
                cylinder.radius,
                (cylinder.origin - torus.center).length,
                1.0
            )
        }

        var harmonicAmplitude: Double {
            hypot(radialSquaredCosine, radialSquaredSine)
        }

        func radialSquared(at angle: Double) -> Double {
            radialSquaredCenter
                + radialSquaredCosine * cos(angle)
                + radialSquaredSine * sin(angle)
        }

        func radialSquaredFirstDerivative(at angle: Double) -> Double {
            -radialSquaredCosine * sin(angle)
                + radialSquaredSine * cos(angle)
        }

        func radialSquaredSecondDerivative(at angle: Double) -> Double {
            -radialSquaredCosine * cos(angle)
                - radialSquaredSine * sin(angle)
        }

        func radicand(at angle: Double) -> Double {
            let radialDistance = sqrt(max(radialSquared(at: angle), 0.0))
            let tubeRadialDistance = radialDistance - torus.majorRadius
            return torus.minorRadius * torus.minorRadius
                - tubeRadialDistance * tubeRadialDistance
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            let squared = radialSquared(at: angle)
            guard squared > Double.leastNonzeroMagnitude else { return .infinity }
            let radial = sqrt(squared)
            let radialFirst = radialSquaredFirstDerivative(at: angle) / (2.0 * radial)
            return -2.0 * (radial - torus.majorRadius) * radialFirst
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    public let torusSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.torusSurface = torusSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
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
                message: "A parallel torus-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
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
                    message: "A full parallel torus-cylinder branch requires a positive root-free radicand domain."
                )
            }
        case .boundedAngularInterval:
            let intervals = Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance
            )
            let matchesCompleteInterval = intervals.contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
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
                    message: "A bounded parallel torus-cylinder component is not a complete simple-root interval."
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
                message: "A parallel torus-cylinder curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(torusProjection.residual, cylinderProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A parallel torus-cylinder curve failed its algebraic reconstruction check."
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
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(at: clamped)
        let radialSquared = composedRadialSquared(
            angle: angle,
            configuration: configuration
        )
        guard radialSquared.value > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sqrt(max(radialSquared.value, 0.0)),
                tolerance: tolerance,
                message: "A parallel torus-cylinder curve reached a singular torus radial coordinate."
            )
        }
        let radialDistance = squareRootDifferential(radialSquared)
        let tubeDistance = ScalarDifferential(
            value: radialDistance.value - configuration.torus.majorRadius,
            first: radialDistance.first,
            second: radialDistance.second
        )
        let radicand = ScalarDifferential(
            value: configuration.torus.minorRadius * configuration.torus.minorRadius
                - tubeDistance.value * tubeDistance.value,
            first: -2.0 * tubeDistance.value * tubeDistance.first,
            second: -2.0 * (
                tubeDistance.first * tubeDistance.first
                    + tubeDistance.value * tubeDistance.second
            )
        )
        let height = try signedSquareRootDifferential(
            radicand,
            fraction: clamped,
            configuration: configuration,
            tolerance: tolerance
        )
        let radial = radialDifferential(
            angle: angle,
            configuration: configuration
        )
        let position = configuration.cylinder.origin
            + radial.value
            + configuration.cylinder.axis * height.value
        let firstDerivative = radial.first
            + configuration.cylinder.axis * height.first
        let secondDerivative = radial.second
            + configuration.cylinder.axis * height.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified parallel torus-cylinder component has a singular differential."
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
        guard surface == torusSurface || surface == cylinderSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parallel torus-cylinder pcurve was requested on an unrelated surface."
            )
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
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let radius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.torus.center.x - radius,
                y: configuration.torus.center.y - radius,
                z: configuration.torus.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.torus.center.x + radius,
                y: configuration.torus.center.y + radius,
                z: configuration.torus.center.z + radius
            )
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

    private func composedRadialSquared(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> ScalarDifferential {
        let angularFirst = configuration.radialSquaredFirstDerivative(at: angle.value)
        return ScalarDifferential(
            value: configuration.radialSquared(at: angle.value),
            first: angularFirst * angle.first,
            second: configuration.radialSquaredSecondDerivative(at: angle.value)
                    * angle.first * angle.first
                + angularFirst * angle.second
        )
    }

    private func squareRootDifferential(
        _ input: ScalarDifferential
    ) -> ScalarDifferential {
        let root = sqrt(input.value)
        return ScalarDifferential(
            value: root,
            first: input.first / (2.0 * root),
            second: input.second / (2.0 * root)
                - input.first * input.first / (4.0 * root * root * root)
        )
    }

    private func radialDifferential(
        angle: ScalarDifferential,
        configuration: Configuration
    ) -> (value: Vector3D, first: Vector3D, second: Vector3D) {
        let value = configuration.cylinder.radialU * cos(angle.value)
            + configuration.cylinder.radialV * sin(angle.value)
        let angularFirst = configuration.cylinder.radialU * -sin(angle.value)
            + configuration.cylinder.radialV * cos(angle.value)
        return (
            value,
            angularFirst * angle.first,
            -value * (angle.first * angle.first) + angularFirst * angle.second
        )
    }

    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
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
        }
        if componentKind == .boundedAngularInterval,
           abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0),
           abs(radicand.value) <= classificationTolerance * 32.0 {
            let squaredSlope = radicand.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A parallel torus-cylinder boundary has no regular square-root continuation."
                )
            }
            let isUpper = cos(2.0 * Double.pi * fraction) < 0.0
            return ScalarDifferential(
                value: 0.0,
                first: (isUpper ? -1.0 : 1.0) * sqrt(squaredSlope),
                second: 0.0
            )
        }
        guard radicand.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -radicand.value,
                tolerance: tolerance,
                message: "A parallel torus-cylinder evaluator left its certified radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A parallel torus-cylinder square-root differential is singular."
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
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try torusSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
        guard case let .torus(sourceTorus) = CanonicalAnalyticSurface(torusSurface),
              case let .cylinder(sourceCylinder) = CanonicalAnalyticSurface(cylinderSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified parallel torus-cylinder curve requires one exact torus and one exact cylinder."
            )
        }
        guard AnalyticAxisRelation.areParallel(
            sourceTorus.axis,
            sourceCylinder.axis,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parallel torus-cylinder curve requires parallel source axes."
            )
        }
        let torusAxis = try sourceTorus.axis.normalized(tolerance: tolerance.distance)
        let cylinderAxis = try sourceCylinder.axis.normalized(tolerance: tolerance.distance)
        let alignedAxis = cylinderAxis.dot(torusAxis) >= 0.0
            ? torusAxis
            : -torusAxis
        let originOffset = sourceTorus.center - sourceCylinder.origin
        let origin = sourceCylinder.origin
            + alignedAxis * originOffset.dot(alignedAxis)
        let basis = try analyticOrthonormalBasis(alignedAxis, tolerance: tolerance)
        let radialU = basis.u * sourceCylinder.radius
        let radialV = basis.v * sourceCylinder.radius
        let centerOffset = origin - sourceTorus.center
        return Configuration(
            torus: Torus(
                center: sourceTorus.center,
                axis: torusAxis,
                majorRadius: sourceTorus.majorRadius,
                minorRadius: sourceTorus.minorRadius
            ),
            cylinder: Cylinder(
                origin: origin,
                axis: alignedAxis,
                radius: sourceCylinder.radius,
                radialU: radialU,
                radialV: radialV
            ),
            radialSquaredCenter: centerOffset.dot(centerOffset)
                + sourceCylinder.radius * sourceCylinder.radius,
            radialSquaredCosine: 2.0 * centerOffset.dot(radialU),
            radialSquaredSine: 2.0 * centerOffset.dot(radialV)
        )
    }

    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let values = [
            configuration.torus.majorRadius - configuration.torus.minorRadius,
            configuration.torus.majorRadius + configuration.torus.minorRadius,
        ].flatMap { radialDistance in
            boundaryAngles(
                radialDistance: radialDistance,
                configuration: configuration,
                tolerance: tolerance
            )
        }.map {
            refinedBoundaryAngle(
                $0,
                configuration: configuration,
                tolerance: tolerance
            )
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

    private static func boundaryAngles(
        radialDistance: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.harmonicAmplitude
        let numericalThreshold = radialSquaredClassificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard amplitude > numericalThreshold else { return [] }
        let ratio = (
            radialDistance * radialDistance
                - configuration.radialSquaredCenter
        ) / amplitude
        let ratioTolerance = numericalThreshold / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let phase = atan2(
            configuration.radialSquaredSine,
            configuration.radialSquaredCosine
        )
        let offset = acos(min(max(ratio, -1.0), 1.0))
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
        let squaredLower = max(
            configuration.radialSquaredCenter - configuration.harmonicAmplitude,
            0.0
        )
        let squaredUpper = max(
            configuration.radialSquaredCenter + configuration.harmonicAmplitude,
            0.0
        )
        let radialLower = sqrt(squaredLower)
        let radialUpper = sqrt(squaredUpper)
        let maximumTubeDistance = max(
            abs(radialLower - configuration.torus.majorRadius),
            abs(radialUpper - configuration.torus.majorRadius)
        )
        return configuration.torus.minorRadius * configuration.torus.minorRadius
            - maximumTubeDistance * maximumTubeDistance
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
        let result = sqrt(rootResidual) + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Parallel torus-cylinder boundary roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 4_096.0,
            tolerance.distance
                * (2.0 * configuration.torus.minorRadius + tolerance.distance)
                * 1.0e-6
        )
    }

    private static func radialSquaredClassificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let outerRadius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
        return max(
            Double.ulpOfOne * max(
                outerRadius * outerRadius,
                configuration.cylinder.radius * configuration.cylinder.radius,
                configuration.radialSquaredCenter,
                1.0
            ) * 128.0,
            tolerance.distance * (2.0 * outerRadius + tolerance.distance) * 1.0e-6
        )
    }

    private static func refinedBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let residualTolerance = max(
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0,
            Double.leastNonzeroMagnitude
        )
        for _ in 0..<64 {
            let value = configuration.radicand(at: angle)
            if abs(value) <= residualTolerance { break }
            let derivative = configuration.radicandFirstDerivative(at: angle)
            guard derivative.isFinite,
                  abs(derivative) > tolerance.angle else { break }
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

    private enum CodingKeys: String, CodingKey {
        case torusSurface
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
                .torusSurface,
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
            torusSurface: container.decode(Surface3D.self, forKey: .torusSurface),
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
                debugDescription: "The parallel torus-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
