import CADCore

/// Closed ramified chart with no other original projection-critical preimage.
package struct OriginalSingularProjectionRegularChart: Sendable {
    package let chart: OriginalSingularRegularChart
    package let originalTransverseDerivative: ExactBivariatePolynomial
    package let criticalPreimages: [OriginalSingularFieldSystemRoot]

    package init<B: RationalAlgebraAdmitting>(germ: OriginalSingularResolution.Germ,
        primitive: ExactBivariatePolynomial, maximumDepth: Int, usage: inout B) throws {
        let derivative = try primitive.differentiated(alongU: false, usage: &usage)
        let original = try OriginalSingularFieldPlanePolynomial.original(derivative,
            in: germ.strictTransform.context, maximumDepth: maximumDepth, usage: &usage)
        let critical = try original.composed(withU: germ.originalU, v: germ.originalV,
            maximumDepth: maximumDepth, usage: &usage)
        var radius = 0.5, depth = germ.depth
        while true {
            let chart = try OriginalSingularRegularChart(germ: germ, maximumDepth: maximumDepth,
                maximumRadius: radius, inheritedDepth: depth, usage: &usage)
            var hasOtherCritical = false
            let roots: [OriginalSingularFieldSystemRoot]
            switch try OriginalSingularFieldSystemSolver.roots(of: [germ.strictTransform, critical],
                over: chart.localDomain, inheritedDepth: chart.sourceDepth, maximumDepth: maximumDepth, usage: &usage) {
            case .finite(let retained): roots = retained
            case .positiveDimension:
                throw rationalAlgebraFailure("Original primitive chart retained an entire projection-critical component.")
            }
            var inherited = chart.sourceDepth
            for root in roots {
                inherited = max(inherited, max(root.projectionRoot.isolation.depth, root.fiberRoot.isolation.depth))
                if case .zero = try root.u.sign(maximumDepth: maximumDepth, usage: &usage),
                    case .zero = try root.v.sign(maximumDepth: maximumDepth, usage: &usage) { continue }
                hasOtherCritical = true
            }
            if !hasOtherCritical {
                self.chart = chart; originalTransverseDerivative = derivative; criticalPreimages = roots
                return
            }
            guard inherited < maximumDepth else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original projection-regular station chart exhausted causal depth.") }
            depth = try rationalAlgebraCount(inherited, 1); radius *= 0.5
        }
    }
}
