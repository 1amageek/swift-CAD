/// Exact repeated-factor removal over the retained original ordered field.
package struct OriginalFieldZeroSetAuthority: Sendable {
    package let original: OriginalSingularFieldPlanePolynomial
    package let repeatedFactor: OriginalSingularFieldPlanePolynomial
    package let squareFree: OriginalSingularFieldPlanePolynomial
    package let maximumAlgebraicDepth: Int
    private let derivatives: [[OriginalSingularFieldPlanePolynomial]]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        maximumAlgebraicDepth: Int, usage: inout B) throws {
        self.original = original; self.maximumAlgebraicDepth = maximumAlgebraicDepth
        if original.isZero { repeatedFactor = original; squareFree = original; derivatives = []; return }
        let u = try original.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let v = try original.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let first = try OriginalSingularFieldPlaneGCD.gcd(original, u,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        repeatedFactor = try OriginalSingularFieldPlaneGCD.gcd(first, v,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        squareFree = try original.dividedExactly(by: repeatedFactor,
            maximumDepth: maximumAlgebraicDepth, usage: &usage).normalized(maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let a = try squareFree.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let b = try squareFree.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let left = try OriginalSingularFieldPlaneGCD.gcd(squareFree, a,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let remaining = try OriginalSingularFieldPlaneGCD.gcd(left, b,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        guard remaining.uDegree <= 0, remaining.vDegree <= 0, !remaining.isZero else {
            throw rationalAlgebraFailure("Original field zero equation retains an unresolved repeated factor.")
        }
        try RationalAlgebraStorage.retain(4, of: [OriginalSingularFieldPlanePolynomial].self, usage: &usage)
        var rows: [[OriginalSingularFieldPlanePolynomial]] = []; rows.reserveCapacity(4)
        for total in 0...3 {
            try RationalAlgebraStorage.retain(total + 1, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
            var row: [OriginalSingularFieldPlanePolynomial] = []; row.reserveCapacity(total + 1)
            for uOrder in 0...total {
                var value = squareFree
                for _ in 0..<uOrder { value = try value.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage) }
                for _ in 0..<(total - uOrder) { value = try value.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage) }
                row.append(value)
            }
            rows.append(row)
        }
        derivatives = rows
    }

    package init<B: ExactScalarAdmission & ~Copyable>(retaining source: OriginalRationalZeroSetAuthority,
        into context: OriginalSingularFieldContext, maximumAlgebraicDepth: Int, usage: inout B) throws {
        guard maximumAlgebraicDepth >= 0 else { throw rationalAlgebraFailure("Original coefficient lifting needs an admitted algebraic depth.") }
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        original = try OriginalFieldHomogeneousImage.lift(source.original, into: context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        repeatedFactor = try OriginalFieldHomogeneousImage.lift(source.repeatedFactor, into: context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        squareFree = try OriginalFieldHomogeneousImage.lift(source.squareFree, into: context,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        if original.isZero { derivatives = []; return }
        try RationalAlgebraStorage.retain(4, of: [OriginalSingularFieldPlanePolynomial].self, usage: &usage)
        var rows: [[OriginalSingularFieldPlanePolynomial]] = []; rows.reserveCapacity(4)
        for total in 0...3 {
            try RationalAlgebraStorage.retain(total + 1, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
            var row: [OriginalSingularFieldPlanePolynomial] = []; row.reserveCapacity(total + 1)
            for uOrder in 0...total {
                var value = squareFree
                for _ in 0..<uOrder { value = try value.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage) }
                for _ in 0..<(total - uOrder) { value = try value.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage) }
                row.append(value)
            }
            rows.append(row)
        }
        derivatives = rows
    }

    package func scalarJet<B: ExactScalarAdmission & ~Copyable>(over box: SurfaceParameterBox,
        inheritedDepth: Int, usage: inout B) throws -> OriginalRationalScalarDerivativeBounds {
        func value(_ u: Int, _ v: Int, usage: inout B) throws -> OutwardScalarInterval {
            if squareFree.isZero { return .exact(0) }
            return try derivatives[u + v][u].partial(over: box, uOrder: 0, vOrder: 0,
                inheritedDepth: inheritedDepth, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        }
        return try .init(value: value(0, 0, usage: &usage), u: value(1, 0, usage: &usage), v: value(0, 1, usage: &usage),
            uu: value(2, 0, usage: &usage), uv: value(1, 1, usage: &usage), vv: value(0, 2, usage: &usage),
            uuu: value(3, 0, usage: &usage), uuv: value(2, 1, usage: &usage), uvv: value(1, 2, usage: &usage), vvv: value(0, 3, usage: &usage))
    }
}
