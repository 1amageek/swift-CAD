import CADCore
import Foundation

struct SurfaceIntervalJet: Sendable {
    let value: OutwardScalarInterval
    let derivativeU: OutwardScalarInterval
    let derivativeV: OutwardScalarInterval
    let secondDerivativeUU: OutwardScalarInterval
    let secondDerivativeUV: OutwardScalarInterval
    let secondDerivativeVV: OutwardScalarInterval
    let thirdDerivativeUUU: OutwardScalarInterval
    let thirdDerivativeUUV: OutwardScalarInterval
    let thirdDerivativeUVV: OutwardScalarInterval
    let thirdDerivativeVVV: OutwardScalarInterval

    static func constant(_ value: Double) -> SurfaceIntervalJet {
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

    static func parameterU(_ interval: ScalarInterval) -> SurfaceIntervalJet {
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

    static func parameterV(_ interval: ScalarInterval) -> SurfaceIntervalJet {
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

    static func + (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
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

    static func - (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
        lhs + (-rhs)
    }

    static prefix func - (value: SurfaceIntervalJet) -> SurfaceIntervalJet {
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

    static func * (lhs: SurfaceIntervalJet, rhs: SurfaceIntervalJet) -> SurfaceIntervalJet {
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

    func reciprocal() -> SurfaceIntervalJet? {
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

    func squareRoot() -> SurfaceIntervalJet? {
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

    static func sine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        applyingUnaryFunction(
            to: argument,
            value: trigonometricRange(
                cosineCoefficient: 0.0,
                sineCoefficient: 1.0,
                parameter: argument.value
            ),
            firstDerivative: trigonometricRange(
                cosineCoefficient: 1.0,
                sineCoefficient: 0.0,
                parameter: argument.value
            ),
            secondDerivative: -trigonometricRange(
                cosineCoefficient: 0.0,
                sineCoefficient: 1.0,
                parameter: argument.value
            ),
            thirdDerivative: -trigonometricRange(
                cosineCoefficient: 1.0,
                sineCoefficient: 0.0,
                parameter: argument.value
            )
        )
    }

    static func cosine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        applyingUnaryFunction(
            to: argument,
            value: trigonometricRange(
                cosineCoefficient: 1.0,
                sineCoefficient: 0.0,
                parameter: argument.value
            ),
            firstDerivative: -trigonometricRange(
                cosineCoefficient: 0.0,
                sineCoefficient: 1.0,
                parameter: argument.value
            ),
            secondDerivative: -trigonometricRange(
                cosineCoefficient: 1.0,
                sineCoefficient: 0.0,
                parameter: argument.value
            ),
            thirdDerivative: trigonometricRange(
                cosineCoefficient: 0.0,
                sineCoefficient: 1.0,
                parameter: argument.value
            )
        )
    }

    static func hyperbolicSine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        applyingUnaryFunction(
            to: argument,
            value: hyperbolicRange(
                function: sinh,
                parameter: argument.value
            ),
            firstDerivative: hyperbolicCosineRange(argument.value),
            secondDerivative: hyperbolicRange(
                function: sinh,
                parameter: argument.value
            ),
            thirdDerivative: hyperbolicCosineRange(argument.value)
        )
    }

    static func hyperbolicCosine(of argument: SurfaceIntervalJet) -> SurfaceIntervalJet {
        applyingUnaryFunction(
            to: argument,
            value: hyperbolicCosineRange(argument.value),
            firstDerivative: hyperbolicRange(
                function: sinh,
                parameter: argument.value
            ),
            secondDerivative: hyperbolicCosineRange(argument.value),
            thirdDerivative: hyperbolicRange(
                function: sinh,
                parameter: argument.value
            )
        )
    }

    func union(_ other: SurfaceIntervalJet) -> SurfaceIntervalJet {
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

    func differentiatedUThroughSecondOrder() -> SurfaceIntervalJet {
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

    func differentiatedVThroughSecondOrder() -> SurfaceIntervalJet {
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

    private static func applyingUnaryFunction(
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
        parameter: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        let amplitude = hypot(cosineCoefficient, sineCoefficient)
        let period = 2.0 * Double.pi
        guard amplitude.isFinite,
              parameter.isFinite,
              parameter.upper - parameter.lower < period,
              max(abs(parameter.lower), abs(parameter.upper)) <= 1.0e12 else {
            return OutwardScalarInterval(
                lower: (-amplitude).nextDown,
                upper: amplitude.nextUp
            )
        }
        var values = [
            cosineCoefficient * cos(parameter.lower)
                + sineCoefficient * sin(parameter.lower),
            cosineCoefficient * cos(parameter.upper)
                + sineCoefficient * sin(parameter.upper),
        ]
        let maximumParameter = atan2(sineCoefficient, cosineCoefficient)
        for (base, extremum) in [
            (maximumParameter, amplitude),
            (maximumParameter + Double.pi, -amplitude),
        ] {
            let firstIndex = ceil((parameter.lower - base) / period)
            let candidate = base + firstIndex * period
            if candidate <= parameter.upper {
                values.append(extremum)
            }
        }
        return OutwardScalarInterval.enclosing(values)
    }

    private static func hyperbolicRange(
        function: (Double) -> Double,
        parameter: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval.enclosing([
            function(parameter.lower),
            function(parameter.upper),
        ])
    }

    private static func hyperbolicCosineRange(
        _ parameter: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        var values = [cosh(parameter.lower), cosh(parameter.upper)]
        if parameter.lower <= 0.0, parameter.upper >= 0.0 {
            values.append(1.0)
        }
        return OutwardScalarInterval.enclosing(values)
    }
}

struct SurfaceIntervalVectorJet: Sendable {
    let x: SurfaceIntervalJet
    let y: SurfaceIntervalJet
    let z: SurfaceIntervalJet

    static func constant(_ point: Point3D) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: .constant(point.x),
            y: .constant(point.y),
            z: .constant(point.z)
        )
    }

    static func constant(_ vector: Vector3D) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: .constant(vector.x),
            y: .constant(vector.y),
            z: .constant(vector.z)
        )
    }

    static func + (
        lhs: SurfaceIntervalVectorJet,
        rhs: SurfaceIntervalVectorJet
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            z: lhs.z + rhs.z
        )
    }

    static prefix func - (value: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(x: -value.x, y: -value.y, z: -value.z)
    }

    static func * (
        lhs: SurfaceIntervalVectorJet,
        rhs: SurfaceIntervalJet
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs
        )
    }

    func dot(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalJet {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    func normalized() -> SurfaceIntervalVectorJet? {
        guard let length = dot(self).squareRoot(),
              let inverseLength = length.reciprocal() else {
            return nil
        }
        return self * inverseLength
    }

    func differentiatedUThroughSecondOrder() -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.differentiatedUThroughSecondOrder(),
            y: y.differentiatedUThroughSecondOrder(),
            z: z.differentiatedUThroughSecondOrder()
        )
    }

    func differentiatedVThroughSecondOrder() -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.differentiatedVThroughSecondOrder(),
            y: y.differentiatedVThroughSecondOrder(),
            z: z.differentiatedVThroughSecondOrder()
        )
    }

    func union(_ other: SurfaceIntervalVectorJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: x.union(other.x),
            y: y.union(other.y),
            z: z.union(other.z)
        )
    }
}
