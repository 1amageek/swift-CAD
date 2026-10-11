/// An interval whose arithmetic operations round away from the represented
/// real result. The model is defined by its stored `Double` values; use
/// `exact(_:)` for those inputs and `init(_:)` only when enclosing a value
/// produced outside this arithmetic boundary.
package struct OutwardScalarInterval: Sendable {
    package let lower: Double
    package let upper: Double

    package init(_ value: Double) {
        lower = value.nextDown
        upper = value.nextUp
    }

    package init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    package static func exact(_ value: Double) -> OutwardScalarInterval {
        OutwardScalarInterval(lower: value, upper: value)
    }

    package static func enclosing(_ values: [Double]) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (values.min() ?? -.infinity).nextDown,
            upper: (values.max() ?? .infinity).nextUp
        )
    }

    package static func enclosing(
        _ values: [OutwardScalarInterval]
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: values.map({ $0.lower }).min() ?? -.infinity,
            upper: values.map({ $0.upper }).max() ?? .infinity
        )
    }

    package static func + (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (lhs.lower + rhs.lower).nextDown,
            upper: (lhs.upper + rhs.upper).nextUp
        )
    }

    package static func - (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (lhs.lower - rhs.upper).nextDown,
            upper: (lhs.upper - rhs.lower).nextUp
        )
    }

    package static func * (
        lhs: OutwardScalarInterval,
        rhs: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        let p00 = lhs.lower * rhs.lower
        let p01 = lhs.lower * rhs.upper
        let p10 = lhs.upper * rhs.lower
        let p11 = lhs.upper * rhs.upper
        // Preserve Sequence's ordered comparison, including signed zero and NaN.
        var minimum = p00
        var maximum = p00
        if p01 < minimum { minimum = p01 }
        if p01 > maximum { maximum = p01 }
        if p10 < minimum { minimum = p10 }
        if p10 > maximum { maximum = p10 }
        if p11 < minimum { minimum = p11 }
        if p11 > maximum { maximum = p11 }
        return OutwardScalarInterval(
            lower: minimum.nextDown,
            upper: maximum.nextUp
        )
    }

    package static prefix func - (
        value: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (-value.upper).nextDown,
            upper: (-value.lower).nextUp
        )
    }

    package func divided(
        by denominator: OutwardScalarInterval
    ) -> OutwardScalarInterval? {
        guard isFinite, denominator.isFinite, denominator.excludesZero,
              lower <= upper, denominator.lower <= denominator.upper else { return nil }
        let q00 = lower / denominator.lower, q01 = lower / denominator.upper
        let q10 = upper / denominator.lower, q11 = upper / denominator.upper
        guard !q00.isNaN, !q01.isNaN, !q10.isNaN, !q11.isNaN else { return nil }
        return .init(lower: min(q00, q01, q10, q11).nextDown,
            upper: max(q00, q01, q10, q11).nextUp)
    }

    package func intersection(
        with other: OutwardScalarInterval
    ) -> OutwardScalarInterval? {
        let intersectionLower = max(lower, other.lower)
        let intersectionUpper = min(upper, other.upper)
        guard intersectionLower <= intersectionUpper else { return nil }
        return OutwardScalarInterval(
            lower: intersectionLower,
            upper: intersectionUpper
        )
    }

    package func union(
        _ other: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: min(lower, other.lower),
            upper: max(upper, other.upper)
        )
    }

    package func contains(_ value: Double) -> Bool {
        lower <= value && value <= upper
    }

    package func intersects(_ other: OutwardScalarInterval) -> Bool {
        lower <= other.upper && other.lower <= upper
    }

    package func isStrictlyInside(_ other: OutwardScalarInterval) -> Bool {
        lower > other.lower && upper < other.upper
    }

    package var width: Double {
        (upper - lower).nextUp
    }

    package var isFinite: Bool {
        lower.isFinite && upper.isFinite
    }

    package var excludesZero: Bool {
        lower > 0.0 || upper < 0.0
    }

    package var sign: Int? {
        if lower > 0.0 { return 1 }
        if upper < 0.0 { return -1 }
        return nil
    }

    package var midpoint: Double {
        if lower < 0, upper > 0 { return lower * 0.5 + upper * 0.5 }
        return lower + (upper - lower) * 0.5
    }

    package var absoluteLowerBound: Double {
        if lower > 0.0 {
            return lower
        }
        if upper < 0.0 {
            return -upper
        }
        return 0.0
    }

    package var absoluteUpperBound: Double {
        max(abs(lower), abs(upper))
    }
}
