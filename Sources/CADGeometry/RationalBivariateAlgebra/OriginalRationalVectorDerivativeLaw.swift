/// Exact formal rational vector partials; source binding and pole admission belong to callers.
package struct OriginalRationalVectorDerivativeLaw: Sendable {
    package struct Partial: Sendable {
        package let uOrder: Int
        package let vOrder: Int
        package let numerators: [ExactBivariatePolynomial]
        package let denominator: ExactBivariatePolynomial
    }
    package let partials: [Partial]

    package init<B: ExactScalarAdmission & ~Copyable>(homogeneous: [ExactBivariatePolynomial],
        throughOrder: Int, usage: inout B) throws {
        guard throughOrder >= 0, homogeneous.count == 4, !homogeneous[3].isZero else { throw rationalAlgebraFailure("Original surface partial order must be nonnegative.") }
        let width = try rationalAlgebraCount(throughOrder, 1)
        let rows = try rationalAlgebraCount(width, try rationalAlgebraCount(width, 1), multiply: true) / 2
        try RationalAlgebraStorage.retain(rows, of: Partial.self, usage: &usage)
        let w = homogeneous[3]
        let wu = try w.differentiated(alongU: true, usage: &usage)
        let wv = try w.differentiated(alongU: false, usage: &usage)
        var result: [Partial] = []; result.reserveCapacity(rows)
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        result.append(.init(uOrder: 0, vOrder: 0,
            numerators: Array(homogeneous[0..<3]), denominator: w))
        if throughOrder > 0 {
            for total in 1...throughOrder {
                let scalar = try ExactRationalCoefficient.natural(total, usage: &usage)
                for u in 0...total {
                    let v = total - u
                    let alongU = u > 0
                    let parentU = alongU ? u - 1 : u
                    let parentV = alongU ? v : v - 1
                    // Prior total-order entries retain the unique original
                    // derivative, independently of the chosen mixed recurrence.
                    var parent: Partial?
                    for entry in result {
                        try usage.consumeWork(1)
                        if entry.uOrder == parentU && entry.vOrder == parentV { parent = entry; break }
                    }
                    guard let parent else { throw rationalAlgebraFailure("Original mixed derivative recurrence lost its parent.") }
                    let dw = try (alongU ? wu : wv).scaled(by: scalar, usage: &usage)
                    try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
                    var numerators: [ExactBivariatePolynomial] = []; numerators.reserveCapacity(3)
                    for a in parent.numerators {
                        numerators.append(try a.differentiated(alongU: alongU, usage: &usage)
                            .multiplied(by: w, usage: &usage)
                            .subtracting(a.multiplied(by: dw, usage: &usage), usage: &usage))
                    }
                    result.append(.init(uOrder: u, vOrder: v, numerators: numerators,
                        denominator: try parent.denominator.multiplied(by: w, usage: &usage)))
                }
            }
        }
        partials = result
    }

    package func equalityNumerators<B: ExactScalarAdmission & ~Copyable>(with other: Self,
        secondTranslation: (alongU: Bool, amount: ExactRationalCoefficient)? = nil,
        requiredPartials: [(uOrder: Int, vOrder: Int)]? = nil,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        guard partials.count == other.partials.count else {
            throw rationalAlgebraFailure("Original surface derivative equality needs the same requested partial order.")
        }
        if let requiredPartials {
            guard !requiredPartials.isEmpty else { throw rationalAlgebraFailure("Original derivative equality needs a nonempty partial selection.") }
            for required in requiredPartials {
                guard required.uOrder >= 0, required.vOrder >= 0 else { throw rationalAlgebraFailure("Original requested partial order is negative.") }
                var found = false
                for entry in partials {
                    try usage.consumeWork(1)
                    if entry.uOrder == required.uOrder, entry.vOrder == required.vOrder { found = true; break }
                }
                guard found else { throw rationalAlgebraFailure("Original derivative table lacks a required partial.") }
            }
        }
        var result: [ExactBivariatePolynomial] = []
        for (a, b) in zip(partials, other.partials) {
            guard a.uOrder == b.uOrder, a.vOrder == b.vOrder else {
                throw rationalAlgebraFailure("Original surface mixed derivative authorities disagree.")
            }
            if let requiredPartials {
                var selected = false
                for required in requiredPartials {
                    try usage.consumeWork(1)
                    if required.uOrder == a.uOrder, required.vOrder == a.vOrder { selected = true; break }
                }
                if !selected { continue }
            }
            try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
            let denominator = try transported(b.denominator, translation: secondTranslation, usage: &usage)
            for axis in 0..<3 {
                let numerator = try transported(b.numerators[axis], translation: secondTranslation, usage: &usage)
                result.append(try a.numerators[axis].multiplied(by: denominator, usage: &usage)
                    .subtracting(numerator.multiplied(by: a.denominator, usage: &usage), usage: &usage))
            }
        }
        return result
    }

    private func transported<B: ExactScalarAdmission & ~Copyable>(_ value: ExactBivariatePolynomial,
        translation: (alongU: Bool, amount: ExactRationalCoefficient)?, usage: inout B) throws -> ExactBivariatePolynomial {
        guard let translation else { return value }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let moved = try (translation.alongU ? u : v).adding(.constant(translation.amount, usage: &usage), usage: &usage)
        return try value.composed(withU: translation.alongU ? moved : u,
            v: translation.alongU ? v : moved, usage: &usage)
    }
}
