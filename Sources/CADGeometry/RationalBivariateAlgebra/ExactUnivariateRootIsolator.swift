import CADCore

/// Exact Sturm certificate retaining rational isolating stations and source multiplicity.
public struct ExactUnivariateRootIsolator: Sendable {
    public struct Root: Sendable {
        public let lower: ExactRationalCoefficient
        public let upper: ExactRationalCoefficient
        public let isRationalStation: Bool
        public let isolationDepth: Int
        public let excludesLowerEndpoint: Bool
        public let excludesUpperEndpoint: Bool
    }
    private struct Pending { let lower: ExactRationalCoefficient; let upper: ExactRationalCoefficient; let depth: Int; let count: Int }
    public init() {}

    public func isolate<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> [Root] {
        guard polynomial.vDegree <= 0, !polynomial.isZero, maximumDepth >= 0,
              try upper.subtracting(lower, usage: &usage).isPositive else {
            throw rationalAlgebraFailure("Exact real-root isolation requires a nonzero univariate source and increasing stations.")
        }
        let gcd = ExactBivariateGCD()
        let derivative = try polynomial.differentiated(alongU: true, usage: &usage)
        let repeated = try gcd.univariateGCD(polynomial, derivative, usage: &usage)
        var squareFree = try polynomial.dividedExactly(by: repeated, usage: &usage)
        var roots: [Root] = []
        for side in 0..<2 {
            let station = side == 0 ? lower : upper
            if try squareFree.evaluated(atU: station, v: .zero, usage: &usage).isZero {
                try RationalAlgebraStorage.retain(1, of: Root.self, usage: &usage)
                roots.append(Root(lower: station, upper: station, isRationalStation: true, isolationDepth: 0, excludesLowerEndpoint: false, excludesUpperEndpoint: false))
                let factor = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                    .subtracting(.constant(station, usage: &usage), usage: &usage)
                squareFree = try squareFree.dividedExactly(by: factor, usage: &usage)
            }
        }
        if squareFree.uDegree <= 0 { return roots }
        try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
        var sturm = [squareFree, try squareFree.differentiated(alongU: true, usage: &usage)]
        while let last = sturm.last, !last.isZero {
            let remainder = try gcd.univariateDivision(sturm[sturm.count - 2], last, usage: &usage).remainder
            if remainder.isZero { break }
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            sturm.append(try remainder.scaled(by: .one.negated, usage: &usage))
        }
        let count = try variations(sturm, at: lower, usage: &usage) - variations(sturm, at: upper, usage: &usage)
        guard count >= 0 else { throw rationalAlgebraFailure("Exact Sturm count is inconsistent.") }
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        var pending = [Pending(lower: lower, upper: upper, depth: 0, count: count)]
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while let current = pending.popLast() {
            try usage.visitExactCell(depth: current.depth)
            if current.count == 0 { continue }
            if current.count == 1 {
                try RationalAlgebraStorage.retain(1, of: Root.self, usage: &usage)
                roots.append(Root(lower: current.lower, upper: current.upper, isRationalStation: false, isolationDepth: current.depth, excludesLowerEndpoint: true, excludesUpperEndpoint: current.upper == upper)); continue
            }
            guard current.depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Exact original root isolation exhausted caller depth.")
            }
            let middle = try current.lower.adding(current.upper, usage: &usage).divided(by: two, usage: &usage)
            let left = try variations(sturm, at: current.lower, usage: &usage) - variations(sturm, at: middle, usage: &usage)
            let right = try variations(sturm, at: middle, usage: &usage) - variations(sturm, at: current.upper, usage: &usage)
            guard left >= 0, right >= 0, left + right == current.count else {
                throw rationalAlgebraFailure("Exact original Sturm subdivision contradicted its root count.")
            }
            try RationalAlgebraStorage.retain(2, of: Pending.self, usage: &usage)
            pending.append(Pending(lower: middle, upper: current.upper, depth: current.depth + 1, count: right))
            pending.append(Pending(lower: current.lower, upper: middle, depth: current.depth + 1, count: left))
        }
        return roots
    }

    private func variations<B: RationalAlgebraAdmitting>(_ sequence: [ExactBivariatePolynomial],
        at station: ExactRationalCoefficient, usage: inout B) throws -> Int {
        var previous = 0, count = 0
        for polynomial in sequence {
            let value = try polynomial.evaluated(atU: station, v: .zero, usage: &usage)
            let sign = value.isPositive ? 1 : value.isNegative ? -1 : 0
            if sign == 0 { continue }
            if previous != 0, previous != sign { count += 1 }
            previous = sign
        }
        return count
    }
}
