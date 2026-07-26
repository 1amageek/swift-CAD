import CADCore
import Foundation

/// A complete cone-torus component for the case where the cone apex lies on
/// the torus.
///
/// The torus equation restricted to every cone generator has the apex root
/// factored out. The remaining cubic defines the geometric branches. Simple
/// zeros of its constant coefficient split the nodal branch at the apex, and
/// simple zeros of its discriminant delimit the generator-tangent loop.
public struct CertifiedConeTorusApexIntersectionCurve:
    Codable,
    Hashable,
    Sendable
{
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case apexNodeInterval
        case generatorTangencyInterval
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Cone {
        let apex: Point3D
        let centerDirection: Vector3D
        let radialU: Vector3D
        let radialV: Vector3D

        func direction(at angle: Double) -> Vector3D {
            centerDirection
                + radialU * cos(angle)
                + radialV * sin(angle)
        }

        func firstDerivative(at angle: Double) -> Vector3D {
            radialU * -sin(angle) + radialV * cos(angle)
        }

        func secondDerivative(at angle: Double) -> Vector3D {
            radialU * -cos(angle) + radialV * -sin(angle)
        }
    }

    private struct Configuration {
        let cone: Cone
        let torusCenter: Point3D
        let torusAxis: Vector3D
        let torusMajorRadius: Double
        let characteristicLength: Double
        let cubicConstant: TrigonometricPolynomial
        let cubicLinear: TrigonometricPolynomial
        let cubicQuadratic: TrigonometricPolynomial
        let cubicDiscriminant: TrigonometricPolynomial

        func coefficients(at angle: Double) -> [Double] {
            [
                cubicConstant.value(at: angle),
                cubicLinear.value(at: angle),
                cubicQuadratic.value(at: angle),
                1.0,
            ]
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
    }

    private struct ScalarRange {
        let lower: Double
        let upper: Double

        init(_ lower: Double, _ upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        static func constant(_ value: Double) -> Self {
            Self(value, value)
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        var minimumAbsoluteValue: Double {
            containsZero ? 0.0 : min(abs(lower), abs(upper)).nextDown
        }

        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper)).nextUp
        }

        func adding(_ other: Self) -> Self {
            Self(lower + other.lower, upper + other.upper)
        }

        func subtracting(_ other: Self) -> Self {
            Self(lower - other.upper, upper - other.lower)
        }

        func multiplied(by other: Self) -> Self {
            let values = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Self(
                values.min() ?? -.infinity,
                values.max() ?? .infinity
            )
        }

        func scaled(by scalar: Double) -> Self {
            scalar >= 0.0
                ? Self(lower * scalar, upper * scalar)
                : Self(upper * scalar, lower * scalar)
        }

        func squared() -> Self {
            containsZero
                ? Self(0.0, max(lower * lower, upper * upper))
                : Self(
                    min(lower * lower, upper * upper),
                    max(lower * lower, upper * upper)
                )
        }
    }

    private struct SimpleRootBounds {
        let lowerValue: Double
        let upperValue: Double
        let firstDerivativeMagnitude: Double
        let secondDerivativeMagnitude: Double
        let thirdDerivativeMagnitude: Double

        func merged(with other: Self) -> Self {
            Self(
                lowerValue: min(lowerValue, other.lowerValue).nextDown,
                upperValue: max(upperValue, other.upperValue).nextUp,
                firstDerivativeMagnitude: max(
                    firstDerivativeMagnitude,
                    other.firstDerivativeMagnitude
                ).nextUp,
                secondDerivativeMagnitude: max(
                    secondDerivativeMagnitude,
                    other.secondDerivativeMagnitude
                ).nextUp,
                thirdDerivativeMagnitude: max(
                    thirdDerivativeMagnitude,
                    other.thirdDerivativeMagnitude
                ).nextUp
            )
        }
    }

    private enum SimpleRootSelection {
        case nearestToZero
        case lower
        case upper

        func select(from roots: [Double]) -> Double? {
            switch self {
            case .nearestToZero:
                roots.min(by: { abs($0) < abs($1) })
            case .lower:
                roots.min()
            case .upper:
                roots.max()
            }
        }
    }

    private struct GeneratorDiscriminantCorrection {
        let companionSelection: SimpleRootSelection
        let lowerValue: Double
        let upperValue: Double
        let lowerDerivative: Double
        let upperDerivative: Double
        let slope: Double
    }

    private struct TrigonometricPolynomial {
        var cosine: [Double]
        var sine: [Double]

        init(cosine: [Double], sine: [Double]) {
            let count = max(cosine.count, sine.count, 1)
            self.cosine = cosine + Array(repeating: 0.0, count: count - cosine.count)
            self.sine = sine + Array(repeating: 0.0, count: count - sine.count)
            self.sine[0] = 0.0
            trim()
        }

        static func constant(_ value: Double) -> Self {
            Self(cosine: [value], sine: [0.0])
        }

        var degree: Int { cosine.count - 1 }

        var coefficientScale: Double {
            max(
                cosine.map(abs).max() ?? 0.0,
                sine.map(abs).max() ?? 0.0,
                1.0
            )
        }

        func value(at angle: Double) -> Double {
            var result = cosine[0]
            if degree > 0 {
                for harmonic in 1...degree {
                    result += cosine[harmonic] * cos(Double(harmonic) * angle)
                        + sine[harmonic] * sin(Double(harmonic) * angle)
                }
            }
            return result
        }

        func firstDerivative(at angle: Double) -> Double {
            guard degree > 0 else { return 0.0 }
            return (1...degree).reduce(0.0) { result, harmonic in
                let scale = Double(harmonic)
                return result
                    - cosine[harmonic] * scale * sin(scale * angle)
                    + sine[harmonic] * scale * cos(scale * angle)
            }
        }

        func secondDerivative(at angle: Double) -> Double {
            derivative(at: angle, order: 2)
        }

        func derivative(at angle: Double, order: Int) -> Double {
            guard order > 0, degree > 0 else {
                return order == 0 ? value(at: angle) : 0.0
            }
            var result = 0.0
            for harmonic in 1...degree {
                let frequency = Double(harmonic)
                let scale = pow(frequency, Double(order))
                let phase = frequency * angle
                    + Double(order) * Double.pi * 0.5
                result += scale * (
                    cosine[harmonic] * cos(phase)
                        + sine[harmonic] * sin(phase)
                )
            }
            return result
        }

        func derivativeMagnitudeUpperBound(order: Int) -> Double {
            guard degree > 0 else { return 0.0 }
            var result = 0.0
            for harmonic in 1...degree {
                let scale = pow(Double(harmonic), Double(order))
                result = (
                    result
                        + scale * hypot(
                            cosine[harmonic],
                            sine[harmonic]
                        )
                ).nextUp
            }
            return result
        }

        func range(
            from lower: Double,
            to upper: Double,
            derivativeOrder: Int = 0
        ) -> ScalarRange {
            let middle = lower + (upper - lower) * 0.5
            let midpoint = derivative(
                at: middle,
                order: derivativeOrder
            )
            let radius = (
                derivativeMagnitudeUpperBound(
                    order: derivativeOrder + 1
                ) * (upper - lower) * 0.5
            ).nextUp
            return ScalarRange(
                midpoint - radius,
                midpoint + radius
            )
        }

        func adding(_ other: Self) -> Self {
            let count = max(cosine.count, other.cosine.count)
            var resultCosine = Array(repeating: 0.0, count: count)
            var resultSine = Array(repeating: 0.0, count: count)
            for index in 0..<count {
                resultCosine[index] = coefficient(cosine, index)
                    + coefficient(other.cosine, index)
                resultSine[index] = coefficient(sine, index)
                    + coefficient(other.sine, index)
            }
            return Self(cosine: resultCosine, sine: resultSine)
        }

        func scaled(by value: Double) -> Self {
            Self(
                cosine: cosine.map { $0 * value },
                sine: sine.map { $0 * value }
            )
        }

        func multiplied(by other: Self) -> Self {
            let resultDegree = degree + other.degree
            var resultCosine = Array(repeating: 0.0, count: resultDegree + 1)
            var resultSine = Array(repeating: 0.0, count: resultDegree + 1)
            for first in 0...degree {
                for second in 0...other.degree {
                    let firstCosine = cosine[first]
                    let firstSine = sine[first]
                    let secondCosine = other.cosine[second]
                    let secondSine = other.sine[second]
                    addCosine(
                        first - second,
                        value: 0.5 * (
                            firstCosine * secondCosine
                                + firstSine * secondSine
                        ),
                        to: &resultCosine
                    )
                    addCosine(
                        first + second,
                        value: 0.5 * (
                            firstCosine * secondCosine
                                - firstSine * secondSine
                        ),
                        to: &resultCosine
                    )
                    addSine(
                        second + first,
                        value: 0.5 * (
                            firstCosine * secondSine
                                + firstSine * secondCosine
                        ),
                        to: &resultSine
                    )
                    addSine(
                        second - first,
                        value: 0.5 * (
                            firstCosine * secondSine
                                - firstSine * secondCosine
                        ),
                        to: &resultSine
                    )
                }
            }
            return Self(cosine: resultCosine, sine: resultSine)
        }

        func tangentHalfAngleCoefficients() -> [Double] {
            let targetDegree = degree
            let denominator = [1.0, 0.0, 1.0]
            let cosineBase = [1.0, 0.0, -1.0]
            let sineBase = [0.0, 2.0]
            var cosineNumerators = [[1.0]]
            var sineNumerators = [[0.0]]
            if targetDegree > 0 {
                for _ in 1...targetDegree {
                    let previousCosine = cosineNumerators.last ?? [1.0]
                    let previousSine = sineNumerators.last ?? [0.0]
                    cosineNumerators.append(subtract(
                        multiply(previousCosine, cosineBase),
                        multiply(previousSine, sineBase)
                    ))
                    sineNumerators.append(add(
                        multiply(previousSine, cosineBase),
                        multiply(previousCosine, sineBase)
                    ))
                }
            }
            var result = [Double](repeating: 0.0, count: targetDegree * 2 + 1)
            for harmonic in 0...targetDegree {
                let elevation = polynomialPower(
                    denominator,
                    exponent: targetDegree - harmonic
                )
                result = add(
                    result,
                    multiply(
                        cosineNumerators[harmonic],
                        elevation
                    ).map { $0 * cosine[harmonic] }
                )
                if harmonic > 0 {
                    result = add(
                        result,
                        multiply(
                            sineNumerators[harmonic],
                            elevation
                        ).map { $0 * sine[harmonic] }
                    )
                }
            }
            return result
        }

        private mutating func trim() {
            while cosine.count > 1,
                  abs(cosine.last ?? 0.0) <= Double.ulpOfOne,
                  abs(sine.last ?? 0.0) <= Double.ulpOfOne {
                cosine.removeLast()
                sine.removeLast()
            }
        }

        private func coefficient(_ values: [Double], _ index: Int) -> Double {
            index < values.count ? values[index] : 0.0
        }

        private func addCosine(
            _ harmonic: Int,
            value: Double,
            to result: inout [Double]
        ) {
            result[abs(harmonic)] += value
        }

        private func addSine(
            _ harmonic: Int,
            value: Double,
            to result: inout [Double]
        ) {
            guard harmonic != 0 else { return }
            result[abs(harmonic)] += harmonic > 0 ? value : -value
        }

        private func add(_ first: [Double], _ second: [Double]) -> [Double] {
            let count = max(first.count, second.count)
            return (0..<count).map {
                coefficient(first, $0) + coefficient(second, $0)
            }
        }

        private func subtract(_ first: [Double], _ second: [Double]) -> [Double] {
            let count = max(first.count, second.count)
            return (0..<count).map {
                coefficient(first, $0) - coefficient(second, $0)
            }
        }

        private func multiply(_ first: [Double], _ second: [Double]) -> [Double] {
            var result = Array(
                repeating: 0.0,
                count: max(first.count + second.count - 1, 1)
            )
            for firstIndex in first.indices {
                for secondIndex in second.indices {
                    result[firstIndex + secondIndex] +=
                        first[firstIndex] * second[secondIndex]
                }
            }
            return result
        }

        private func polynomialPower(
            _ polynomial: [Double],
            exponent: Int
        ) -> [Double] {
            guard exponent > 0 else { return [1.0] }
            return (0..<exponent).reduce([1.0]) { result, _ in
                multiply(result, polynomial)
            }
        }
    }

    public let coneSurface: Surface3D
    public let torusSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        try validate(tolerance: tolerance)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedConeTorusApexIntersectionCurve] {
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let apexAngles = try simpleAngles(
            of: configuration.cubicConstant,
            configuration: configuration,
            tolerance: tolerance
        )
        guard apexAngles.count == 2 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: Double(apexAngles.count),
                tolerance: tolerance,
                message: "A cone-torus apex node requires exactly two simple generator directions."
            )
        }
        var result = try [
            (apexAngles[0], apexAngles[1]),
            (apexAngles[1], apexAngles[0] + 2.0 * Double.pi),
        ].map {
            try CertifiedConeTorusApexIntersectionCurve(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                componentKind: .apexNodeInterval,
                lowerAngle: $0.0,
                upperAngle: $0.1,
                tolerance: tolerance
            )
        }

        let tangencyAngles = try simpleAngles(
            of: configuration.cubicDiscriminant,
            configuration: configuration,
            tolerance: tolerance
        )
        for index in tangencyAngles.indices {
            let lower = tangencyAngles[index]
            let upper = index + 1 < tangencyAngles.count
                ? tangencyAngles[index + 1]
                : tangencyAngles[0] + 2.0 * Double.pi
            let middle = lower + (upper - lower) * 0.5
            let discriminant = configuration.cubicDiscriminant.value(at: middle)
            if discriminant > classificationTolerance(
                polynomial: configuration.cubicDiscriminant,
                tolerance: tolerance
            ) {
                result.append(try CertifiedConeTorusApexIntersectionCurve(
                    coneSurface: coneSurface,
                    torusSurface: torusSurface,
                    componentKind: .generatorTangencyInterval,
                    lowerAngle: lower,
                    upperAngle: upper,
                    tolerance: tolerance
                ))
            }
        }
        return result
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative,
              lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle < 2.0 * Double.pi,
              maximumResidualUpperBound > 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus apex component has an invalid stored contract."
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let boundaryPolynomial = componentKind == .apexNodeInterval
            ? configuration.cubicConstant
            : configuration.cubicDiscriminant
        let boundaryTolerance = Self.classificationTolerance(
            polynomial: boundaryPolynomial,
            tolerance: tolerance
        )
        let lowerResidual = abs(boundaryPolynomial.value(at: lowerAngle))
        let upperResidual = abs(boundaryPolynomial.value(at: upperAngle))
        let lowerSlope = abs(boundaryPolynomial.firstDerivative(at: lowerAngle))
        let upperSlope = abs(boundaryPolynomial.firstDerivative(at: upperAngle))
        guard lowerResidual <= boundaryTolerance * 32.0,
              upperResidual <= boundaryTolerance * 32.0,
              lowerSlope > boundaryTolerance,
              upperSlope > boundaryTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(lowerResidual, upperResidual),
                tolerance: tolerance,
                message: "A cone-torus apex component does not retain simple certified boundaries."
            )
        }
        if componentKind == .generatorTangencyInterval {
            let middle = lowerAngle + (upperAngle - lowerAngle) * 0.5
            guard configuration.cubicDiscriminant.value(at: middle)
                    > boundaryTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A cone-torus generator-tangent component must contain three real cubic roots."
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
        let boundedFraction = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let angle = angleDifferential(at: boundedFraction)
        let slantDifferential: ScalarDifferential
        switch componentKind {
        case .apexNodeInterval:
            let slant = try apexNodeSlantValue(
                angle: angle.value,
                configuration: configuration,
                tolerance: tolerance
            )
            slantDifferential = try regularSlantDifferential(
                slant: slant,
                angle: angle,
                configuration: configuration,
                tolerance: tolerance
            )
        case .generatorTangencyInterval:
            slantDifferential = try generatorSlantDifferential(
                angle: angle,
                fraction: boundedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
        }
        let slant = slantDifferential.value
        let direction = configuration.cone.direction(at: angle.value)
        let directionFirst = configuration.cone.firstDerivative(at: angle.value)
        let directionSecond = configuration.cone.secondDerivative(at: angle.value)
        let position = configuration.cone.apex + direction * slant
        let firstDerivative = directionFirst * (angle.first * slant)
            + direction * slantDifferential.first
        let secondDerivative = directionSecond
                * (angle.first * angle.first * slant)
            + directionFirst
                * (angle.second * slant + 2.0 * angle.first * slantDifferential.first)
            + direction * slantDifferential.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A cone-torus apex component has a singular spatial differential."
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
        guard surface == coneSurface || surface == torusSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus apex pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        guard case let .torus(torus) = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus apex bound requires an analytic torus."
            )
        }
        let radius = torus.majorRadius + torus.minorRadius + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: torus.center.x - radius,
                y: torus.center.y - radius,
                z: torus.center.z - radius
            ),
            maximum: Point3D(
                x: torus.center.x + radius,
                y: torus.center.y + radius,
                z: torus.center.z + radius
            )
        )
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        switch componentKind {
        case .apexNodeInterval:
            return try apexNodeSpatialDifferentialMagnitudeBounds(
                lowerFraction: lower,
                upperFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        case .generatorTangencyInterval:
            return try generatorTangencySpatialDifferentialMagnitudeBounds(
                lowerFraction: lower,
                upperFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            )
        }
    }

    private func apexNodeSpatialDifferentialMagnitudeBounds(
        lowerFraction: Double,
        upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let span = upperAngle - lowerAngle
        let angleLower = lowerAngle + span * lowerFraction
        let angleUpper = lowerAngle + span * upperFraction
        let root = try simpleMainRootBounds(
            lowerAngle: angleLower,
            upperAngle: angleUpper,
            selection: .nearestToZero,
            configuration: configuration,
            tolerance: tolerance
        )
        return try Self.spatialBounds(
            slantMagnitude: max(
                abs(root.lowerValue),
                abs(root.upperValue)
            ).nextUp,
            slantFirstMagnitude: (
                root.firstDerivativeMagnitude * span
            ).nextUp,
            slantSecondMagnitude: (
                root.secondDerivativeMagnitude * span * span
            ).nextUp,
            angleFirstMagnitude: span.nextUp,
            angleSecondMagnitude: 0.0,
            cone: configuration.cone,
            tolerance: tolerance,
            label: "Cone-torus apex-node"
        )
    }

    private func generatorTangencySpatialDifferentialMagnitudeBounds(
        lowerFraction: Double,
        upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let span = upperAngle - lowerAngle
        let halfSpan = span * 0.5
        let correction = try generatorDiscriminantCorrection(
            configuration: configuration,
            tolerance: tolerance
        )
        let companionSelection = correction.companionSelection
        let mainRoot = try simpleMainRootBounds(
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            selection: companionSelection,
            configuration: configuration,
            tolerance: tolerance
        )
        let derivativeBounds = Self.quadraticDiscriminantDerivativeBounds(
            root: mainRoot,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration
        )
        let requestedAngle = requestedGeneratorAngleRange(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 1_048_576.0
        ).nextUp
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: max(requestedAngle.lower, lowerAngle),
            requestedUpper: min(requestedAngle.upper, upperAngle),
            lowerValue: correction.lowerValue,
            upperValue: correction.upperValue,
            lowerDerivative: correction.lowerDerivative,
            upperDerivative: correction.upperDerivative,
            firstDerivativeMagnitudeUpperBound:
                derivativeBounds[1],
            secondDerivativeMagnitudeUpperBound:
                derivativeBounds[2],
            thirdDerivativeMagnitudeUpperBound:
                derivativeBounds[3],
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                let root = try simpleMainRootBounds(
                    lowerAngle: rangeLower,
                    upperAngle: rangeUpper,
                    selection: companionSelection,
                    configuration: configuration,
                    tolerance: tolerance
                )
                let middle = rangeLower
                    + (rangeUpper - rangeLower) * 0.5
                let midpointRoot = try mainRootDifferential(
                    at: middle,
                    selection: companionSelection,
                    configuration: configuration,
                    tolerance: tolerance
                )
                let midpointValue = Self.quadraticDiscriminant(
                    angle: middle,
                    root: midpointRoot.value,
                    configuration: configuration
                )
                let cellDerivativeBounds =
                    Self.quadraticDiscriminantDerivativeBounds(
                    root: root,
                    lowerAngle: rangeLower,
                    upperAngle: rangeUpper,
                    configuration: configuration
                )
                let midpointFirst =
                    Self.quadraticDiscriminantFirstDerivative(
                        angle: middle,
                        root: midpointRoot,
                        configuration: configuration
                    )
                let halfWidth = (rangeUpper - rangeLower) * 0.5
                let firstBound = (
                    abs(midpointFirst)
                        + cellDerivativeBounds[2] * halfWidth
                ).nextUp
                let radius = (
                    firstBound * halfWidth
                ).nextUp
                return (
                    (midpointValue - radius - arithmeticEnvelope).nextDown,
                    (midpointValue + radius + arithmeticEnvelope).nextUp
                )
            },
            tolerance: tolerance,
            label: "Cone-torus generator-fold quadratic factor"
        )
        let factorRootLower = sqrt(factor.lower).nextDown
        let factorRootUpper = sqrt(factor.upper).nextUp
        guard factorRootLower > 0.0, factorRootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus generator-fold factor lost its positive square-root margin."
            )
        }
        let factorRootFirst = (
            factor.first / (2.0 * factorRootLower).nextDown
        ).nextUp
        let factorRootSecond = (
            factor.second / (2.0 * factorRootLower).nextDown
                + factor.first * factor.first
                    / (
                        4.0 * factor.lower * factorRootLower
                    ).nextDown
        ).nextUp
        let phase = ScalarRange(
            2.0 * Double.pi * lowerFraction,
            2.0 * Double.pi * upperFraction
        )
        let sineMagnitude = Self.trigonometricMagnitude(
            phase,
            sine: true
        )
        let cosineMagnitude = Self.trigonometricMagnitude(
            phase,
            sine: false
        )
        let angleFirst = (
            span * Double.pi * sineMagnitude
        ).nextUp
        let angleSecond = (
            2.0 * span * Double.pi * Double.pi
                * cosineMagnitude
        ).nextUp
        let composedFactorFirst = (
            factorRootFirst * angleFirst
        ).nextUp
        let composedFactorSecond = (
            factorRootSecond * angleFirst * angleFirst
                + factorRootFirst * angleSecond
        ).nextUp
        let distance = (halfSpan * 0.5 * sineMagnitude).nextUp
        let distanceFirst = (
            halfSpan * Double.pi * cosineMagnitude
        ).nextUp
        let distanceSecond = (
            2.0 * halfSpan * Double.pi * Double.pi
                * sineMagnitude
        ).nextUp
        let splitMagnitude = (distance * factorRootUpper).nextUp
        let splitFirst = (
            distanceFirst * factorRootUpper
                + distance * composedFactorFirst
        ).nextUp
        let splitSecond = (
            distanceSecond * factorRootUpper
                + 2.0 * distanceFirst * composedFactorFirst
                + distance * composedFactorSecond
        ).nextUp
        let quadratic = configuration.cubicQuadratic
        let quadraticMagnitude = quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper
        ).maximumAbsoluteValue
        let quadraticFirst = quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper,
            derivativeOrder: 1
        ).maximumAbsoluteValue
        let quadraticSecond = quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper,
            derivativeOrder: 2
        ).maximumAbsoluteValue
        let baseMagnitude = (
            0.5 * (
                quadraticMagnitude
                    + max(
                        abs(mainRoot.lowerValue),
                        abs(mainRoot.upperValue)
                    )
            )
        ).nextUp
        let baseFirst = (
            0.5 * (
                quadraticFirst
                    + mainRoot.firstDerivativeMagnitude
            ) * angleFirst
        ).nextUp
        let baseSecond = (
            0.5 * (
                (
                    quadraticSecond
                        + mainRoot.secondDerivativeMagnitude
                ) * angleFirst * angleFirst
                    + (
                        quadraticFirst
                            + mainRoot.firstDerivativeMagnitude
                    ) * angleSecond
            )
        ).nextUp
        return try Self.spatialBounds(
            slantMagnitude: (baseMagnitude + splitMagnitude).nextUp,
            slantFirstMagnitude: (baseFirst + splitFirst).nextUp,
            slantSecondMagnitude: (baseSecond + splitSecond).nextUp,
            angleFirstMagnitude: angleFirst,
            angleSecondMagnitude: angleSecond,
            cone: configuration.cone,
            tolerance: tolerance,
            label: "Cone-torus generator-fold"
        )
    }

    private func requestedGeneratorAngleRange(
        lowerFraction: Double,
        upperFraction: Double
    ) -> (lower: Double, upper: Double) {
        let span = upperAngle - lowerAngle
        func angle(_ fraction: Double) -> Double {
            lowerAngle + span * 0.5
                * (1.0 - cos(2.0 * Double.pi * fraction))
        }
        var values = [angle(lowerFraction), angle(upperFraction)]
        if lowerFraction < 0.5, upperFraction > 0.5 {
            values.append(upperAngle)
        }
        return (
            (values.min() ?? lowerAngle).nextDown,
            (values.max() ?? upperAngle).nextUp
        )
    }

    private static func spatialBounds(
        slantMagnitude: Double,
        slantFirstMagnitude: Double,
        slantSecondMagnitude: Double,
        angleFirstMagnitude: Double,
        angleSecondMagnitude: Double,
        cone: Cone,
        tolerance: ModelingTolerance,
        label: String
    ) throws -> SpatialDifferentialMagnitudeBounds {
        let angularMagnitude = hypot(
            cone.radialU.length,
            cone.radialV.length
        ).nextUp
        let first = (
            angularMagnitude * angleFirstMagnitude * slantMagnitude
                + slantFirstMagnitude
        ).nextUp
        let second = (
            angularMagnitude * (
                angleFirstMagnitude * angleFirstMagnitude
                    + angleSecondMagnitude
            ) * slantMagnitude
                + 2.0 * angularMagnitude * angleFirstMagnitude
                    * slantFirstMagnitude
                + slantSecondMagnitude
        ).nextUp
        guard first.isFinite, second.isFinite,
              first > 0.0, second > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "\(label) spatial bounds exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second
        )
    }

    private func simpleMainRootBounds(
        lowerAngle: Double,
        upperAngle: Double,
        selection: SimpleRootSelection,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SimpleRootBounds {
        struct Cell {
            let lower: Double
            let upper: Double
            let depth: Int
        }
        var cells = [Cell(
            lower: lowerAngle,
            upper: upperAngle,
            depth: 0
        )]
        var result: SimpleRootBounds?
        var processed = 0
        while let cell = cells.popLast() {
            processed += 1
            guard processed <= 65_536 else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "Cone-torus simple-root certification exceeded its cell budget."
                )
            }
            if let certified = try certifySimpleMainRootCell(
                lowerAngle: cell.lower,
                upperAngle: cell.upper,
                selection: selection,
                configuration: configuration,
                tolerance: tolerance
            ) {
                result = result?.merged(with: certified) ?? certified
                continue
            }
            guard cell.depth < 24 else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "Cone-torus \(componentKind.rawValue) simple-root certification exhausted its subdivision depth for requested angles \(lowerAngle)...\(upperAngle), near \(cell.lower)...\(cell.upper)."
                )
            }
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            cells.append(Cell(
                lower: middle,
                upper: cell.upper,
                depth: cell.depth + 1
            ))
            cells.append(Cell(
                lower: cell.lower,
                upper: middle,
                depth: cell.depth + 1
            ))
        }
        guard let result else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Cone-torus simple-root certification produced no root tube."
            )
        }
        return result
    }

    private func certifySimpleMainRootCell(
        lowerAngle: Double,
        upperAngle: Double,
        selection: SimpleRootSelection,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SimpleRootBounds? {
        let middle = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let coefficients = configuration.coefficients(at: middle)
        let roots = try Self.reducedCubicRoots(
            coefficients: coefficients,
            configuration: configuration,
            tolerance: tolerance
        )
        guard let root = selection.select(from: roots) else {
            return nil
        }
        let derivativeRoots = try Self.reducedCubicRoots(
            coefficients: [
                coefficients[1],
                2.0 * coefficients[2],
                3.0,
            ],
            configuration: configuration,
            tolerance: tolerance
        )
        let criticalDistance = derivativeRoots.map {
            abs($0 - root)
        }.filter {
            $0 > tolerance.distance
        }.min()
        let radius = (
            (criticalDistance ?? configuration.characteristicLength)
                * 0.375
        ).nextDown
        guard radius > tolerance.distance else { return nil }
        let slant = ScalarRange(root - radius, root + radius)
        let lowerBoundary = Self.reducedCubicRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: .constant(slant.lower),
            configuration: configuration
        )
        let upperBoundary = Self.reducedCubicRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: .constant(slant.upper),
            configuration: configuration
        )
        let hasOppositeBoundarySigns = (
            lowerBoundary.upper < 0.0 && upperBoundary.lower > 0.0
        ) || (
            lowerBoundary.lower > 0.0 && upperBoundary.upper < 0.0
        )
        guard hasOppositeBoundarySigns else { return nil }
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let c2Range = c2.range(from: lowerAngle, to: upperAngle)
        let c3Range = c3.range(from: lowerAngle, to: upperAngle)
        var rootRange = slant
        var slantDerivative = Self.reducedCubicSlantDerivativeRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: rootRange,
            configuration: configuration
        )
        var denominator = slantDerivative.minimumAbsoluteValue
        guard denominator > Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        ) else {
            return nil
        }
        let c1First = c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        )
        let c2First = c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        )
        let c3First = c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        )
        var angleDerivative = c1First
            .adding(c2First.multiplied(by: rootRange))
            .adding(c3First.multiplied(by: rootRange.squared()))
        var first = (
            angleDerivative.maximumAbsoluteValue / denominator
        ).nextUp
        let halfWidth = (upperAngle - lowerAngle) * 0.5
        for _ in 0..<3 {
            let valueVariation = (first * halfWidth).nextUp
            rootRange = ScalarRange(
                max(slant.lower, root - valueVariation),
                min(slant.upper, root + valueVariation)
            )
            slantDerivative = Self.reducedCubicSlantDerivativeRange(
                angleLower: lowerAngle,
                angleUpper: upperAngle,
                slant: rootRange,
                configuration: configuration
            )
            denominator = slantDerivative.minimumAbsoluteValue
            guard denominator > Self.derivativeThreshold(
                configuration: configuration,
                tolerance: tolerance
            ) else {
                return nil
            }
            angleDerivative = c1First
                .adding(c2First.multiplied(by: rootRange))
                .adding(c3First.multiplied(by: rootRange.squared()))
            first = (
                angleDerivative.maximumAbsoluteValue / denominator
            ).nextUp
        }
        let c1Second = c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        )
        let c2Second = c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        )
        let c3Second = c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        )
        let angleAngle = c1Second
            .adding(c2Second.multiplied(by: rootRange))
            .adding(c3Second.multiplied(by: rootRange.squared()))
        let angleSlant = c2First
            .adding(c3First.multiplied(by: rootRange).scaled(by: 2.0))
        let slantSlant = c3Range
            .scaled(by: 2.0)
            .adding(rootRange.scaled(by: 6.0))
        let second = (
            (
                angleAngle.maximumAbsoluteValue
                    + 2.0 * angleSlant.maximumAbsoluteValue * first
                    + slantSlant.maximumAbsoluteValue * first * first
            ) / denominator
        ).nextUp
        let c1Third = c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        )
        let c2Third = c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        )
        let c3Third = c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        )
        let angleAngleAngle = c1Third
            .adding(c2Third.multiplied(by: rootRange))
            .adding(c3Third.multiplied(by: rootRange.squared()))
        let angleAngleSlant = c2Second
            .adding(c3Second.multiplied(by: rootRange).scaled(by: 2.0))
        let angleSlantSlant = c3First.scaled(by: 2.0)
        let third = (
            (
                angleAngleAngle.maximumAbsoluteValue
                    + 3.0 * angleAngleSlant.maximumAbsoluteValue * first
                    + 3.0 * angleSlantSlant.maximumAbsoluteValue
                        * first * first
                    + 6.0 * first * first * first
                    + 3.0 * (
                        angleSlant.maximumAbsoluteValue
                            + slantSlant.maximumAbsoluteValue * first
                    ) * second
            ) / denominator
        ).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            return nil
        }
        let valueVariation = (first * halfWidth).nextUp
        return SimpleRootBounds(
            lowerValue: (root - valueVariation).nextDown,
            upperValue: (root + valueVariation).nextUp,
            firstDerivativeMagnitude: first,
            secondDerivativeMagnitude: second,
            thirdDerivativeMagnitude: third
        )
    }

    private static func reducedCubicRoots(
        coefficients: [Double],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.distance * 1.0e-7,
                Double.ulpOfOne
                    * configuration.characteristicLength * 256.0
            ),
            residualTolerance: max(
                tolerance.distance * 1.0e-8,
                Double.ulpOfOne * 4_096.0
            )
        )
        return try solver.realRoots(coefficients: coefficients)
    }

    private static func generatorCompanionRootSelection(
        lowerAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SimpleRootSelection {
        let coefficients = configuration.coefficients(at: lowerAngle)
        let derivativeRoots = try reducedCubicRoots(
            coefficients: [
                coefficients[1],
                2.0 * coefficients[2],
                3.0,
            ],
            configuration: configuration,
            tolerance: tolerance
        )
        guard let fold = derivativeRoots.min(by: {
            abs(polynomialValue(coefficients, at: $0))
                < abs(polynomialValue(coefficients, at: $1))
        }) else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus generator fold lost its repeated-root direction."
            )
        }
        let companion = -coefficients[2] - 2.0 * fold
        guard abs(companion - fold) > derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        ) else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus generator fold lost its distinct companion root."
            )
        }
        return companion < fold ? .lower : .upper
    }

    private func generatorDiscriminantCorrection(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> GeneratorDiscriminantCorrection {
        let selection = try Self.generatorCompanionRootSelection(
            lowerAngle: lowerAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        let lowerRoot = try mainRootDifferential(
            at: lowerAngle,
            selection: selection,
            configuration: configuration,
            tolerance: tolerance
        )
        let upperRoot = try mainRootDifferential(
            at: upperAngle,
            selection: selection,
            configuration: configuration,
            tolerance: tolerance
        )
        let lowerValue = Self.quadraticDiscriminant(
            angle: lowerAngle,
            root: lowerRoot.value,
            configuration: configuration
        )
        let upperValue = Self.quadraticDiscriminant(
            angle: upperAngle,
            root: upperRoot.value,
            configuration: configuration
        )
        let span = upperAngle - lowerAngle
        return GeneratorDiscriminantCorrection(
            companionSelection: selection,
            lowerValue: lowerValue,
            upperValue: upperValue,
            lowerDerivative: Self.quadraticDiscriminantFirstDerivative(
                angle: lowerAngle,
                root: lowerRoot,
                configuration: configuration
            ),
            upperDerivative: Self.quadraticDiscriminantFirstDerivative(
                angle: upperAngle,
                root: upperRoot,
                configuration: configuration
            ),
            slope: (upperValue - lowerValue) / span
        )
    }

    private static func reducedCubicRange(
        angleLower: Double,
        angleUpper: Double,
        slant: ScalarRange,
        configuration: Configuration
    ) -> ScalarRange {
        configuration.cubicConstant.range(
            from: angleLower,
            to: angleUpper
        ).adding(
            configuration.cubicLinear.range(
                from: angleLower,
                to: angleUpper
            ).multiplied(by: slant)
        ).adding(
            configuration.cubicQuadratic.range(
                from: angleLower,
                to: angleUpper
            ).multiplied(by: slant.squared())
        ).adding(
            slant.squared().multiplied(by: slant)
        )
    }

    private static func reducedCubicSlantDerivativeRange(
        angleLower: Double,
        angleUpper: Double,
        slant: ScalarRange,
        configuration: Configuration
    ) -> ScalarRange {
        let middle = angleLower + (angleUpper - angleLower) * 0.5
        let c2 = configuration.cubicLinear.value(at: middle)
        let c3 = configuration.cubicQuadratic.value(at: middle)
        func value(at slant: Double) -> Double {
            c2 + 2.0 * c3 * slant + 3.0 * slant * slant
        }
        var fixedAngleValues = [
            value(at: slant.lower),
            value(at: slant.upper),
        ]
        let vertex = -c3 / 3.0
        if vertex > slant.lower, vertex < slant.upper {
            fixedAngleValues.append(value(at: vertex))
        }
        let c2Range = configuration.cubicLinear.range(
            from: angleLower,
            to: angleUpper
        )
        let c3Range = configuration.cubicQuadratic.range(
            from: angleLower,
            to: angleUpper
        )
        let c2Variation = max(
            abs(c2Range.lower - c2),
            abs(c2Range.upper - c2)
        ).nextUp
        let c3Variation = max(
            abs(c3Range.lower - c3),
            abs(c3Range.upper - c3)
        ).nextUp
        let maximumSlant = max(abs(slant.lower), abs(slant.upper)).nextUp
        let angleVariation = (
            c2Variation + 2.0 * c3Variation * maximumSlant
        ).nextUp
        return ScalarRange(
            (fixedAngleValues.min() ?? -.infinity) - angleVariation,
            (fixedAngleValues.max() ?? .infinity) + angleVariation
        )
    }

    private func mainRootDifferential(
        at angle: Double,
        selection: SimpleRootSelection,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let coefficients = configuration.coefficients(at: angle)
        let roots = try Self.reducedCubicRoots(
            coefficients: coefficients,
            configuration: configuration,
            tolerance: tolerance
        )
        guard let root = selection.select(from: roots) else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus quadratic factor lost its simple main root."
            )
        }
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let denominator = c2.value(at: angle)
            + 2.0 * c3.value(at: angle) * root
            + 3.0 * root * root
        guard abs(denominator) > Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        ) else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus quadratic factor lost main-root simplicity."
            )
        }
        let angleDerivative = c1.firstDerivative(at: angle)
            + c2.firstDerivative(at: angle) * root
            + c3.firstDerivative(at: angle) * root * root
        let first = -angleDerivative / denominator
        let angleAngle = c1.secondDerivative(at: angle)
            + c2.secondDerivative(at: angle) * root
            + c3.secondDerivative(at: angle) * root * root
        let angleSlant = c2.firstDerivative(at: angle)
            + 2.0 * c3.firstDerivative(at: angle) * root
        let slantSlant = 2.0 * c3.value(at: angle) + 6.0 * root
        let second = -(
            angleAngle
                + 2.0 * angleSlant * first
                + slantSlant * first * first
        ) / denominator
        return ScalarDifferential(
            value: root,
            first: first,
            second: second
        )
    }

    private static func quadraticDiscriminant(
        angle: Double,
        root: Double,
        configuration: Configuration
    ) -> Double {
        let quadratic = configuration.cubicQuadratic.value(at: angle)
        let linear = configuration.cubicLinear.value(at: angle)
        return quadratic * quadratic
            - 2.0 * quadratic * root
            - 3.0 * root * root
            - 4.0 * linear
    }

    private static func quadraticDiscriminantFirstDerivative(
        angle: Double,
        root: ScalarDifferential,
        configuration: Configuration
    ) -> Double {
        let quadratic = configuration.cubicQuadratic.value(at: angle)
        let quadraticFirst = configuration.cubicQuadratic
            .firstDerivative(at: angle)
        return 2.0 * quadratic * quadraticFirst
            - 2.0 * (
                quadraticFirst * root.value
                    + quadratic * root.first
            )
            - 6.0 * root.value * root.first
            - 4.0 * configuration.cubicLinear
                .firstDerivative(at: angle)
    }

    private static func quadraticDiscriminantSecondDerivative(
        angle: Double,
        root: ScalarDifferential,
        configuration: Configuration
    ) -> Double {
        let quadratic = configuration.cubicQuadratic.value(at: angle)
        let quadraticFirst = configuration.cubicQuadratic
            .firstDerivative(at: angle)
        let quadraticSecond = configuration.cubicQuadratic
            .secondDerivative(at: angle)
        return 2.0 * (
            quadraticFirst * quadraticFirst
                + quadratic * quadraticSecond
        )
            - 2.0 * (
                quadraticSecond * root.value
                    + 2.0 * quadraticFirst * root.first
                    + quadratic * root.second
            )
            - 6.0 * (
                root.first * root.first
                    + root.value * root.second
            )
            - 4.0 * configuration.cubicLinear
                .secondDerivative(at: angle)
    }

    private static func quadraticDiscriminantDerivativeBounds(
        root: SimpleRootBounds,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration
    ) -> [Double] {
        let quadratic = (0...3).map {
            configuration.cubicQuadratic.range(
                from: lowerAngle,
                to: upperAngle,
                derivativeOrder: $0
            ).maximumAbsoluteValue
        }
        let linear = (0...3).map {
            configuration.cubicLinear.range(
                from: lowerAngle,
                to: upperAngle,
                derivativeOrder: $0
            ).maximumAbsoluteValue
        }
        let rootDerivatives = [
            max(abs(root.lowerValue), abs(root.upperValue)).nextUp,
            root.firstDerivativeMagnitude,
            root.secondDerivativeMagnitude,
            root.thirdDerivativeMagnitude,
        ]
        var result = Array(repeating: 0.0, count: 4)
        for order in 0...3 {
            result[order] = (
                Self.derivativeProductMagnitude(
                    quadratic,
                    quadratic,
                    order: order
                )
                    + 2.0 * Self.derivativeProductMagnitude(
                        quadratic,
                        rootDerivatives,
                        order: order
                    )
                    + 3.0 * Self.derivativeProductMagnitude(
                        rootDerivatives,
                        rootDerivatives,
                        order: order
                    )
                    + 4.0 * linear[order]
            ).nextUp
        }
        return result
    }

    private static func derivativeProductMagnitude(
        _ first: [Double],
        _ second: [Double],
        order: Int
    ) -> Double {
        var result = 0.0
        for index in 0...order {
            result = (
                result
                    + binomial(order, index)
                        * first[index] * second[order - index]
            ).nextUp
        }
        return result
    }

    private static func binomial(_ order: Int, _ index: Int) -> Double {
        guard index > 0, index < order else { return 1.0 }
        let selected = min(index, order - index)
        var result = 1.0
        for step in 1...selected {
            result *= Double(order - selected + step) / Double(step)
        }
        return result.nextUp
    }

    private static func trigonometricMagnitude(
        _ range: ScalarRange,
        sine: Bool
    ) -> Double {
        let phase = sine ? Double.pi * 0.5 : 0.0
        var result = max(
            abs(cos(range.lower - phase)),
            abs(cos(range.upper - phase))
        )
        let firstIndex = Int(
            floor((range.lower - phase) / Double.pi)
        ) - 1
        let lastIndex = Int(
            ceil((range.upper - phase) / Double.pi)
        ) + 1
        for index in firstIndex...lastIndex {
            let extremum = phase + Double(index) * Double.pi
            if extremum >= range.lower, extremum <= range.upper {
                result = 1.0
            }
        }
        return result.nextUp
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

    private func angleDifferential(at fraction: Double) -> ScalarDifferential {
        let span = upperAngle - lowerAngle
        switch componentKind {
        case .apexNodeInterval:
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0
            )
        case .generatorTangencyInterval:
            let phase = 2.0 * Double.pi * fraction
            let halfSpan = span * 0.5
            return ScalarDifferential(
                value: lowerAngle + halfSpan * (1.0 - cos(phase)),
                first: halfSpan * 2.0 * Double.pi * sin(phase),
                second: halfSpan * 4.0 * Double.pi * Double.pi * cos(phase)
            )
        }
    }

    private func apexNodeSlantValue(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let coefficients = configuration.coefficients(at: angle)
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.distance * 1.0e-7,
                Double.ulpOfOne * configuration.characteristicLength * 256.0
            ),
            residualTolerance: max(
                tolerance.distance * 1.0e-8,
                Double.ulpOfOne * 4_096.0
            )
        )
        let roots = try solver.realRoots(coefficients: coefficients)
        guard roots.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A cone-torus apex component lost its reduced cubic root."
            )
        }
        return roots.min(by: { abs($0) < abs($1) }) ?? roots[0]
    }

    private func generatorSlantDifferential(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let correction = try generatorDiscriminantCorrection(
            configuration: configuration,
            tolerance: tolerance
        )
        let companion = try mainRootDifferential(
            at: angle.value,
            selection: correction.companionSelection,
            configuration: configuration,
            tolerance: tolerance
        )
        let quadratic = configuration.cubicQuadratic
        let quadraticValue = quadratic.value(at: angle.value)
        let quadraticFirst = quadratic.firstDerivative(at: angle.value)
        let quadraticSecond = quadratic.secondDerivative(at: angle.value)
        let baseValue = -0.5 * (quadraticValue + companion.value)
        let baseAngleFirst = -0.5 * (
            quadraticFirst + companion.first
        )
        let baseAngleSecond = -0.5 * (
            quadraticSecond + companion.second
        )
        let baseFirst = baseAngleFirst * angle.first
        let baseSecond = baseAngleSecond * angle.first * angle.first
            + baseAngleFirst * angle.second
        let rawDiscriminant = Self.quadraticDiscriminant(
            angle: angle.value,
            root: companion.value,
            configuration: configuration
        )
        let rawFirst = Self.quadraticDiscriminantFirstDerivative(
            angle: angle.value,
            root: companion,
            configuration: configuration
        )
        let correctedValue = rawDiscriminant
            - correction.lowerValue
            - correction.slope * (angle.value - lowerAngle)
        let correctedAngleFirst = rawFirst - correction.slope
        let correctedAngleSecond =
            Self.quadraticDiscriminantSecondDerivative(
                angle: angle.value,
                root: companion,
                configuration: configuration
            )
        let joins = [0.0, 0.5, 1.0]
        let join = joins.min(by: {
            abs(fraction - $0) < abs(fraction - $1)
        }) ?? 0.0
        let joinOffset = fraction - join
        if abs(joinOffset) <= 1.0e-4 {
            let isUpperJoin = join == 0.5
            let endpointAngle = isUpperJoin ? upperAngle : lowerAngle
            let endpointRoot = try mainRootDifferential(
                at: endpointAngle,
                selection: correction.companionSelection,
                configuration: configuration,
                tolerance: tolerance
            )
            let endpointSecond =
                Self.quadraticDiscriminantSecondDerivative(
                    angle: endpointAngle,
                    root: endpointRoot,
                    configuration: configuration
                )
            let endpointFirst = (
                isUpperJoin
                    ? correction.upperDerivative
                    : correction.lowerDerivative
            ) - correction.slope
            let span = upperAngle - lowerAngle
            let angularQuadratic = (
                (isUpperJoin ? -1.0 : 1.0)
                    * span * Double.pi * Double.pi
            )
            let angularQuartic = -angularQuadratic
                * Double.pi * Double.pi / 3.0
            let discriminantQuadratic =
                endpointFirst * angularQuadratic
            let discriminantQuartic =
                endpointFirst * angularQuartic
                    + 0.5 * endpointSecond
                        * angularQuadratic * angularQuadratic
            guard discriminantQuadratic > 0.0,
                  discriminantQuadratic.isFinite,
                  discriminantQuartic.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: discriminantQuadratic,
                    tolerance: tolerance,
                    message: "A cone-torus generator fold lost its regularized endpoint differential."
                )
            }
            let splitLinearMagnitude =
                0.5 * sqrt(discriminantQuadratic)
            let splitLinear = (
                isUpperJoin ? 1.0 : -1.0
            ) * splitLinearMagnitude
            let splitCubic = splitLinear
                * discriminantQuartic
                / (2.0 * discriminantQuadratic)
            let offsetSquared = joinOffset * joinOffset
            return ScalarDifferential(
                value: baseValue
                    + splitLinear * joinOffset
                    + splitCubic * joinOffset * offsetSquared,
                first: baseFirst
                    + splitLinear
                    + 3.0 * splitCubic * offsetSquared,
                second: baseSecond
                    + 6.0 * splitCubic * joinOffset
            )
        }
        guard correctedValue > 0.0, correctedValue.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: correctedValue,
                tolerance: tolerance,
                message: "A cone-torus generator fold lost its positive regularized discriminant."
            )
        }
        let root = sqrt(correctedValue)
        let discriminantFirst = correctedAngleFirst * angle.first
        let discriminantSecond =
            correctedAngleSecond * angle.first * angle.first
                + correctedAngleFirst * angle.second
        let branchSign = fraction <= 0.5 ? -1.0 : 1.0
        let splitValue = branchSign * 0.5 * root
        let splitFirst = branchSign * discriminantFirst / (4.0 * root)
        let splitSecond = branchSign * (
            discriminantSecond / (4.0 * root)
                - discriminantFirst * discriminantFirst
                    / (8.0 * root * root * root)
        )
        return ScalarDifferential(
            value: baseValue + splitValue,
            first: baseFirst + splitFirst,
            second: baseSecond + splitSecond
        )
    }

    private func regularSlantDifferential(
        slant: Double,
        angle: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let firstAngle = c1.firstDerivative(at: angle.value)
            + c2.firstDerivative(at: angle.value) * slant
            + c3.firstDerivative(at: angle.value) * slant * slant
        let secondAngle = c1.secondDerivative(at: angle.value)
            + c2.secondDerivative(at: angle.value) * slant
            + c3.secondDerivative(at: angle.value) * slant * slant
        let slantDerivative = c2.value(at: angle.value)
            + 2.0 * c3.value(at: angle.value) * slant
            + 3.0 * slant * slant
        let mixed = c2.firstDerivative(at: angle.value)
            + 2.0 * c3.firstDerivative(at: angle.value) * slant
        let secondSlant = 2.0 * c3.value(at: angle.value) + 6.0 * slant
        let threshold = Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        )
        guard abs(slantDerivative) > threshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(slantDerivative),
                tolerance: tolerance,
                message: "A cone-torus apex evaluator reached an uncertified cubic fold."
            )
        }
        let slantAngleFirst = -firstAngle / slantDerivative
        let slantAngleSecond = -(
            secondAngle
                + 2.0 * mixed * slantAngleFirst
                + secondSlant * slantAngleFirst * slantAngleFirst
        ) / slantDerivative
        return ScalarDifferential(
            value: slant,
            first: slantAngleFirst * angle.first,
            second: slantAngleSecond * angle.first * angle.first
                + slantAngleFirst * angle.second
        )
    }

    private static func makeConfiguration(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try coneSurface.validate(tolerance: tolerance)
        try torusSurface.validate(tolerance: tolerance)
        guard case let .cone(sourceCone) = CanonicalAnalyticSurface(coneSurface),
              case let .torus(sourceTorus) = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus apex curve requires exact analytic source surfaces."
            )
        }
        let coneAxis = try sourceCone.axis.normalized(
            tolerance: tolerance.distance
        )
        let torusAxis = try sourceTorus.axis.normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(coneAxis, tolerance: tolerance)
        let sine = sin(sourceCone.halfAngle)
        let cone = Cone(
            apex: sourceCone.apex,
            centerDirection: coneAxis * cos(sourceCone.halfAngle),
            radialU: basis.u * sine,
            radialV: basis.v * sine
        )
        let offset = sourceCone.apex - sourceTorus.center
        let axialOffset = offset.dot(torusAxis)
        let pointDirection = TrigonometricPolynomial(
            cosine: [
                offset.dot(cone.centerDirection),
                offset.dot(cone.radialU),
            ],
            sine: [0.0, offset.dot(cone.radialV)]
        )
        let axialDirection = TrigonometricPolynomial(
            cosine: [
                torusAxis.dot(cone.centerDirection),
                torusAxis.dot(cone.radialU),
            ],
            sine: [0.0, torusAxis.dot(cone.radialV)]
        )
        let q0 = offset.dot(offset)
            + sourceTorus.majorRadius * sourceTorus.majorRadius
            - sourceTorus.minorRadius * sourceTorus.minorRadius
        let majorFactor = 4.0 * sourceTorus.majorRadius
            * sourceTorus.majorRadius
        let cubicConstant = pointDirection.scaled(by: 4.0 * q0)
            .adding(
                pointDirection.adding(
                    axialDirection.scaled(by: -axialOffset)
                ).scaled(by: -2.0 * majorFactor)
            )
        let cubicLinear = pointDirection.multiplied(by: pointDirection)
            .scaled(by: 4.0)
            .adding(.constant(2.0 * q0 - majorFactor))
            .adding(
                axialDirection.multiplied(by: axialDirection)
                    .scaled(by: majorFactor)
            )
        let cubicQuadratic = pointDirection.scaled(by: 4.0)
        let discriminant = cubicQuadratic
            .multiplied(by: cubicLinear)
            .multiplied(by: cubicConstant)
            .scaled(by: 18.0)
            .adding(
                cubicQuadratic.multiplied(by: cubicQuadratic)
                    .multiplied(by: cubicLinear)
                    .multiplied(by: cubicLinear)
            )
            .adding(
                cubicQuadratic.multiplied(by: cubicQuadratic)
                    .multiplied(by: cubicQuadratic)
                    .multiplied(by: cubicConstant)
                    .scaled(by: -4.0)
            )
            .adding(
                cubicLinear.multiplied(by: cubicLinear)
                    .multiplied(by: cubicLinear)
                    .scaled(by: -4.0)
            )
            .adding(
                cubicConstant.multiplied(by: cubicConstant)
                    .scaled(by: -27.0)
            )
        let meridianDistance = hypot(
            sqrt(max(0.0, offset.dot(offset) - axialOffset * axialOffset))
                - sourceTorus.majorRadius,
            axialOffset
        )
        let apexResidual = abs(meridianDistance - sourceTorus.minorRadius)
        guard apexResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: apexResidual,
                tolerance: tolerance,
                message: "A cone-torus apex certificate requires the cone apex on the torus."
            )
        }
        return Configuration(
            cone: cone,
            torusCenter: sourceTorus.center,
            torusAxis: torusAxis,
            torusMajorRadius: sourceTorus.majorRadius,
            characteristicLength: max(
                offset.length,
                sourceTorus.majorRadius + sourceTorus.minorRadius,
                1.0
            ),
            cubicConstant: cubicConstant,
            cubicLinear: cubicLinear,
            cubicQuadratic: cubicQuadratic,
            cubicDiscriminant: discriminant
        )
    }

    private static func simpleAngles(
        of polynomial: TrigonometricPolynomial,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 1.0e-3, Double.ulpOfOne * 512.0),
            coefficientTolerance: Double.ulpOfOne * 1_024.0,
            maximumRefinementIterations: 256,
            tolerance: tolerance
        )
        var angles = try solver.roots(
            coefficients: polynomial.tangentHalfAngleCoefficients()
        ).map {
            normalizedAngle(2.0 * atan($0.value))
        }
        let threshold = classificationTolerance(
            polynomial: polynomial,
            tolerance: tolerance
        )
        if abs(polynomial.value(at: Double.pi)) <= threshold * 8.0 {
            angles.append(Double.pi)
        }
        angles.sort()
        var unique: [Double] = []
        for angle in angles {
            guard abs(polynomial.value(at: angle)) <= threshold * 32.0,
                  abs(polynomial.firstDerivative(at: angle)) > threshold else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(polynomial.firstDerivative(at: angle)),
                    tolerance: tolerance,
                    message: "A cone-torus apex classification boundary is not a simple root."
                )
            }
            if let last = unique.last,
               angularDistance(last, angle) <= tolerance.angle {
                continue
            }
            unique.append(angle)
        }
        return unique
    }

    private static func classificationTolerance(
        polynomial: TrigonometricPolynomial,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            polynomial.coefficientScale * Double.ulpOfOne * 65_536.0,
            polynomial.coefficientScale * tolerance.relative * 1.0e-3
        )
    }

    private static func derivativeThreshold(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.distance * 1.0e-7
                * configuration.characteristicLength,
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength
                * 1_024.0
        )
    }

    private static func polynomialValue(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) {
            $0 * value + $1
        }
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: period)
        return value < 0.0 ? value + period : value
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        let period = 2.0 * Double.pi
        let difference = abs(first - second).truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
    }

    private func canonicalFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        if fraction < 0.0, fraction >= -tolerance.relative { return 0.0 }
        if fraction > 1.0, fraction <= 1.0 + tolerance.relative { return 1.0 }
        return min(max(fraction, 0.0), 1.0)
    }
}
