import CADCore

/// Whole original homogeneous residual for an affine UV hint; never root existence.
struct OverlapAffineComposedResidualAuthority: Sendable {
    private typealias Interval = OutwardScalarInterval
    private typealias Polynomial = [Interval]
    let source: BSplineCurve3D
    let target: BSplineSurface3D
    let pair: OverlapRegularGraphCell.Pair
    let start: SurfaceParameter
    let end: SurfaceParameter
    let sourceDomain: ScalarInterval
    let errors: [Double]

    private init(source: BSplineCurve3D, target: BSplineSurface3D,
                 pair: OverlapRegularGraphCell.Pair, start: SurfaceParameter,
                 end: SurfaceParameter, sourceDomain: ScalarInterval, errors: [Double]) {
        self.source = source; self.target = target; self.pair = pair
        self.start = start; self.end = end; self.sourceDomain = sourceDomain; self.errors = errors
    }

    static func preparationWork(degree: Int, sourceKnots: Int, targetKnots: Int, tolerance: ModelingTolerance) throws -> Int {
        // Six polynomial products each execute at most 3*(degree+1) terms.
        // Each term includes outward normalization, multiplication and summation.
        // Recurrence and scratch fees include every live coefficient array.
        var total = 512
        func add(_ count: Int, _ factor: Int) throws {
            let product = count.multipliedReportingOverflow(by: factor)
            let next = total.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !next.overflow, count >= 0 else { throw overflow(tolerance) }
            total = next.partialValue
        }
        let n = degree.addingReportingOverflow(3)
        let knots = sourceKnots.addingReportingOverflow(targetKnots)
        guard degree >= 1, !n.overflow, !knots.overflow else { throw overflow(tolerance) }
        try add(knots.partialValue, 2)
        try add(n.partialValue, 32) // Source, target and result scratch and scans.
        try add(n.partialValue, 48) // Six outward binomial recurrences.
        try add(n.partialValue, 216) // Six products, three terms, twelve operations.
        try add(n.partialValue, 6) // Three cross-product subtractions and bounds.
        return total
    }

