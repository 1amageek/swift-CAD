import CADCore
import CADGeometry

/// Closed Faà di Bruno transport of original native derivatives, through order five.
package struct OriginalCurveJetComposition {
    package init() {}

    package func compose(_ curve: IntervalVectorDerivativeJet,
        parameter: IntervalDerivativeJet, order: Int,
        using execution: inout OriginalQueryExecution
    ) throws -> IntervalVectorDerivativeJet {
        guard order >= 0, order <= 5, curve.x.order >= order,
              curve.y.order >= order, curve.z.order >= order, parameter.order >= order else {
            throw GeometryConversionError.invalidInput("Original derivative composition needs a complete order-zero-through-five jet.")
        }
        let side = order + 1
        try execution.retainStorage(bytes:(side * side + 3 * side) * MemoryLayout<OutwardScalarInterval>.stride)
        var bell = Array(repeating: OutwardScalarInterval.exact(0), count: side * side)
        bell[0] = .exact(1)
        func binomial(_ n: Int, _ k: Int) -> Double {
            if k == 0 || k == n { return 1 }
            var result = 1.0
            for index in 1...min(k, n-k) { result = result * Double(n-index+1) / Double(index) }
            return result
        }
        if order > 0 {
            for n in 1...order {
                for k in 1...n {
                    var value = OutwardScalarInterval.exact(0)
                    for j in 1...(n-k+1) {
                        try execution.consumeWork(1)
                        value = value + .exact(binomial(n-1, j-1)) * parameter.derivatives[j]
                            * bell[(n-j) * side + k-1]
                    }
                    bell[n * side + k] = value
                }
            }
        }
        func component(_ source: IntervalDerivativeJet) throws -> IntervalDerivativeJet {
            var derivatives: [OutwardScalarInterval] = []
            derivatives.reserveCapacity(side)
            derivatives.append(source.value)
            if order > 0 { for n in 1...order {
                var value = OutwardScalarInterval.exact(0)
                for k in 1...n { try execution.consumeWork(1); value = value + source.derivatives[k] * bell[n * side + k] }
                guard value.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Original derivative composition has nonfinite closed bounds.") }
                derivatives.append(value)
            } }
            return .init(derivatives: derivatives)
        }
        return try .init(x: component(curve.x), y: component(curve.y), z: component(curve.z))
    }
}
