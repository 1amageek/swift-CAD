import CADCore

/// Positive original continuation witness; no clipped-completeness inference.
struct OriginalCurveCurveSingularContinuation {
    func certificate(common: OriginalNativeCurveCurveCommonFactor,
        at roots: [ExactBivariateSystemRoot], over domain: SurfaceParameterBox,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> SurfaceParameterBox? {
        for root in roots {
            let resolution = try OriginalSingularResolution(original: common.factor,
                at: root, maximumDepth: maximumDepth, usage: &budget)
            for germ in resolution.germs {
                let chart = try OriginalSingularRegularChart(germ: germ, maximumDepth: maximumDepth, usage: &budget)
                let clipped = try OriginalSingularRegularChartClip(chart: chart, over: domain,
                    maximumDepth: maximumDepth, usage: &budget)
                for span in clipped.spans {
                    var lower = clipped.stations[span.lowerStation].endpoint
                    var upper = clipped.stations[span.upperStation].endpoint
                    let witness = span.originalFreeWitness
                    while try !((try witness.subtracting(lower.upper, usage: &budget)).isPositive
                        && (try upper.lower.subtracting(witness, usage: &budget)).isPositive) {
                        if case .algebraic(let root) = lower {
                            lower = .algebraic(try root.refinedOnce(maximumDepth: maximumDepth, usage: &budget))
                        }
                        if case .algebraic(let root) = upper {
                            upper = .algebraic(try root.refinedOnce(maximumDepth: maximumDepth, usage: &budget))
                        }
                    }
                    let two = try ExactRationalCoefficient.natural(2, usage: &budget)
                    var left = try lower.upper.adding(witness, usage: &budget).divided(by: two, usage: &budget)
                    var right = try upper.lower.adding(witness, usage: &budget).divided(by: two, usage: &budget)
                    var depth = max(chart.sourceDepth, max(lower.depth, upper.depth))
                    var coefficientWidth = try ExactRationalCoefficient.originalDouble(
                        min(domain.u.width, domain.v.width), usage: &budget)
                    while depth <= maximumDepth {
                        try budget.visitExactCell(depth: depth)
                        let leftLabel = try left.outwardInterval(usage: &budget).lower
                        let rightLabel = try right.outwardInterval(usage: &budget).upper
                        guard leftLabel < rightLabel else { break }
                        let exactLeft = try ExactRationalCoefficient.originalDouble(leftLabel, usage: &budget)
                        let exactRight = try ExactRationalCoefficient.originalDouble(rightLabel, usage: &budget)
                        guard (try exactLeft.subtracting(lower.upper, usage: &budget)).isPositive,
                              (try upper.lower.subtracting(exactRight, usage: &budget)).isPositive else { break }
                        let interval = try ScalarInterval(lower: leftLabel, upper: rightLabel)
                        let enclosure = try chart.enclosure(over: interval,
                            maximumCoefficientWidth: coefficientWidth, maximumDepth: maximumDepth, usage: &budget)
                        let box = enclosure.originalParameters
                        guard enclosure.originalDerivatives.count == 4 else {
                            throw GeometryConversionError.invalidInput("Original clipped continuation lost its native parameter derivatives.")
                        }
                        let derivative = enclosure.originalDerivatives[1]
                        let nonconstant = derivative.x.lower > 0 || derivative.x.upper < 0
                            || derivative.y.lower > 0 || derivative.y.upper < 0
                        if nonconstant {
                            // Complete exact clipping proves the admitted graph
                            // stays in the rectangle. Its outward query box may
                            // overrun a coincident boundary by rounding only.
                            return try SurfaceParameterBox(u: ScalarInterval(
                                    lower: max(box.u.lower, domain.u.lower), upper: min(box.u.upper, domain.u.upper)),
                                v: ScalarInterval(lower: max(box.v.lower, domain.v.lower),
                                    upper: min(box.v.upper, domain.v.upper)))
                        }
                        guard depth < maximumDepth else { break }
                        depth += 1
                        left = try left.adding(witness, usage: &budget).divided(by: two, usage: &budget)
                        right = try right.adding(witness, usage: &budget).divided(by: two, usage: &budget)
                        coefficientWidth = try coefficientWidth.divided(by: two, usage: &budget)
                    }
                }
                for positive in [true, false] {
                    var upper = positive ? chart.parameterDomain.upper : -chart.parameterDomain.lower
                    var depth = chart.sourceDepth
                    var coefficientWidth = try ExactRationalCoefficient.originalDouble(
                        min(domain.u.width, domain.v.width), usage: &budget)
                    let two = try ExactRationalCoefficient.natural(2, usage: &budget)
                    while depth <= maximumDepth {
                        try budget.visitExactCell(depth: depth)
                        let lower = upper * 0.5
                        guard lower > 0, lower < upper, upper.isFinite else { break }
                        let interval = try ScalarInterval(lower: positive ? lower : -upper,
                            upper: positive ? upper : -lower)
                        let enclosure = try chart.enclosure(over: interval,
                            maximumCoefficientWidth: coefficientWidth, maximumDepth: maximumDepth, usage: &budget)
                        let box = enclosure.originalParameters
                        guard enclosure.originalDerivatives.count == 4 else {
                            throw GeometryConversionError.invalidInput("Original singular chart lost its native parameter differential.")
                        }
                        let derivative = enclosure.originalDerivatives[1]
                        let nonconstant = derivative.x.lower > 0 || derivative.x.upper < 0
                            || derivative.y.lower > 0 || derivative.y.upper < 0
                        if nonconstant, box.u.lower >= domain.u.lower, box.u.upper <= domain.u.upper,
                           box.v.lower >= domain.v.lower, box.v.upper <= domain.v.upper { return box }
                        if box.u.upper < domain.u.lower || box.u.lower > domain.u.upper
                            || box.v.upper < domain.v.lower || box.v.lower > domain.v.upper { break }
                        guard depth < maximumDepth else { break }
                        depth += 1; upper = lower
                        coefficientWidth = try coefficientWidth.divided(by: two, usage: &budget)
                    }
                }
            }
        }
        return nil
    }
}
