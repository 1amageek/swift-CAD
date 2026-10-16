/// Requested typed buffers for original graph preparation and mesh consumers.
package enum OriginalGraphBandStorage {
    package static func reserve<Element, A: ExactScalarAdmission & ~Copyable>(_ count: Int,
        in values: inout [Element], using a: inout A) throws {
        guard count >= 0 else { throw ExactScalarFailure.countOverflow }
        guard count > values.capacity else { return }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Element.self))
        values.reserveCapacity(count)
    }
    package static func append<Element, A: ExactScalarAdmission & ~Copyable>(_ element: Element,
        to values: inout [Element], using a: inout A) throws {
        if values.count == values.capacity {
            let growth = values.capacity.multipliedReportingOverflow(by: 2)
            guard !growth.overflow else { throw ExactScalarFailure.countOverflow }
            try reserve(max(1, growth.partialValue), in: &values, using: &a)
        }
        values.append(element)
    }
    package static func map<Values: Sequence, Result, A: ExactScalarAdmission & ~Copyable>(_ values: Values,
        using a: inout A, _ transform: (Values.Element, inout A) throws -> Result) throws -> [Result] {
        var result: [Result] = []
        try reserve(values.underestimatedCount, in: &result, using: &a)
        for value in values {
            try a.consumeWork(1)
            try append(transform(value, &a), to: &result, using: &a)
        }
        return result
    }
    package static func ordered<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(_ values: Values,
        using a: inout A, less: (Values.Element, Values.Element) -> Bool) throws -> [Values.Element] {
        var result = try map(values, using: &a) { value, a in value }
        func sift(_ start: Int, _ count: Int) throws {
            var parent = start
            while parent < count / 2 {
                try a.consumeWork(1)
                var child = parent * 2 + 1
                if child + 1 < count, less(result[child], result[child + 1]) { child += 1 }
                guard less(result[parent], result[child]) else { return }
                result.swapAt(parent, child); parent = child
            }
        }
        if result.count > 1 {
            for parent in stride(from: result.count / 2 - 1, through: 0, by: -1) { try sift(parent, result.count) }
            for end in stride(from: result.count - 1, through: 1, by: -1) {
                try a.consumeWork(1); result.swapAt(0, end); try sift(0, end)
            }
        }
        return result
    }
    package static func insert<Element: Hashable, A: ExactScalarAdmission & ~Copyable>(_ element: Element,
        in values: inout Set<Element>, using a: inout A) throws {
        try a.consumeWork(1)
        guard !values.contains(element) else { return }
        if values.count == values.capacity {
            let doubled = values.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
            let capacity = max(1, doubled.partialValue)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: capacity, of: Element.self))
            values.reserveCapacity(capacity)
        }
        values.insert(element)
    }
}
