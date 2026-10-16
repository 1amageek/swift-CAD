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

/// A complete cone-torus component for the case where the cone apex lies on
/// the torus.
///
/// The torus equation restricted to every cone generator has the apex root
/// factored out. The remaining cubic defines the geometric branches. Simple
/// zeros of its constant coefficient split the nodal branch at the apex, and
/// simple zeros of its discriminant delimit the generator-tangent loop.
public struct CertifiedConeTorusApexIntersectionCurve:
    Hashable,
    Sendable
{
    public enum ComponentKind: String, Hashable, Sendable {
        case apexNodeInterval
        case generatorTangencyInterval
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    struct ThirdOrderDifferentialGeometry {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
        let thirdDerivative: Vector3D
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

        func thirdDerivative(at angle: Double) -> Vector3D {
            radialU * sin(angle) + radialV * -cos(angle)
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

        func coefficients(at angle: Double, using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
            return [
                try cubicConstant.value(at: angle, using: &execution),
                try cubicLinear.value(at: angle, using: &execution),
                try cubicQuadratic.value(at: angle, using: &execution),
                1.0,
            ]
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
        let third: Double
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
            let first = lower * other.lower
            let second = lower * other.upper
            let third = upper * other.lower
            let fourth = upper * other.upper
            return Self(min(first, second, third, fourth), max(first, second, third, fourth))
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
        let fourthDerivativeMagnitude: Double

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
                ).nextUp,
                fourthDerivativeMagnitude: max(
                    fourthDerivativeMagnitude,
                    other.fourthDerivativeMagnitude
                ).nextUp
            )
        }
    }

    private enum SimpleRootSelection {
        case nearestToZero
        case lower
        case upper

        func select(from roots: [Double], using execution: inout OriginalQueryExecution) throws -> Double? {
            try execution.consumeWork(1)
            switch self {
            case .nearestToZero:
                return try roots.min { first, second in
                    try execution.consumeWork(1)
                    return abs(first) < abs(second)
                }
            case .lower:
                return try roots.min { first, second in
                    try execution.consumeWork(1)
                    return first < second
                }
            case .upper:
                return try roots.max { first, second in
                    try execution.consumeWork(1)
                    return first < second
                }
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

        init(cosine: [Double], sine: [Double], using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            let count = try max(cosine.count, sine.count, 1)
            try execution.retainStorage(count: count, stride: MemoryLayout<Double>.stride)
            self.cosine = cosine + (try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: count - cosine.count, using: &execution))
            try execution.retainStorage(count: count, stride: MemoryLayout<Double>.stride)
            self.sine = sine + (try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: count - sine.count, using: &execution))
            self.sine[0] = 0.0
            try trim(using: &execution)
        }

        static func constant(_ value: Double, using execution: inout OriginalQueryExecution) throws -> Self {
            try execution.consumeWork(1)
            return try Self(cosine: [value], sine: [0.0], using: &execution)
        }

        var degree: Int { cosine.count - 1 }

        func coefficientScale(using execution: inout OriginalQueryExecution) throws -> Double {
            var result = try 1.0
            for value in cosine { try execution.consumeWork(1); result = max(result, abs(value)) }
            for value in sine { try execution.consumeWork(1); result = max(result, abs(value)) }
            return try result
        }

        func value(at angle: Double, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            var result = try cosine[0]
            if degree > 0 {
                for harmonic in 1...degree {
                try execution.consumeWork(1)

                    result += cosine[harmonic] * cos(Double(harmonic) * angle)
                        + sine[harmonic] * sin(Double(harmonic) * angle)
                }
            }
            return try result
        }

        func firstDerivative(at angle: Double, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            guard degree > 0 else { return try 0.0 }
            var result = try 0.0
            for harmonic in 1...degree {
                try execution.consumeWork(1)

                let scale = try Double(harmonic)
                result = result - cosine[harmonic] * scale * sin(scale * angle)
                    + sine[harmonic] * scale * cos(scale * angle)
            }
            return try result
        }

        func secondDerivative(at angle: Double, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            return try derivative(at: angle, order: 2, using: &execution)
        }

        func derivative(at angle: Double, order: Int, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            guard order > 0, degree > 0 else {
                return try order == 0 ? value(at: angle, using: &execution) : 0.0
            }
            var result = try 0.0
            for harmonic in 1...degree {
                try execution.consumeWork(1)

                let frequency = try Double(harmonic)
                let scale = try pow(frequency, Double(order))
                let phase = try frequency * angle
                    + Double(order) * Double.pi * 0.5
                result += scale * (
                    cosine[harmonic] * cos(phase)
                        + sine[harmonic] * sin(phase)
                )
            }
            return try result
        }

        func derivativeMagnitudeUpperBound(order: Int, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            guard degree > 0 else { return try 0.0 }
            var result = try 0.0
            for harmonic in 1...degree {
                try execution.consumeWork(1)

                let scale = try pow(Double(harmonic), Double(order))
                result = (
                    result
                        + scale * hypot(
                            cosine[harmonic],
                            sine[harmonic]
                        )
                ).nextUp
            }
            return try result
        }

        func range(
            from lower: Double,
            to upper: Double,
            derivativeOrder: Int = 0
        , using execution: inout OriginalQueryExecution) throws -> ScalarRange {
            try execution.consumeWork(1)
            let middle = try lower + (upper - lower) * 0.5
            let midpoint = try derivative(
                at: middle,
                order: derivativeOrder
            , using: &execution)
            let radius = try (
                try derivativeMagnitudeUpperBound(
                    order: derivativeOrder + 1
                , using: &execution) * (upper - lower) * 0.5
            ).nextUp
            return try ScalarRange(
                midpoint - radius,
                midpoint + radius
            )
        }

        func adding(_ other: Self, using execution: inout OriginalQueryExecution) throws -> Self {
            try execution.consumeWork(1)
            let count = try max(cosine.count, other.cosine.count)
            var resultCosine = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: count, using: &execution)
            var resultSine = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: count, using: &execution)
            for index in 0..<count {
                try execution.consumeWork(1)

                resultCosine[index] = try coefficient(cosine, index, using: &execution)
                    + coefficient(other.cosine, index, using: &execution)
                resultSine[index] = try coefficient(sine, index, using: &execution)
                    + coefficient(other.sine, index, using: &execution)
            }
            return try Self(cosine: resultCosine, sine: resultSine, using: &execution)
        }

        func scaled(by value: Double, using execution: inout OriginalQueryExecution) throws -> Self {
            try execution.consumeWork(1)
            return try Self(
                cosine: CertifiedAnalyticCurveEvaluation.map(cosine, using: &execution) { element, _ in element * value },
                sine: CertifiedAnalyticCurveEvaluation.map(sine, using: &execution) { element, _ in element * value }
            , using: &execution)
        }

        func multiplied(by other: Self, using execution: inout OriginalQueryExecution) throws -> Self {
            try execution.consumeWork(1)
            let resultDegree = try degree + other.degree
            var resultCosine = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: resultDegree + 1, using: &execution)
            var resultSine = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: resultDegree + 1, using: &execution)
            for first in 0...degree {
                try execution.consumeWork(1)

                for second in 0...other.degree {
                try execution.consumeWork(1)

                    let firstCosine = try cosine[first]
                    let firstSine = try sine[first]
                    let secondCosine = try other.cosine[second]
                    let secondSine = try other.sine[second]
                    try addCosine(
                        first - second,
                        value: 0.5 * (
                            firstCosine * secondCosine
                                + firstSine * secondSine
                        ),
                        to: &resultCosine
                    , using: &execution)
                    try addCosine(
                        first + second,
                        value: 0.5 * (
                            firstCosine * secondCosine
                                - firstSine * secondSine
                        ),
                        to: &resultCosine
                    , using: &execution)
                    try addSine(
                        second + first,
                        value: 0.5 * (
                            firstCosine * secondSine
                                + firstSine * secondCosine
                        ),
                        to: &resultSine
                    , using: &execution)
                    try addSine(
                        second - first,
                        value: 0.5 * (
                            firstCosine * secondSine
                                - firstSine * secondCosine
                        ),
                        to: &resultSine
                    , using: &execution)
                }
            }
            return try Self(cosine: resultCosine, sine: resultSine, using: &execution)
        }

        func tangentHalfAngleCoefficients(using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            let targetDegree = try degree
            let denominator = try [1.0, 0.0, 1.0]
            let cosineBase = try [1.0, 0.0, -1.0]
            let sineBase = try [0.0, 2.0]
            try execution.retainStorage(count: targetDegree + 1, stride: MemoryLayout<[Double]>.stride)
            try execution.retainStorage(count: targetDegree + 1, stride: MemoryLayout<[Double]>.stride)
            var cosineNumerators = try [[1.0]]
            var sineNumerators = try [[0.0]]
            cosineNumerators.reserveCapacity(targetDegree + 1)
            sineNumerators.reserveCapacity(targetDegree + 1)
            if targetDegree > 0 {
                for _ in 1...targetDegree {
                try execution.consumeWork(1)

                    let previousCosine = try cosineNumerators.last ?? [1.0]
                    let previousSine = try sineNumerators.last ?? [0.0]
                    cosineNumerators.append(try subtract(
                        try multiply(previousCosine, cosineBase, using: &execution),
                        try multiply(previousSine, sineBase, using: &execution)
                    , using: &execution))
                    sineNumerators.append(try add(
                        try multiply(previousSine, cosineBase, using: &execution),
                        try multiply(previousCosine, sineBase, using: &execution)
                    , using: &execution))
                }
            }
            var result = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: targetDegree * 2 + 1, using: &execution)
            for harmonic in 0...targetDegree {
                try execution.consumeWork(1)

                let elevation = try polynomialPower(
                    denominator,
                    exponent: targetDegree - harmonic
                , using: &execution)
                result = try add(
                    result,
                    try CertifiedAnalyticCurveEvaluation.map(
                        multiply(cosineNumerators[harmonic], elevation, using: &execution),
                        using: &execution
                    ) { element, _ in element * cosine[harmonic] }
                , using: &execution)
                if harmonic > 0 {
                    result = try add(
                        result,
                        try CertifiedAnalyticCurveEvaluation.map(
                            multiply(sineNumerators[harmonic], elevation, using: &execution),
                            using: &execution
                        ) { element, _ in element * sine[harmonic] }
                    , using: &execution)
                }
            }
            return try result
        }

        private mutating func trim(using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            try execution.retainStorage(count: cosine.count, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: sine.count, stride: MemoryLayout<Double>.stride)
            while cosine.count > 1,
                  abs(cosine.last ?? 0.0) <= Double.ulpOfOne,
                  abs(sine.last ?? 0.0) <= Double.ulpOfOne {
                try execution.consumeWork(1)

                cosine.removeLast()
                sine.removeLast()
            }
        }

        private func coefficient(_ values: [Double], _ index: Int, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            return index < values.count ? values[index] : 0.0
        }

        private func addCosine(
            _ harmonic: Int,
            value: Double,
            to result: inout [Double]
        , using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            result[abs(harmonic)] += value
        }

        private func addSine(
            _ harmonic: Int,
            value: Double,
            to result: inout [Double]
        , using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            guard harmonic != 0 else { return }
            result[abs(harmonic)] += harmonic > 0 ? value : -value
        }

        private func add(_ first: [Double], _ second: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            let count = try max(first.count, second.count)
            return try CertifiedAnalyticCurveEvaluation.map(0..<count, using: &execution) { index, execution in
                try coefficient(first, index, using: &execution) + coefficient(second, index, using: &execution)
            }
        }

        private func subtract(_ first: [Double], _ second: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            let count = try max(first.count, second.count)
            return try CertifiedAnalyticCurveEvaluation.map(0..<count, using: &execution) { index, execution in
                try coefficient(first, index, using: &execution) - coefficient(second, index, using: &execution)
            }
        }

        private func multiply(_ first: [Double], _ second: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            var result = try CertifiedAnalyticCurveEvaluation.repeated(
                0.0, count: max(first.count + second.count - 1, 1), using: &execution
            )
            for firstIndex in first.indices {
                try execution.consumeWork(1)

                for secondIndex in second.indices {
                try execution.consumeWork(1)

                    result[firstIndex + secondIndex] +=
                        first[firstIndex] * second[secondIndex]
                }
            }
            return try result
        }

        private func polynomialPower(
            _ polynomial: [Double],
            exponent: Int
        , using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
            guard exponent > 0 else { return try [1.0] }
            var result = try [1.0]
            for _ in 0..<exponent {
                try execution.consumeWork(1)
 result = try multiply(result, polynomial, using: &execution) }
            return try result
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(coneSurface: coneSurface, torusSurface: torusSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        try validate(tolerance: tolerance, using: &execution)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedConeTorusApexIntersectionCurve] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifiedCurves(coneSurface: coneSurface, torusSurface: torusSurface, tolerance: tolerance, using: &execution)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [CertifiedConeTorusApexIntersectionCurve] {
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let apexAngles = try simpleAngles(
            of: configuration.cubicConstant,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard apexAngles.count == 2 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: Double(apexAngles.count),
                tolerance: tolerance,
                message: "A cone-torus apex node requires exactly two simple generator directions."
            )
        }
        try execution.retainStorage(count: 2, stride: MemoryLayout<(Double, Double)>.stride)
        var result = try CertifiedAnalyticCurveEvaluation.map([
            (apexAngles[0], apexAngles[1]),
            (apexAngles[1], apexAngles[0] + 2.0 * Double.pi),
        ], using: &execution) {element, execution in
            try CertifiedConeTorusApexIntersectionCurve(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                componentKind: .apexNodeInterval,
                lowerAngle: element.0,
                upperAngle: element.1,
                tolerance: tolerance
            , using: &execution)
        }
        var resultCapacity = result.count

        let tangencyAngles = try simpleAngles(
            of: configuration.cubicDiscriminant,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        for index in tangencyAngles.indices {
            try execution.consumeWork(1)
            let lower = tangencyAngles[index]
            let upper = index + 1 < tangencyAngles.count
                ? tangencyAngles[index + 1]
                : tangencyAngles[0] + 2.0 * Double.pi
            let middle = lower + (upper - lower) * 0.5
            let discriminant = (try configuration.cubicDiscriminant.value(at: middle, using: &execution))
            if discriminant > (try classificationTolerance(
                polynomial: configuration.cubicDiscriminant,
                tolerance: tolerance
            , using: &execution)) {
                try CertifiedAnalyticCurveEvaluation.append(try CertifiedConeTorusApexIntersectionCurve(
                    coneSurface: coneSurface,
                    torusSurface: torusSurface,
                    componentKind: .generatorTangencyInterval,
                    lowerAngle: lower,
                    upperAngle: upper,
                    tolerance: tolerance
                , using: &execution), to: &result, using: &execution, capacity: &resultCapacity)
            }
        }
        return result
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
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
        , using: &execution)
        let boundaryPolynomial = componentKind == .apexNodeInterval
            ? configuration.cubicConstant
            : configuration.cubicDiscriminant
        let boundaryTolerance = try Self.classificationTolerance(
            polynomial: boundaryPolynomial,
            tolerance: tolerance
        , using: &execution)
        let lowerResidual = abs((try boundaryPolynomial.value(at: lowerAngle, using: &execution)))
        let upperResidual = abs((try boundaryPolynomial.value(at: upperAngle, using: &execution)))
        let lowerSlope = abs((try boundaryPolynomial.firstDerivative(at: lowerAngle, using: &execution)))
        let upperSlope = abs((try boundaryPolynomial.firstDerivative(at: upperAngle, using: &execution)))
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
            guard (try configuration.cubicDiscriminant.value(at: middle, using: &execution))
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
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
    ,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        let geometry = try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative,
            secondDerivative: geometry.secondDerivative
        )
    }

    func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> ThirdOrderDifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try derivativesThroughThirdOrder(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ThirdOrderDifferentialGeometry {
        try execution.consumeWork(1)
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
        , using: &execution)
        let angle = try angleDifferential(at: boundedFraction, using: &execution)
        let slantDifferential: ScalarDifferential
        switch componentKind {
        case .apexNodeInterval:
            let slant = try apexNodeSlantValue(
                angle: angle.value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            slantDifferential = try regularSlantDifferential(
                slant: slant,
                angle: angle,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .generatorTangencyInterval:
            slantDifferential = try generatorSlantDifferential(
                angle: angle,
                fraction: boundedFraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }
        let slant = slantDifferential.value
        let direction = configuration.cone.direction(at: angle.value)
        let directionFirst = configuration.cone.firstDerivative(at: angle.value)
        let directionSecond = configuration.cone.secondDerivative(at: angle.value)
        let directionThird = configuration.cone.thirdDerivative(at: angle.value)
        let composedDirectionFirst = directionFirst * angle.first
        let composedDirectionSecond = directionSecond
                * (angle.first * angle.first)
            + directionFirst * angle.second
        let composedDirectionThird = directionThird
                * (angle.first * angle.first * angle.first)
            + directionSecond * (3.0 * angle.first * angle.second)
            + directionFirst * angle.third
        let position = configuration.cone.apex + direction * slant
        let firstDerivative = composedDirectionFirst * slant
            + direction * slantDifferential.first
        let secondDerivative = composedDirectionSecond * slant
            + composedDirectionFirst * (2.0 * slantDifferential.first)
            + direction * slantDifferential.second
        let thirdDerivative = composedDirectionThird * slant
            + composedDirectionSecond * (3.0 * slantDifferential.first)
            + composedDirectionFirst * (3.0 * slantDifferential.second)
            + direction * slantDifferential.third
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A cone-torus apex component has a singular spatial differential."
            )
        }
        guard thirdDerivative.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus apex third differential exceeded finite arithmetic."
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
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
        , using: &execution)
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }

    public func boundingBox(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
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
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        switch componentKind {
        case .apexNodeInterval:
            return try apexNodeSpatialDifferentialMagnitudeBounds(
                lowerFraction: lower,
                upperFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .generatorTangencyInterval:
            return try generatorTangencySpatialDifferentialMagnitudeBounds(
                lowerFraction: lower,
                upperFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }
    }



    private func apexNodeSpatialDifferentialMagnitudeBounds(
        lowerFraction: Double,
        upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let span = upperAngle - lowerAngle
        let angleLower = lowerAngle + span * lowerFraction
        let angleUpper = lowerAngle + span * upperFraction
        let root = try simpleMainRootBounds(
            lowerAngle: angleLower,
            upperAngle: angleUpper,
            selection: .nearestToZero,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
            slantThirdMagnitude: (
                root.thirdDerivativeMagnitude * span * span * span
            ).nextUp,
            angleFirstMagnitude: span.nextUp,
            angleSecondMagnitude: 0.0,
            angleThirdMagnitude: 0.0,
            cone: configuration.cone,
            tolerance: tolerance,
            label: "Cone-torus apex-node"
        , using: &execution)
    }



    private func generatorTangencySpatialDifferentialMagnitudeBounds(
        lowerFraction: Double,
        upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let span = upperAngle - lowerAngle
        let halfSpan = span * 0.5
        let correction = try generatorDiscriminantCorrection(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let companionSelection = correction.companionSelection
        let mainRoot = try simpleMainRootBounds(
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            selection: companionSelection,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let derivativeBounds = try Self.quadraticDiscriminantDerivativeBounds(
            root: mainRoot,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration
        , using: &execution)
        let requestedAngle = try requestedGeneratorAngleRange(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction
        , using: &execution)
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
            fourthDerivativeMagnitudeUpperBound:
                derivativeBounds[4],
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper, execution in
                let root = try simpleMainRootBounds(
                    lowerAngle: rangeLower,
                    upperAngle: rangeUpper,
                    selection: companionSelection,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
                let middle = rangeLower
                    + (rangeUpper - rangeLower) * 0.5
                let midpointRoot = try mainRootDifferential(
                    at: middle,
                    selection: companionSelection,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
                let midpointValue = try Self.quadraticDiscriminant(
                    angle: middle,
                    root: midpointRoot.value,
                    configuration: configuration
                , using: &execution)
                let cellDerivativeBounds =
                    try Self.quadraticDiscriminantDerivativeBounds(
                    root: root,
                    lowerAngle: rangeLower,
                    upperAngle: rangeUpper,
                    configuration: configuration
                , using: &execution)
                let midpointFirst =
                    try Self.quadraticDiscriminantFirstDerivative(
                        angle: middle,
                        root: midpointRoot,
                        configuration: configuration
                    , using: &execution)
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
        , using: &execution)
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
        let factorRootFifthLower = (
            factor.lower * factor.lower * factorRootLower
        ).nextDown
        let factorRootThird = (
            factor.third / (2.0 * factorRootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (
                        4.0 * factor.lower * factorRootLower
                    ).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * factorRootFifthLower).nextDown
        ).nextUp
        let phase = ScalarRange(
            2.0 * Double.pi * lowerFraction,
            2.0 * Double.pi * upperFraction
        )
        let sineMagnitude = try Self.trigonometricMagnitude(
            phase,
            sine: true
        , using: &execution)
        let cosineMagnitude = try Self.trigonometricMagnitude(
            phase,
            sine: false
        , using: &execution)
        let angleFirst = (
            span * Double.pi * sineMagnitude
        ).nextUp
        let angleSecond = (
            2.0 * span * Double.pi * Double.pi
                * cosineMagnitude
        ).nextUp
        let angleThird = (
            4.0 * span * pow(Double.pi, 3.0)
                * sineMagnitude
        ).nextUp
        let composedFactorFirst = (
            factorRootFirst * angleFirst
        ).nextUp
        let composedFactorSecond = (
            factorRootSecond * angleFirst * angleFirst
                + factorRootFirst * angleSecond
        ).nextUp
        let composedFactorThird = (
            factorRootThird * angleFirst * angleFirst * angleFirst
                + 3.0 * factorRootSecond * angleFirst * angleSecond
                + factorRootFirst * angleThird
        ).nextUp
        let distance = (halfSpan * 0.5 * sineMagnitude).nextUp
        let distanceFirst = (
            halfSpan * Double.pi * cosineMagnitude
        ).nextUp
        let distanceSecond = (
            2.0 * halfSpan * Double.pi * Double.pi
                * sineMagnitude
        ).nextUp
        let distanceThird = (
            4.0 * halfSpan * pow(Double.pi, 3.0)
                * cosineMagnitude
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
        let splitThird = (
            distanceThird * factorRootUpper
                + 3.0 * distanceSecond * composedFactorFirst
                + 3.0 * distanceFirst * composedFactorSecond
                + distance * composedFactorThird
        ).nextUp
        let quadratic = configuration.cubicQuadratic
        let quadraticMagnitude = (try quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper
        , using: &execution)).maximumAbsoluteValue
        let quadraticFirst = (try quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper,
            derivativeOrder: 1
        , using: &execution)).maximumAbsoluteValue
        let quadraticSecond = (try quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper,
            derivativeOrder: 2
        , using: &execution)).maximumAbsoluteValue
        let quadraticThird = (try quadratic.range(
            from: requestedAngle.lower,
            to: requestedAngle.upper,
            derivativeOrder: 3
        , using: &execution)).maximumAbsoluteValue
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
        let baseThird = (
            0.5 * (
                (
                    quadraticThird
                        + mainRoot.thirdDerivativeMagnitude
                ) * angleFirst * angleFirst * angleFirst
                    + 3.0 * (
                        quadraticSecond
                            + mainRoot.secondDerivativeMagnitude
                    ) * angleFirst * angleSecond
                    + (
                        quadraticFirst
                            + mainRoot.firstDerivativeMagnitude
                    ) * angleThird
            )
        ).nextUp
        return try Self.spatialBounds(
            slantMagnitude: (baseMagnitude + splitMagnitude).nextUp,
            slantFirstMagnitude: (baseFirst + splitFirst).nextUp,
            slantSecondMagnitude: (baseSecond + splitSecond).nextUp,
            slantThirdMagnitude: (baseThird + splitThird).nextUp,
            angleFirstMagnitude: angleFirst,
            angleSecondMagnitude: angleSecond,
            angleThirdMagnitude: angleThird,
            cone: configuration.cone,
            tolerance: tolerance,
            label: "Cone-torus generator-fold"
        , using: &execution)
    }



    private func requestedGeneratorAngleRange(
        lowerFraction: Double,
        upperFraction: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let span = upperAngle - lowerAngle
        func angle(_ fraction: Double) -> Double {
            lowerAngle + span * 0.5
                * (1.0 - cos(2.0 * Double.pi * fraction))
        }
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var values = [angle(lowerFraction), angle(upperFraction)]
        var valuesCapacity = values.count
        if lowerFraction < 0.5, upperFraction > 0.5 {
            try CertifiedAnalyticCurveEvaluation.append(upperAngle, to: &values, using: &execution, capacity: &valuesCapacity)
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
        slantThirdMagnitude: Double,
        angleFirstMagnitude: Double,
        angleSecondMagnitude: Double,
        angleThirdMagnitude: Double,
        cone: Cone,
        tolerance: ModelingTolerance,
        label: String
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
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
        let directionSecondMagnitude = (
            angularMagnitude * (
                angleFirstMagnitude * angleFirstMagnitude
                    + angleSecondMagnitude
            )
        ).nextUp
        let directionThirdMagnitude = (
            angularMagnitude * (
                angleFirstMagnitude * angleFirstMagnitude
                    * angleFirstMagnitude
                    + 3.0 * angleFirstMagnitude
                        * angleSecondMagnitude
                    + angleThirdMagnitude
            )
        ).nextUp
        let third = (
            directionThirdMagnitude * slantMagnitude
                + 3.0 * directionSecondMagnitude
                    * slantFirstMagnitude
                + 3.0 * angularMagnitude * angleFirstMagnitude
                    * slantSecondMagnitude
                + slantThirdMagnitude
        ).nextUp
        guard first.isFinite, second.isFinite, third.isFinite,
              first > 0.0, second > 0.0, third > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "\(label) spatial bounds exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }



    private func simpleMainRootBounds(
        lowerAngle: Double,
        upperAngle: Double,
        selection: SimpleRootSelection,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SimpleRootBounds {
        try execution.consumeWork(1)
        struct Cell {
            let lower: Double
            let upper: Double
            let depth: Int
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
        var cells = [Cell(
            lower: lowerAngle,
            upper: upperAngle,
            depth: 0
        )]
        var cellsCapacity = cells.count
        var result: SimpleRootBounds?
        var processed = 0
        while let cell = cells.popLast() {
            try execution.admitGeometricDepth(cell.depth)
            try execution.consumeCells()
            try execution.consumeWork(1)
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
            , using: &execution) {
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
            try CertifiedAnalyticCurveEvaluation.append(Cell(
                lower: middle,
                upper: cell.upper,
                depth: cell.depth + 1
            ), to: &cells, using: &execution, capacity: &cellsCapacity)
            try CertifiedAnalyticCurveEvaluation.append(Cell(
                lower: cell.lower,
                upper: middle,
                depth: cell.depth + 1
            ), to: &cells, using: &execution, capacity: &cellsCapacity)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> SimpleRootBounds? {
        try execution.consumeWork(1)
        let middle = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let coefficients = (try configuration.coefficients(at: middle, using: &execution))
        let roots = try Self.reducedCubicRoots(
            coefficients: coefficients,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard let root = (try selection.select(from: roots, using: &execution)) else {
            return nil
        }
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let derivativeRoots = try Self.reducedCubicRoots(
            coefficients: [
                coefficients[1],
                2.0 * coefficients[2],
                3.0,
            ],
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let criticalDistance = try CertifiedAnalyticCurveEvaluation.filter(CertifiedAnalyticCurveEvaluation.map(derivativeRoots, using: &execution) {element, execution in
            abs(element - root)
        }, using: &execution) {element, execution in
            element > tolerance.distance
        }.min()
        let radius = (
            (criticalDistance ?? configuration.characteristicLength)
                * 0.375
        ).nextDown
        guard radius > tolerance.distance else { return nil }
        let slant = ScalarRange(root - radius, root + radius)
        let lowerBoundary = try Self.reducedCubicRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: .constant(slant.lower),
            configuration: configuration
        , using: &execution)
        let upperBoundary = try Self.reducedCubicRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: .constant(slant.upper),
            configuration: configuration
        , using: &execution)
        let hasOppositeBoundarySigns = (
            lowerBoundary.upper < 0.0 && upperBoundary.lower > 0.0
        ) || (
            lowerBoundary.lower > 0.0 && upperBoundary.upper < 0.0
        )
        guard hasOppositeBoundarySigns else { return nil }
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let c3Range = (try c3.range(from: lowerAngle, to: upperAngle, using: &execution))
        var rootRange = slant
        var slantDerivative = try Self.reducedCubicSlantDerivativeRange(
            angleLower: lowerAngle,
            angleUpper: upperAngle,
            slant: rootRange,
            configuration: configuration
        , using: &execution)
        var denominator = slantDerivative.minimumAbsoluteValue
        guard denominator > (try Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)) else {
            return nil
        }
        let c1First = (try c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        , using: &execution))
        let c2First = (try c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        , using: &execution))
        let c3First = (try c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 1
        , using: &execution))
        var angleDerivative = c1First
            .adding(c2First.multiplied(by: rootRange))
            .adding(c3First.multiplied(by: rootRange.squared()))
        var first = (
            angleDerivative.maximumAbsoluteValue / denominator
        ).nextUp
        let halfWidth = (upperAngle - lowerAngle) * 0.5
        for _ in 0..<3 {
            try execution.consumeWork(1)
            let valueVariation = (first * halfWidth).nextUp
            rootRange = ScalarRange(
                max(slant.lower, root - valueVariation),
                min(slant.upper, root + valueVariation)
            )
            slantDerivative = try Self.reducedCubicSlantDerivativeRange(
                angleLower: lowerAngle,
                angleUpper: upperAngle,
                slant: rootRange,
                configuration: configuration
            , using: &execution)
            denominator = slantDerivative.minimumAbsoluteValue
            guard denominator > (try Self.derivativeThreshold(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)) else {
                return nil
            }
            angleDerivative = c1First
                .adding(c2First.multiplied(by: rootRange))
                .adding(c3First.multiplied(by: rootRange.squared()))
            first = (
                angleDerivative.maximumAbsoluteValue / denominator
            ).nextUp
        }
        let c1Second = (try c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        , using: &execution))
        let c2Second = (try c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        , using: &execution))
        let c3Second = (try c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 2
        , using: &execution))
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
        let c1Third = (try c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        , using: &execution))
        let c2Third = (try c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        , using: &execution))
        let c3Third = (try c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 3
        , using: &execution))
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
        let c1Fourth = (try c1.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 4
        , using: &execution))
        let c2Fourth = (try c2.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 4
        , using: &execution))
        let c3Fourth = (try c3.range(
            from: lowerAngle,
            to: upperAngle,
            derivativeOrder: 4
        , using: &execution))
        let angleAngleAngleAngle = c1Fourth
            .adding(c2Fourth.multiplied(by: rootRange))
            .adding(c3Fourth.multiplied(by: rootRange.squared()))
        let angleAngleAngleSlant = c2Third
            .adding(c3Third.multiplied(by: rootRange).scaled(by: 2.0))
        let angleAngleSlantSlant = c3Second.scaled(by: 2.0)
        let fourth = (
            (
                angleAngleAngleAngle.maximumAbsoluteValue
                    + 4.0 * angleAngleAngleSlant.maximumAbsoluteValue
                        * first
                    + 6.0 * angleAngleSlantSlant.maximumAbsoluteValue
                        * first * first
                    + 6.0 * second * (
                        angleAngleSlant.maximumAbsoluteValue
                            + 2.0 * angleSlantSlant.maximumAbsoluteValue
                                * first
                            + 6.0 * first * first
                    )
                    + 3.0 * slantSlant.maximumAbsoluteValue
                        * second * second
                    + 4.0 * third * (
                        angleSlant.maximumAbsoluteValue
                            + slantSlant.maximumAbsoluteValue * first
                    )
            ) / denominator
        ).nextUp
        guard first.isFinite,
              second.isFinite,
              third.isFinite,
              fourth.isFinite else {
            return nil
        }
        let valueVariation = (first * halfWidth).nextUp
        return SimpleRootBounds(
            lowerValue: (root - valueVariation).nextDown,
            upperValue: (root + valueVariation).nextUp,
            firstDerivativeMagnitude: first,
            secondDerivativeMagnitude: second,
            thirdDerivativeMagnitude: third,
            fourthDerivativeMagnitude: fourth
        )
    }



    private static func reducedCubicRoots(
        coefficients: [Double],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
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
        return try solver.realRoots(coefficients: coefficients, using: &execution)
    }



    private static func generatorCompanionRootSelection(
        lowerAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SimpleRootSelection {
        try execution.consumeWork(1)
        let coefficients = (try configuration.coefficients(at: lowerAngle, using: &execution))
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let derivativeRoots = try reducedCubicRoots(
            coefficients: [
                coefficients[1],
                2.0 * coefficients[2],
                3.0,
            ],
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard let fold = try derivativeRoots.min(by: {
            abs(try polynomialValue(coefficients, at: $0, using: &execution))
                < abs(try polynomialValue(coefficients, at: $1, using: &execution))
        }) else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus generator fold lost its repeated-root direction."
            )
        }
        let companion = -coefficients[2] - 2.0 * fold
        guard abs(companion - fold) > (try derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)) else {
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
    ,
        using execution: inout OriginalQueryExecution) throws -> GeneratorDiscriminantCorrection {
        try execution.consumeWork(1)
        let selection = try Self.generatorCompanionRootSelection(
            lowerAngle: lowerAngle,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let lowerRoot = try mainRootDifferential(
            at: lowerAngle,
            selection: selection,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let upperRoot = try mainRootDifferential(
            at: upperAngle,
            selection: selection,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let lowerValue = try Self.quadraticDiscriminant(
            angle: lowerAngle,
            root: lowerRoot.value,
            configuration: configuration
        , using: &execution)
        let upperValue = try Self.quadraticDiscriminant(
            angle: upperAngle,
            root: upperRoot.value,
            configuration: configuration
        , using: &execution)
        let span = upperAngle - lowerAngle
        return GeneratorDiscriminantCorrection(
            companionSelection: selection,
            lowerValue: lowerValue,
            upperValue: upperValue,
            lowerDerivative: try Self.quadraticDiscriminantFirstDerivative(
                angle: lowerAngle,
                root: lowerRoot,
                configuration: configuration
            , using: &execution),
            upperDerivative: try Self.quadraticDiscriminantFirstDerivative(
                angle: upperAngle,
                root: upperRoot,
                configuration: configuration
            , using: &execution),
            slope: (upperValue - lowerValue) / span
        )
    }



    private static func reducedCubicRange(
        angleLower: Double,
        angleUpper: Double,
        slant: ScalarRange,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarRange {
        try execution.consumeWork(1)
        return (try configuration.cubicConstant.range(
            from: angleLower,
            to: angleUpper
        , using: &execution)).adding(
            (try configuration.cubicLinear.range(
                from: angleLower,
                to: angleUpper
            , using: &execution)).multiplied(by: slant)
        ).adding(
            (try configuration.cubicQuadratic.range(
                from: angleLower,
                to: angleUpper
            , using: &execution)).multiplied(by: slant.squared())
        ).adding(
            slant.squared().multiplied(by: slant)
        )
    }



    private static func reducedCubicSlantDerivativeRange(
        angleLower: Double,
        angleUpper: Double,
        slant: ScalarRange,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarRange {
        try execution.consumeWork(1)
        let middle = angleLower + (angleUpper - angleLower) * 0.5
        let c2 = (try configuration.cubicLinear.value(at: middle, using: &execution))
        let c3 = (try configuration.cubicQuadratic.value(at: middle, using: &execution))
        func value(at slant: Double) -> Double {
            c2 + 2.0 * c3 * slant + 3.0 * slant * slant
        }
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var fixedAngleValues = [
            value(at: slant.lower),
            value(at: slant.upper),
        ]
        var fixedAngleValuesCapacity = fixedAngleValues.count
        let vertex = -c3 / 3.0
        if vertex > slant.lower, vertex < slant.upper {
            try CertifiedAnalyticCurveEvaluation.append(value(at: vertex), to: &fixedAngleValues, using: &execution, capacity: &fixedAngleValuesCapacity)
        }
        let c2Range = (try configuration.cubicLinear.range(
            from: angleLower,
            to: angleUpper
        , using: &execution))
        let c3Range = (try configuration.cubicQuadratic.range(
            from: angleLower,
            to: angleUpper
        , using: &execution))
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let coefficients = (try configuration.coefficients(at: angle, using: &execution))
        let roots = try Self.reducedCubicRoots(
            coefficients: coefficients,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard let root = (try selection.select(from: roots, using: &execution)) else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus quadratic factor lost its simple main root."
            )
        }
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let denominator = (try c2.value(at: angle, using: &execution))
            + 2.0 * (try c3.value(at: angle, using: &execution)) * root
            + 3.0 * root * root
        guard abs(denominator) > (try Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)) else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A cone-torus quadratic factor lost main-root simplicity."
            )
        }
        let angleDerivative = (try c1.firstDerivative(at: angle, using: &execution))
            + (try c2.firstDerivative(at: angle, using: &execution)) * root
            + (try c3.firstDerivative(at: angle, using: &execution)) * root * root
        let first = -angleDerivative / denominator
        let angleAngle = (try c1.secondDerivative(at: angle, using: &execution))
            + (try c2.secondDerivative(at: angle, using: &execution)) * root
            + (try c3.secondDerivative(at: angle, using: &execution)) * root * root
        let angleSlant = (try c2.firstDerivative(at: angle, using: &execution))
            + 2.0 * (try c3.firstDerivative(at: angle, using: &execution)) * root
        let slantSlant = 2.0 * (try c3.value(at: angle, using: &execution)) + 6.0 * root
        let second = -(
            angleAngle
                + 2.0 * angleSlant * first
                + slantSlant * first * first
        ) / denominator
            return ScalarDifferential(
                value: root,
                first: first,
                second: second,
                third: -(
                    (try c1.derivative(at: angle, order: 3, using: &execution))
                        + (try c2.derivative(at: angle, order: 3, using: &execution)) * root
                        + (try c3.derivative(at: angle, order: 3, using: &execution)) * root * root
                        + 3.0 * (
                            (try c2.secondDerivative(at: angle, using: &execution))
                                + 2.0 * (try c3.secondDerivative(at: angle, using: &execution)) * root
                        ) * first
                        + 6.0 * (try c3.firstDerivative(at: angle, using: &execution))
                            * first * first
                        + 6.0 * first * first * first
                        + 3.0 * (
                            angleSlant + slantSlant * first
                        ) * second
                ) / denominator
            )
    }



    private static func quadraticDiscriminant(
        angle: Double,
        root: Double,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let quadratic = (try configuration.cubicQuadratic.value(at: angle, using: &execution))
        let linear = (try configuration.cubicLinear.value(at: angle, using: &execution))
        return quadratic * quadratic
            - 2.0 * quadratic * root
            - 3.0 * root * root
            - 4.0 * linear
    }



    private static func quadraticDiscriminantFirstDerivative(
        angle: Double,
        root: ScalarDifferential,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let quadratic = (try configuration.cubicQuadratic.value(at: angle, using: &execution))
        let quadraticFirst = (try configuration.cubicQuadratic
            .firstDerivative(at: angle, using: &execution))
        return 2.0 * quadratic * quadraticFirst
            - 2.0 * (
                quadraticFirst * root.value
                    + quadratic * root.first
            )
            - 6.0 * root.value * root.first
            - 4.0 * (try configuration.cubicLinear
                .firstDerivative(at: angle, using: &execution))
    }



    private static func quadraticDiscriminantSecondDerivative(
        angle: Double,
        root: ScalarDifferential,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let quadratic = (try configuration.cubicQuadratic.value(at: angle, using: &execution))
        let quadraticFirst = (try configuration.cubicQuadratic
            .firstDerivative(at: angle, using: &execution))
        let quadraticSecond = (try configuration.cubicQuadratic
            .secondDerivative(at: angle, using: &execution))
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
            - 4.0 * (try configuration.cubicLinear
                .secondDerivative(at: angle, using: &execution))
    }



    private static func quadraticDiscriminantThirdDerivative(
        angle: Double,
        root: ScalarDifferential,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let quadratic = configuration.cubicQuadratic
        let linear = configuration.cubicLinear
        let value = (try quadratic.value(at: angle, using: &execution))
        let first = (try quadratic.firstDerivative(at: angle, using: &execution))
        let second = (try quadratic.secondDerivative(at: angle, using: &execution))
        let third = (try quadratic.derivative(at: angle, order: 3, using: &execution))
        return 2.0 * (3.0 * first * second + value * third)
            - 2.0 * (
                third * root.value
                    + 3.0 * second * root.first
                    + 3.0 * first * root.second
                    + value * root.third
            )
            - 6.0 * (
                3.0 * root.first * root.second
                    + root.value * root.third
            )
            - 4.0 * (try linear.derivative(at: angle, order: 3, using: &execution))
    }



    private static func quadraticDiscriminantDerivativeBounds(
        root: SimpleRootBounds,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let quadratic = try CertifiedAnalyticCurveEvaluation.map((0...4), using: &execution) {element, execution in
            (try configuration.cubicQuadratic.range(
                from: lowerAngle,
                to: upperAngle,
                derivativeOrder: element
            , using: &execution)).maximumAbsoluteValue
        }
        let linear = try CertifiedAnalyticCurveEvaluation.map((0...4), using: &execution) {element, execution in
            (try configuration.cubicLinear.range(
                from: lowerAngle,
                to: upperAngle,
                derivativeOrder: element
            , using: &execution)).maximumAbsoluteValue
        }
        try execution.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
        let rootDerivatives = [
            max(abs(root.lowerValue), abs(root.upperValue)).nextUp,
            root.firstDerivativeMagnitude,
            root.secondDerivativeMagnitude,
            root.thirdDerivativeMagnitude,
            root.fourthDerivativeMagnitude,
        ]
        var result = try CertifiedAnalyticCurveEvaluation.repeated(0.0, count: 5, using: &execution)
        for order in 0...4 {
            try execution.consumeWork(1)
            result[order] = (
                try Self.derivativeProductMagnitude(
                    quadratic,
                    quadratic,
                    order: order
                , using: &execution)
                    + 2.0 * (try Self.derivativeProductMagnitude(
                        quadratic,
                        rootDerivatives,
                        order: order
                    , using: &execution))
                    + 3.0 * (try Self.derivativeProductMagnitude(
                        rootDerivatives,
                        rootDerivatives,
                        order: order
                    , using: &execution))
                    + 4.0 * linear[order]
            ).nextUp
        }
        return result
    }



    private static func derivativeProductMagnitude(
        _ first: [Double],
        _ second: [Double],
        order: Int
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var result = 0.0
        for index in 0...order {
            try execution.consumeWork(1)
            result = (
                result
                    + (try binomial(order, index, using: &execution))
                        * first[index] * second[order - index]
            ).nextUp
        }
        return result
    }



    private static func binomial(_ order: Int, _ index: Int,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard index > 0, index < order else { return 1.0 }
        let selected = min(index, order - index)
        var result = 1.0
        for step in 1...selected {
            try execution.consumeWork(1)
            result *= Double(order - selected + step) / Double(step)
        }
        return result.nextUp
    }



    private static func trigonometricMagnitude(
        _ range: ScalarRange,
        sine: Bool
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
            try execution.consumeWork(1)
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



    private func angleDifferential(at fraction: Double,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let span = upperAngle - lowerAngle
        switch componentKind {
        case .apexNodeInterval:
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0,
                third: 0.0
            )
        case .generatorTangencyInterval:
            let phase = 2.0 * Double.pi * fraction
            let halfSpan = span * 0.5
            return ScalarDifferential(
                value: lowerAngle + halfSpan * (1.0 - cos(phase)),
                first: halfSpan * 2.0 * Double.pi * sin(phase),
                second: halfSpan * 4.0 * Double.pi * Double.pi * cos(phase),
                third: -halfSpan * 8.0 * pow(Double.pi, 3.0) * sin(phase)
            )
        }
    }



    private func apexNodeSlantValue(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let coefficients = (try configuration.coefficients(at: angle, using: &execution))
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
        let roots = try solver.realRoots(coefficients: coefficients, using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let correction = try generatorDiscriminantCorrection(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let companion = try mainRootDifferential(
            at: angle.value,
            selection: correction.companionSelection,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let quadratic = configuration.cubicQuadratic
        let quadraticValue = (try quadratic.value(at: angle.value, using: &execution))
        let quadraticFirst = (try quadratic.firstDerivative(at: angle.value, using: &execution))
        let quadraticSecond = (try quadratic.secondDerivative(at: angle.value, using: &execution))
        let quadraticThird = (try quadratic.derivative(
            at: angle.value,
            order: 3
        , using: &execution))
        let baseValue = -0.5 * (quadraticValue + companion.value)
        let baseAngleFirst = -0.5 * (
            quadraticFirst + companion.first
        )
        let baseAngleSecond = -0.5 * (
            quadraticSecond + companion.second
        )
        let baseAngleThird = -0.5 * (
            quadraticThird + companion.third
        )
        let baseFirst = baseAngleFirst * angle.first
        let baseSecond = baseAngleSecond * angle.first * angle.first
            + baseAngleFirst * angle.second
        let baseThird = baseAngleThird
                * angle.first * angle.first * angle.first
            + 3.0 * baseAngleSecond * angle.first * angle.second
            + baseAngleFirst * angle.third
        let rawDiscriminant = try Self.quadraticDiscriminant(
            angle: angle.value,
            root: companion.value,
            configuration: configuration
        , using: &execution)
        let rawFirst = try Self.quadraticDiscriminantFirstDerivative(
            angle: angle.value,
            root: companion,
            configuration: configuration
        , using: &execution)
        let correctedValue = rawDiscriminant
            - correction.lowerValue
            - correction.slope * (angle.value - lowerAngle)
        let correctedAngleFirst = rawFirst - correction.slope
        let correctedAngleSecond =
            try Self.quadraticDiscriminantSecondDerivative(
                angle: angle.value,
                root: companion,
                configuration: configuration
            , using: &execution)
        let correctedAngleThird =
            try Self.quadraticDiscriminantThirdDerivative(
                angle: angle.value,
                root: companion,
                configuration: configuration
            , using: &execution)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
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
            , using: &execution)
            let endpointSecond =
                try Self.quadraticDiscriminantSecondDerivative(
                    angle: endpointAngle,
                    root: endpointRoot,
                    configuration: configuration
                , using: &execution)
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
                    + 6.0 * splitCubic * joinOffset,
                third: baseThird + 6.0 * splitCubic
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
        let discriminantThird = correctedAngleThird
                * angle.first * angle.first * angle.first
            + 3.0 * correctedAngleSecond * angle.first * angle.second
            + correctedAngleFirst * angle.third
        let branchSign = fraction <= 0.5 ? -1.0 : 1.0
        let splitValue = branchSign * 0.5 * root
        let splitFirst = branchSign * discriminantFirst / (4.0 * root)
        let splitSecond = branchSign * (
            discriminantSecond / (4.0 * root)
                - discriminantFirst * discriminantFirst
                    / (8.0 * root * root * root)
        )
        let splitThird = branchSign * (
            discriminantThird / (4.0 * root)
                - 3.0 * discriminantFirst * discriminantSecond
                    / (8.0 * root * root * root)
                + 3.0 * discriminantFirst * discriminantFirst
                    * discriminantFirst / (16.0 * pow(root, 5.0))
        )
        return ScalarDifferential(
            value: baseValue + splitValue,
            first: baseFirst + splitFirst,
            second: baseSecond + splitSecond,
            third: baseThird + splitThird
        )
    }



    private func regularSlantDifferential(
        slant: Double,
        angle: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let c1 = configuration.cubicConstant
        let c2 = configuration.cubicLinear
        let c3 = configuration.cubicQuadratic
        let firstAngle = (try c1.firstDerivative(at: angle.value, using: &execution))
            + (try c2.firstDerivative(at: angle.value, using: &execution)) * slant
            + (try c3.firstDerivative(at: angle.value, using: &execution)) * slant * slant
        let secondAngle = (try c1.secondDerivative(at: angle.value, using: &execution))
            + (try c2.secondDerivative(at: angle.value, using: &execution)) * slant
            + (try c3.secondDerivative(at: angle.value, using: &execution)) * slant * slant
        let thirdAngle = (try c1.derivative(at: angle.value, order: 3, using: &execution))
            + (try c2.derivative(at: angle.value, order: 3, using: &execution)) * slant
            + (try c3.derivative(at: angle.value, order: 3, using: &execution)) * slant * slant
        let slantDerivative = (try c2.value(at: angle.value, using: &execution))
            + 2.0 * (try c3.value(at: angle.value, using: &execution)) * slant
            + 3.0 * slant * slant
        let mixed = (try c2.firstDerivative(at: angle.value, using: &execution))
            + 2.0 * (try c3.firstDerivative(at: angle.value, using: &execution)) * slant
        let secondSlant = 2.0 * (try c3.value(at: angle.value, using: &execution)) + 6.0 * slant
        let secondAngleSlant = (try c2.secondDerivative(at: angle.value, using: &execution))
            + 2.0 * (try c3.secondDerivative(at: angle.value, using: &execution)) * slant
        let angleSecondSlant = 2.0 * (try c3.firstDerivative(at: angle.value, using: &execution))
        let threshold = try Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
        let slantAngleThird = -(
            thirdAngle
                + 3.0 * secondAngleSlant * slantAngleFirst
                + 3.0 * angleSecondSlant
                    * slantAngleFirst * slantAngleFirst
                + 6.0 * slantAngleFirst * slantAngleFirst
                    * slantAngleFirst
                + 3.0 * (
                    mixed + secondSlant * slantAngleFirst
                ) * slantAngleSecond
        ) / slantDerivative
        return ScalarDifferential(
            value: slant,
            first: slantAngleFirst * angle.first,
            second: slantAngleSecond * angle.first * angle.first
                + slantAngleFirst * angle.second,
            third: slantAngleThird
                    * angle.first * angle.first * angle.first
                + 3.0 * slantAngleSecond * angle.first * angle.second
                + slantAngleFirst * angle.third
        )
    }



    private static func makeConfiguration(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.consumeWork(1)
        try coneSurface.validate(tolerance: tolerance, using: &execution)
        try torusSurface.validate(tolerance: tolerance, using: &execution)
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
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        let pointDirection = try TrigonometricPolynomial(
            cosine: [
                offset.dot(cone.centerDirection),
                offset.dot(cone.radialU),
            ],
            sine: [0.0, offset.dot(cone.radialV)]
        , using: &execution)
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        let axialDirection = try TrigonometricPolynomial(
            cosine: [
                torusAxis.dot(cone.centerDirection),
                torusAxis.dot(cone.radialU),
            ],
            sine: [0.0, torusAxis.dot(cone.radialV)]
        , using: &execution)
        let q0 = offset.dot(offset)
            + sourceTorus.majorRadius * sourceTorus.majorRadius
            - sourceTorus.minorRadius * sourceTorus.minorRadius
        let majorFactor = 4.0 * sourceTorus.majorRadius
            * sourceTorus.majorRadius
        let cubicConstant = try pointDirection.scaled(by: 4.0 * q0, using: &execution)
            .adding(
                pointDirection.adding(
                    axialDirection.scaled(by: -axialOffset, using: &execution)
                , using: &execution).scaled(by: -2.0 * majorFactor, using: &execution)
            , using: &execution)
        let cubicLinear = try pointDirection.multiplied(by: pointDirection, using: &execution)
            .scaled(by: 4.0, using: &execution)
            .adding(.constant(2.0 * q0 - majorFactor, using: &execution), using: &execution)
            .adding(
                axialDirection.multiplied(by: axialDirection, using: &execution)
                    .scaled(by: majorFactor, using: &execution)
            , using: &execution)
        let cubicQuadratic = try pointDirection.scaled(by: 4.0, using: &execution)
        let discriminant = try cubicQuadratic
            .multiplied(by: cubicLinear, using: &execution)
            .multiplied(by: cubicConstant, using: &execution)
            .scaled(by: 18.0, using: &execution)
            .adding(
                cubicQuadratic.multiplied(by: cubicQuadratic, using: &execution)
                    .multiplied(by: cubicLinear, using: &execution)
                    .multiplied(by: cubicLinear, using: &execution)
            , using: &execution)
            .adding(
                cubicQuadratic.multiplied(by: cubicQuadratic, using: &execution)
                    .multiplied(by: cubicQuadratic, using: &execution)
                    .multiplied(by: cubicConstant, using: &execution)
                    .scaled(by: -4.0, using: &execution)
            , using: &execution)
            .adding(
                cubicLinear.multiplied(by: cubicLinear, using: &execution)
                    .multiplied(by: cubicLinear, using: &execution)
                    .scaled(by: -4.0, using: &execution)
            , using: &execution)
            .adding(
                cubicConstant.multiplied(by: cubicConstant, using: &execution)
                    .scaled(by: -27.0, using: &execution)
            , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 1.0e-3, Double.ulpOfOne * 512.0),
            coefficientTolerance: Double.ulpOfOne * 1_024.0,
            maximumRefinementIterations: 256,
            tolerance: tolerance
        )
        var angles = try CertifiedAnalyticCurveEvaluation.map(solver.roots(
            coefficients: (try polynomial.tangentHalfAngleCoefficients(using: &execution))
        , using: &execution), using: &execution) {element, execution in
            try normalizedAngle(2.0 * atan(element.value), using: &execution)
        }
        var anglesCapacity = angles.count
        let threshold = try classificationTolerance(
            polynomial: polynomial,
            tolerance: tolerance
        , using: &execution)
        if abs((try polynomial.value(at: Double.pi, using: &execution))) <= threshold * 8.0 {
            try CertifiedAnalyticCurveEvaluation.append(Double.pi, to: &angles, using: &execution, capacity: &anglesCapacity)
        }
        angles = try CertifiedAnalyticCurveEvaluation.sorted(angles, using: &execution)
        var unique: [Double] = []
        var uniqueCapacity = unique.count
        for angle in angles {
            try execution.consumeWork(1)
            guard abs((try polynomial.value(at: angle, using: &execution))) <= threshold * 32.0,
                  abs((try polynomial.firstDerivative(at: angle, using: &execution))) > threshold else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs((try polynomial.firstDerivative(at: angle, using: &execution))),
                    tolerance: tolerance,
                    message: "A cone-torus apex classification boundary is not a simple root."
                )
            }
            if let last = unique.last,
               try angularDistance(last, angle, using: &execution) <= tolerance.angle {
                continue
            }
            try CertifiedAnalyticCurveEvaluation.append(angle, to: &unique, using: &execution, capacity: &uniqueCapacity)
        }
        return unique
    }



    private static func classificationTolerance(
        polynomial: TrigonometricPolynomial,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
            (try polynomial.coefficientScale(using: &execution)) * Double.ulpOfOne * 65_536.0,
            (try polynomial.coefficientScale(using: &execution)) * tolerance.relative * 1.0e-3
        )
    }



    private static func derivativeThreshold(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var result = 0.0
        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            result = result * value + coefficient
        }
        return result
    }



    private static func normalizedAngle(_ angle: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: period)
        return value < 0.0 ? value + period : value
    }



    private static func angularDistance(_ first: Double, _ second: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
extension CertifiedConeTorusApexIntersectionCurve: Codable {}
extension CertifiedConeTorusApexIntersectionCurve.ComponentKind: Codable {}
#endif
