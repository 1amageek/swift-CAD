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
            guard degree > 0 else { return 0.0 }
            return (1...degree).reduce(0.0) { result, harmonic in
                let scale = Double(harmonic * harmonic)
                return result
                    - cosine[harmonic] * scale * cos(Double(harmonic) * angle)
                    - sine[harmonic] * scale * sin(Double(harmonic) * angle)
            }
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
        let slant = try slantValue(
            angle: angle.value,
            fraction: boundedFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let slantDifferential: ScalarDifferential
        if componentKind == .generatorTangencyInterval,
           isTangencyFraction(boundedFraction, tolerance: tolerance) {
            slantDifferential = try tangencySlantDifferential(
                slant: slant,
                angle: angle,
                fraction: boundedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
        } else {
            slantDifferential = try regularSlantDifferential(
                slant: slant,
                angle: angle,
                configuration: configuration,
                tolerance: tolerance
            )
        }
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

    private func slantValue(
        angle: Double,
        fraction: Double,
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
        if componentKind == .generatorTangencyInterval,
           isTangencyFraction(fraction, tolerance: tolerance) {
            let derivativeRoots = try solver.realRoots(coefficients: [
                coefficients[1],
                2.0 * coefficients[2],
                3.0,
            ])
            guard let fold = derivativeRoots.min(by: {
                abs(Self.polynomialValue(coefficients, at: $0))
                    < abs(Self.polynomialValue(coefficients, at: $1))
            }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A cone-torus generator tangency lost its repeated cubic root."
                )
            }
            return fold
        }
        if componentKind == .apexNodeInterval {
            return roots.min(by: { abs($0) < abs($1) }) ?? roots[0]
        }
        let main = roots.min(by: { abs($0) < abs($1) }) ?? roots[0]
        let extras = roots.filter {
            abs($0 - main) > max(tolerance.distance * 4.0, Double.ulpOfOne * 512.0)
        }.sorted()
        if extras.count == 1 {
            return extras[0]
        }
        guard extras.count == 2 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(extras.count),
                tolerance: tolerance,
                message: "A cone-torus generator-tangent loop changed cubic root count."
            )
        }
        return fraction <= 0.5 ? extras[0] : extras[1]
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

    private func tangencySlantDifferential(
        slant: Double,
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let firstAngle = c1.firstDerivative(at: angle.value)
            + c2.firstDerivative(at: angle.value) * slant
            + c3.firstDerivative(at: angle.value) * slant * slant
        let mixed = c2.firstDerivative(at: angle.value)
            + 2.0 * c3.firstDerivative(at: angle.value) * slant
        let secondSlant = 2.0 * c3.value(at: angle.value) + 6.0 * slant
        let squaredFirst = -firstAngle * angle.second / secondSlant
        guard squaredFirst > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: squaredFirst,
                tolerance: tolerance,
                message: "A cone-torus cubic fold has no regular square-root continuation."
            )
        }
        let probeDirection = fraction == 0.5 ? -1.0 : 1.0
        let probeFraction = canonicalFraction(
            fraction + probeDirection * 1.0e-5,
            tolerance: tolerance
        )
        let probeAngle = angleDifferential(at: probeFraction)
        let probeSlant = try slantValue(
            angle: probeAngle.value,
            fraction: probeFraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let sign = (probeSlant - slant) * (probeFraction - fraction) >= 0.0
            ? 1.0
            : -1.0
        let first = sign * sqrt(squaredFirst)
        let second = -(
            3.0 * mixed * angle.second * first
                + 6.0 * first * first * first
        ) / (3.0 * secondSlant * first)
        return ScalarDifferential(value: slant, first: first, second: second)
    }

    private func isTangencyFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        let threshold = max(tolerance.relative, Double.ulpOfOne * 512.0)
        return fraction <= threshold
            || abs(fraction - 0.5) <= threshold
            || fraction >= 1.0 - threshold
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
