import CADCore
import CADGeometry

/// Caller-paid scalar construction buffers with in-place exact sorting/deduplication.
package struct OriginalOffsetConstructionBuffers: Sendable {
    package let admission: GeometryConversionAdmission
    package func retain<T>(_ count: Int, of: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Offset construction storage overflowed.")
        }
        try admission.chargeStorage(bytes: bytes.partialValue)
    }
    package func sortedUnique(_ values: [Double]) throws -> [Double] {
        try retain(values.count, of: Double.self)
        var values = values
        func sift(_ start: Int, _ end: Int) throws {
            var root = start
            while root < end / 2 {
                try admission.chargeWork()
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
                try admission.chargeWork(); values.swapAt(0, end); try sift(0, end)
            }
        }
        var retained = 0
        for index in values.indices {
            try admission.chargeWork()
            if retained == 0 || values[index] != values[retained - 1] {
                values[retained] = values[index]; retained += 1
            }
        }
        values.removeLast(values.count - retained)
        return values
    }
    package func knots(_ breaks: [Double]) throws -> [Double] {
        try retain(breaks.count + 6, of: Double.self)
        var result: [Double] = []
        result.reserveCapacity(breaks.count + 6)
        for _ in 0..<4 { try admission.chargeWork(); result.append(breaks[0]) }
        for point in breaks.dropFirst().dropLast() { try admission.chargeWork(); result.append(point) }
        for _ in 0..<4 { try admission.chargeWork(); result.append(breaks[breaks.count - 1]) }
        return result
    }
}
