import CADCore
import CADGeometry

/// Admits requested typed query buffer storage before capacity growth.
package enum DistanceQueryStorage {
    package static func charge<Element, A: ExactScalarAdmission & ~Copyable>(_ count: Int, of type: Element.Type,
        using execution: inout A) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original distance typed storage request overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }

    package static func reserveForAppend<Element, A: ExactScalarAdmission & ~Copyable>(_ values: inout [Element],
        using execution: inout A) throws {
        guard values.count == values.capacity else { return }
        let doubled = values.capacity.multipliedReportingOverflow(by: 2)
        guard !doubled.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original distance buffer capacity overflowed.")
        }
        let capacity = max(1,doubled.partialValue)
        let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original distance buffer byte request overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
        values.reserveCapacity(capacity)
    }
    /// Orders the invocation-owned buffer without a temporary sorting allocation.
    package static func orderAndDeduplicate<Element: Comparable, A: ExactScalarAdmission & ~Copyable>(_ values: inout [Element],
        using execution: inout A) throws {
        guard values.count > 1 else { return }
        func sift(_ values: inout [Element], from first: Int, until end: Int) throws {
            var root = first
            while end > 1, root <= (end - 2) / 2 {
                let left = root * 2 + 1
                var child = left
                if left + 1 < end {
                    try execution.consumeWork(1)
                    if values[left] < values[left + 1] { child = left + 1 }
                }
                try execution.consumeWork(1)
                guard values[root] < values[child] else { return }
                try execution.consumeWork(1); values.swapAt(root, child)
                root = child
            }
        }
        for first in stride(from: (values.count - 2) / 2, through: 0, by: -1) {
            try sift(&values, from: first, until: values.count)
        }
        for end in stride(from: values.count - 1, through: 1, by: -1) {
            try execution.consumeWork(1); values.swapAt(0, end)
            try sift(&values, from: 0, until: end)
        }
        var retained = 1
        for index in 1..<values.count {
            try execution.consumeWork(1)
            if values[index] != values[retained - 1] {
                if retained != index { try execution.consumeWork(1); values[retained] = values[index] }
                retained += 1
            }
        }
        if retained < values.count { values.removeSubrange(retained..<values.count) }
    }

}
