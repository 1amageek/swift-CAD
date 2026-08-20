enum FloatingPointExpansion {
    private static let splitter = 134_217_729.0

    static func difference(_ lhs: Double, _ rhs: Double) -> [Double] {
        let estimate = lhs - rhs
        let virtualRHS = lhs - estimate
        let virtualLHS = estimate + virtualRHS
        let rhsRoundoff = virtualRHS - rhs
        let lhsRoundoff = lhs - virtualLHS
        return eliminatingZeros([lhsRoundoff + rhsRoundoff, estimate])
    }

    static func sum(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        rhs.reduce(lhs) { partial, component in
            grow(partial, by: component)
        }
    }

    static func subtract(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        sum(lhs, rhs.map { -$0 })
    }

    static func product(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        var result: [Double] = []
        for left in lhs {
            for right in rhs {
                result = sum(result, twoProduct(left, right))
            }
        }
        return result
    }

    static func estimate(_ expansion: [Double]) -> Double {
        expansion.reduce(0.0, +)
    }

    static func sign(_ expansion: [Double]) -> RobustSign {
        guard expansion.allSatisfy(\.isFinite) else {
            return .indeterminate
        }
        for component in expansion.reversed() where component != 0.0 {
            return component < 0.0 ? .negative : .positive
        }
        return .zero
    }

    static func hornerSign(
        coefficients: [Double],
        at value: Double
    ) -> RobustSign {
        var result: [Double] = []
        var product: [Double] = []
        var scratch: [Double] = []
        let maximumComponentCount = max(1, coefficients.count * 2)
        result.reserveCapacity(maximumComponentCount)
        product.reserveCapacity(maximumComponentCount)
        scratch.reserveCapacity(maximumComponentCount)

        for coefficient in coefficients.reversed() {
            product.removeAll(keepingCapacity: true)
            for component in result {
                let pair = twoProductComponents(component, value)
                if pair.error != 0.0 {
                    grow(product, by: pair.error, into: &scratch)
                    swap(&product, &scratch)
                }
                if pair.estimate != 0.0 {
                    grow(product, by: pair.estimate, into: &scratch)
                    swap(&product, &scratch)
                } else if pair.error == 0.0 {
                    grow(product, by: 0.0, into: &scratch)
                    swap(&product, &scratch)
                }
            }
            swap(&result, &product)
            grow(result, by: coefficient, into: &scratch)
            swap(&result, &scratch)
        }
        return sign(result)
    }

    private static func grow(_ expansion: [Double], by value: Double) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(expansion.count + 1)
        grow(expansion, by: value, into: &result)
        return result
    }

    private static func grow(
        _ expansion: [Double],
        by value: Double,
        into result: inout [Double]
    ) {
        result.removeAll(keepingCapacity: true)
        result.reserveCapacity(expansion.count + 1)
        var accumulator = value
        for component in expansion {
            let pair = twoSum(accumulator, component)
            if pair.error != 0.0 {
                result.append(pair.error)
            }
            accumulator = pair.estimate
        }
        if accumulator != 0.0 || result.isEmpty {
            result.append(accumulator)
        }
    }

    private static func twoSum(_ lhs: Double, _ rhs: Double) -> (error: Double, estimate: Double) {
        let estimate = lhs + rhs
        let virtualRHS = estimate - lhs
        let virtualLHS = estimate - virtualRHS
        let rhsRoundoff = rhs - virtualRHS
        let lhsRoundoff = lhs - virtualLHS
        return (lhsRoundoff + rhsRoundoff, estimate)
    }

    private static func twoProduct(_ lhs: Double, _ rhs: Double) -> [Double] {
        let pair = twoProductComponents(lhs, rhs)
        return eliminatingZeros([pair.error, pair.estimate])
    }

    private static func twoProductComponents(
        _ lhs: Double,
        _ rhs: Double
    ) -> (error: Double, estimate: Double) {
        let estimate = lhs * rhs
        let lhsParts = split(lhs)
        let rhsParts = split(rhs)
        let firstError = estimate - lhsParts.high * rhsParts.high
        let secondError = firstError - lhsParts.low * rhsParts.high
        let thirdError = secondError - lhsParts.high * rhsParts.low
        let error = lhsParts.low * rhsParts.low - thirdError
        return (error, estimate)
    }

    private static func split(_ value: Double) -> (high: Double, low: Double) {
        let product = splitter * value
        let large = product - value
        let high = product - large
        return (high, value - high)
    }

    private static func eliminatingZeros(_ expansion: [Double]) -> [Double] {
        let result = expansion.filter { $0 != 0.0 }
        return result.isEmpty ? [0.0] : result
    }
}
