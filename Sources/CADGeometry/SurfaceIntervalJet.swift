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

package struct SurfaceIntervalJet: Sendable {
    package let value: OutwardScalarInterval
    package let derivativeU: OutwardScalarInterval
    package let derivativeV: OutwardScalarInterval
    package let secondDerivativeUU: OutwardScalarInterval
    package let secondDerivativeUV: OutwardScalarInterval
    package let secondDerivativeVV: OutwardScalarInterval
    package let thirdDerivativeUUU: OutwardScalarInterval
    package let thirdDerivativeUUV: OutwardScalarInterval
    package let thirdDerivativeUVV: OutwardScalarInterval
    package let thirdDerivativeVVV: OutwardScalarInterval

    package init(value: OutwardScalarInterval,
        derivativeU: OutwardScalarInterval,
        derivativeV: OutwardScalarInterval,
        secondDerivativeUU: OutwardScalarInterval,
        secondDerivativeUV: OutwardScalarInterval,
        secondDerivativeVV: OutwardScalarInterval,
        thirdDerivativeUUU: OutwardScalarInterval,
        thirdDerivativeUUV: OutwardScalarInterval,
        thirdDerivativeUVV: OutwardScalarInterval,
        thirdDerivativeVVV: OutwardScalarInterval) {
        self.value = value
        self.derivativeU = derivativeU
        self.derivativeV = derivativeV
        self.secondDerivativeUU = secondDerivativeUU
        self.secondDerivativeUV = secondDerivativeUV
        self.secondDerivativeVV = secondDerivativeVV
        self.thirdDerivativeUUU = thirdDerivativeUUU
        self.thirdDerivativeUUV = thirdDerivativeUUV
        self.thirdDerivativeUVV = thirdDerivativeUVV
        self.thirdDerivativeVVV = thirdDerivativeVVV
    }

    package static func constant(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval.exact(0)
        return .init(value: value, derivativeU: zero, derivativeV: zero,
            secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    package static func constant(_ value: Double) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: OutwardScalarInterval(value),
            derivativeU: zero,
            derivativeV: zero,
            secondDerivativeUU: zero,
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: zero,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    package static func parameterU(_ interval: ScalarInterval) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: OutwardScalarInterval(lower: interval.lower, upper: interval.upper),
            derivativeU: OutwardScalarInterval(1.0),
            derivativeV: zero,
            secondDerivativeUU: zero,
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: zero,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    package static func parameterV(_ interval: ScalarInterval) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: OutwardScalarInterval(lower: interval.lower, upper: interval.upper),
            derivativeU: zero,
            derivativeV: OutwardScalarInterval(1.0),
            secondDerivativeUU: zero,
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: zero,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    package static func + (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
        SurfaceIntervalJet(
            value: lhs.value + rhs.value,
            derivativeU: lhs.derivativeU + rhs.derivativeU,
            derivativeV: lhs.derivativeV + rhs.derivativeV,
            secondDerivativeUU: lhs.secondDerivativeUU + rhs.secondDerivativeUU,
            secondDerivativeUV: lhs.secondDerivativeUV + rhs.secondDerivativeUV,
            secondDerivativeVV: lhs.secondDerivativeVV + rhs.secondDerivativeVV,
            thirdDerivativeUUU: lhs.thirdDerivativeUUU + rhs.thirdDerivativeUUU,
            thirdDerivativeUUV: lhs.thirdDerivativeUUV + rhs.thirdDerivativeUUV,
            thirdDerivativeUVV: lhs.thirdDerivativeUVV + rhs.thirdDerivativeUVV,
            thirdDerivativeVVV: lhs.thirdDerivativeVVV + rhs.thirdDerivativeVVV
        )
    }

    package static func - (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
        lhs + (-rhs)
    }

    package static prefix func - (value: SurfaceIntervalJet) -> SurfaceIntervalJet {
        SurfaceIntervalJet(
            value: -value.value,
            derivativeU: -value.derivativeU,
            derivativeV: -value.derivativeV,
            secondDerivativeUU: -value.secondDerivativeUU,
            secondDerivativeUV: -value.secondDerivativeUV,
            secondDerivativeVV: -value.secondDerivativeVV,
            thirdDerivativeUUU: -value.thirdDerivativeUUU,
            thirdDerivativeUUV: -value.thirdDerivativeUUV,
            thirdDerivativeUVV: -value.thirdDerivativeUVV,
            thirdDerivativeVVV: -value.thirdDerivativeVVV
        )
    }

    package static func * (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
        SurfaceIntervalJet(
            value: lhs.value * rhs.value,
            derivativeU: lhs.derivativeU * rhs.value + lhs.value * rhs.derivativeU,
            derivativeV: lhs.derivativeV * rhs.value + lhs.value * rhs.derivativeV,
            secondDerivativeUU: lhs.secondDerivativeUU * rhs.value
                + OutwardScalarInterval(2.0) * lhs.derivativeU * rhs.derivativeU
                + lhs.value * rhs.secondDerivativeUU,
            secondDerivativeUV: lhs.secondDerivativeUV * rhs.value
                + lhs.derivativeU * rhs.derivativeV
                + lhs.derivativeV * rhs.derivativeU
                + lhs.value * rhs.secondDerivativeUV,
            secondDerivativeVV: lhs.secondDerivativeVV * rhs.value
                + OutwardScalarInterval(2.0) * lhs.derivativeV * rhs.derivativeV
                + lhs.value * rhs.secondDerivativeVV,
            thirdDerivativeUUU: lhs.thirdDerivativeUUU * rhs.value
                + OutwardScalarInterval(3.0)
                    * lhs.secondDerivativeUU * rhs.derivativeU
                + OutwardScalarInterval(3.0)
                    * lhs.derivativeU * rhs.secondDerivativeUU
                + lhs.value * rhs.thirdDerivativeUUU,
            thirdDerivativeUUV: lhs.thirdDerivativeUUV * rhs.value
                + lhs.secondDerivativeUU * rhs.derivativeV
                + OutwardScalarInterval(2.0)
                    * lhs.secondDerivativeUV * rhs.derivativeU
                + OutwardScalarInterval(2.0)
                    * lhs.derivativeU * rhs.secondDerivativeUV
                + lhs.derivativeV * rhs.secondDerivativeUU
                + lhs.value * rhs.thirdDerivativeUUV,
            thirdDerivativeUVV: lhs.thirdDerivativeUVV * rhs.value
                + lhs.secondDerivativeVV * rhs.derivativeU
                + OutwardScalarInterval(2.0)
                    * lhs.secondDerivativeUV * rhs.derivativeV
                + OutwardScalarInterval(2.0)
                    * lhs.derivativeV * rhs.secondDerivativeUV
                + lhs.derivativeU * rhs.secondDerivativeVV
                + lhs.value * rhs.thirdDerivativeUVV,
            thirdDerivativeVVV: lhs.thirdDerivativeVVV * rhs.value
                + OutwardScalarInterval(3.0)
                    * lhs.secondDerivativeVV * rhs.derivativeV
                + OutwardScalarInterval(3.0)
                    * lhs.derivativeV * rhs.secondDerivativeVV
                + lhs.value * rhs.thirdDerivativeVVV
        )
    }

    package func reciprocal() -> SurfaceIntervalJet? {
        guard value.lower > 0.0 else {
            return nil
        }
        let inverse = OutwardScalarInterval(
            lower: (1.0 / value.upper).nextDown,
            upper: (1.0 / value.lower).nextUp
        )
        let firstDerivative = -(inverse * inverse)
        let secondDerivative = OutwardScalarInterval(2.0) * inverse * inverse * inverse
        let thirdDerivative = OutwardScalarInterval(-6.0)
            * inverse * inverse * inverse * inverse
        return SurfaceIntervalJet(
            value: inverse,
            derivativeU: firstDerivative * derivativeU,
            derivativeV: firstDerivative * derivativeV,
            secondDerivativeUU: secondDerivative * derivativeU * derivativeU
                + firstDerivative * secondDerivativeUU,
            secondDerivativeUV: secondDerivative * derivativeU * derivativeV
                + firstDerivative * secondDerivativeUV,
            secondDerivativeVV: secondDerivative * derivativeV * derivativeV
                + firstDerivative * secondDerivativeVV,
            thirdDerivativeUUU: thirdDerivative * derivativeU * derivativeU * derivativeU
                + OutwardScalarInterval(3.0)
                    * secondDerivative * derivativeU * secondDerivativeUU
                + firstDerivative * thirdDerivativeUUU,
            thirdDerivativeUUV: thirdDerivative * derivativeU * derivativeU * derivativeV
                + secondDerivative * (
                    secondDerivativeUU * derivativeV
                        + OutwardScalarInterval(2.0)
                            * derivativeU * secondDerivativeUV
                )
                + firstDerivative * thirdDerivativeUUV,
            thirdDerivativeUVV: thirdDerivative * derivativeU * derivativeV * derivativeV
                + secondDerivative * (
                    secondDerivativeVV * derivativeU
                        + OutwardScalarInterval(2.0)
                            * derivativeV * secondDerivativeUV
                )
                + firstDerivative * thirdDerivativeUVV,
            thirdDerivativeVVV: thirdDerivative * derivativeV * derivativeV * derivativeV
                + OutwardScalarInterval(3.0)
                    * secondDerivative * derivativeV * secondDerivativeVV
                + firstDerivative * thirdDerivativeVVV
        )
    }

    package func squareRoot() -> SurfaceIntervalJet? {
        guard value.lower > 0.0 else {
            return nil
        }
        let root = OutwardScalarInterval(
            lower: sqrt(value.lower).nextDown,
            upper: sqrt(value.upper).nextUp
        )
        guard let inverseRoot = OutwardScalarInterval(1.0).divided(by: root) else {
            return nil
        }
        let firstDerivative = OutwardScalarInterval(0.5) * inverseRoot
        let secondDerivative = OutwardScalarInterval(-0.25)
            * inverseRoot * inverseRoot * inverseRoot
        let thirdDerivative = OutwardScalarInterval(0.375)
            * inverseRoot * inverseRoot * inverseRoot * inverseRoot * inverseRoot
        return Self.applyingUnaryFunction(
            to: self,
            value: root,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            thirdDerivative: thirdDerivative
        )
    }

    package static func sine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        sine(of: argument, consumeWork: {})
    }

    package static func sine(of argument: SurfaceIntervalJet,
        consumeWork: () throws -> Void) rethrows -> SurfaceIntervalJet {
        let sine = try trigonometricRange(cosineCoefficient: 0, sineCoefficient: 1,
            parameter: argument.value, consumeWork: consumeWork)
        let cosine = try trigonometricRange(cosineCoefficient: 1, sineCoefficient: 0,
            parameter: argument.value, consumeWork: consumeWork)
        return applyingUnaryFunction(to: argument, value: sine, firstDerivative: cosine,
            secondDerivative: -sine, thirdDerivative: -cosine)
    }

    package static func cosine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        cosine(of: argument, consumeWork: {})
    }

    package static func cosine(of argument: SurfaceIntervalJet,
        consumeWork: () throws -> Void) rethrows -> SurfaceIntervalJet {
        let cosine = try trigonometricRange(cosineCoefficient: 1, sineCoefficient: 0,
            parameter: argument.value, consumeWork: consumeWork)
        let sine = try trigonometricRange(cosineCoefficient: 0, sineCoefficient: 1,
            parameter: argument.value, consumeWork: consumeWork)
        return applyingUnaryFunction(to: argument, value: cosine, firstDerivative: -sine,
            secondDerivative: -cosine, thirdDerivative: sine)
    }

    package static func hyperbolicSine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        hyperbolicSine(of: argument, consumeWork: {})
    }

    package static func hyperbolicSine(of argument: SurfaceIntervalJet,
        consumeWork: () throws -> Void) rethrows -> SurfaceIntervalJet {
        let sine = try hyperbolicRange(function: sinh, parameter: argument.value, consumeWork: consumeWork)
        let cosine = try hyperbolicCosineRange(argument.value, consumeWork: consumeWork)
        return applyingUnaryFunction(to: argument, value: sine, firstDerivative: cosine,
            secondDerivative: sine, thirdDerivative: cosine)
    }

    package static func hyperbolicCosine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        hyperbolicCosine(of: argument, consumeWork: {})
    }

    package static func hyperbolicCosine(of argument: SurfaceIntervalJet,
        consumeWork: () throws -> Void) rethrows -> SurfaceIntervalJet {
        let sine = try hyperbolicRange(function: sinh, parameter: argument.value, consumeWork: consumeWork)
        let cosine = try hyperbolicCosineRange(argument.value, consumeWork: consumeWork)
        return applyingUnaryFunction(to: argument, value: cosine, firstDerivative: sine,
            secondDerivative: cosine, thirdDerivative: sine)
    }

    package func union(_ other: SurfaceIntervalJet) -> SurfaceIntervalJet {
        SurfaceIntervalJet(
            value: value.union(other.value),
            derivativeU: derivativeU.union(other.derivativeU),
            derivativeV: derivativeV.union(other.derivativeV),
            secondDerivativeUU: secondDerivativeUU.union(other.secondDerivativeUU),
            secondDerivativeUV: secondDerivativeUV.union(other.secondDerivativeUV),
            secondDerivativeVV: secondDerivativeVV.union(other.secondDerivativeVV),
            thirdDerivativeUUU: thirdDerivativeUUU.union(other.thirdDerivativeUUU),
            thirdDerivativeUUV: thirdDerivativeUUV.union(other.thirdDerivativeUUV),
            thirdDerivativeUVV: thirdDerivativeUVV.union(other.thirdDerivativeUVV),
            thirdDerivativeVVV: thirdDerivativeVVV.union(other.thirdDerivativeVVV)
        )
    }

    package func differentiatedUThroughSecondOrder() -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: derivativeU,
            derivativeU: secondDerivativeUU,
            derivativeV: secondDerivativeUV,
            secondDerivativeUU: thirdDerivativeUUU,
            secondDerivativeUV: thirdDerivativeUUV,
            secondDerivativeVV: thirdDerivativeUVV,
            thirdDerivativeUUU: zero,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    package func differentiatedVThroughSecondOrder() -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: derivativeV,
            derivativeU: secondDerivativeUV,
            derivativeV: secondDerivativeVV,
            secondDerivativeUU: thirdDerivativeUUV,
            secondDerivativeUV: thirdDerivativeUVV,
            secondDerivativeVV: thirdDerivativeVVV,
            thirdDerivativeUUU: zero,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    static func applyingUnaryFunction(
        to argument: SurfaceIntervalJet,
        value: OutwardScalarInterval,
        firstDerivative: OutwardScalarInterval,
        secondDerivative: OutwardScalarInterval,
        thirdDerivative: OutwardScalarInterval
    ) -> SurfaceIntervalJet {
        SurfaceIntervalJet(
            value: value,
            derivativeU: firstDerivative * argument.derivativeU,
            derivativeV: firstDerivative * argument.derivativeV,
            secondDerivativeUU: secondDerivative
                * argument.derivativeU
                * argument.derivativeU
                + firstDerivative * argument.secondDerivativeUU,
            secondDerivativeUV: secondDerivative
                * argument.derivativeU
                * argument.derivativeV
                + firstDerivative * argument.secondDerivativeUV,
            secondDerivativeVV: secondDerivative
                * argument.derivativeV
                * argument.derivativeV
                + firstDerivative * argument.secondDerivativeVV,
            thirdDerivativeUUU: thirdDerivative
                * argument.derivativeU
                * argument.derivativeU
                * argument.derivativeU
                + OutwardScalarInterval(3.0)
                    * secondDerivative
                    * argument.derivativeU
                    * argument.secondDerivativeUU
                + firstDerivative * argument.thirdDerivativeUUU,
            thirdDerivativeUUV: thirdDerivative
                * argument.derivativeU
                * argument.derivativeU
                * argument.derivativeV
                + secondDerivative * (
                    argument.secondDerivativeUU * argument.derivativeV
                        + OutwardScalarInterval(2.0)
                            * argument.derivativeU
                            * argument.secondDerivativeUV
                )
                + firstDerivative * argument.thirdDerivativeUUV,
            thirdDerivativeUVV: thirdDerivative
                * argument.derivativeU
                * argument.derivativeV
                * argument.derivativeV
                + secondDerivative * (
                    argument.secondDerivativeVV * argument.derivativeU
                        + OutwardScalarInterval(2.0)
                            * argument.derivativeV
                            * argument.secondDerivativeUV
                )
                + firstDerivative * argument.thirdDerivativeUVV,
            thirdDerivativeVVV: thirdDerivative
                * argument.derivativeV
                * argument.derivativeV
                * argument.derivativeV
                + OutwardScalarInterval(3.0)
                    * secondDerivative
                    * argument.derivativeV
                    * argument.secondDerivativeVV
                + firstDerivative * argument.thirdDerivativeVVV
        )
    }

    private static func trigonometricRange(
        cosineCoefficient: Double,
        sineCoefficient: Double,
        parameter: OutwardScalarInterval,
        consumeWork: () throws -> Void
    ) rethrows -> OutwardScalarInterval {
        try consumeWork()
        let amplitude = hypot(cosineCoefficient, sineCoefficient)
        let period = 2.0 * Double.pi
        guard amplitude.isFinite, parameter.isFinite,
              parameter.upper - parameter.lower < period,
              max(abs(parameter.lower), abs(parameter.upper)) <= 1.0e12 else {
            return OutwardScalarInterval(lower: (-amplitude).nextDown, upper: amplitude.nextUp)
        }
        try consumeWork()
        let first = cosineCoefficient * cos(parameter.lower) + sineCoefficient * sin(parameter.lower)
        try consumeWork()
        let last = cosineCoefficient * cos(parameter.upper) + sineCoefficient * sin(parameter.upper)
        var lower = min(first, last), upper = max(first, last)
        let maximumParameter = atan2(sineCoefficient, cosineCoefficient)
        for index in 0..<2 {
            try consumeWork()
            let base = index == 0 ? maximumParameter : maximumParameter + Double.pi
            let extremum = index == 0 ? amplitude : -amplitude
            let firstIndex = ceil((parameter.lower - base) / period)
            let candidate = base + firstIndex * period
            if candidate <= parameter.upper {
                lower = min(lower, extremum); upper = max(upper, extremum)
            }
        }
        return .init(lower: lower.nextDown, upper: upper.nextUp)
    }

    private static func hyperbolicRange(function: (Double) -> Double,
        parameter: OutwardScalarInterval, consumeWork: () throws -> Void) rethrows -> OutwardScalarInterval {
        try consumeWork(); let first = function(parameter.lower)
        try consumeWork(); let last = function(parameter.upper)
        return .init(lower: min(first, last).nextDown, upper: max(first, last).nextUp)
    }

    private static func hyperbolicCosineRange(_ parameter: OutwardScalarInterval,
        consumeWork: () throws -> Void) rethrows -> OutwardScalarInterval {
        try consumeWork(); let first = cosh(parameter.lower)
        try consumeWork(); let last = cosh(parameter.upper)
        var lower = min(first, last)
        let upper = max(first, last)
        try consumeWork()
        if parameter.lower <= 0, parameter.upper >= 0 { lower = min(lower, 1) }
        return .init(lower: lower.nextDown, upper: upper.nextUp)
    }

}

