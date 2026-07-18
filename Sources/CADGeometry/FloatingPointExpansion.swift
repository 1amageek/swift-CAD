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
        for component in expansion.reversed() where component != 0.0 {
            return component < 0.0 ? .negative : .positive
        }
        return .zero
    }

    private static func grow(_ expansion: [Double], by value: Double) -> [Double] {
        var result: [Double] = []
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
        return result
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
        let estimate = lhs * rhs
        let lhsParts = split(lhs)
        let rhsParts = split(rhs)
        let firstError = estimate - lhsParts.high * rhsParts.high
        let secondError = firstError - lhsParts.low * rhsParts.high
        let thirdError = secondError - lhsParts.high * rhsParts.low
        let error = lhsParts.low * rhsParts.low - thirdError
        return eliminatingZeros([error, estimate])
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
