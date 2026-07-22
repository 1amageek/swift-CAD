import CADCore
import Foundation

public struct CertifiedConeCylinderIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case tangentFullBranch
        case boundedAngularInterval
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
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        var coefficientScale: Double {
            max(absoluteCoefficientMaximum, 1.0)
        }

        var absoluteCoefficientMaximum: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                abs(sineDouble)
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
        let cone: Cone
        let cylinder: Cylinder
        let cylinderRadialU: Vector3D
        let cylinderRadialV: Vector3D
        let coneMetricScale: Double
        let generatorQuadratic: Double
        let halfLinearPolynomial: TrigonometricPolynomial
        let discriminantPolynomial: TrigonometricPolynomial

        var characteristicLength: Double {
            max(
                (cylinder.origin - cone.apex).length,
                cylinder.radius,
                1.0
            )
        }

        func cylinderBaseOffset(at angle: Double) -> Vector3D {
            cylinder.origin - cone.apex
                + cylinderRadialU * cos(angle)
                + cylinderRadialV * sin(angle)
        }

        func coneMetric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    public let coneSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.coneSurface = coneSurface
        self.cylinderSurface = cylinderSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
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
                message: "A cone-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        try Self.rejectApexContact(
            cone: configuration.cone,
            cylinder: configuration.cylinder,
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
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let boundaries = try Self.roots(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
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
                    message: "A full cone-cylinder branch requires a positive root-free discriminant domain."
                )
            }
        case .tangentFullBranch:
            let maximumAbsoluteDiscriminant = try Self.maximumAbsoluteValue(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  maximumAbsoluteDiscriminant <= classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: maximumAbsoluteDiscriminant,
                    tolerance: tolerance,
                    message: "A tangent cone-cylinder branch requires an identically zero discriminant."
                )
            }
        case .boundedAngularInterval:
            let boundaries = try Self.roots(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let lowerResidual = abs(
                configuration.discriminantPolynomial.value(at: lowerAngle)
            )
            let upperResidual = abs(
                configuration.discriminantPolynomial.value(at: upperAngle)
            )
            let lowerSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(at: lowerAngle)
            )
            let upperSlope = abs(
                configuration.discriminantPolynomial.firstDerivative(at: upperAngle)
            )
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
                  lowerSlope > classificationTolerance,
                  upperSlope > classificationTolerance,
                  matchesCompleteInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded cone-cylinder component is not a complete simple-root interval."
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
                message: "A cone-cylinder curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let coneProjection = try coneSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let cylinderProjection = try cylinderSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let residual = max(coneProjection.residual, cylinderProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A cone-cylinder curve failed its algebraic reconstruction check."
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
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(at: normalizedFraction)
        let halfLinear = composedDifferential(
            configuration.halfLinearPolynomial,
            angle: angle
        )
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
        let inverseQuadratic = 1.0 / configuration.generatorQuadratic
        let height = ScalarDifferential(
            value: (-halfLinear.value + root.value) * inverseQuadratic,
            first: (-halfLinear.first + root.first) * inverseQuadratic,
            second: (-halfLinear.second + root.second) * inverseQuadratic
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
        let apexResidual = (geometry.position - configuration.cone.apex).length
        guard apexResidual > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "A certified cone-cylinder curve reaches the cone apex."
            )
        }
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-cylinder component has a singular differential."
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
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let maximumHalfLinear = try Self.maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let maximumDiscriminant = max(
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: true,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            ),
            0.0
        )
        let maximumHeight = (maximumHalfLinear + sqrt(maximumDiscriminant))
            / abs(configuration.generatorQuadratic)
        let radius = configuration.cylinder.radius
            + maximumHeight + tolerance.distance
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

    private func angleDifferential(at fraction: Double) -> ScalarDifferential {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .tangentFullBranch:
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
        if componentKind == .tangentFullBranch {
            return ScalarDifferential(value: 0.0, first: 0.0, second: 0.0)
        }
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
        case .tangentFullBranch:
            branchSign = 0.0
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
                    message: "A cone-cylinder discriminant endpoint has no regular square-root continuation."
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
                message: "A cone-cylinder evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(discriminant.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A cone-cylinder square-root differential is singular."
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

    private static func makeConfiguration(
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try coneSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
        guard case let .cone(coneCanonical) = CanonicalAnalyticSurface(coneSurface),
              case let .cylinder(cylinderCanonical) = CanonicalAnalyticSurface(
                cylinderSurface
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cone-cylinder curve requires exact cone and cylinder surfaces."
            )
        }
        let cone = try canonicalCone(coneCanonical, tolerance: tolerance)
        let cylinder = try canonicalCylinder(
            cylinderCanonical,
            tolerance: tolerance
        )
        let coneMetricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)
        let generatorQuadratic = 1.0
            - coneMetricScale * pow(cylinder.axis.dot(cone.axis), 2.0)
        let singularityThreshold = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * 512.0
        )
        guard abs(generatorQuadratic) > singularityThreshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(generatorQuadratic),
                tolerance: tolerance,
                message: "Cone-cylinder generator is parallel to a cone ruling."
            )
        }
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
        let radialU = zeroPoint - cylinder.origin
        let radialV = quarterPoint - cylinder.origin
        let baseOffset = cylinder.origin - cone.apex

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }

        func offset(at angle: Double) -> Vector3D {
            baseOffset
                + radialU * cos(angle)
                + radialV * sin(angle)
        }

        let halfLinear = trigonometricPolynomial { angle in
            metric(offset(at: angle), cylinder.axis)
        }
        let discriminant = trigonometricPolynomial { angle in
            let value = offset(at: angle)
            let linear = metric(value, cylinder.axis)
            return linear * linear - generatorQuadratic * metric(value, value)
        }
        return Configuration(
            cone: cone,
            cylinder: cylinder,
            cylinderRadialU: radialU,
            cylinderRadialV: radialV,
            coneMetricScale: coneMetricScale,
            generatorQuadratic: generatorQuadratic,
            halfLinearPolynomial: halfLinear,
            discriminantPolynomial: discriminant
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
        let denominator = abs(configuration.generatorQuadratic)
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0 / denominator
        let algebraicBound: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            algebraicBound = 0.0
        case .tangentFullBranch:
            let maximumDiscriminant = try maximumAbsoluteValue(
                of: configuration.discriminantPolynomial,
                residualTolerance: classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            algebraicBound = sqrt(max(maximumDiscriminant, 0.0)) / denominator
        case .boundedAngularInterval:
            let rootResidual = max(
                abs(configuration.discriminantPolynomial.value(at: lowerAngle)),
                abs(configuration.discriminantPolynomial.value(at: upperAngle))
            )
            algebraicBound = sqrt(rootResidual) / denominator
        }
        let result = machineBound + algebraicBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Cone-cylinder algebraic reconstruction exceeds the requested tolerance."
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

    private static func rejectApexContact(
        cone: Cone,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws {
        let offset = cone.apex - cylinder.origin
        let axialDistance = offset.dot(cylinder.axis)
        let radialDistance = (offset - cylinder.axis * axialDistance).length
        let residual = abs(radialDistance - cylinder.radius)
        if residual <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: residual,
                tolerance: tolerance,
                message: "Cone-cylinder intersection passes through the cone's singular apex parameter."
            )
        }
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
        case coneSurface
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
                .coneSurface,
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
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
            cylinderSurface: container.decode(
                Surface3D.self,
                forKey: .cylinderSurface
            ),
            componentKind: container.decode(
                ComponentKind.self,
                forKey: .componentKind
            ),
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
                debugDescription: "The cone-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
