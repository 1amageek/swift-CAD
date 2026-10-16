import CADCore

/// Reads an existing word's exact context; no coefficient is numerically rounded.
enum OriginalAffineWordCoefficientImport {
    static func values<A: ExactScalarAdmission & ~Copyable>(
        _ prepared: borrowing PreparedOriginalAffineOperationWord,
        tolerance: ModelingTolerance, maximumDepth: Int, using admission: inout A
    ) throws(ExactScalarFailure) -> [OriginalExactScalar] {
        try admission.checkpoint()
        guard maximumDepth >= 0 else { throw .invalidSource }
        let result = try ExactScalarNumericAccess.withAdmission(&admission,
            maximum: .init(uncheckedValue: maximumDepth, coefficient: maximumDepth)) { usage in
            let normalized = try prepared.originalNormalizedFrame(usage: &usage)
            if let retained = normalized {
                guard retained.frame.context.coefficientDepth <= maximumDepth else {
                    throw ExactScalarFailure.resourceLimit(.coefficientDepth)
                }
                guard retained.frame.context.depth <= maximumDepth else {
                    throw ExactScalarFailure.resourceLimit(.valueDepth)
                }
            }
            try prepared.source.validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
            try RationalAlgebraStorage.retain(12, of: OriginalExactScalar.self, usage: &usage)
            var values: [OriginalExactScalar] = []; values.reserveCapacity(12)
            if let retained = normalized {
                let depth = ExactScalarDepth(uncheckedValue: retained.frame.context.depth,
                    coefficient: retained.frame.context.coefficientDepth)
                try usage.visitCell(axis: .coefficient, depth: depth.coefficient)
                try usage.visitCell(axis: .value, depth: depth.value)
                for row in 0..<3 { for column in 0..<4 {
                    try usage.consumeWork(1)
                    let value = try OriginalAffineFieldAction.coefficient(retained.frame,
                        row: row, column: column, maximumDepth: maximumDepth, usage: &usage)
                    values.append(.init(original: value, depth: depth))
                } }
            } else {
                let rational = try prepared.exactRationalCoefficients(usage: &usage)
                let context = try OriginalSingularFieldContext(usage: &usage)
                for coefficient in rational {
                    try usage.consumeWork(1)
                    values.append(.init(original: try .constant(coefficient, in: context,
                        maximumDepth: maximumDepth, usage: &usage), depth: .zero))
                }
            }
            return values
        }
        // Read/import operations can attain stricter depths than the immutable
        // frame's initial context. Every retained value keeps the attained evidence.
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 12, of: OriginalExactScalar.self))
        var values: [OriginalExactScalar] = []; values.reserveCapacity(12)
        for value in result.value {
            try admission.consumeWork(1)
            let depth = try ExactScalarDepth(value: max(value.depth.value, result.depth.value),
                coefficient: max(value.depth.coefficient, result.depth.coefficient))
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            values.append(.init(original: value.original, depth: depth))
        }
        try admission.checkpoint(); return values
    }
}
