import CADCore

enum FloatingPointExpansion {
    private static let splitter = 134_217_729.0

    static func difference(_ lhs: Double, _ rhs: Double) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try difference(lhs, rhs, using: &execution)
    }

    static func sum(_ lhs: [Double], _ rhs: [Double]) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sum(lhs, rhs, using: &execution)
    }

    static func subtract(_ lhs: [Double], _ rhs: [Double]) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subtract(lhs, rhs, using: &execution)
    }

    static func product(_ lhs: [Double], _ rhs: [Double]) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try product(lhs, rhs, using: &execution)
    }

    static func estimate(_ expansion: [Double]) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try estimate(expansion, using: &execution)
    }

    static func sign(_ expansion: [Double]) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sign(expansion, using: &execution)
    }

    private static func twoDifference(_ lhs: Double, _ rhs: Double) -> (error: Double, estimate: Double) {
        let estimate = lhs - rhs
        let virtualRHS = lhs - estimate
        let virtualLHS = estimate + virtualRHS
        let rhsRoundoff = virtualRHS - rhs
        let lhsRoundoff = lhs - virtualLHS
        return (lhsRoundoff + rhsRoundoff, estimate)
    }

    /// One direct core owns expansion scratch; fixed error-free transforms allocate no storage.
    static func difference<A: ExactScalarAdmission & ~Copyable>(_ lhs: Double, _ rhs: Double,
        using execution: inout A) throws -> [Double] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let result = try components(twoDifference(lhs, rhs), using: &execution)
        try execution.checkpoint(); return result
    }

    static func sum<A: ExactScalarAdmission & ~Copyable>(_ lhs: [Double], _ rhs: [Double],
        using execution: inout A) throws -> [Double] {
        try execution.checkpoint()
        var result = lhs
        for component in rhs { result = try grow(result, by: component, using: &execution) }
        try execution.checkpoint(); return result
    }

    static func subtract<A: ExactScalarAdmission & ~Copyable>(_ lhs: [Double], _ rhs: [Double],
        using execution: inout A) throws -> [Double] {
        try execution.checkpoint()
        try OriginalCoefficientAllocation.reserve(count: rhs.count, of: Double.self, using: &execution)
        var negative: [Double] = []; negative.reserveCapacity(rhs.count)
        for component in rhs { try execution.consumeWork(1); negative.append(-component) }
        let result = try sum(lhs, negative, using: &execution)
        try execution.checkpoint(); return result
    }

    static func product<A: ExactScalarAdmission & ~Copyable>(_ lhs: [Double], _ rhs: [Double],
        using execution: inout A) throws -> [Double] {
        try execution.checkpoint()
        var result: [Double] = []
        for left in lhs { for right in rhs {
            try execution.consumeWork(1)
            let pair = try components(twoProductComponents(left, right), using: &execution)
            result = try sum(result, pair, using: &execution)
        } }
        try execution.checkpoint(); return result
    }

    static func estimate<A: ExactScalarAdmission & ~Copyable>(_ expansion: [Double],
        using execution: inout A) throws -> Double {
        try execution.checkpoint()
        var result = 0.0
        for component in expansion { try execution.consumeWork(1); result += component }
        try execution.checkpoint(); return result
    }

    static func sign<A: ExactScalarAdmission & ~Copyable>(_ expansion: [Double],
        using execution: inout A) throws -> RobustSign {
        try execution.checkpoint()
        for component in expansion {
            try execution.consumeWork(1)
            guard component.isFinite else { try execution.checkpoint(); return .indeterminate }
        }
        for component in expansion.reversed() {
            try execution.consumeWork(1)
            if component != 0 { try execution.checkpoint(); return component < 0 ? .negative : .positive }
        }
        try execution.checkpoint(); return .zero
    }

    private static func components<A: ExactScalarAdmission & ~Copyable>(
        _ pair: (error: Double, estimate: Double), using execution: inout A) throws -> [Double] {
        try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
        var result: [Double] = []; result.reserveCapacity(2)
        if pair.error != 0 { result.append(pair.error) }
        if pair.estimate != 0 { result.append(pair.estimate) }
        if result.isEmpty { result.append(0) }
        return result
    }

    private static func grow<A: ExactScalarAdmission & ~Copyable>(_ expansion: [Double],
        by value: Double, using execution: inout A) throws -> [Double] {
        let count = expansion.count.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try OriginalCoefficientAllocation.reserve(count: count.partialValue, of: Double.self, using: &execution)
        var result: [Double] = []; result.reserveCapacity(count.partialValue)
        var accumulator = value
        for component in expansion {
            try execution.consumeWork(1)
            let pair = twoSum(accumulator, component)
            if pair.error != 0 { result.append(pair.error) }
            accumulator = pair.estimate
        }
        if accumulator != 0 || result.isEmpty { result.append(accumulator) }
        return result
    }

    static func hornerSign<A: ExactScalarAdmission & ~Copyable>(
        coefficients: [Double],
        at value: Double,
        using execution: inout A
    ) throws -> RobustSign {
        var result: [Double] = []
        var product: [Double] = []
        var scratch: [Double] = []
        let maximumComponentCount = max(1, try exactScalarCount(coefficients.count, 2, multiply: true))
        try OriginalCoefficientAllocation.reserve(count: maximumComponentCount, of: Double.self, using: &execution)
        result.reserveCapacity(maximumComponentCount)
        try OriginalCoefficientAllocation.reserve(count: maximumComponentCount, of: Double.self, using: &execution)
        product.reserveCapacity(maximumComponentCount)
        try OriginalCoefficientAllocation.reserve(count: maximumComponentCount, of: Double.self, using: &execution)
        scratch.reserveCapacity(maximumComponentCount)


        func accumulate(_ expansion: [Double], by value: Double,
            into output: inout [Double], using execution: inout A) throws {
            output.removeAll(keepingCapacity: true)
            let required = try exactScalarCount(expansion.count, 1, multiply: false)
            if required > output.capacity {
                try OriginalCoefficientAllocation.reserve(count: required, of: Double.self, using: &execution)
                output.reserveCapacity(required)
            }
            var accumulator = value
            for component in expansion {
                try execution.consumeWork(1)
                let pair = twoSum(accumulator, component)
                if pair.error != 0.0 { output.append(pair.error) }
                accumulator = pair.estimate
            }
            if accumulator != 0.0 || output.isEmpty { output.append(accumulator) }
        }

        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            product.removeAll(keepingCapacity: true)
            for component in result {
                try execution.consumeWork(1)
                let pair = twoProductComponents(component, value)
                if pair.error != 0.0 {
                    try accumulate(product, by: pair.error, into: &scratch, using: &execution)
                    swap(&product, &scratch)
                }
                if pair.estimate != 0.0 {
                    try accumulate(product, by: pair.estimate, into: &scratch, using: &execution)
                    swap(&product, &scratch)
                } else if pair.error == 0.0 {
                    try accumulate(product, by: 0.0, into: &scratch, using: &execution)
                    swap(&product, &scratch)
                }
            }
            swap(&result, &product)
            try accumulate(result, by: coefficient, into: &scratch, using: &execution)
            swap(&result, &scratch)
        }
        return try sign(result, using: &execution)
    }

    private static func twoSum(_ lhs: Double, _ rhs: Double) -> (error: Double, estimate: Double) {
        let estimate = lhs + rhs
        let virtualRHS = estimate - lhs
        let virtualLHS = estimate - virtualRHS
        let rhsRoundoff = rhs - virtualRHS
        let lhsRoundoff = lhs - virtualLHS
        return (lhsRoundoff + rhsRoundoff, estimate)
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


}
