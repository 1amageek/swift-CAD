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
    private let firstX: [Interval]
    private let secondX: [Interval]
    private let firstY: [Interval]
    private let secondY: [Interval]
    private let firstWeight: [Interval]
    private let secondWeight: [Interval]
    let uDirection: Int
    let minimumAbsoluteUDerivative: Double
    let uDerivativeHull: Interval
    let endpointAffineResidualUpperBound: Double

    struct GraphJet: Sendable {
        let v: Interval
        let first: Interval
        let second: Interval
        let normalizedParameters: ScalarInterval
    }

    init(boundaryIndex: Int, nativeIndex: Int, nativeParameters: ScalarInterval,
         points: [Point2D], weights: [Double], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
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
        self.weights = try OriginalGraphBandStorage.map(weights, using: &execution) { value, execution in Interval.exact(value) }
        x = try OriginalGraphBandStorage.map(zip(points, self.weights), using: &execution) { pair, execution in Interval.exact(pair.0.x) * pair.1 }
        y = try OriginalGraphBandStorage.map(zip(points, self.weights), using: &execution) { pair, execution in Interval.exact(pair.0.y) * pair.1 }
        firstX = try Self.derivative(x, using: &execution)
        secondX = try Self.derivative(firstX, using: &execution)
        firstY = try Self.derivative(y, using: &execution)
        secondY = try Self.derivative(firstY, using: &execution)
        firstWeight = try Self.derivative(self.weights, using: &execution)
        secondWeight = try Self.derivative(firstWeight, using: &execution)
        let numerator = try Self.difference(
            Self.product(firstX, self.weights, using: &execution),
            Self.product(x, firstWeight, using: &execution), using: &execution)
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
        // Elevation and multiplication use outward arithmetic over original
        // homogeneous coefficients; near-affine data never becomes exact data.
        let degree = points.count - 1
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: degree + 2, of: Interval.self))
        var elevatedX = [Interval](repeating: .exact(0), count: degree + 2)
        elevatedX[0] = x[0]
        elevatedX[degree + 1] = x[degree]
        for index in 1...degree {
            let ratio = Interval.exact(Double(index)).divided(by: .exact(Double(degree + 1)))!
            elevatedX[index] = ratio * x[index - 1] + (.exact(1) - ratio) * x[index]
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Interval.self))
        let affineWeight = try Self.product([.exact(points[0].x), .exact(points[degree].x)], self.weights, using: &execution)
        let residual = try Self.difference(elevatedX, affineWeight, using: &execution)
        guard let bound = Interval.exact(residual.reduce(0) { max($0, $1.absoluteUpperBound) })
            .divided(by: .exact(weights.min()!)), bound.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph endpoint residual exceeded finite arithmetic.")
        }
        endpointAffineResidualUpperBound = bound.absoluteUpperBound
    }

    var uBounds: ScalarInterval {
        get throws {
            try ScalarInterval(lower: min(points[0].x, points[points.count - 1].x),
                               upper: max(points[0].x, points[points.count - 1].x))
        }
    }

    func value(over normalized: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> (u: Interval, v: Interval) {
        try validate(normalized, tolerance: tolerance)
        if normalized.lower == normalized.upper, normalized.lower == 0 || normalized.lower == 1 {
            let point = normalized.lower == 0 ? points[0] : points[points.count - 1]
            return (.exact(point.x), .exact(point.y))
        }
        let t = Interval(lower: normalized.lower, upper: normalized.upper)
        // Nonnegative original Bernstein basis and partition of unity retain
        // the positive stored weight hull even when interval de Casteljau
        // loses the correlation between t and 1-t over a whole native interval.
        guard let denominator = try Self.evaluate(weights, at: t, using: &execution)
                .intersection(with: Interval.enclosing(weights)), denominator.lower > 0,
              let u = try Self.evaluate(x, at: t, using: &execution).divided(by: denominator),
              let v = try Self.evaluate(y, at: t, using: &execution).divided(by: denominator),
              u.isFinite, v.isFinite else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph evaluation could not enclose a finite positive quotient.")
        }
        // Positive original weights and the native Bernstein partition of unity
        // independently retain the original Cartesian convex hull.
        var uLower = points[0].x, uUpper = uLower
        var vLower = points[0].y, vUpper = vLower
        for point in points {
            try execution.consumeWork(1)
            uLower = min(uLower, point.x); uUpper = max(uUpper, point.x)
            vLower = min(vLower, point.y); vUpper = max(vUpper, point.y)
        }
        let uHull = Interval(lower: uLower, upper: uUpper)
        let vHull = Interval(lower: vLower, upper: vUpper)
        guard let boundedU = u.intersection(with: uHull), let boundedV = v.intersection(with: vHull) else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph quotient and coefficient hulls are inconsistent.")
        }
        return (boundedU, boundedV)
    }

    /// A monotone original inverse bracket. An undecidable midpoint retains its full bracket.
    func inverse(u: Double, tolerance: ModelingTolerance,
                 using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        let domain = try uBounds
        guard domain.contains(u) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original graph inversion requires a station in its native U range.")
        }
        if u == points[0].x || u == points[points.count - 1].x {
            try execution.visitGeometricCell(depth: 0)
            let endpoint = u == points[0].x ? 0.0 : 1.0
            return try ScalarInterval(lower: endpoint, upper: endpoint)
        }
        try execution.visitGeometricCell(depth: 0)
        let delta = Interval.exact(points[points.count - 1].x) - .exact(points[0].x)
        let residual = Interval(lower: -endpointAffineResidualUpperBound,
                                upper: endpointAffineResidualUpperBound)
        guard let initial = (Interval.exact(u) - .exact(points[0].x) + residual)
            .divided(by: delta)?.intersection(with: Interval(lower: 0, upper: 1)), initial.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph affine residual could not enclose its inverse.")
        }
        var lower = initial.lower
        var upper = initial.upper
        for depth in 0...32 {
            try execution.visitGeometricCell(depth: depth)
            let midpoint = lower + (upper - lower) * 0.5
            guard midpoint > lower, midpoint < upper else { break }
            let point = try value(over: ScalarInterval(lower: midpoint, upper: midpoint), tolerance: tolerance, using: &execution).u
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
        try CurrentTaskCancellationChecker().checkCancellation()
        return try ScalarInterval(lower: lower, upper: upper)
    }

    func graphJet(over u: ScalarInterval, tolerance: ModelingTolerance,
                  using execution: inout OriginalQueryExecution) throws -> GraphJet {
        let a = try inverse(u: u.lower, tolerance: tolerance, using: &execution)
        let b = u.lower == u.upper ? a
            : try inverse(u: u.upper, tolerance: tolerance, using: &execution)
        let normalized = try ScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        let t = Interval(lower: normalized.lower, upper: normalized.upper)
        func homogeneousJet(_ controls: [Interval], first: [Interval], second: [Interval], using execution: inout OriginalQueryExecution) throws -> IntervalDerivativeJet {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            return try IntervalDerivativeJet(derivatives: [Self.evaluate(controls, at: t, using: &execution),
                Self.evaluate(first, at: t, using: &execution), Self.evaluate(second, at: t, using: &execution)])
        }
        let weightJet: IntervalDerivativeJet
        if weights.allSatisfy({ $0.lower == weights[0].lower && $0.upper == weights[0].upper }) {
            // Exact stored uniform weights imply the original Bernstein weight
            // polynomial is constant; partition of unity is coefficient authority.
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            weightJet = IntervalDerivativeJet(derivatives: [weights[0], .exact(0), .exact(0)])
        } else {
            let original = try homogeneousJet(weights, first: firstWeight, second: secondWeight, using: &execution)
            guard let boundedValue = original.value.intersection(with: Interval.enclosing(weights)) else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                                  message: "Original graph weight enclosures are inconsistent.")
            }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            weightJet = IntervalDerivativeJet(derivatives: [boundedValue,
                original.derivatives[1], original.derivatives[2]])
        }
        guard let reciprocal = try Self.reciprocal(weightJet, using: &execution) else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                              message: "Original graph jets could not certify the weight quotient.")
        }
        let ux = try homogeneousJet(x, first: firstX, second: secondX, using: &execution)
        let uj = try Self.multiply(ux, reciprocal, using: &execution)
        let vy = try homogeneousJet(y, first: firstY, second: secondY, using: &execution)
        let vj = try Self.multiply(vy, reciprocal, using: &execution)
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
        let coordinate = try value(over: normalized, tolerance: tolerance, using: &execution).v
        return GraphJet(v: coordinate, first: first, second: second, normalizedParameters: normalized)
    }

    private static func reciprocal(_ source: IntervalDerivativeJet,
        using execution: inout OriginalQueryExecution) throws -> IntervalDerivativeJet? {
        guard let first = Interval.exact(1).divided(by: source.value) else { return nil }
        var result: [Interval] = []
        try OriginalGraphBandStorage.reserve(3, in: &result, using: &execution)
        result.append(first)
        for n in 1...2 {
            var sum = Interval.exact(0)
            for k in 1...n {
                try execution.consumeWork(1)
                let factor = Interval.exact(Double(n == 2 && k == 1 ? 2 : 1))
                let term = factor * source.derivatives[k] * result[n - k]
                sum = sum + term
            }
            result.append(-(sum * first))
        }
        return IntervalDerivativeJet(derivatives: result)
    }

    private static func multiply(_ lhs: IntervalDerivativeJet, _ rhs: IntervalDerivativeJet,
        using execution: inout OriginalQueryExecution) throws -> IntervalDerivativeJet {
        var result: [Interval] = []
        try OriginalGraphBandStorage.reserve(3, in: &result, using: &execution)
        for n in 0...2 {
            var sum = Interval.exact(0)
            for k in 0...n {
                try execution.consumeWork(1)
                let factor = Interval.exact(Double(n == 2 && k == 1 ? 2 : 1))
                let term = factor * lhs.derivatives[k] * rhs.derivatives[n - k]
                sum = sum + term
            }
            result.append(sum)
        }
        return IntervalDerivativeJet(derivatives: result)
    }

    private func validate(_ normalized: ScalarInterval, tolerance: ModelingTolerance) throws {
        guard normalized.lower >= 0, normalized.upper <= 1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original native graph evaluation requires its closed normalized interval.")
        }
    }

    private static func derivative(_ controls: [Interval], using execution: inout OriginalQueryExecution) throws -> [Interval] {
        guard controls.count > 1 else {
            try execution.retainStorage(bytes: MemoryLayout<Interval>.stride)
            return [.exact(0)]
        }
        let degree = Interval.exact(Double(controls.count - 1))
        return try OriginalGraphBandStorage.map(0..<(controls.count - 1), using: &execution) { index, execution in degree * (controls[index + 1] - controls[index]) }
    }

    private static func evaluate(_ controls: [Interval], at t: Interval, using execution: inout OriginalQueryExecution) throws -> Interval {
        var row = controls
        guard row.isEmpty == false else { return .exact(0) }
        let oneMinus = Interval.exact(1) - t
        while row.count > 1 {
            row = try OriginalGraphBandStorage.map(0..<(row.count - 1), using: &execution) { index, execution in oneMinus * row[index] + t * row[index + 1] }
        }
        return row[0]
    }

    private static func difference(_ a: [Interval], _ b: [Interval], using execution: inout OriginalQueryExecution) throws -> [Interval] {
        try OriginalGraphBandStorage.map(zip(a, b), using: &execution) { pair, execution in pair.0 - pair.1 }
    }

    private static func product(_ a: [Interval], _ b: [Interval], using execution: inout OriginalQueryExecution) throws -> [Interval] {
        let n = a.count - 1
        let m = b.count - 1
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: n + m + 1, of: Interval.self))
        var result = [Interval](repeating: .exact(0), count: n + m + 1)
        func binomial(_ n: Int, _ k: Int) -> Double {
            if k == 0 || k == n { return 1 }
            var value = 1
            for index in 1...min(k, n - k) { value = value * (n + 1 - index) / index }
            return Double(value)
        }
        for i in a.indices {
            for j in b.indices {
                try execution.consumeWork(1)
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