    static func certificate(source: BSplineCurve3D, target: BSplineSurface3D,
                            pair: OverlapRegularGraphCell.Pair,
                            budget: inout OverlapProofBudget) throws -> Self? {
        guard !source.isPeriodic, !target.isUPeriodic, !target.isVPeriodic,
              source.degree > 0, source.degree <= budget.options.maximumPolynomialDegree,
              source.controlPointCount == source.degree + 1,
              source.weights.count == source.controlPointCount,
              target.uDegree == 1, target.vDegree == 1,
              target.uControlPointCount == 2, target.vControlPointCount == 2,
              target.weights.count == 2, target.weights.allSatisfy({ $0.count == 2 }),
              target.controlPoints.allSatisfy({ $0.count == 2 }) else { return nil }
        let composedDegree = source.degree.addingReportingOverflow(2)
        guard !composedDegree.overflow, composedDegree.partialValue <= budget.options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Affine composed residual exceeds the caller polynomial degree budget.", budget)
        }
        let targetKnots = target.uKnots.count.addingReportingOverflow(target.vKnots.count)
        guard !targetKnots.overflow else { throw overflow(budget.tolerance) }
        try budget.work(try preparationWork(degree: source.degree, sourceKnots: source.knots.count,
            targetKnots: targetKnots.partialValue, tolerance: budget.tolerance))
        guard clampedSingle(source.knots, degree: source.degree),
              clampedSingle(target.uKnots, degree: 1), clampedSingle(target.vKnots, degree: 1),
              source.weights.allSatisfy({ $0.isFinite && $0 > 0 }),
              target.weights.allSatisfy({ $0.allSatisfy({ $0.isFinite && $0 > 0 }) }),
              source.controlPoints.allSatisfy(finite), target.controlPoints.allSatisfy({ $0.allSatisfy(finite) }) else { return nil }
        let ul = target.uKnots[1], uh = target.uKnots[2], vl = target.vKnots[1], vh = target.vKnots[2]
        func corner(_ point: Point3D) -> (u: Int, v: Int)? {
            for v in 0..<2 {
                for u in 0..<2 {
                    let candidate = target.controlPoints[v][u]
                    if OverlapRegularGraphCell.coordinate(point, pair.first) == OverlapRegularGraphCell.coordinate(candidate, pair.first),
                       OverlapRegularGraphCell.coordinate(point, pair.second) == OverlapRegularGraphCell.coordinate(candidate, pair.second) {
                        return (u, v)
                    }
                }
            }
            return nil
        }
        guard let first = corner(source.controlPoints[0]),
              let last = corner(source.controlPoints[source.controlPointCount - 1]) else { return nil }
        let u: Polynomial = [.exact(Double(first.u)), .exact(Double(last.u))]
        let v: Polynomial = [.exact(Double(first.v)), .exact(Double(last.v))]
        let oneMinusU = u.map { Interval.exact(1) - $0 }, oneMinusV = v.map { Interval.exact(1) - $0 }
        let origin = source.controlPoints[0]
        var composed = [[Interval]](repeating: [.exact(0), .exact(0), .exact(0)], count: 4)
        for row in 0..<2 {
            for column in 0..<2 {
                try Task.checkCancellation()
                let basis = try multiply(column == 0 ? oneMinusU : u, row == 0 ? oneMinusV : v,
                    maximumDegree: budget.options.maximumPolynomialDegree, budget: budget)
                let weight = Interval.exact(target.weights[row][column])
                for axis in 0..<4 {
                    let coefficient = axis == 3 ? weight :
                        (Interval.exact(OverlapRegularGraphCell.coordinate(target.controlPoints[row][column], axis))
                            - .exact(OverlapRegularGraphCell.coordinate(origin, axis))) * weight
                    for index in basis.indices { composed[axis][index] = composed[axis][index] + coefficient * basis[index] }
                }
            }
        }
        let sourceWeight = source.weights.map(Interval.exact)
        guard let minimumSource = source.weights.min() else { return nil }
        var minimumTarget = target.weights[0][0]
        for row in target.weights { for weight in row { minimumTarget = min(minimumTarget, weight) } }
        let denominator = Interval.exact(minimumSource) * .exact(minimumTarget)
        guard denominator.isFinite, denominator.lower > 0 else {
            throw failure(.resourceLimitExceeded, "Affine composed residual has no finite positive original denominator.", budget)
        }
        var errors: [Double] = []
        for axis in 0..<3 {
            try Task.checkCancellation()
            let spatial = source.controlPoints.indices.map {
                (Interval.exact(OverlapRegularGraphCell.coordinate(source.controlPoints[$0], axis))
                    - .exact(OverlapRegularGraphCell.coordinate(origin, axis))) * sourceWeight[$0]
            }
            let a = try multiply(composed[axis], sourceWeight,
                maximumDegree: budget.options.maximumPolynomialDegree, budget: budget)
            let b = try multiply(spatial, composed[3],
                maximumDegree: budget.options.maximumPolynomialDegree, budget: budget)
            var magnitude = 0.0
            for index in a.indices {
                let residual = a[index] - b[index]
                guard residual.isFinite else { throw failure(.resourceLimitExceeded, "Affine original residual coefficients exceed finite arithmetic.", budget) }
                magnitude = max(magnitude, residual.absoluteUpperBound)
            }
            guard let quotient = Interval.exact(magnitude).divided(by: denominator), quotient.isFinite else {
                throw failure(.resourceLimitExceeded, "Affine original residual division exceeds finite arithmetic.", budget)
            }
            errors.append(quotient.upper)
        }
        return Self(source: source, target: target, pair: pair,
            start: SurfaceParameter(u: first.u == 0 ? ul : uh, v: first.v == 0 ? vl : vh),
            end: SurfaceParameter(u: last.u == 0 ? ul : uh, v: last.v == 0 ? vl : vh),
            sourceDomain: try ScalarInterval(lower: source.knots[source.degree], upper: source.knots[source.controlPointCount]),
            errors: errors)
    }

    func candidateBox(over range: ScalarInterval, budget: inout OverlapProofBudget) throws -> SurfaceParameterBox {
        try budget.work(32)
        guard range.lower >= sourceDomain.lower, range.upper <= sourceDomain.upper else {
            throw Self.failure(.intersectionFailure, "An affine residual candidate changed its original source domain.", budget)
        }
        let width = Interval.exact(sourceDomain.upper) - .exact(sourceDomain.lower)
        guard width.isFinite, width.lower > 0,
              let normalized = (Interval(lower: range.lower, upper: range.upper) - .exact(sourceDomain.lower)).divided(by: width),
              let parameter = normalized.intersection(with: Interval(lower: 0, upper: 1)) else {
            throw Self.failure(.resourceLimitExceeded, "An affine residual candidate has no finite normalized source range.", budget)
        }
        func axis(_ start: Double, _ end: Double) throws -> ScalarInterval {
            let value = Interval.exact(start) + parameter * (Interval.exact(end) - .exact(start))
            // The original affine hint is a convex combination of native corners.
            guard let retained = value.intersection(with: Interval(lower: min(start, end), upper: max(start, end))), retained.isFinite else {
                throw Self.failure(.intersectionFailure, "An affine residual hint lost its original native corner hull.", budget)
            }
            return try ScalarInterval(lower: retained.lower, upper: retained.upper)
        }
        return SurfaceParameterBox(u: try axis(start.u, end.u), v: try axis(start.v, end.v))
    }

    private static func multiply(_ a: Polynomial, _ b: Polynomial, maximumDegree: Int,
                                 budget: OverlapProofBudget) throws -> Polynomial {
        let m = a.count - 1, n = b.count - 1
        guard m + n <= maximumDegree else { throw failure(.resourceLimitExceeded, "Affine residual product exceeds its admitted degree.", budget) }
        let left = try binomials(m, budget: budget), right = try binomials(n, budget: budget), output = try binomials(m + n, budget: budget)
        var result = Polynomial(repeating: .exact(0), count: m + n + 1)
        for i in a.indices {
            try Task.checkCancellation()
            for j in b.indices {
                guard let coefficient = (left[i] * right[j]).divided(by: output[i + j]) else {
                    throw failure(.resourceLimitExceeded, "Affine residual Bernstein normalization is unresolved.", budget)
                }
                result[i + j] = result[i + j] + a[i] * b[j] * coefficient
                guard result[i + j].isFinite else { throw failure(.resourceLimitExceeded, "Affine residual product is nonfinite.", budget) }
            }
        }
        return result
    }

    private static func binomials(_ degree: Int, budget: OverlapProofBudget) throws -> Polynomial {
        var result: Polynomial = [.exact(1)]
        if degree > 0 {
            for index in 1...degree {
                guard let value = (result[index - 1] * .exact(Double(degree - index + 1))).divided(by: .exact(Double(index))), value.isFinite else {
                    throw failure(.resourceLimitExceeded, "Affine residual binomial coefficients are nonfinite.", budget)
                }
                result.append(value)
            }
        }
        return result
    }

    private static func finite(_ point: Point3D) -> Bool { point.x.isFinite && point.y.isFinite && point.z.isFinite }
    private static func clampedSingle(_ knots: [Double], degree: Int) -> Bool {
        guard knots.count == (degree + 1) * 2 else { return false }
        let lower = knots[degree], upper = knots[degree + 1]
        return lower.isFinite && upper.isFinite && lower < upper
            && knots.prefix(degree + 1).allSatisfy({ $0 == lower })
            && knots.suffix(degree + 1).allSatisfy({ $0 == upper })
    }
    private static func failure(_ code: KernelErrorCode, _ message: String, _ budget: OverlapProofBudget) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: budget.tolerance, message: message)
    }
    private static func overflow(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: "Affine residual preparation work count overflowed.")
    }
}
