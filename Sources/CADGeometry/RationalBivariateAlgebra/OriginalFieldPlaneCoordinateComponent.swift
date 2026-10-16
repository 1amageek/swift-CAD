import CADCore

/// Whole original real coordinate line, including a constant-parameter source.
package struct OriginalFieldPlaneCoordinateComponent: Sendable {
    package let original: OriginalSingularFieldPlanePolynomial
    package let fixedAlongU: Bool
    package let fixedRoot: OriginalSingularFieldRoot
    package let fixedValue: OriginalSingularFieldElement
    package let sourceDomain: SurfaceParameterBox
    package let sourceDepth: Int

    package static func proven<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        fixedAlongU: Bool, at root: OriginalSingularFieldRoot, over domain: SurfaceParameterBox,
        inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws -> Self? {
        guard !original.isZero, original.context === root.polynomial.context,
            domain.u.width > 0, domain.v.width > 0, inheritedDepth >= 0,
            max(inheritedDepth, root.isolation.depth) <= maximumDepth else {
            throw rationalAlgebraFailure("Original coordinate component needs a nonzero source, same root owner and admitted positive native domain.")
        }
        let fixedDomain = fixedAlongU ? domain.u : domain.v
        var selected = OriginalSingularFieldEndpoint.algebraic(root)
        var lower = OriginalSingularFieldEndpoint.authored(try .originalDouble(fixedDomain.lower, usage: &usage))
        var upper = OriginalSingularFieldEndpoint.authored(try .originalDouble(fixedDomain.upper, usage: &usage))
        guard try OriginalSingularFieldEndpoint.compare(&selected, &lower, maximumDepth: maximumDepth, usage: &usage) >= 0,
            try OriginalSingularFieldEndpoint.compare(&selected, &upper, maximumDepth: maximumDepth, usage: &usage) <= 0 else { return nil }
        guard case .algebraic(let retained) = selected else { throw rationalAlgebraFailure("Original coordinate root lost its retained authority.") }
        let oriented = fixedAlongU ? original : try original.exchangedAxes(maximumDepth: maximumDepth, usage: &usage)
        for power in 0...max(0, oriented.vDegree) {
            let coefficient = try OriginalSingularFieldPlaneGCD.coefficient(oriented, vPower: power,
                maximumDepth: maximumDepth, usage: &usage)
            guard case .zero = try retained.sign(of: coefficient, maximumDepth: maximumDepth, usage: &usage) else { return nil }
        }
        let depth = max(inheritedDepth, retained.isolation.depth)
        try usage.visitCell(axis: .value, depth: depth)
        let value = try retained.value(maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(original: original, fixedAlongU: fixedAlongU, fixedRoot: retained,
            fixedValue: value, sourceDomain: domain, sourceDepth: max(depth, value.context.depth))
    }

    /// Preserves the native source axes; a constant coordinate is not discarded.
    package func originalParameters<B: ExactScalarAdmission & ~Copyable>(atFreeParameter parameter: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement) {
        let freeDomain = fixedAlongU ? sourceDomain.v : sourceDomain.u
        let low = try ExactRationalCoefficient.originalDouble(freeDomain.lower, usage: &usage)
        let high = try ExactRationalCoefficient.originalDouble(freeDomain.upper, usage: &usage)
        guard !(try parameter.subtracting(low, usage: &usage)).isNegative,
            !(try high.subtracting(parameter, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original coordinate-component query exceeds its positive native free interval.")
        }
        let free = try OriginalSingularFieldElement.constant(parameter, in: fixedValue.context,
            maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1,
            of: (OriginalSingularFieldElement, OriginalSingularFieldElement).self, usage: &usage)
        return fixedAlongU ? (fixedValue, free) : (free, fixedValue)
    }

    package static func all<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        over domain: SurfaceParameterBox, inheritedDepth: Int, maximumDepth: Int,
        usage: inout B) throws -> [Self] {
        var result: [Self] = []
        for fixedAlongU in [true, false] {
            let oriented = fixedAlongU ? original : try original.exchangedAxes(maximumDepth: maximumDepth, usage: &usage)
            let content = try OriginalSingularFieldPlaneGCD.content(oriented, maximumDepth: maximumDepth, usage: &usage)
            if content.degree <= 0 { continue }
            let bounds = fixedAlongU ? domain.u : domain.v
            let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(content,
                lower: .originalDouble(bounds.lower, usage: &usage), upper: .originalDouble(bounds.upper, usage: &usage),
                inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage)
            for root in roots {
                guard let component = try proven(original: original, fixedAlongU: fixedAlongU, at: root,
                    over: domain, inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original content root contradicted complete fixed-coordinate coefficient vanishing.")
                }
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage); result.append(component)
            }
        }
        return result
    }
}
