import CADCore
import Foundation

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
            lower: values.map(\.lower).min() ?? -.infinity,
            upper: values.map(\.upper).max() ?? .infinity
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

package struct IntervalVector3DBounds: Sendable {
    package let x: OutwardScalarInterval
    package let y: OutwardScalarInterval
    package let z: OutwardScalarInterval

    package init(x: OutwardScalarInterval, y: OutwardScalarInterval, z: OutwardScalarInterval) {
        self.x = x
        self.y = y
        self.z = z
    }

    package static func + (lhs: IntervalVector3DBounds, rhs: IntervalVector3DBounds) -> IntervalVector3DBounds {
        .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    package func dot(_ other: IntervalVector3DBounds) -> OutwardScalarInterval {
        x * other.x + y * other.y + z * other.z
    }

    package static func - (
        lhs: IntervalVector3DBounds,
        rhs: IntervalVector3DBounds
    ) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            z: lhs.z - rhs.z
        )
    }

    package static func * (
        lhs: IntervalVector3DBounds,
        rhs: OutwardScalarInterval
    ) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs
        )
    }

    package func cross(
        _ other: IntervalVector3DBounds
    ) -> IntervalVector3DBounds {
        IntervalVector3DBounds(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    package func dot(_ vector: Vector3D) -> OutwardScalarInterval {
        x * OutwardScalarInterval(vector.x)
            + y * OutwardScalarInterval(vector.y)
            + z * OutwardScalarInterval(vector.z)
    }

    /// Encloses the original direction after a positive common scale cancels.
    package func normalized(consumeWork: () throws -> Void = {}) throws -> Self? {
        let scale = max(x.absoluteUpperBound, y.absoluteUpperBound, z.absoluteUpperBound)
        guard scale.isFinite, scale > 0 else { return nil }
        let divisor = OutwardScalarInterval.exact(scale)
        try consumeWork()
        guard let a = x.divided(by: divisor) else { return nil }
        try consumeWork()
        guard let b = y.divided(by: divisor) else { return nil }
        try consumeWork()
        guard let c = z.divided(by: divisor) else { return nil }
        try consumeWork(); let aa = a * a
        try consumeWork(); let bb = b * b
        try consumeWork(); let cc = c * c
        try consumeWork(); let first = aa + bb
        try consumeWork(); let squared = first + cc
        guard squared.isFinite, squared.lower > 0 else { return nil }
        try consumeWork(); let lowerLength = squared.lower.squareRoot().nextDown
        try consumeWork(); let upperLength = squared.upper.squareRoot().nextUp
        let length = OutwardScalarInterval(lower: lowerLength, upper: upperLength)
        guard length.lower > 0, length.isFinite else { return nil }
        try consumeWork()
        guard let nx = a.divided(by: length) else { return nil }
        try consumeWork()
        guard let ny = b.divided(by: length) else { return nil }
        try consumeWork()
        guard let nz = c.divided(by: length), nx.isFinite, ny.isFinite, nz.isFinite else { return nil }
        return .init(x: nx, y: ny, z: nz)
    }

    package var midpoint: Vector3D {
        Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }

    package var lengthLowerBound: Double {
        guard x.isFinite, y.isFinite, z.isFinite else { return 0 }
        let a = x.absoluteLowerBound, b = y.absoluteLowerBound, c = z.absoluteLowerBound
        let scale = max(a, b, c)
        guard scale > 0 else { return 0 }
        guard scale.isFinite else { return scale }
        func square(_ value: Double) -> Double {
            let ratio = max(0, (value / scale).nextDown)
            return max(0, (ratio * ratio).nextDown)
        }
        let sum = max(0, ((square(a) + square(b)).nextDown + square(c)).nextDown)
        let root = max(0, sqrt(sum).nextDown)
        let lower = (root * scale).nextDown
        return max(scale, lower.isFinite ? lower : Double.greatestFiniteMagnitude)
    }

    package var lengthUpperBound: Double {
        guard x.isFinite, y.isFinite, z.isFinite else { return .infinity }
        let a = x.absoluteUpperBound, b = y.absoluteUpperBound, c = z.absoluteUpperBound
        let scale = max(a, b, c)
        guard scale > 0 else { return 0 }
        guard scale.isFinite else { return .infinity }
        if (a == 0 && b == 0) || (a == 0 && c == 0) || (b == 0 && c == 0) { return scale }
        func square(_ value: Double) -> Double {
            guard value > 0 else { return 0 }
            let ratio = (value / scale).nextUp
            return (ratio * ratio).nextUp
        }
        let sum = ((square(a) + square(b)).nextUp + square(c)).nextUp
        return (sqrt(sum).nextUp * scale).nextUp
    }
}
