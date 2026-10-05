import CADCore

/// Retained original system parameters, independent of numerical localization.
public struct OriginalCurveContactParameterAuthority: Sendable {
    package enum Root: Sendable {
        case rational(ExactBivariateSystemRoot)
        case field(OriginalSingularFieldSystemRoot)
    }
    package let originalRoot: Root
    package init(_ root: ExactBivariateSystemRoot) { originalRoot = .rational(root) }
    package init(_ root: OriginalSingularFieldSystemRoot) { originalRoot = .field(root) }

    /// Exact first-curve station equality; spatial proximity never merges events.
    package func hasSameFirstParameter(as other: Self,
        allowance: inout OriginalCurveContactAllowance) throws -> Bool {
        let policy = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(policy) }
        let depth = allowance.budget.maximumAlgebraicDepth
        if case .rational(let first) = originalRoot, case .rational(let second) = other.originalRoot {
            return try ExactMonotoneGraphEndpoint.algebraic(first.projectionRoot).hasSameValue(
                as: .algebraic(second.projectionRoot), maximumDepth: depth, usage: &allowance.budget)
        }
        func value(_ root: Root, budget: inout NativeCurveCurveContactBudget)
            throws -> OriginalSingularFieldElement {
            switch root {
            case .field(let root): return root.u
            case .rational(let root):
                let context = try OriginalSingularFieldContext(usage: &budget)
                return try OriginalSingularFieldTransport().originalScalarValue(
                    .algebraic(root.projectionRoot), into: context, maximumDepth: depth, usage: &budget)
            }
        }
        let first = try value(originalRoot, budget: &allowance.budget)
        let second = try value(other.originalRoot, budget: &allowance.budget)
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(second.context, into: first.context,
            maximumDepth: depth, usage: &allowance.budget)
        let a = try first.embedded(in: context, maximumDepth: depth, usage: &allowance.budget)
        let b = try transport.applying(to: second, in: context, maximumDepth: depth, usage: &allowance.budget)
        if case .zero = try a.subtracting(b, maximumDepth: depth, usage: &allowance.budget)
            .sign(maximumDepth: depth, usage: &allowance.budget) { return true }
        return false
    }

    /// Tests closed native chart membership at the same retained original root.
    package func isInside<B: RationalAlgebraAdmitting>(
        uLower: ExactRationalCoefficient, uUpper: ExactRationalCoefficient,
        vLower: ExactRationalCoefficient, vUpper: ExactRationalCoefficient,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws -> Bool {
        switch originalRoot {
        case .rational(let root):
            for (alongU, lower, upper) in [(true, uLower, uUpper), (false, vLower, vUpper)] {
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
                let first = try coordinate.subtracting(.constant(lower, usage: &usage), usage: &usage)
                let last = try coordinate.subtracting(.constant(upper, usage: &usage), usage: &usage)
                if case .negative = try root.sign(of: first, maximumDepth: maximumDepth, usage: &usage) { return false }
                if case .positive = try root.sign(of: last, maximumDepth: maximumDepth, usage: &usage) { return false }
            }
            return true
        case .field(let root):
            var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumAlgebraicDepth)
            defer { usage = admission.base }
            let context = root.projectionRoot.polynomial.context
            for (alongU, lower, upper) in [(true, uLower, uUpper), (false, vLower, vUpper)] {
                let coordinate = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: alongU,
                    in: context, maximumDepth: maximumDepth, usage: &admission)
                func difference(_ bound: ExactRationalCoefficient) throws -> OriginalSingularFieldPlanePolynomial {
                    let constant = try OriginalSingularFieldElement.constant(bound, in: context,
                        maximumDepth: maximumDepth, usage: &admission)
                    return try coordinate.subtracting(.constant(constant, maximumDepth: maximumDepth,
                        usage: &admission), maximumDepth: maximumDepth, usage: &admission)
                }
                if case .negative = try root.sign(of: difference(lower), maximumDepth: maximumDepth, usage: &admission) { return false }
                if case .positive = try root.sign(of: difference(upper), maximumDepth: maximumDepth, usage: &admission) { return false }
            }
            return true
        }
    }
}
