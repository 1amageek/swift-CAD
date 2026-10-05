import CADCore

/// Original near-parallel field continuation with whole spatial and angular bounds.
struct OriginalProjectedFieldCurveCurveToleranceContact {
    func certificate(original: OriginalAtlasCurveCurveFieldEquationSet,
        over domain: SurfaceParameterBox, maximumDepth: Int,
        selectedJets: (ScalarInterval, ScalarInterval, inout NativeCurveCurveContactBudget) throws
            -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
        budget: inout NativeCurveCurveContactBudget) throws -> SurfaceParameterBox? {
        let equations = original.equations, denominator = original.denominator
        guard equations.count == 3, maximumDepth >= 0, domain.u.width > 0, domain.v.width > 0 else {
            throw budget.exhausted()
        }
        let coefficientWidth = try ExactRationalCoefficient.originalDouble(budget.tolerance.relative, usage: &budget)
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        func derivative(_ value: OriginalSingularFieldPlanePolynomial, alongU: Bool,
            budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldPlanePolynomial {
            let prior = budget.enterExactAlgebra(); defer { budget.restoreExactAlgebra(prior) }
            return try value.differentiated(alongU: alongU, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
        }
        func product(_ first: OriginalSingularFieldPlanePolynomial, _ second: OriginalSingularFieldPlanePolynomial,
            minusThird: OriginalSingularFieldPlanePolynomial, timesFourth: OriginalSingularFieldPlanePolynomial,
            budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldPlanePolynomial {
            let prior = budget.enterExactAlgebra(); defer { budget.restoreExactAlgebra(prior) }
            return try first.multiplied(by: second, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                .subtracting(minusThird.multiplied(by: timesFourth,
                    maximumDepth: budget.maximumAlgebraicDepth, usage: &budget),
                    maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
        }
        func remainder(_ value: OriginalSingularFieldPlanePolynomial, by relation: OriginalSingularFieldPlanePolynomial,
            budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldPlanePolynomial {
            let prior = budget.enterExactAlgebra(); defer { budget.restoreExactAlgebra(prior) }
            return try value.quotientAndRemainder(dividingBy: relation,
                maximumDepth: budget.maximumAlgebraicDepth, usage: &budget).remainder
        }
        func bounds(_ value: OriginalSingularFieldPlanePolynomial, over box: SurfaceParameterBox,
            budget: inout NativeCurveCurveContactBudget) throws -> OutwardScalarInterval {
            let prior = budget.enterExactAlgebra(); defer { budget.restoreExactAlgebra(prior) }
            return try value.partial(over: box, uOrder: 0, vOrder: 0,
                maximumCoefficientWidth: coefficientWidth,
                maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
        }
        func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
            .init(lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
                upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
        }
        let dU = try derivative(denominator, alongU: true, budget: &budget)
        let dV = try derivative(denominator, alongU: false, budget: &budget)
        try RationalAlgebraStorage.retain(6, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
        var firstTangents: [OriginalSingularFieldPlanePolynomial] = []
        var secondTangents: [OriginalSingularFieldPlanePolynomial] = []
        firstTangents.reserveCapacity(3); secondTangents.reserveCapacity(3)
        for equation in equations {
            let du = try derivative(equation, alongU: true, budget: &budget)
            let dv = try derivative(equation, alongU: false, budget: &budget)
            firstTangents.append(try product(du, denominator, minusThird: equation, timesFourth: dU, budget: &budget))
            secondTangents.append(try product(equation, dV, minusThird: dv, timesFourth: denominator, budget: &budget))
        }
        func admitted(_ box: SurfaceParameterBox, relation: OriginalSingularFieldPlanePolynomial,
            budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            let weight = try bounds(denominator, over: box, budget: &budget)
            guard weight.lower > 0 else { return false }
            var residual = OutwardScalarInterval.exact(0)
            for equation in equations {
                let originalRemainder = try remainder(equation, by: relation, budget: &budget)
                guard let value = try bounds(originalRemainder, over: box, budget: &budget).divided(by: weight) else {
                    throw budget.exhausted()
                }
                residual = residual + square(value)
            }
            guard residual.upper <= threshold.lower else { return false }
            let hu = try derivative(relation, alongU: true, budget: &budget)
            let hv = try derivative(relation, alongU: false, budget: &budget)
            let u = try bounds(hu, over: box, budget: &budget), v = try bounds(hv, over: box, budget: &budget)
            guard u.excludesZero, v.excludesZero,
                let mapDerivative = (-u).divided(by: v), mapDerivative.excludesZero else { return false }
            let direction = OutwardScalarInterval.exact(mapDerivative.lower > 0 ? 1 : -1)
            try RationalAlgebraStorage.retain(6, of: OutwardScalarInterval.self, usage: &budget)
            var a: [OutwardScalarInterval] = [], b: [OutwardScalarInterval] = []
            a.reserveCapacity(3); b.reserveCapacity(3)
            for axis in 0..<3 {
                let ar = try remainder(firstTangents[axis], by: relation, budget: &budget)
                let br = try remainder(secondTangents[axis], by: relation, budget: &budget)
                a.append(try bounds(ar, over: box, budget: &budget))
                b.append(try bounds(br, over: box, budget: &budget) * direction)
            }
            var lengthA = OutwardScalarInterval.exact(0), lengthB = lengthA, dot = lengthA
            for axis in 0..<3 {
                try budget.work(1)
                lengthA = lengthA + square(a[axis]); lengthB = lengthB + square(b[axis])
                dot = dot + a[axis] * b[axis]
            }
            guard lengthA.lower > 0, lengthB.lower > 0, dot.lower > 0 else { return false }
            var cross = OutwardScalarInterval.exact(0), exactParallel = true
            for axis in 0..<3 {
                let i = (axis+1)%3, j = (axis+2)%3
                let originalCross = try product(firstTangents[i], secondTangents[j],
                    minusThird: firstTangents[j], timesFourth: secondTangents[i], budget: &budget)
                let reduced = try remainder(originalCross, by: relation, budget: &budget)
                if !reduced.isZero { exactParallel = false }
                cross = cross + square(try bounds(reduced, over: box, budget: &budget))
            }
            if exactParallel { return true }
            let angular = OutwardScalarInterval.exact(min(1, budget.tolerance.angle)) * .exact(0.5)
            return cross.upper <= (angular * angular * lengthA * lengthB).lower
        }
        for equation in equations where !equation.isZero {
            let projection = try OriginalSingularFieldPlaneProjection(original: equation,
                over: domain, inheritedDepth: 0, maximumDepth: maximumDepth, usage: &budget)
            guard projection.sectors.contains(where: { !$0.fiberRoots.isEmpty }) else { continue }
            let atlas = try OriginalFieldPlaneAtlas(retaining: projection, maximumDepth: maximumDepth, usage: &budget)
            for strip in atlas.strips {
                for piece in strip.originalInteriorCover.pieces {
                    try budget.work(1)
                    guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
                    if try admitted(piece.domain, relation: projection.squareFree, budget: &budget) {
                        _ = try selectedJets(piece.domain.u, piece.domain.v, &budget)
                        return piece.domain
                    }
                }
            }
        }
        return nil
    }
}
