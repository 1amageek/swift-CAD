import CADCore

/// The original ideal conic's rational construction parameter, not its fitted net.
package struct OriginalCircularRationalParameterLaw: Sendable {
    private let start: Double
    private let end: Double

    package init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    package func jet(over fraction: OutwardScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: (Int) throws -> Void) throws -> IntervalDerivativeJet {
        try consumeWork()
        guard start.isFinite, end.isFinite, start != end, order >= 0, order <= 5,
              fraction.isFinite, fraction.lower >= 0, fraction.upper <= 1 else {
            throw failure(.invalidInput, "An original circular construction chart needs finite directed endpoints and a contained fraction.", tolerance)
        }
        let half = (OutwardScalarInterval.exact(end) - .exact(start)) * .exact(0.5)
        // Positive half-weight is the original quadratic's single atan atlas.
        // Wider arcs are split by the construction owner before this proof.
        guard half.isFinite, half.absoluteUpperBound < Double.pi * 0.5 else {
            throw failure(.resourceLimitExceeded, "The original circular half-angle does not retain one positive rational chart.", tolerance)
        }
        try consumeWork()
        let label = SurfaceIntervalJet.constant(half)
        let c = try CanonicalSphereAngularPhase.harmonic(of: label, cosine: true,
            consumeWork: consumeWork).value
        let s = try CanonicalSphereAngularPhase.harmonic(of: label, cosine: false,
            consumeWork: consumeWork).value
        let d = OutwardScalarInterval.exact(1) - c
        guard c.lower > 0, c.isFinite, s.isFinite else {
            throw failure(.resourceLimitExceeded, "The original conic half-weight has no positive closed proof.", tolerance)
        }
        func quadratic(_ value: Double) -> OutwardScalarInterval {
            .exact(value) * (.exact(1) - .exact(value))
        }
        let firstQ = quadratic(fraction.lower), lastQ = quadratic(fraction.upper)
        let q = OutwardScalarInterval(lower: max(0, min(firstQ.lower, lastQ.lower)),
            upper: fraction.lower <= 0.5 && fraction.upper >= 0.5
                ? 0.25 : min(0.25, max(firstQ.upper, lastQ.upper)))
        let x = c + .exact(2) * d * q
        let y = s * (.exact(2) * fraction - .exact(1))
        guard x.lower > 0, let ratio = y.divided(by: x), ratio.isFinite else {
            throw failure(.resourceLimitExceeded, "The complete original conic fraction has no single inverse-angle chart.", tolerance)
        }
        func atan(_ value: OutwardScalarInterval) throws -> OutwardScalarInterval {
            func endpoint(_ x: Double) throws -> OutwardScalarInterval {
                try consumeWork()
                let magnitude = abs(x)
                let positive: OutwardScalarInterval
                if magnitude <= 1 {
                    positive = try CertifiedRotationTrigonometry.inverseTangent(.exact(magnitude),
                        tolerance: tolerance, consumeWork: consumeWork)
                } else {
                    guard let reciprocal = OutwardScalarInterval.exact(1).divided(by: .exact(magnitude)) else {
                        throw failure(.resourceLimitExceeded, "The original conic reciprocal inverse chart is not finite.", tolerance)
                    }
                    positive = CanonicalSphereAngularPhase.piBounds * .exact(0.5)
                        - (try CertifiedRotationTrigonometry.inverseTangent(reciprocal,
                            tolerance: tolerance, consumeWork: consumeWork))
                }
                return x < 0 ? -positive : positive
            }
            // Atan is monotone on the entire positive-half-weight chart.
            // Endpoint enclosures use its reciprocal identity, never a libm station.
            let first = try endpoint(value.lower), last = try endpoint(value.upper)
            return .init(lower: first.lower, upper: last.upper)
        }
        let middle = OutwardScalarInterval.exact(start) * .exact(0.5)
            + .exact(end) * .exact(0.5)
        guard let angle = try atan(ratio).divided(by: CanonicalSphereAngularPhase.scaleBounds) else {
            throw failure(.resourceLimitExceeded, "The original conic angle cannot retain its authored label gain.", tolerance)
        }
        let native: OutwardScalarInterval
        if fraction.lower == 0, fraction.upper == 0 { native = .exact(start) }
        else if fraction.lower == 1, fraction.upper == 1 { native = .exact(end) }
        else {
            guard let retained = (middle + angle).intersection(with: .init(lower: min(start, end), upper: max(start, end))) else {
                throw failure(.classificationFailure, "The original circular station lost its directed source interval.", tolerance)
            }
            native = retained
        }
        try consumeStorage((order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
        var derivatives: [OutwardScalarInterval] = []
        derivatives.reserveCapacity(order + 1)
        derivatives.append(native)
        if order == 0 { return .init(derivatives: derivatives) }
        try consumeStorage(2 * order * MemoryLayout<OutwardScalarInterval>.stride)
        var w: [OutwardScalarInterval] = [], inverse: [OutwardScalarInterval] = []
        w.reserveCapacity(order); inverse.reserveCapacity(order)
        w.append(.exact(1) - .exact(2) * d * q)
        if order > 1 { w.append(.exact(2) * d * (.exact(2) * fraction - .exact(1))) }
        if order > 2 { w.append(.exact(4) * d) }
        while w.count < order { try consumeWork(); w.append(.exact(0)) }
        guard w[0].lower > 0, let initial = OutwardScalarInterval.exact(1).divided(by: w[0]),
              let rate = (.exact(2) * s).divided(by: CanonicalSphereAngularPhase.scaleBounds) else {
            throw failure(.resourceLimitExceeded, "The original rational angular derivative has no positive denominator.", tolerance)
        }
        inverse.append(initial)
        func binomial(_ n: Int, _ k: Int) -> Double {
            if k == 0 || k == n { return 1 }
            var result = 1.0
            for index in 1...min(k, n-k) { result = result * Double(n-index+1) / Double(index) }
            return result
        }
        if order > 1 {
            for n in 1..<order {
                var sum = OutwardScalarInterval.exact(0)
                for k in 1...n {
                    try consumeWork()
                    sum = sum + .exact(binomial(n, k)) * w[k] * inverse[n-k]
                }
                inverse.append(-(sum * initial))
            }
        }
        for field in inverse { try consumeWork(); derivatives.append(rate * field) }
        guard derivatives.allSatisfy({ $0.isFinite }) else {
            throw failure(.resourceLimitExceeded, "Original circular chart derivatives exceed finite interval precision.", tolerance)
        }
        return .init(derivatives: derivatives)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
