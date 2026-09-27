import Foundation

/// Gauss–Legendre nodes and weights on [−1, 1]. With `count` nodes the rule integrates every
/// polynomial of degree below `2 · count` exactly.
struct GaussLegendreRule: Sendable {
    let nodes: [Double]
    let weights: [Double]

    /// Nodes and weights by Newton iteration on Pₙ.
    init(count: Int) {
        var nodes: [Double] = [], weights: [Double] = []
        for index in 1...count {
            var x = cos(.pi * (Double(index) - 0.25) / (Double(count) + 0.5))
            var derivative = 0.0
            for _ in 0..<100 {
                var p0 = 1.0, p1 = x
                if count > 1 {
                    for order in 2...count {
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
            nodes.append(x)
            weights.append(2 / ((1 - x * x) * derivative * derivative))
        }
        self.nodes = nodes
        self.weights = weights
    }

    /// ∫ f over [low, high].
    func integrate(from low: Double, to high: Double, _ integrand: (Double) throws -> Double) rethrows -> Double {
        let half = (high - low) / 2, middle = (high + low) / 2
        var sum = 0.0
        for (node, weight) in zip(nodes, weights) {
            sum += weight * half * (try integrand(middle + half * node))
        }
        return sum
    }
}
