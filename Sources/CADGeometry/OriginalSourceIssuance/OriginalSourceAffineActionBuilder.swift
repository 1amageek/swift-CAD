#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Only source-family readers may provide the original coefficients.
enum OriginalSourceAffineActionBuilder {
    static func issue<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<S>,field: F,limits: OriginalSourceIssuanceLimits,using a: inout A,
        coefficient: (Int,Int,inout A) throws -> F.Value
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceAffineActionReceipt<S,F> {
        do {
            try a.checkpoint();try a.consumeWork(1);try source.require(limits)
            let result = try a.withProofScope { usage in
                try usage.retainStorage(bytes:exactScalarPayloadBytes(count:12,of:F.Value.self))
                var values: [F.Value] = [];values.reserveCapacity(12)
                for row in 0..<3 { for column in 0..<4 {
                    try usage.consumeWork(1)
                    let value = try coefficient(row,column,&usage)
                    _ = try field.sign(of:value,using:&usage);values.append(value)
                } }
                let payload = try exactScalarPayloadBytes(count:1,of:(F,[F.Value],ExactScalarDepth).self)
                let header = try exactScalarPayloadBytes(count:2,of:UnsafeRawPointer.self)
                let total = payload.addingReportingOverflow(header)
                guard !total.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                try usage.retainStorage(bytes:total.partialValue)
                try usage.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceAffineActionReceipt<S,F>.self))
                return OriginalSourceAffineActionReceipt(source:source,action:.init(field:field,coefficients:values,depth:try usage.depth))
            }
            try a.checkpoint();return result
        } catch { throw .init(preserving:error) }
    }
}
