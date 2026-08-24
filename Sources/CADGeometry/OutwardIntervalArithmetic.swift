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
        let products = [
            lhs.lower * rhs.lower,
            lhs.lower * rhs.upper,
            lhs.upper * rhs.lower,
            lhs.upper * rhs.upper,
        ]
        return OutwardScalarInterval(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
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
        guard denominator.lower > 0.0 || denominator.upper < 0.0 else {
            return nil
        }
        let reciprocalValues = [
            1.0 / denominator.lower,
            1.0 / denominator.upper,
        ]
        let reciprocal = OutwardScalarInterval(
            lower: (reciprocalValues.min() ?? -.infinity).nextDown,
            upper: (reciprocalValues.max() ?? .infinity).nextUp
        )
        return self * reciprocal
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
        lower + (upper - lower) * 0.5
    }

    package var absoluteLowerBound: Double {
        if lower > 0.0 {
            return lower.nextDown
        }
        if upper < 0.0 {
            return (-upper).nextDown
        }
        return 0.0
    }

    package var absoluteUpperBound: Double {
        max(abs(lower), abs(upper)).nextUp
    }
}

package struct IntervalVector3DBounds: Sendable {
    package let x: OutwardScalarInterval
    package let y: OutwardScalarInterval
    package let z: OutwardScalarInterval

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

    package var midpoint: Vector3D {
        Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }

    package var lengthLowerBound: Double {
        max(x.absoluteLowerBound, y.absoluteLowerBound, z.absoluteLowerBound)
    }

    package var lengthUpperBound: Double {
        let xUpper = x.absoluteUpperBound
        let yUpper = y.absoluteUpperBound
        let zUpper = z.absoluteUpperBound
        let xSquared = (xUpper * xUpper).nextUp
        let ySquared = (yUpper * yUpper).nextUp
        let zSquared = (zUpper * zUpper).nextUp
        let xySquared = (xSquared + ySquared).nextUp
        return sqrt((xySquared + zSquared).nextUp).nextUp
    }
}
