import L0
import L1
import L2
import OriginalCoordinateTransfer

@main struct ScalarPerformance {
    static func main() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let base = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try ExactAlgebraicScalarDomain.base(field: base, maximumExtensionLevel: 4, using: &a)
        let roots = try ExactRealRootDomain(field: field, using: &a), p = roots.polynomials
        let x = try p.variable(0, using: &a)
        let law = try p.subtracting(p.multiplying(x, x, using: &a), p.constant(field.integer(2, using: &a), using: &a), using: &a)
        let source = try roots.bind(law, using: &a)
        let range = try roots.domain(lower: .finite(field.integer(1, using: &a)), upper: .finite(field.integer(2, using: &a)), using: &a)
        let selected = try roots.isolate(source, in: range, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extended = try field.adjoin(selected, using: &a)
        let y = extended.generator, f = extended.domain
        let square = try f.multiplying(y, y, using: &a)
        let reciprocal = try f.dividing(f.integer(1, using: &a), y, using: &a)
        let sum = try f.adding(y, f.integer(1, using: &a), using: &a)

        let wrappedConstant = try f.integer(7, using: &a)
        let baseConstant = try field.integer(7, using: &a)
        for (label, input) in [("baseConstant", baseConstant), ("rootWrappedConstant", wrappedConstant)] {
            for repetition in 0..<5 {
                var ledger = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
                let start = ContinuousClock.now
                let result = try DefaultExactOriginalScalarTransporter().transfer([input], into: base, using: &ledger)
                let elapsed = start.duration(to: .now)
                guard try result.field.compare(result.values[0], result.field.integer(7, using: &a), using: &a) == .equal else { fatalError("Wrong constant") }
                print("CONSTANT", label, repetition, elapsed, "work", ledger.work, "bytes", ledger.storageBytes)
            }
        }
        let pattern = [y, square, reciprocal, sum]
        for count in [3, 12, 48] {
            let input = (0..<count).map { pattern[$0 % pattern.count] }
            for repetition in 0..<5 {
                var ledger = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
                let start = ContinuousClock.now
                let result = try DefaultExactOriginalScalarTransporter().transfer(input, into: base, using: &ledger)
                let elapsed = start.duration(to: .now)
                var finalLedger = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
                let finish = ContinuousClock.now
                let again = try DefaultOriginalScalarTransporter().transfer(result.values, into: result.field, using: &finalLedger)
                let finalElapsed = finish.duration(to: .now)
                guard again.values.count == count else { fatalError("Incomplete transfer") }
                print("SCALAR", count, repetition, elapsed, "work", ledger.work, "bytes", ledger.storageBytes,
                    "sameOwnerFinal", finalElapsed, "finalWork", finalLedger.work, "finalBytes", finalLedger.storageBytes)
            }
        }
    }
}
