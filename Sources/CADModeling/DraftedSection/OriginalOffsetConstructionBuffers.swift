import CADCore
import CADGeometry

/// Caller-paid scalar construction buffers with in-place exact sorting/deduplication.
package struct OriginalOffsetConstructionBuffers: Sendable {
    package func retain<T>(_ count: Int, of: T.Type, using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Offset construction storage overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }
    package func sortedUnique(_ values: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try retain(values.count, of: Double.self, using: &execution)
        var values = values
        func sift(_ start: Int, _ end: Int) throws {
            var root = start
            while root < end / 2 {
                try execution.consumeWork(1)
                let left = root * 2 + 1
                guard left < end else { break }
                var child = left
                if left + 1 < end, values[left] < values[left + 1] { child += 1 }
                guard values[root] < values[child] else { break }
                values.swapAt(root, child); root = child
            }
        }
        if values.count > 1 {
            for index in stride(from: values.count / 2 - 1, through: 0, by: -1) { try sift(index, values.count) }
            for end in stride(from: values.count - 1, through: 1, by: -1) {
                try execution.consumeWork(1); values.swapAt(0, end); try sift(0, end)
            }
        }
        var retained = 0
        for index in values.indices {
            try execution.consumeWork(1)
            if retained == 0 || values[index] != values[retained - 1] {
                values[retained] = values[index]; retained += 1
            }
        }
        values.removeLast(values.count - retained)
        return values
    }
    package func knots(_ breaks: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        let capacity = breaks.count.addingReportingOverflow(6)
        guard breaks.count >= 2, !capacity.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Offset knot storage exceeds its finite capacity.")
        }
        try retain(capacity.partialValue, of: Double.self, using: &execution)
        var result: [Double] = []
        result.reserveCapacity(capacity.partialValue)
        for _ in 0..<4 { try execution.consumeWork(1); result.append(breaks[0]) }
        for point in breaks.dropFirst().dropLast() { try execution.consumeWork(1); result.append(point) }
        for _ in 0..<4 { try execution.consumeWork(1); result.append(breaks[breaks.count - 1]) }
        return result
    }
}
