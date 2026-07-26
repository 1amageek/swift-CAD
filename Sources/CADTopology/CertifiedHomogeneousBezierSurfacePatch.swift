import CADCore

struct CertifiedHomogeneousBezierSurfacePatch: Sendable, Hashable {
    struct ScalarBounds: Sendable, Hashable {
        let lower: Double
        let upper: Double

        init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func exact(_ value: Double) -> ScalarBounds {
            ScalarBounds(lower: value, upper: value)
        }

        static prefix func - (value: ScalarBounds) -> ScalarBounds {
            ScalarBounds(
                lower: (-value.upper).nextDown,
                upper: (-value.lower).nextUp
            )
        }

        static func + (lhs: ScalarBounds, rhs: ScalarBounds) -> ScalarBounds {
            ScalarBounds(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (lhs: ScalarBounds, rhs: ScalarBounds) -> ScalarBounds {
            lhs + (-rhs)
        }

        static func * (lhs: ScalarBounds, rhs: ScalarBounds) -> ScalarBounds {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return ScalarBounds(
                lower: products.min()!.nextDown,
                upper: products.max()!.nextUp
            )
        }

        static func / (lhs: ScalarBounds, rhs: ScalarBounds) -> ScalarBounds {
            guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
                // Division by a zero-containing interval is unbounded. The
                // enclosing certificate owner converts non-finite bounds into
                // a typed failure before publishing a result.
                return ScalarBounds(lower: -.infinity, upper: .infinity)
            }
            let reciprocals = ScalarBounds(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
            return lhs * reciprocals
        }

        var isFinite: Bool {
            lower.isFinite && upper.isFinite && lower <= upper
        }
    }

    struct HomogeneousPoint: Sendable, Hashable {
        let x: ScalarBounds
        let y: ScalarBounds
        let z: ScalarBounds
        let weight: ScalarBounds

        func interpolated(
            to other: HomogeneousPoint,
            parameter: ScalarBounds
        ) -> HomogeneousPoint {
            let complement = ScalarBounds.exact(1.0) - parameter
            return HomogeneousPoint(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter,
                z: z * complement + other.z * parameter,
                weight: weight * complement + other.weight * parameter
            )
        }

        var isFiniteAndPositiveWeight: Bool {
            x.isFinite
                && y.isFinite
                && z.isFinite
                && weight.isFinite
                && weight.lower > 0.0
        }
    }

    let controls: [[HomogeneousPoint]]
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double
}
