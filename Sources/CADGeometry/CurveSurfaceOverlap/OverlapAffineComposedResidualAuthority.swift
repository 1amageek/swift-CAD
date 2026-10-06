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

    static func preparationWork(sourceDegree: Int, uDegree: Int, vDegree: Int,
                                sourceKnots: Int, targetKnots: Int,
                                tolerance: ModelingTolerance) throws -> Int {
        if uDegree == 1 && vDegree == 1 {
            return try preparationWork(degree: sourceDegree, sourceKnots: sourceKnots,
                targetKnots: targetKnots, tolerance: tolerance)
        }
        var total = 512
        func sum(_ a: Int, _ b: Int) throws -> Int {
            let result = a.addingReportingOverflow(b)
            guard a >= 0, b >= 0, !result.overflow else { throw overflow(tolerance) }
            return result.partialValue
        }
        func product(_ a: Int, _ b: Int) throws -> Int {
            let result = a.multipliedReportingOverflow(by: b)
            guard a >= 0, b >= 0, !result.overflow else { throw overflow(tolerance) }
            return result.partialValue
        }
        func add(_ count: Int, _ factor: Int) throws {
            total = try sum(total, product(count, factor))
        }
        guard sourceDegree > 0, uDegree > 0, vDegree > 0 else { throw overflow(tolerance) }
        let targetDegree = try sum(uDegree, vDegree)
        let outputCount = try sum(sum(sourceDegree, targetDegree), 1)
        let tensorCount = try product(sum(uDegree, 1), sum(vDegree, 1))
        try add(sum(sourceKnots, targetKnots), 2)
        // Every live source/result scratch array and all six binomial recurrences.
        try add(outputCount, 128)
        // Each tensor basis product has at most tensorCount terms; accumulation
        // and its three binomial recurrences are bounded by the target degree.
        try add(product(tensorCount, tensorCount), 16)
        try add(product(tensorCount, sum(targetDegree, 1)), 32)
        // Six complete numerator products, including outward normalization.
        try add(product(sum(sourceDegree, 1), sum(targetDegree, 1)), 96)
        return total
    }

    static func certificate(source: BSplineCurve3D, target: BSplineSurface3D,
                            pair: OverlapRegularGraphCell.Pair,
                            predictor: (start: SurfaceParameter, end: SurfaceParameter)? = nil,
                            budget: inout OverlapProofBudget) throws -> Self? {
        guard !source.isPeriodic, !target.isUPeriodic, !target.isVPeriodic,
              source.degree > 0, source.degree < Int.max,
              source.degree <= budget.options.maximumPolynomialDegree,
              source.controlPointCount == source.degree + 1,
              source.weights.count == source.controlPointCount,
              target.uDegree > 0, target.vDegree > 0,
              target.uDegree < Int.max, target.vDegree < Int.max,
              target.uControlPointCount == target.uDegree + 1,
              target.vControlPointCount == target.vDegree + 1,
              target.weights.count == target.vControlPointCount,
              target.controlPoints.count == target.vControlPointCount else { return nil }
        let targetDegree = target.uDegree.addingReportingOverflow(target.vDegree)
        let composedDegree = source.degree.addingReportingOverflow(targetDegree.partialValue)
        guard !targetDegree.overflow, !composedDegree.overflow,
              composedDegree.partialValue <= budget.options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Affine composed residual exceeds the caller polynomial degree budget.", budget)
        }
        let targetKnots = target.uKnots.count.addingReportingOverflow(target.vKnots.count)
        guard !targetKnots.overflow else { throw overflow(budget.tolerance) }
        try budget.work(try preparationWork(sourceDegree: source.degree,
            uDegree: target.uDegree, vDegree: target.vDegree, sourceKnots: source.knots.count,
            targetKnots: targetKnots.partialValue, tolerance: budget.tolerance))
        guard clampedSingle(source.knots, degree: source.degree),
              clampedSingle(target.uKnots, degree: target.uDegree),
              clampedSingle(target.vKnots, degree: target.vDegree),
              target.weights.allSatisfy({ $0.count == target.uControlPointCount }),
              target.controlPoints.allSatisfy({ $0.count == target.uControlPointCount }),
              source.weights.allSatisfy({ $0.isFinite && $0 > 0 }),
              target.weights.allSatisfy({ $0.allSatisfy({ $0.isFinite && $0 > 0 }) }),
              source.controlPoints.allSatisfy(finite), target.controlPoints.allSatisfy({ $0.allSatisfy(finite) }) else { return nil }
        let ul = target.uKnots[target.uDegree], uh = target.uKnots[target.uControlPointCount]
        let vl = target.vKnots[target.vDegree], vh = target.vKnots[target.vControlPointCount]
        func corner(_ point: Point3D) -> (u: Int, v: Int)? {
            for v in 0..<2 {
                for u in 0..<2 {
                    let candidate = target.controlPoints[v == 0 ? 0 : target.vDegree][u == 0 ? 0 : target.uDegree]
                    if OverlapRegularGraphCell.coordinate(point, pair.first) == OverlapRegularGraphCell.coordinate(candidate, pair.first),
                       OverlapRegularGraphCell.coordinate(point, pair.second) == OverlapRegularGraphCell.coordinate(candidate, pair.second) {
                        return (u, v)
                    }
                }
            }
            return nil
        }
        let start: SurfaceParameter, end: SurfaceParameter
        let uBasis: [Polynomial]?, vBasis: [Polynomial]?
        let first = corner(source.controlPoints[0])
        let last = corner(source.controlPoints[source.controlPointCount - 1])
        if let first, let last {
            start = SurfaceParameter(u: first.u == 0 ? ul : uh, v: first.v == 0 ? vl : vh)
            end = SurfaceParameter(u: last.u == 0 ? ul : uh, v: last.v == 0 ? vl : vh)
            uBasis = nil; vBasis = nil
        } else if let predictor {
            func contained(_ value: SurfaceParameter) -> Bool {
                value.u.isFinite && value.v.isFinite && value.u >= ul && value.u <= uh
                    && value.v >= vl && value.v <= vh
            }
            guard contained(predictor.start), contained(predictor.end) else { return nil }
            start = predictor.start; end = predictor.end
            // Original UV seeds are only hints. Charge every complete polynomial
            // operation before allocating their outward Bernstein representations.
            try budget.work(try predictorPreparationWork(uDegree: target.uDegree,
                vDegree: target.vDegree, tolerance: budget.tolerance))
            uBasis = try affineBasis(degree: target.uDegree, start: start.u, end: end.u,
                lower: ul, upper: uh, budget: budget)
            vBasis = try affineBasis(degree: target.vDegree, start: start.v, end: end.v,
                lower: vl, upper: vh, budget: budget)
        } else { return nil }
        func cornerBasis(index: Int, degree: Int, start: Int, end: Int) -> Polynomial {
            if start == end {
                return Polynomial(repeating: .exact(index == (start == 0 ? 0 : degree) ? 1 : 0), count: degree + 1)
            }
            var values = Polynomial(repeating: .exact(0), count: degree + 1)
            values[start == 0 ? index : degree - index] = .exact(1)
            return values
        }
        let origin = source.controlPoints[0]
        var composed = [[Interval]](repeating: Polynomial(repeating: .exact(0), count: targetDegree.partialValue + 1), count: 4)
        for row in 0...target.vDegree {
            for column in 0...target.uDegree {
                try CurrentTaskCancellationChecker().checkCancellation()
                let u: Polynomial, v: Polynomial
                if let uBasis, let vBasis {
                    u = uBasis[column]; v = vBasis[row]
                } else if let first, let last {
                    u = cornerBasis(index: column, degree: target.uDegree, start: first.u, end: last.u)
                    v = cornerBasis(index: row, degree: target.vDegree, start: first.v, end: last.v)
                } else {
                    throw failure(.intersectionFailure, "An affine predictor lost its complete native basis authority.", budget)
                }
                let composedBasis = try multiply(u, v,
                    maximumDegree: budget.options.maximumPolynomialDegree, budget: budget)
                let weight = Interval.exact(target.weights[row][column])
                for axis in 0..<4 {
                    let coefficient = axis == 3 ? weight :
                        (Interval.exact(OverlapRegularGraphCell.coordinate(target.controlPoints[row][column], axis))
                            - .exact(OverlapRegularGraphCell.coordinate(origin, axis))) * weight
                    for index in composedBasis.indices { composed[axis][index] = composed[axis][index] + coefficient * composedBasis[index] }
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
            try CurrentTaskCancellationChecker().checkCancellation()
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
            start: start, end: end,
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
            // The represented affine hint remains in its original native endpoint hull.
            guard let retained = value.intersection(with: Interval(lower: min(start, end), upper: max(start, end))), retained.isFinite else {
                throw Self.failure(.intersectionFailure, "An affine residual hint lost its original native endpoint hull.", budget)
            }
            return try ScalarInterval(lower: retained.lower, upper: retained.upper)
        }
        return SurfaceParameterBox(u: try axis(start.u, end.u), v: try axis(start.v, end.v))
    }

    private static func predictorPreparationWork(uDegree: Int, vDegree: Int,
                                                 tolerance: ModelingTolerance) throws -> Int {
        var total = 64
        for degree in [uDegree, vDegree] {
            let count = degree.addingReportingOverflow(1)
            let square = count.partialValue.multipliedReportingOverflow(by: count.partialValue)
            let cube = square.partialValue.multipliedReportingOverflow(by: count.partialValue)
            let fee = cube.partialValue.multipliedReportingOverflow(by: 128)
            let next = total.addingReportingOverflow(fee.partialValue)
            guard degree > 0, !count.overflow, !square.overflow, !cube.overflow,
                  !fee.overflow, !next.overflow else { throw overflow(tolerance) }
            // Each axis owns two complete power tables, all basis products and
            // binomial recurrences. Their scalar arithmetic and scratch storage
            // are bounded by 128*(degree+1)^3 before any work is performed.
            total = next.partialValue
        }
        return total
    }

    private static func affineBasis(degree: Int, start: Double, end: Double,
                                    lower: Double, upper: Double,
                                    budget: OverlapProofBudget) throws -> [Polynomial] {
        let width = Interval.exact(upper) - .exact(lower)
        guard width.isFinite, width.lower > 0,
              let first = (Interval.exact(start) - .exact(lower)).divided(by: width),
              let last = (Interval.exact(end) - .exact(lower)).divided(by: width),
              let a = first.intersection(with: Interval(lower: 0, upper: 1)),
              let b = last.intersection(with: Interval(lower: 0, upper: 1)) else {
            throw failure(.resourceLimitExceeded, "An affine predictor has no finite original-axis normalization.", budget)
        }
        let parameter: Polynomial = [a, b]
        let complement: Polynomial = [.exact(1) - a, .exact(1) - b]
        var powers: [Polynomial] = [[.exact(1)]]
        var complements: [Polynomial] = [[.exact(1)]]
        for _ in 1...degree {
            try CurrentTaskCancellationChecker().checkCancellation()
            powers.append(try multiply(powers[powers.count - 1], parameter,
                maximumDegree: budget.options.maximumPolynomialDegree, budget: budget))
            complements.append(try multiply(complements[complements.count - 1], complement,
                maximumDegree: budget.options.maximumPolynomialDegree, budget: budget))
        }
        let coefficients = try binomials(degree, budget: budget)
        var bases: [Polynomial] = []
        for index in 0...degree {
            try CurrentTaskCancellationChecker().checkCancellation()
            let product = try multiply(powers[index], complements[degree - index],
                maximumDegree: budget.options.maximumPolynomialDegree, budget: budget)
            let values = product.map { $0 * coefficients[index] }
            guard values.allSatisfy({ $0.isFinite }) else {
                throw failure(.resourceLimitExceeded, "An affine native Bernstein basis exceeds finite arithmetic.", budget)
            }
            bases.append(values)
        }
        return bases
    }

    private static func multiply(_ a: Polynomial, _ b: Polynomial, maximumDegree: Int,
                                 budget: OverlapProofBudget) throws -> Polynomial {
        let m = a.count - 1, n = b.count - 1
        guard m + n <= maximumDegree else { throw failure(.resourceLimitExceeded, "Affine residual product exceeds its admitted degree.", budget) }
        let left = try binomials(m, budget: budget), right = try binomials(n, budget: budget), output = try binomials(m + n, budget: budget)
        var result = Polynomial(repeating: .exact(0), count: m + n + 1)
        for i in a.indices {
            try CurrentTaskCancellationChecker().checkCancellation()
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
