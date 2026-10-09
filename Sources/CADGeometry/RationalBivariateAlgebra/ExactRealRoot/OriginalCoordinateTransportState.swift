#if ORIGINAL_COORDINATE_ISOLATED_VERIFICATION
@testable import L0
import L1
@testable import L2
#elseif L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

struct OriginalCoordinateTransportState {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Value = ExactAlgebraicScalar<Base>
    struct Entry {
        let source: ExactAlgebraicContext<Base>
        let generator: OriginalExactScalar
    }
    var field: Base
    var entries: [Entry] = []
    var bases: [OriginalScalarTransferReceipt] = []

    mutating func value<A: ExactScalarAdmission & ~Copyable>(_ source: Value,
        using a: inout A) throws(ExactScalarFailure) -> OriginalExactScalar {
        try a.checkpoint(); try a.consumeWork(1)
        try a.admitDepth(value: source.depth.value, coefficient: source.depth.coefficient)
        if let calculation = source.calculation {
            try a.admitDepth(value: calculation.depth.value, coefficient: calculation.depth.coefficient)
        }
        switch source.storage {
        case .base(let value):
            for receipt in bases {
                try a.consumeWork(1)
                if receipt.sources[0].original.context === value.original.context {
                    let mapped = try DefaultOriginalScalarTransporter().importing(value, through: receipt, using: &a)
                    return try field.importing(mapped, using: &a)
                }
            }
            let receipt = try DefaultOriginalScalarTransporter().transfer([value], into: field, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalScalarTransferReceipt.self))
            bases.append(receipt)
            field = receipt.field; return receipt.values[0]
        case .fraction(let numerator, let denominator):
            let generator = try generator(source.context, using: &a)
            let n = try polynomial(numerator, at: generator, using: &a)
            let d = try polynomial(denominator, at: generator, using: &a)
            let currentN = try field.importing(n, using: &a), currentD = try field.importing(d, using: &a)
            return try field.dividing(currentN, currentD, using: &a)
        }
    }

    mutating func polynomial<A: ExactScalarAdmission & ~Copyable>(
        _ polynomial: ExactPolynomial<Field>, at station: OriginalExactScalar,
        using a: inout A) throws(ExactScalarFailure) -> OriginalExactScalar {
        guard polynomial.variableCount == 1 else { throw .invalidEvidence }
        try a.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
        var result = try field.integer(0, using: &a)
        for term in polynomial.terms {
            try a.consumeWork(1)
            let coefficient = try value(term.coefficient, using: &a)
            var exponent = term.powers[0]
            guard exponent >= 0 else { throw .invalidEvidence }
            var power = try field.integer(1, using: &a)
            var base = try field.importing(station, using: &a)
            while exponent > 0 {
                try a.consumeWork(1)
                if exponent & 1 == 1 { power = try field.multiplying(power, base, using: &a) }
                exponent >>= 1
                if exponent > 0 { base = try field.multiplying(base, base, using: &a) }
            }
            let product = try field.multiplying(field.importing(coefficient, using: &a), power, using: &a)
            result = try field.adding(field.importing(result, using: &a), product, using: &a)
        }
        return result
    }
}
