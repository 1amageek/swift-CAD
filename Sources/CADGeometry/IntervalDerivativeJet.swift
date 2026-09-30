import CADCore

/// Enclosures of a function's value and its derivatives through a fixed order over a set of
/// parameters: `derivatives[k]` contains the k-th derivative at every parameter of the set.
///
/// Sums and products follow the Leibniz rule, reciprocals and square roots their derivative
/// recurrences, all in outward interval arithmetic, so a combined jet encloses the combined
/// function's derivatives wherever its operands enclose theirs. A jet over a whole parameter
/// interval therefore bounds a derivative over that interval, as a Taylor remainder needs.
package struct IntervalDerivativeJet: Sendable {
    package typealias Interval = OutwardScalarInterval

    package let derivatives: [Interval]

    package init(derivatives: [Interval]) {
        self.derivatives = derivatives
    }

    package static func constant(_ value: Interval, order: Int) -> IntervalDerivativeJet {
        IntervalDerivativeJet(derivatives: [value] + Array(repeating: .exact(0), count: max(order, 0)))
    }

    package var order: Int { derivatives.count - 1 }
    package var value: Interval { derivatives[0] }

    /// Binomial coefficients through order six, exact in `Double`.
    private static let binomials: [[Double]] = [
        [1], [1, 1], [1, 2, 1], [1, 3, 3, 1], [1, 4, 6, 4, 1], [1, 5, 10, 10, 5, 1], [1, 6, 15, 20, 15, 6, 1],
    ]

    private static func binomial(_ n: Int, _ k: Int) -> Interval {
        .exact(binomials[n][k])
    }

    package static func + (lhs: IntervalDerivativeJet, rhs: IntervalDerivativeJet) -> IntervalDerivativeJet {
        let order = min(lhs.order, rhs.order)
        return IntervalDerivativeJet(derivatives: (0...order).map { lhs.derivatives[$0] + rhs.derivatives[$0] })
    }

    package static func - (lhs: IntervalDerivativeJet, rhs: IntervalDerivativeJet) -> IntervalDerivativeJet {
        let order = min(lhs.order, rhs.order)
        return IntervalDerivativeJet(derivatives: (0...order).map { lhs.derivatives[$0] - rhs.derivatives[$0] })
    }

    package static func * (lhs: IntervalDerivativeJet, rhs: IntervalDerivativeJet) -> IntervalDerivativeJet {
        let order = min(lhs.order, rhs.order)
        return IntervalDerivativeJet(derivatives: (0...order).map { n in
            (0...n).reduce(Interval.exact(0)) { sum, k in
                sum + binomial(n, k) * lhs.derivatives[k] * rhs.derivatives[n - k]
            }
        })
    }

    package func scaled(by factor: Interval) -> IntervalDerivativeJet {
        IntervalDerivativeJet(derivatives: derivatives.map { $0 * factor })
    }

    /// The derivative's jet, one order lower.
    package func differentiated() -> IntervalDerivativeJet? {
        guard order >= 1 else { return nil }
        return IntervalDerivativeJet(derivatives: Array(derivatives.dropFirst()))
    }

    /// `1 / f`, or `nil` when the value's enclosure reaches zero.
    package func reciprocal() -> IntervalDerivativeJet? {
        guard order <= 6, let first = Interval.exact(1).divided(by: value) else { return nil }
        var result = [first]
        for n in stride(from: 1, through: order, by: 1) {
            let sum = (1...n).reduce(Interval.exact(0)) { sum, k in
                sum + Self.binomial(n, k) * derivatives[k] * result[n - k]
            }
            result.append(-(sum * first))
        }
        return IntervalDerivativeJet(derivatives: result)
    }

    /// `√f`, or `nil` unless the value's enclosure is positive.
    package func squareRoot() -> IntervalDerivativeJet? {
        guard order <= 6, value.lower > 0, value.upper.isFinite else { return nil }
        let first = Interval(lower: value.lower.squareRoot().nextDown, upper: value.upper.squareRoot().nextUp)
        let twice = first * .exact(2)
        var result = [first]
        for n in stride(from: 1, through: order, by: 1) {
            let sum = stride(from: 1, to: n, by: 1).reduce(Interval.exact(0)) { sum, k in
                sum + Self.binomial(n, k) * result[k] * result[n - k]
            }
            guard let next = (derivatives[n] - sum).divided(by: twice) else { return nil }
            result.append(next)
        }
        return IntervalDerivativeJet(derivatives: result)
    }
}

/// Three coordinate jets of one vector function.
package struct IntervalVectorDerivativeJet: Sendable {
    package let x: IntervalDerivativeJet
    package let y: IntervalDerivativeJet
    package let z: IntervalDerivativeJet

    package init(x: IntervalDerivativeJet, y: IntervalDerivativeJet, z: IntervalDerivativeJet) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// A constant vector, every derivative zero.
    package static func constant(
        _ components: [OutwardScalarInterval], order: Int
    ) -> IntervalVectorDerivativeJet {
        IntervalVectorDerivativeJet(
            x: .constant(components[0], order: order),
            y: .constant(components[1], order: order),
            z: .constant(components[2], order: order)
        )
    }

    package var components: [IntervalDerivativeJet] { [x, y, z] }

    package static func + (lhs: IntervalVectorDerivativeJet, rhs: IntervalVectorDerivativeJet) -> IntervalVectorDerivativeJet {
        IntervalVectorDerivativeJet(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    package static func - (lhs: IntervalVectorDerivativeJet, rhs: IntervalVectorDerivativeJet) -> IntervalVectorDerivativeJet {
        IntervalVectorDerivativeJet(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    package func scaled(by factor: IntervalDerivativeJet) -> IntervalVectorDerivativeJet {
        IntervalVectorDerivativeJet(x: x * factor, y: y * factor, z: z * factor)
    }

    package func dot(_ other: IntervalVectorDerivativeJet) -> IntervalDerivativeJet {
        x * other.x + y * other.y + z * other.z
    }

    package func cross(_ other: IntervalVectorDerivativeJet) -> IntervalVectorDerivativeJet {
        IntervalVectorDerivativeJet(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    package func differentiated() -> IntervalVectorDerivativeJet? {
        guard let dx = x.differentiated(), let dy = y.differentiated(), let dz = z.differentiated() else { return nil }
        return IntervalVectorDerivativeJet(x: dx, y: dy, z: dz)
    }

    /// The enclosures of the k-th derivative's coordinates.
    package func derivative(_ k: Int) -> [OutwardScalarInterval] {
        [x.derivatives[k], y.derivatives[k], z.derivatives[k]]
    }
}
