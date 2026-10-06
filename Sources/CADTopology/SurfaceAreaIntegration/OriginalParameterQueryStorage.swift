import CADCore

/// Admission for requested typed storage owned by original parameter queries.
enum OriginalParameterQueryStorage {
    static func reserve<Element>(_ capacity: Int, in values: inout [Element],
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws {
        guard capacity >= 0 else {
            throw failure()
        }
        guard capacity > values.capacity else { return }
        let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard !bytes.overflow else { throw failure() }
        try consumeStorage?(bytes.partialValue)
        values.reserveCapacity(capacity)
    }

    static func append<Element>(_ element: Element, to values: inout [Element],
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws {
        if values.count == values.capacity {
            let doubled = values.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw failure() }
            try reserve(max(1, doubled.partialValue), in: &values, consumeStorage: consumeStorage)
        }
        values.append(element)
    }

    static func map<Input, Output>(_ values: [Input],
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        transform: (Input) throws -> Output) throws -> [Output] {
        var result: [Output] = []
        try reserve(values.count, in: &result, consumeStorage: consumeStorage)
        for value in values {
            try Task.checkCancellation(); try consumeWork?(0)
            result.append(try transform(value))
        }
        return result
    }

    /// Sorts admitted uniquely owned storage without an auxiliary merge buffer.
    static func sort<Element>(_ values: inout [Element],
        consumeWork: (@Sendable (Int) throws -> Void)?,
        less: (Element, Element) -> Bool) throws {
        func sift(_ root: Int, _ count: Int, _ storage: inout [Element]) throws {
            var parent = root
            while parent < count / 2 {
                try Task.checkCancellation(); try consumeWork?(0)
                var child = parent * 2 + 1
                if child + 1 < count, less(storage[child], storage[child + 1]) { child += 1 }
                if !less(storage[parent], storage[child]) { return }
                storage.swapAt(parent, child); parent = child
            }
        }
        guard values.count > 1 else { return }
        for root in stride(from: values.count / 2 - 1, through: 0, by: -1) {
            try sift(root, values.count, &values)
        }
        for end in stride(from: values.count - 1, through: 1, by: -1) {
            try consumeWork?(0); values.swapAt(0, end); try sift(0, end, &values)
        }
    }

    private static func failure() -> KernelError {
        KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: nil,
            message: "Original parameter query typed byte request overflowed.")
    }
}
