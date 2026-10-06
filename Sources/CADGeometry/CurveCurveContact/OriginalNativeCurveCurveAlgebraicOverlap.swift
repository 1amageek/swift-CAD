import CADCore

/// Proves a real continuous branch with signed original factor and edge laws.
struct OriginalNativeCurveCurveAlgebraicOverlap {
    func certificate(polynomial: OriginalNativeCurveCurvePolynomial,
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstParameters: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondParameters: ScalarInterval,
                     budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveAlgebraicCorrespondence? {
        let equations = polynomial.equations
        if equations.allSatisfy({ $0.isZero }) {
            try budget.work(1)
            return NativeCurveCurveAlgebraicCorrespondence(parameters: SurfaceParameterBox(u: firstParameters, v: secondParameters),
                commonFactor: .zero, originalEquationQuotients: [], dependentParameter: .unconstrained,
                firstNativeSpan: first.index, secondNativeSpan: second.index)
        }
        guard let common = polynomial.commonFactor else { return nil }
        if let branch = try OriginalCurveCurveBinomialCorrespondence().certificate(common: common,
            over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
            firstNativeSpan: first.index, secondNativeSpan: second.index,
            maximumDepth: budget.maximumDepth, budget: &budget) { return branch }
        if let branch = try OriginalCurveCurveQuadraticCorrespondence().certificate(common: common,
            over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
            firstNativeSpan: first.index, secondNativeSpan: second.index,
            maximumDepth: budget.maximumDepth, budget: &budget) { return branch }
        if let cusp = try OriginalCurveCurveCuspCorrespondence().certificate(common: common,
            over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
            firstNativeSpan: first.index, secondNativeSpan: second.index,
            maximumDepth: budget.maximumDepth, budget: &budget) { return cusp }
        let factor = common.factor
        let regularBranch = OriginalNativeCurveCurveRegularBranchSeed()
        func central(_ range: ScalarInterval, depth: Int) throws -> ScalarInterval? {
            let width = range.width
            let fractions: [(Double, Double)] = [(0.25, 0.75), (0.125, 0.375), (0.625, 0.875)]
            let pair = fractions[depth % fractions.count]
            let lower = range.lower + width * pair.0, upper = range.lower + width * pair.1
            guard lower > range.lower, upper < range.upper, lower < upper else { return nil }
            return try ScalarInterval(lower: lower, upper: upper)
        }
        // A signed derivative and opposite signs on both full boundary edges
        // establish a unique real graph for every station of the independent axis.
        // A GCD or a box containing zero alone never publishes a correspondence.
        var pending: [(parameters: SurfaceParameterBox, depth: Int)] = [
            (SurfaceParameterBox(u: firstParameters, v: secondParameters), 0)
        ]
        try budget.work(1)
        while let cell = pending.popLast() {
            try budget.cell()
            let whole = try factor.enclosure(over: cell.parameters, usage: &budget)
            if whole.absoluteLowerBound > 0 { continue }
            let firstParameters = cell.parameters.u, secondParameters = cell.parameters.v
            for pass in 0..<3 {
                if let u = try central(firstParameters, depth: pass),
                   let receipt = try regularBranch.certificate(common: common,
                    over: SurfaceParameterBox(u: u, v: secondParameters), independentAlongU: true,
                    firstNativeSpan: first.index, secondNativeSpan: second.index, budget: &budget) {
                    return receipt
                }
                if let v = try central(secondParameters, depth: pass),
                   let receipt = try regularBranch.certificate(common: common,
                    over: SurfaceParameterBox(u: firstParameters, v: v), independentAlongU: false,
                    firstNativeSpan: first.index, secondNativeSpan: second.index, budget: &budget) {
                    return receipt
                }
            }
            // The retained original pair is seeded once. A candidate slice root
            // does not cover unresolved cells or replace the signed-box proof.
            if cell.depth == 0 {
                if let receipt = try regularBranch.certificate(common: common,
                    first: first, firstRange: firstParameters, second: second, secondRange: secondParameters,
                    budget: &budget) { return receipt }
            }
            guard cell.depth < budget.maximumDepth else { continue }
            try budget.work(2)
            if firstParameters.width >= secondParameters.width {
                let middle = firstParameters.midpoint
                guard middle > firstParameters.lower, middle < firstParameters.upper else { continue }
                for u in [try ScalarInterval(lower: firstParameters.lower, upper: middle),
                          try ScalarInterval(lower: middle, upper: firstParameters.upper)] {
                    pending.append((SurfaceParameterBox(u: u, v: secondParameters), cell.depth + 1))
                }
            } else {
                let middle = secondParameters.midpoint
                guard middle > secondParameters.lower, middle < secondParameters.upper else { continue }
                for v in [try ScalarInterval(lower: secondParameters.lower, upper: middle),
                          try ScalarInterval(lower: middle, upper: secondParameters.upper)] {
                    pending.append((SurfaceParameterBox(u: firstParameters, v: v), cell.depth + 1))
                }
            }
        }
        return nil
    }
}
