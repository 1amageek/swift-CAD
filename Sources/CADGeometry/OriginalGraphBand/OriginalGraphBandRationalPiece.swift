import CADCore

/// Original native Bezier coefficients; no Cartesian extraction or fitted curve enters this owner.
struct OriginalGraphBandRationalPiece: Sendable {
    typealias Interval = OutwardScalarInterval
    let boundaryIndex: Int
    let nativeIndex: Int
    let nativeParameters: ScalarInterval
    let points: [Point2D]
    let weights: [Interval]
    let x: [Interval]
    let y: [Interval]
    let uDirection: Int
    let minimumAbsoluteUDerivative: Double
    let uDerivativeHull: Interval

    struct GraphJet: Sendable {
        let v: Interval
        let first: Interval
        let second: Interval
        let normalizedParameters: ScalarInterval
    }

    init(boundaryIndex: Int, nativeIndex: Int, nativeParameters: ScalarInterval,
         points: [Point2D], weights: [Double], tolerance: ModelingTolerance) throws {
        guard (2...5).contains(points.count), points.count == weights.count,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "An original graph piece requires finite positive native coefficients.")
        }
        self.boundaryIndex = boundaryIndex
        self.nativeIndex = nativeIndex
        self.nativeParameters = nativeParameters
        self.points = points
        self.weights = weights.map(Interval.exact)
        x = zip(points, self.weights).map { Interval.exact($0.0.x) * $0.1 }
        y = zip(points, self.weights).map { Interval.exact($0.0.y) * $0.1 }
        let numerator = Self.difference(
            Self.product(Self.derivative(x), self.weights),
            Self.product(x, Self.derivative(self.weights)))
        if numerator.allSatisfy({ $0.lower > 0 }) {
            uDirection = 1
        } else if numerator.allSatisfy({ $0.upper < 0 }) {
            uDirection = -1
        } else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original native graph coefficients do not certify a strict U derivative.")
        }
        let weightHull = Interval.enclosing(self.weights)
        guard let derivativeHull = Interval.enclosing(numerator).divided(by: weightHull * weightHull),
              derivativeHull.absoluteLowerBound > 0, derivativeHull.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph monotonicity exceeded finite derivative arithmetic.")
        }
        minimumAbsoluteUDerivative = derivativeHull.absoluteLowerBound
        uDerivativeHull = derivativeHull
    }

    var uBounds: ScalarInterval {
        get throws {
            try ScalarInterval(lower: min(points[0].x, points[points.count - 1].x),
                               upper: max(points[0].x, points[points.count - 1].x))
        }
    }

    func value(over normalized: ScalarInterval, tolerance: ModelingTolerance) throws -> (u: Interval, v: Interval) {
        try validate(normalized, tolerance: tolerance)
        if normalized.lower == normalized.upper, normalized.lower == 0 || normalized.lower == 1 {
            let point = normalized.lower == 0 ? points[0] : points[points.count - 1]
            return (.exact(point.x), .exact(point.y))
        }
        let t = Interval(lower: normalized.lower, upper: normalized.upper)
        // Nonnegative original Bernstein basis and partition of unity retain
        // the positive stored weight hull even when interval de Casteljau
        // loses the correlation between t and 1-t over a whole native interval.
        guard let denominator = Self.evaluate(weights, at: t)
                .intersection(with: Interval.enclosing(weights)), denominator.lower > 0,
              let u = Self.evaluate(x, at: t).divided(by: denominator),
              let v = Self.evaluate(y, at: t).divided(by: denominator),
              u.isFinite, v.isFinite else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph evaluation could not enclose a finite positive quotient.")
        }
        // Positive original weights and the native Bernstein partition of unity
        // independently retain the original Cartesian convex hull.
        let uHull = Interval(lower: points.map(\.x).min()!, upper: points.map(\.x).max()!)
        let vHull = Interval(lower: points.map(\.y).min()!, upper: points.map(\.y).max()!)
        guard let boundedU = u.intersection(with: uHull), let boundedV = v.intersection(with: vHull) else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph quotient and coefficient hulls are inconsistent.")
        }
        return (boundedU, boundedV)
    }

    /// A monotone original inverse bracket. An undecidable midpoint retains its full bracket.
    func inverse(u: Double, tolerance: ModelingTolerance,
                 proofUsage: inout OriginalTessellationProofUsage) throws -> ScalarInterval {
        let domain = try uBounds
        guard domain.contains(u) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original graph inversion requires a station in its native U range.")
        }
        if u == points[0].x || u == points[points.count - 1].x {
            try proofUsage.consume(depth: 0, tolerance: tolerance)
            let endpoint = u == points[0].x ? 0.0 : 1.0
            return try ScalarInterval(lower: endpoint, upper: endpoint)
        }
        var lower = 0.0
        var upper = 1.0
        for depth in 0...32 {
            try proofUsage.consume(depth: depth, tolerance: tolerance)
            let midpoint = lower + (upper - lower) * 0.5
            guard midpoint > lower, midpoint < upper else { break }
            let point = try value(over: ScalarInterval(lower: midpoint, upper: midpoint), tolerance: tolerance).u
            if point.upper < u {
                if uDirection > 0 { lower = midpoint } else { upper = midpoint }
            } else if point.lower > u {
                if uDirection > 0 { upper = midpoint } else { lower = midpoint }
            } else {
                // The strict original derivative gives a mean-value root bracket
                // even when the exact midpoint image cannot be distinguished.
                let residual = point - .exact(u)
                guard let displacement = Interval.exact(residual.absoluteUpperBound)
                    .divided(by: .exact(minimumAbsoluteUDerivative)) else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "Original graph inversion exceeded finite displacement arithmetic.")
                }
                let radius = displacement.absoluteUpperBound
                let newLower = max(lower, (midpoint - radius).nextDown)
                let newUpper = min(upper, (midpoint + radius).nextUp)
                guard newLower <= newUpper else {
                    throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                                      message: "Original graph inversion produced inconsistent root bounds.")
                }
                guard newLower > lower || newUpper < upper else { break }
                lower = newLower
                upper = newUpper
            }
        }
        try Task.checkCancellation()
        return try ScalarInterval(lower: lower, upper: upper)
    }

    func graphJet(over u: ScalarInterval, tolerance: ModelingTolerance,
                  proofUsage: inout OriginalTessellationProofUsage) throws -> GraphJet {
        let a = try inverse(u: u.lower, tolerance: tolerance, proofUsage: &proofUsage)
        let b = try inverse(u: u.upper, tolerance: tolerance, proofUsage: &proofUsage)
        let normalized = try ScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        let t = Interval(lower: normalized.lower, upper: normalized.upper)
        func homogeneousJet(_ controls: [Interval]) -> IntervalDerivativeJet {
            let first = Self.derivative(controls)
            let second = Self.derivative(first)
            return IntervalDerivativeJet(derivatives: [Self.evaluate(controls, at: t),
                Self.evaluate(first, at: t), Self.evaluate(second, at: t)])
        }
        let weightJet: IntervalDerivativeJet
        if weights.allSatisfy({ $0.lower == weights[0].lower && $0.upper == weights[0].upper }) {
            // Exact stored uniform weights imply the original Bernstein weight
            // polynomial is constant; partition of unity is coefficient authority.
            weightJet = .constant(weights[0], order: 2)
        } else {
            let original = homogeneousJet(weights)
            guard let boundedValue = original.value.intersection(with: Interval.enclosing(weights)) else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                                  message: "Original graph weight enclosures are inconsistent.")
            }
            weightJet = IntervalDerivativeJet(derivatives: [boundedValue,
                original.derivatives[1], original.derivatives[2]])
        }
        guard let reciprocal = weightJet.reciprocal() else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph jets could not certify the weight quotient.")
        }
        let uj = homogeneousJet(x) * reciprocal
        let vj = homogeneousJet(y) * reciprocal
        guard let ut = uj.derivatives[1].intersection(with: uDerivativeHull) else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph derivative enclosures are inconsistent.")
        }
        guard let first = vj.derivatives[1].divided(by: ut),
              let second = (vj.derivatives[2] * ut - vj.derivatives[1] * uj.derivatives[2])
                .divided(by: ut * ut * ut),
              first.isFinite, second.isFinite else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original graph inversion could not certify its derivative denominator.")
        }
        let coordinate = try value(over: normalized, tolerance: tolerance).v
        return GraphJet(v: coordinate, first: first, second: second, normalizedParameters: normalized)
    }

    private func validate(_ normalized: ScalarInterval, tolerance: ModelingTolerance) throws {
        guard normalized.lower >= 0, normalized.upper <= 1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original native graph evaluation requires its closed normalized interval.")
        }
    }

    private static func derivative(_ controls: [Interval]) -> [Interval] {
        guard controls.count > 1 else { return [.exact(0)] }
        let degree = Interval.exact(Double(controls.count - 1))
        return (0..<(controls.count - 1)).map { degree * (controls[$0 + 1] - controls[$0]) }
    }

    private static func evaluate(_ controls: [Interval], at t: Interval) -> Interval {
        var row = controls
        guard row.isEmpty == false else { return .exact(0) }
        let oneMinus = Interval.exact(1) - t
        while row.count > 1 {
            row = (0..<(row.count - 1)).map { oneMinus * row[$0] + t * row[$0 + 1] }
        }
        return row[0]
    }

    private static func difference(_ a: [Interval], _ b: [Interval]) -> [Interval] {
        zip(a, b).map { $0.0 - $0.1 }
    }

    private static func product(_ a: [Interval], _ b: [Interval]) -> [Interval] {
        let n = a.count - 1
        let m = b.count - 1
        var result = [Interval](repeating: .exact(0), count: n + m + 1)
        func binomial(_ n: Int, _ k: Int) -> Double {
            if k == 0 || k == n { return 1 }
            var value = 1
            for index in 1...min(k, n - k) { value = value * (n + 1 - index) / index }
            return Double(value)
        }
        for i in a.indices {
            for j in b.indices {
                // Integer binomials are exact here (degrees at most four); the
                // quotient itself is directed, never a rounded exact coefficient.
                let numerator = Interval.exact(binomial(n, i) * binomial(m, j))
                let denominator = Interval.exact(binomial(n + m, i + j))
                let factor = numerator.divided(by: denominator)!
                result[i + j] = result[i + j] + a[i] * b[j] * factor
            }
        }
        return result
    }
}
