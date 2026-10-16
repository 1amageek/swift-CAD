import CADCore

/// Closed original field germ chart excluding every other projection-critical preimage.
package struct OriginalFieldProjectionRegularChart: Sendable {
    package let chart: OriginalSingularRegularChart
    package let originalTransverseDerivative: OriginalSingularFieldPlanePolynomial
    package let criticalPreimages: [OriginalSingularFieldSystemRoot]

    package init<B: ExactScalarAdmission & ~Copyable>(germ: OriginalSingularResolution.Germ,
        primitive: OriginalSingularFieldPlanePolynomial, maximumDepth: Int, usage: inout B) throws {
        let derivative = try primitive.differentiated(alongU: false, maximumDepth: maximumDepth, usage: &usage)
        let critical = try derivative.embedded(in: germ.strictTransform.context,
            maximumDepth: maximumDepth, usage: &usage).composed(withU: germ.originalU, v: germ.originalV,
                maximumDepth: maximumDepth, usage: &usage)
        var radius = 0.5, depth = germ.depth
        while true {
            let chart = try OriginalSingularRegularChart(germ: germ, maximumDepth: maximumDepth,
                maximumRadius: radius, inheritedDepth: depth, usage: &usage)
            let roots: [OriginalSingularFieldSystemRoot]
            switch try OriginalSingularFieldSystemSolver.roots(of: [germ.strictTransform, critical],
                over: chart.localDomain, inheritedDepth: chart.sourceDepth, maximumDepth: maximumDepth, usage: &usage) {
            case .finite(let values): roots = values
            case .positiveDimension:
                throw rationalAlgebraFailure("Original field primitive chart retained a projection-critical component.")
            }
            var inherited = chart.sourceDepth, other = false
            for root in roots {
                inherited = max(inherited, max(root.projectionRoot.isolation.depth, root.fiberRoot.isolation.depth))
                if case .zero = try root.u.sign(maximumDepth: maximumDepth, usage: &usage),
                    case .zero = try root.v.sign(maximumDepth: maximumDepth, usage: &usage) { continue }
                other = true
            }
            if !other {
                self.chart = chart; originalTransverseDerivative = derivative; criticalPreimages = roots; return
            }
            guard inherited < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original field projection-regular chart exhausted causal caller depth.")
            }
            depth = try rationalAlgebraCount(inherited, 1); radius *= 0.5
        }
    }
}
