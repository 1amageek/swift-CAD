import CADCore
import CADGeometry

/// Canonical ancestry with paid original visits and no separate sort buffer.
package enum AdmittedSewingProvenance {
    package static func canonical<A: ExactScalarAdmission & ~Copyable>(_ input: [SubshapeID],
        using execution: inout A) throws -> [SubshapeID] {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
        guard !input.isEmpty else { return [] }
        let bytes = input.count.multipliedReportingOverflow(by: MemoryLayout<SubshapeID>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: nil,
                message: "Sewing ancestry byte admission overflowed its original ID buffer.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
        var output: [SubshapeID] = []
        output.reserveCapacity(input.count)
        for value in input {
            try CurrentTaskCancellationChecker().checkCancellation()
            try execution.consumeWork(1)
            output.append(value)
        }
        func sift(_ root: Int, count: Int, values: inout [SubshapeID]) throws {
            var parent = root
            while parent < count / 2 {
                try CurrentTaskCancellationChecker().checkCancellation()
                try execution.consumeWork(1)
                var child = parent * 2 + 1
                if child + 1 < count {
                    try execution.consumeWork(1)
                    if values[child] < values[child + 1] { child += 1 }
                }
                try execution.consumeWork(1)
                guard values[parent] < values[child] else { return }
                try execution.consumeWork(1)
                values.swapAt(parent, child)
                parent = child
            }
        }
        if output.count > 1 {
            for root in stride(from: (output.count - 2) / 2, through: 0, by: -1) {
                try sift(root, count: output.count, values: &output)
            }
            for end in stride(from: output.count - 1, through: 1, by: -1) {
                try CurrentTaskCancellationChecker().checkCancellation()
                try execution.consumeWork(1)
                output.swapAt(0, end)
                try sift(0, count: end, values: &output)
            }
        }
        var retained = 1
        for index in output.indices.dropFirst() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try execution.consumeWork(1)
            if output[index] != output[retained - 1] {
                try execution.consumeWork(1)
                output[retained] = output[index]
                retained += 1
            }
        }
        if retained < output.count { output.removeLast(output.count - retained) }
        return output
    }
}
