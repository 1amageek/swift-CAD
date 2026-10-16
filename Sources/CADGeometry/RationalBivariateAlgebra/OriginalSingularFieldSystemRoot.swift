/// An exact original pair in one retained singular-resolution field tower.
package struct OriginalSingularFieldSystemRoot: Sendable {
    package let equations: [OriginalSingularFieldPlanePolynomial]
    package let projectionRoot: OriginalSingularFieldRoot
    package let fiberRoot: OriginalSingularFieldRoot
    package let u: OriginalSingularFieldElement
    package let v: OriginalSingularFieldElement
    package let sourceDomain: SurfaceParameterBox

    package func evaluated<B: ExactScalarAdmission & ~Copyable>(_ expression: OriginalSingularFieldPlanePolynomial,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let context = v.context
        let first = try u.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        var result = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        for (power, coefficient) in try expression.orderedTerms(usage: &usage) {
            var value = try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<power.u { value = try value.multiplied(by: first, maximumDepth: maximumDepth, usage: &usage) }
            for _ in 0..<power.v { value = try value.multiplied(by: v, maximumDepth: maximumDepth, usage: &usage) }
            result = try result.adding(value, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    package func sign<B: ExactScalarAdmission & ~Copyable>(of expression: OriginalSingularFieldPlanePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try evaluated(expression, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage)
    }
}
