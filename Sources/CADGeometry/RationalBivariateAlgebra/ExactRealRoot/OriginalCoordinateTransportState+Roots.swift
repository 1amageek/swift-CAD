#if ORIGINAL_COORDINATE_ISOLATED_VERIFICATION
import L0
import L1
@testable import L2
#elseif L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension OriginalCoordinateTransportState {
    mutating func generator<A: ExactScalarAdmission & ~Copyable>(
        _ context: ExactAlgebraicContext<Base>, using a: inout A
    ) throws(ExactScalarFailure) -> OriginalExactScalar {
        do {
            try a.checkpoint()
            for entry in entries {
                try a.consumeWork(1)
                if entry.source === context { return try field.importing(entry.generator, using: &a) }
            }
            guard let original = context.root, let parent = context.parent else {
                throw ExactScalarFailure.invalidEvidence
            }
            try a.admitDepth(value: context.depth.value, coefficient: context.depth.coefficient)
            let parentField = Field(context: parent)
            let roots = try ExactRealRootDomain(retaining: original.source, using: &a)
            let q = ExactRationalScalarDomain()
            let two = try q.integer(2, using: &a)
            var width = try q.integer(1, using: &a)
            var selected = original
            var lower = ExactRationalCoefficient.zero, upper = ExactRationalCoefficient.zero
            var depth = original.depth
            while true {
                try a.consumeWork(1)
                guard case .finite(let low) = selected.isolation.lower,
                    case .finite(let high) = selected.isolation.upper else {
                    throw ExactScalarFailure.invalidEvidence
                }
                let l = try value(low, using: &a), h = try value(high, using: &a)
                lower = try bracket(field.importing(l, using: &a), width: width, using: &a).0
                upper = try bracket(field.importing(h, using: &a), width: width, using: &a).1
                let ll = try parentField.importingBase(parent.base.rational(exactly: lower, using: &a), using: &a)
                let hh = try parentField.importingBase(parent.base.rational(exactly: upper, using: &a), using: &a)
                let interval = try roots.domain(lower: .finite(ll), upper: .finite(hh), using: &a)
                let counted = try roots.count(original.source, in: interval, using: &a)
                depth = try .init(value: max(depth.value, max(selected.depth.value, counted.depth.value)),
                    coefficient: max(depth.coefficient, max(selected.depth.coefficient, counted.depth.coefficient)))
                guard case .finite(let count, _) = counted.classification, count > 0 else {
                    throw ExactScalarFailure.invalidEvidence
                }
                if count == 1 { break }
                width = try q.dividing(width, two, using: &a)
                let exactWidth = try parentField.importingBase(parent.base.rational(exactly: width, using: &a), using: &a)
                selected = try roots.refine(selected, maximumWidth: exactWidth, using: &a)
            }
            let polynomial = original.proof.polynomial
            guard polynomial.variableCount == 1 else { throw ExactScalarFailure.invalidEvidence }
            var degree = 0
            for term in polynomial.terms {
                try a.consumeWork(1); degree = max(degree, term.powers[0])
            }
            let count = degree.addingReportingOverflow(1)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count.partialValue,
                of: OriginalExactScalar.self))
            let zero = try field.integer(0, using: &a)
            var coefficients = [OriginalExactScalar](repeating: zero, count: count.partialValue)
            for term in polynomial.terms {
                try a.consumeWork(1); coefficients[term.powers[0]] = try value(term.coefficient, using: &a)
            }
            let transported = try DefaultOriginalScalarTransporter().transfer(coefficients, into: field, using: &a)
            let receipt = try DefaultOriginalScalarTransporter().bindSelectedRoot(
                coefficients: transported.values, in: transported.field, lower: lower, upper: upper,
                includesLower: true, includesUpper: true, depth: depth,
                axis: original.source.refinementAxis, using: &a)
            field = receipt.field
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Entry.self))
            entries.append(.init(source: context, generator: receipt.value))
            try a.checkpoint(); return receipt.value
        } catch let failure as ExactScalarFailure { throw failure }
        catch let failure as ExactRealRootFailure {
            switch failure {
            case .scalar(let scalar), .polynomial(.scalar(let scalar)): throw scalar
            case .invalidEvidence, .invalidSource, .invalidDomain, .invalidVariable: throw .invalidEvidence
            case .countOverflow, .polynomial(.countOverflow): throw .countOverflow
            case .unresolved: throw .unresolved
            default: throw .admissionRejected(failure)
            }
        } catch { throw .admissionRejected(error) }
    }

    func bracket<A: ExactScalarAdmission & ~Copyable>(_ value: OriginalExactScalar,
        width: ExactRationalCoefficient, using a: inout A
    ) throws(ExactScalarFailure) -> (ExactRationalCoefficient, ExactRationalCoefficient) {
        let q = ExactRationalScalarDomain(), two = try q.integer(2, using: &a)
        var magnitude = try q.integer(1, using: &a)
        while true {
            try a.consumeWork(1)
            let lower = try field.rational(exactly: q.negated(magnitude, using: &a), using: &a)
            let upper = try field.rational(exactly: magnitude, using: &a)
            if try field.compare(value, lower, using: &a) != .less,
                try field.compare(value, upper, using: &a) != .greater { break }
            magnitude = try q.multiplying(magnitude, two, using: &a)
        }
        var lower = try q.negated(magnitude, using: &a), upper = magnitude
        while try q.compare(q.subtracting(upper, lower, using: &a), width, using: &a) == .greater {
            try a.consumeWork(1)
            let middle = try q.dividing(q.adding(lower, upper, using: &a), two, using: &a)
            switch try field.compare(value, field.rational(exactly: middle, using: &a), using: &a) {
            case .equal: return (middle, middle)
            case .less: upper = middle
            case .greater: lower = middle
            }
        }
        return (lower, upper)
    }
}
