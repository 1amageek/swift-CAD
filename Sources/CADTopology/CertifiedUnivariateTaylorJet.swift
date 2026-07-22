import CADCore

/// A factorial-scaled interval Taylor jet used for directional rational
/// surface-flux derivative bounds.
struct CertifiedUnivariateTaylorJet: Sendable {
    typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval

    static let order = 7
    var coefficients: [Interval]

    static func constant(_ value: Double) -> Self {
        constant(.exact(value))
    }

    static func constant(_ value: Interval) -> Self {
        var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
        coefficients[0] = value
        return Self(coefficients: coefficients)
    }

    static func variable(_ value: Interval) -> Self {
        var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
        coefficients[0] = value
        coefficients[1] = .exact(1.0)
        return Self(coefficients: coefficients)
    }

    static func series(_ values: [Interval]) -> Self {
        var coefficients = Array(repeating: Interval.exact(0.0), count: order + 1)
        for index in 0..<min(values.count, order + 1) {
            coefficients[index] = values[index]
        }
        return Self(coefficients: coefficients)
    }

    var value: Interval {
        coefficients[0]
    }

    func derivative() -> Self {
        var result = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
        for degree in 0..<Self.order {
            result[degree] = coefficients[degree + 1] * .exact(Double(degree + 1))
        }
        return Self(coefficients: result)
    }

    func divided(
        by denominator: Self,
        tolerance: ModelingTolerance
    ) throws -> Self {
        self * (try denominator.reciprocal(tolerance: tolerance))
    }

    func reciprocal(tolerance: ModelingTolerance) throws -> Self {
        let constant = value
        guard constant.lower > 0.0 || constant.upper < 0.0 else {
            let minimumAbsolute = constant.lower <= 0.0 && constant.upper >= 0.0
                ? 0.0
                : min(abs(constant.lower), abs(constant.upper))
            throw KernelError(
                phase: .topology,
                code: .singularSystem,
                residual: minimumAbsolute,
                tolerance: tolerance,
                message: "Certified directional surface flux encountered a singular reciprocal jet."
            )
        }
        let inverse = Interval.exact(1.0) / constant
        var result = Array(repeating: Interval.exact(0.0), count: Self.order + 1)
        result[0] = inverse
        for degree in 1...Self.order {
            var sum = Interval.exact(0.0)
            for index in 1...degree {
                sum = sum + coefficients[index] * result[degree - index]
            }
            result[degree] = -inverse * sum
        }
        return Self(coefficients: result)
    }

    static prefix func - (value: Self) -> Self {
        Self(coefficients: value.coefficients.map { -$0 })
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(coefficients: zip(lhs.coefficients, rhs.coefficients).map { $0 + $1 })
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        lhs + (-rhs)
    }

    static func * (lhs: Self, rhs: Self) -> Self {
        var result = Array(repeating: Interval.exact(0.0), count: order + 1)
        for degree in 0...order {
            for index in 0...degree {
                result[degree] = result[degree]
                    + lhs.coefficients[index] * rhs.coefficients[degree - index]
            }
        }
        return Self(coefficients: result)
    }
}
