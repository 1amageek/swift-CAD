import CADCore

/// Positive original near-parallel correspondence; never a zero-root exclusion.
struct OriginalProjectedCurveCurveToleranceContact {
    func certificate(equations: [ExactBivariatePolynomial], denominator: ExactBivariatePolynomial,
        over domain: SurfaceParameterBox, maximumDepth: Int,
        budget: inout NativeCurveCurveContactBudget) throws -> SurfaceParameterBox? {
        guard equations.count == 3, domain.u.width > 0, domain.v.width > 0 else { throw budget.exhausted() }
        let dU = try denominator.differentiated(alongU: true, usage: &budget)
        let dV = try denominator.differentiated(alongU: false, usage: &budget)
        try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &budget)
        var firstTangent: [ExactBivariatePolynomial] = []
        var secondTangent: [ExactBivariatePolynomial] = []
        for equation in equations {
            firstTangent.append(try equation.differentiated(alongU: true, usage: &budget)
                .multiplied(by: denominator, usage: &budget)
                .subtracting(equation.multiplied(by: dU, usage: &budget), usage: &budget))
            secondTangent.append(try equation.multiplied(by: dV, usage: &budget)
                .subtracting(equation.differentiated(alongU: false, usage: &budget)
                    .multiplied(by: denominator, usage: &budget), usage: &budget))
        }
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
            let low = value.absoluteLowerBound, high = value.absoluteUpperBound
            return .init(lower: max(0, (low * low).nextDown), upper: (high * high).nextUp)
        }
        func admitted(_ box: SurfaceParameterBox, relation: ExactBivariatePolynomial,
            hu: ExactBivariatePolynomial, hv: ExactBivariatePolynomial,
            budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            let weight = try denominator.enclosure(over: box, usage: &budget)
            guard weight.excludesZero else { return false }
            var residual = OutwardScalarInterval.exact(0)
            for equation in equations {
                let remainder = try equation.quotientAndRemainder(dividingBy: relation, usage: &budget).remainder
                guard let value = try remainder.enclosure(over: box, usage: &budget).divided(by: weight) else {
                    throw budget.exhausted()
                }
                residual = residual + square(value)
            }
            guard residual.upper <= threshold.lower else { return false }
            let u = try hu.enclosure(over: box, usage: &budget)
            let v = try hv.enclosure(over: box, usage: &budget)
            // Both original parameters must vary. A scalar graph with
            // constant other parameter is not a paired overlap witness.
            guard u.excludesZero, v.excludesZero,
                  let mapDerivative = (-u).divided(by: v), mapDerivative.excludesZero else { return false }
            let direction = OutwardScalarInterval.exact(mapDerivative.lower > 0 ? 1 : -1)
            try RationalAlgebraStorage.retain(6, of: OutwardScalarInterval.self, usage: &budget)
            var a: [OutwardScalarInterval] = [], b: [OutwardScalarInterval] = []
            for axis in 0..<3 {
                let ar = try firstTangent[axis].quotientAndRemainder(dividingBy: relation, usage: &budget).remainder
                let br = try secondTangent[axis].quotientAndRemainder(dividingBy: relation, usage: &budget).remainder
                a.append(try ar.enclosure(over: box, usage: &budget))
                b.append(try br.enclosure(over: box, usage: &budget) * direction)
            }
            var lengthA = OutwardScalarInterval.exact(0), lengthB = lengthA, dot = lengthA
            for axis in 0..<3 {
                lengthA = lengthA + square(a[axis]); lengthB = lengthB + square(b[axis])
                dot = dot + a[axis] * b[axis]
            }
            guard lengthA.lower > 0, lengthB.lower > 0, dot.lower > 0 else { return false }
            var crossSquared = OutwardScalarInterval.exact(0)
            var exactParallel = true
            for axis in 0..<3 {
                let i = (axis + 1) % 3, j = (axis + 2) % 3
                let originalCross = try firstTangent[i].multiplied(by: secondTangent[j], usage: &budget)
                    .subtracting(firstTangent[j].multiplied(by: secondTangent[i], usage: &budget), usage: &budget)
                    .quotientAndRemainder(dividingBy: relation, usage: &budget).remainder
                if !originalCross.isZero { exactParallel = false }
                crossSquared = try crossSquared + square(originalCross.enclosure(over: box, usage: &budget))
            }
            // On [0,1], sin(angle) >= angle/2. Positive dot restricts
            // the actual angle to [0,pi/2], so this sufficient original
            // bound preserves the authored angular tolerance without
            // admitting transverse crossings or changing its value.
            if exactParallel { return true }
            let angular = OutwardScalarInterval.exact(min(1, budget.tolerance.angle)) * .exact(0.5)
            let allowed = angular * angular * lengthA * lengthB
            return crossSquared.upper <= allowed.lower
        }
        for coordinate in equations.indices where !equations[coordinate].isZero {
            let authority = try OriginalRationalZeroSetAuthority(original: equations[coordinate], usage: &budget)
            let relation = authority.squareFree
            let hu = try relation.differentiated(alongU: true, usage: &budget)
            let hv = try relation.differentiated(alongU: false, usage: &budget)
            for freeAlongU in [true, false] {
                guard let graph = try ExactMonotoneRectangleGraphProducer.graph(of: relation,
                    over: domain, freeAlongU: freeAlongU, maximumDepth: maximumDepth, usage: &budget),
                    !graph.spans.isEmpty else { continue }
                for span in graph.spans {
                    let low = try graph.stations[span.lowerStation].endpoint.upper.outwardInterval(usage: &budget).upper
                    let high = try graph.stations[span.upperStation].endpoint.lower.outwardInterval(usage: &budget).lower
                    guard low < high else { continue }
                    let free = try ScalarInterval(lower: low, upper: high)
                    let box = freeAlongU ? SurfaceParameterBox(u: free, v: domain.v)
                        : SurfaceParameterBox(u: domain.u, v: free)
                    if try admitted(box, relation: relation, hu: hu, hv: hv, budget: &budget) { return box }
                }
            }
            let projection = try OriginalRationalPlaneCurveProjection(original: authority,
                over: domain, maximumDepth: maximumDepth, usage: &budget)
            // A finite exact zero set has no positive original relation sector.
            // It supplies no tolerance-contact absence authority.
            if try projection.finiteOriginalRoots(usage: &budget) != nil { continue }
            let atlas = try OriginalRationalPlaneCurveAtlas(retaining: projection,
                maximumDepth: maximumDepth, usage: &budget)
            for strip in atlas.strips {
                for piece in strip.originalCover.pieces {
                    try budget.work(1)
                    guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
                    if try admitted(piece.domain, relation: relation, hu: hu, hv: hv, budget: &budget) {
                        return piece.domain
                    }
                }
            }
        }
        return nil
    }
}
