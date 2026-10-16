import CADCore
import CADGeometry

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Gauss–Legendre nodes and weights on [−1, 1]. With `count` nodes the rule integrates every
/// polynomial of degree below `2 · count` exactly.
struct GaussLegendreRule: Sendable {
    let nodes: [Double]
    let weights: [Double]

    /// Nodes and weights by Newton iteration on Pₙ.
    init(count: Int) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(count: count, using: &execution)
    }

    init(count: Int, using execution: inout OriginalQueryExecution) throws {
        guard count > 0 else { throw ExactScalarFailure.countOverflow }
        var nodes: [Double] = [], weights: [Double] = []
        for index in 1...count {
            try execution.consumeWork(1)
            var x = cos(.pi * (Double(index) - 0.25) / (Double(count) + 0.5))
            var derivative = 0.0
            for _ in 0..<100 {
                try execution.consumeWork(1)
                var p0 = 1.0, p1 = x
                if count > 1 {
                    for order in 2...count {
                        try execution.consumeWork(1)
                        let p2 = ((2 * Double(order) - 1) * x * p1 - (Double(order) - 1) * p0) / Double(order)
                        p0 = p1
                        p1 = p2
                    }
                }
                derivative = Double(count) * (x * p1 - p0) / (x * x - 1)
                let step = p1 / derivative
                x -= step
                if abs(step) < 1e-16 { break }
            }
            try OriginalParameterQueryStorage.append(x, to: &nodes, using: &execution)
            try OriginalParameterQueryStorage.append(2 / ((1 - x * x) * derivative * derivative), to: &weights, using: &execution)
        }
        self.nodes = nodes
        self.weights = weights
    }


    /// Integrates with the caller owner and visits each retained node once.
    func integrate(from low: Double, to high: Double,
        using execution: inout OriginalQueryExecution,
        _ integrand: (Double, inout OriginalQueryExecution) throws -> Double
    ) throws -> Double {
        let half = (high - low) / 2, middle = (high + low) / 2
        var sum = 0.0
        for (node, weight) in zip(nodes, weights) {
            try execution.consumeWork(1)
            sum += weight * half * (try integrand(middle + half * node, &execution))
        }
        return sum
    }

}
