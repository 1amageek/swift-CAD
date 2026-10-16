import CADCore

/// Checked admission immediately preceding concrete coefficient storage growth.
struct OriginalCoefficientAllocation {
    static func reserve<Element, A: ExactScalarAdmission & ~Copyable>(count: Int, of: Element.Type,
        using execution: inout A) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original coefficient byte count overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }
    /// Admits each replacement buffer before a query-local array grows.
    static func reserveAppend<Element, A: ExactScalarAdmission & ~Copyable>(to array: inout [Element],
        capacity: inout Int, using execution: inout A) throws {
        guard capacity >= 0, array.count <= capacity else { throw ExactScalarFailure.invalidEvidence }
        guard array.count == capacity else { return }
        let next = capacity == 0 ? 1 : try exactScalarCount(capacity, 2, multiply: true)
        try reserve(count: next, of: Element.self, using: &execution)
        array.reserveCapacity(next)
        capacity = next
    }

    /// Owns checked result storage and visits while the caller retains all geometry formulas.
    static func map<Elements: RandomAccessCollection, Result, A: ExactScalarAdmission & ~Copyable>(
        elements: Elements, using execution: inout A,
        _ transform: (Elements.Element, inout A) throws -> Result) throws -> [Result] {
        try reserve(count: elements.count, of: Result.self, using: &execution)
        var result: [Result] = []; result.reserveCapacity(elements.count)
        for element in elements {
            try execution.consumeWork(1)
            result.append(try transform(element, &execution))
        }
        return result
    }
    static func map<First: RandomAccessCollection, Second: RandomAccessCollection, Result,
        A: ExactScalarAdmission & ~Copyable>(first: First, second: Second, using execution: inout A,
        _ transform: ((First.Element, Second.Element), inout A) throws -> Result) throws -> [Result] {
        let count = min(first.count, second.count)
        try reserve(count: count, of: Result.self, using: &execution)
        var result: [Result] = []; result.reserveCapacity(count)
        for pair in zip(first, second) {
            try execution.consumeWork(1)
            result.append(try transform(pair, &execution))
        }
        return result
    }
    static func singleton<Element, A: ExactScalarAdmission & ~Copyable>(_ element: Element,
        using execution: inout A) throws -> [Element] {
        try reserve(count: 1, of: Element.self, using: &execution)
        return [element]
    }
    static func flatten<Element, A: ExactScalarAdmission & ~Copyable>(rows: [[Element]],
        using execution: inout A) throws -> [Element] {
        var count = 0
        for row in rows {
            try execution.consumeWork(1)
            let next = count.addingReportingOverflow(row.count)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            count = next.partialValue
        }
        try reserve(count: count, of: Element.self, using: &execution)
        var result: [Element] = []; result.reserveCapacity(count)
        for row in rows { for element in row {
            try execution.consumeWork(1); result.append(element)
        } }
        return result
    }
}
