import CADCore

/// Collection operations used while evaluating retained analytic equations.
enum CertifiedAnalyticCurveEvaluation {
    static func map<Values: Sequence, Result, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values, using execution: inout A,
        _ transform: (Values.Element, inout A) throws -> Result
    ) throws -> [Result] {
        var result: [Result] = []
        var capacity = 0
        for value in values {
            try execution.consumeWork(1)
            let transformed = try transform(value, &execution)
            try append(transformed, to: &result, using: &execution, capacity: &capacity)
        }
        return result
    }

    static func map<Values: Collection, Result, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values,
        using execution: inout A,
        _ transform: (Values.Element, inout A) throws -> Result
    ) throws -> [Result] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: values.count, of: Result.self))
        var result: [Result] = []
        result.reserveCapacity(values.count)
        for value in values {
            try execution.consumeWork(1)
            result.append(try transform(value, &execution))
        }
        return result
    }

    static func append<Element, A: ExactScalarAdmission & ~Copyable>(
        _ element: Element, to values: inout [Element],
        using execution: inout A, capacity: inout Int
    ) throws {
        try OriginalCoefficientAllocation.reserveAppend(to: &values, capacity: &capacity, using: &execution)
        values.append(element)
    }

    static func reserveCapacity<Element, A: ExactScalarAdmission & ~Copyable>(
        _ count: Int, in values: inout [Element],
        using execution: inout A
    ) throws {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Element.self))
        values.reserveCapacity(count)
    }

    static func repeated<Element, A: ExactScalarAdmission & ~Copyable>(
        _ value: Element, count: Int,
        using execution: inout A
    ) throws -> [Element] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Element.self))
        try execution.consumeWork(count)
        return Array(repeating: value, count: count)
    }

    static func filter<Values: Collection, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values, using execution: inout A,
        _ predicate: (Values.Element, inout A) throws -> Bool
    ) throws -> [Values.Element] {
        var result: [Values.Element] = []
        var capacity = 0
        for value in values {
            try execution.consumeWork(1)
            if try predicate(value, &execution) {
                try append(value, to: &result, using: &execution, capacity: &capacity)
            }
        }
        return result
    }

    static func compactMap<Values: Collection, Result, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values, using execution: inout A,
        _ transform: (Values.Element, inout A) throws -> Result?
    ) throws -> [Result] {
        var result: [Result] = []
        var capacity = 0
        for value in values {
            try execution.consumeWork(1)
            if let transformed = try transform(value, &execution) {
                try append(transformed, to: &result, using: &execution, capacity: &capacity)
            }
        }
        return result
    }

    static func sorted<Element: Comparable, A: ExactScalarAdmission & ~Copyable>(
        _ values: [Element], using execution: inout A
    ) throws -> [Element] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: values.count, of: Element.self))
        return try values.sorted { first, second in
            try execution.consumeWork(1)
            return first < second
        }
    }

    static func sorted<Element, A: ExactScalarAdmission & ~Copyable>(
        _ values: [Element], using execution: inout A,
        by compare: (Element, Element) throws -> Bool
    ) throws -> [Element] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: values.count, of: Element.self))
        return try values.sorted { first, second in
            try execution.consumeWork(1)
            return try compare(first, second)
        }
    }

    static func values<Element, A: ExactScalarAdmission & ~Copyable>(_ first: Element, using execution: inout A) throws -> [Element] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Element.self))
        return [first]
    }

    static func values<Element, A: ExactScalarAdmission & ~Copyable>(_ first: Element, _ second: Element,
        using execution: inout A) throws -> [Element] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Element.self))
        return [first, second]
    }
}
