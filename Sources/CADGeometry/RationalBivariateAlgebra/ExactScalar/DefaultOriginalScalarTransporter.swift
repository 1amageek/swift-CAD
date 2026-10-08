/// Uses the existing retained-root transport under one exclusive caller admission.
public struct DefaultOriginalScalarTransporter: OriginalScalarTransferring {
    public init() {}

    public func transfer<A: ExactScalarAdmission & ~Copyable>(
        _ sources: borrowing [OriginalExactScalar],
        into destination: borrowing OriginalExactScalarDomain,
        using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalScalarTransferReceipt {
        try admission.checkpoint()
        var inherited = destination.originalDepth
        var original = destination.originalDepth
        for index in sources.indices {
            let value = sources[index]
            try admission.consumeWork(1)
            inherited = .init(uncheckedValue: max(inherited.value, value.depth.value),
                coefficient: max(inherited.coefficient, value.depth.coefficient))
            original = .init(uncheckedValue: max(original.value, value.original.context.depth),
                coefficient: max(original.coefficient, value.original.context.coefficientDepth))
        }
        let result = try ExactScalarNumericAccess.withAdmission(&admission,
            original: original, inherited: inherited,
            maximum: .init(uncheckedValue: destination.maximumValueDepth,
                coefficient: destination.maximumCoefficientDepth)) { usage in
            var transport = OriginalSingularFieldTransport()
            var context = destination.context
            for index in sources.indices {
                let value = sources[index]
                try usage.consumeExactWork(1)
                context = try transport.importing(value.original.context, into: context,
                    maximumDepth: destination.maximumValueDepth, usage: &usage)
            }
            try RationalAlgebraStorage.retain(sources.count,
                of: OriginalSingularFieldElement.self, usage: &usage)
            var values: [OriginalSingularFieldElement] = []
            values.reserveCapacity(sources.count)
            for index in sources.indices {
                let value = sources[index]
                try usage.consumeExactWork(1)
                values.append(try transport.applying(to: value.original, in: context,
                    maximumDepth: destination.maximumValueDepth, usage: &usage))
            }
            return values
        }
        let field: OriginalExactScalarDomain
        if let first = result.value.first {
            field = try .init(retaining: .init(original: first, depth: result.depth),
                maximumValueDepth: destination.maximumValueDepth,
                maximumCoefficientDepth: destination.maximumCoefficientDepth, using: &admission)
        } else {
            field = copy destination
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: sources.count,
            of: OriginalExactScalar.self))
        var values: [OriginalExactScalar] = []; values.reserveCapacity(sources.count)
        for value in result.value {
            try admission.consumeWork(1)
            values.append(.init(original: value, depth: result.depth))
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: OriginalScalarTransferReceipt.self))
        let receipt = OriginalScalarTransferReceipt(sources: copy sources, field: field, values: values)
        try admission.checkpoint()
        return receipt
    }
}