package struct SurfaceIntervalVectorJet: Sendable {
    package let x: SurfaceIntervalJet
    package let y: SurfaceIntervalJet
    package let z: SurfaceIntervalJet

    package init(x: SurfaceIntervalJet, y: SurfaceIntervalJet, z: SurfaceIntervalJet) {
        self.x = x; self.y = y; self.z = z
    }

    package static func constant(_ point: Point3D) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: .constant(point.x),
            y: .constant(point.y),
            z: .constant(point.z)
        )
    }

    package static func constant(_ vector: IntervalVector3DBounds) -> SurfaceIntervalVectorJet {
        .init(x: .constant(vector.x), y: .constant(vector.y), z: .constant(vector.z))
    }

    package static func constant(_ vector: Vector3D) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: .constant(vector.x),
            y: .constant(vector.y),
            z: .constant(vector.z)
        )
    }

    package static func + (
        lhs: SurfaceIntervalVectorJet,
        rhs: SurfaceIntervalVectorJet
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            z: lhs.z + rhs.z
        )
    }

    package static prefix func - (value: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(x: -value.x, y: -value.y, z: -value.z)
    }

    package static func * (
        lhs: SurfaceIntervalVectorJet,
        rhs: SurfaceIntervalJet
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs
        )
    }

    package func dot(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalJet {
        x * other.x + y * other.y + z * other.z
    }

    package func cross(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    package func normalized() -> SurfaceIntervalVectorJet? {
        guard let length = dot(self).squareRoot(),
              let inverseLength = length.reciprocal() else {
            return nil
        }
        return self * inverseLength
    }

    package func differentiatedUThroughSecondOrder() -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.differentiatedUThroughSecondOrder(),
            y: y.differentiatedUThroughSecondOrder(),
            z: z.differentiatedUThroughSecondOrder()
        )
    }

    package func differentiatedVThroughSecondOrder() -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.differentiatedVThroughSecondOrder(),
            y: y.differentiatedVThroughSecondOrder(),
            z: z.differentiatedVThroughSecondOrder()
        )
    }

    package func union(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.union(other.x),
            y: y.union(other.y),
            z: z.union(other.z)
        )
    }
}
