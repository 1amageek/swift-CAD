/// Exact inverse source blowup for one retained regular strip point.
package struct OriginalSingularGermPoint: Sendable {
    package let germ: OriginalSingularResolution.Germ
    package let originalU: OriginalSingularFieldElement
    package let originalV: OriginalSingularFieldElement
    package let localU: OriginalSingularFieldElement
    package let localV: OriginalSingularFieldElement

    package static func proven<B: ExactScalarAdmission & ~Copyable>(originalU: ExactRationalCoefficient,
        originalV: ExactAlgebraicRealRoot, in germ: OriginalSingularResolution.Germ,
        maximumDepth: Int, usage: inout B) throws -> Self? {
        let fiber = try OriginalSingularFieldRoot.retaining(originalV, in: germ.strictTransform.context,
            maximumDepth: maximumDepth, usage: &usage)
        let v = try fiber.value(maximumDepth: maximumDepth, usage: &usage)
        let context = v.context
        let u = try OriginalSingularFieldElement.constant(originalU, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        return try Self.proven(originalU: u, originalV: v, in: germ,
            sourceDepth: fiber.isolation.depth, maximumDepth: maximumDepth, usage: &usage)
    }

    package static func proven<B: ExactScalarAdmission & ~Copyable>(originalU: ExactRationalCoefficient,
        originalV: OriginalSingularFieldRoot, in germ: OriginalSingularResolution.Germ,
        maximumDepth: Int, usage: inout B) throws -> Self? {
        let fiber = try OriginalSingularFieldRoot.retaining(originalV, in: germ.strictTransform.context,
            maximumDepth: maximumDepth, usage: &usage)
        let v = try fiber.value(maximumDepth: maximumDepth, usage: &usage)
        let u = try OriginalSingularFieldElement.constant(originalU, in: v.context,
            maximumDepth: maximumDepth, usage: &usage)
        return try Self.proven(originalU: u, originalV: v, in: germ,
            sourceDepth: fiber.isolation.depth, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func proven<B: ExactScalarAdmission & ~Copyable>(originalU u: OriginalSingularFieldElement,
        originalV v: OriginalSingularFieldElement, in germ: OriginalSingularResolution.Germ,
        sourceDepth: Int, maximumDepth: Int, usage: inout B) throws -> Self? {
        let context = v.context
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context,
            maximumDepth: maximumDepth, usage: &usage)
        let centerU = try germ.originalU.evaluated(atU: zero, v: zero,
            maximumDepth: maximumDepth, usage: &usage)
        let centerV = try germ.originalV.evaluated(atU: zero, v: zero,
            maximumDepth: maximumDepth, usage: &usage)
        var x = try u.subtracting(centerU, maximumDepth: maximumDepth, usage: &usage)
        var y = try v.subtracting(centerV, maximumDepth: maximumDepth, usage: &usage)
        for step in germ.steps {
            try usage.visitCell(axis: .value, depth: max(step.sourceDepth, sourceDepth))
            switch step.direction {
            case .finite:
                if case .zero = try x.sign(maximumDepth: maximumDepth, usage: &usage) { return nil }
                guard let tangent = step.tangentValue else { throw rationalAlgebraFailure("Original finite blowup lost its retained tangent value.") }
                let slope = try tangent.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
                y = try y.divided(by: x, maximumDepth: maximumDepth, usage: &usage)
                    .subtracting(slope, maximumDepth: maximumDepth, usage: &usage)
            case .vertical:
                if case .zero = try y.sign(maximumDepth: maximumDepth, usage: &usage) { return nil }
                let first = y
                let second = try x.divided(by: y, maximumDepth: maximumDepth, usage: &usage)
                x = first; y = second
            }
        }
        guard case .zero = try germ.strictTransform.evaluated(atU: x, v: y,
            maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) else { return nil }
        let mappedU = try germ.originalU.evaluated(atU: x, v: y, maximumDepth: maximumDepth, usage: &usage)
        let mappedV = try germ.originalV.evaluated(atU: x, v: y, maximumDepth: maximumDepth, usage: &usage)
        guard case .zero = try mappedU.subtracting(u, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage),
              case .zero = try mappedV.subtracting(v, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original inverse blowup contradicts its retained parameter maps.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(germ: germ, originalU: u, originalV: v, localU: x, localV: y)
    }

    package func belongs<B: ExactScalarAdmission & ~Copyable>(to chart: OriginalSingularRegularChart,
        strictly: Bool, maximumDepth: Int, usage: inout B) throws -> Bool {
        guard chart.germ.strictTransform.context === germ.strictTransform.context else {
            throw rationalAlgebraFailure("Original local membership uses an unrelated germ field.")
        }
        for (value, bounds) in [(localU, chart.localDomain.u), (localV, chart.localDomain.v)] {
            let lower = try OriginalSingularFieldElement.constant(.originalDouble(bounds.lower, usage: &usage),
                in: value.context, maximumDepth: maximumDepth, usage: &usage)
            let upper = try OriginalSingularFieldElement.constant(.originalDouble(bounds.upper, usage: &usage),
                in: value.context, maximumDepth: maximumDepth, usage: &usage)
            switch try value.subtracting(lower, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) {
            case .negative: return false; case .zero: if strictly { return false }; case .positive: break
            }
            switch try value.subtracting(upper, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) {
            case .positive: return false; case .zero: if strictly { return false }; case .negative: break
            }
        }
        return true
    }
}
