import CADCore

/// Certifies native-basis isocurves without treating projection as proof.
struct OverlapIsoparametricMembershipCertifier {
    struct Certificate: Sendable {
        let correspondence: OverlapIsoparametricCorrespondence
        let deviation: Double
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This retained verification algorithm
    // bounds homogeneous deviation without issuing original source equality.
    // Public CS dispatch bypasses it; U4 must provide an exact source relation
    // before a successful certificate can authorize intersection publication.
    func certificate(curve: BSplineCurve3D, surface: BSplineSurface3D,
                     range: ScalarInterval, options: CurveSurfaceIntersectionOptions,
                     tolerance: ModelingTolerance) throws -> Certificate? {
        var execution = try OriginalQueryExecution.independentGeometry()
        let policy = try OverlapProofPolicy(options: options, tolerance: tolerance, using: &execution)
        return try certificate(curve: curve, surface: surface, range: range,
            options: options, tolerance: tolerance, policy: policy, using: &execution)
    }

    private func nonperiodicCertificate(curve: BSplineCurve3D, surface: BSplineSurface3D,
        range: ScalarInterval, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, policy: OverlapProofPolicy,
        using execution: inout OriginalQueryExecution) throws -> Certificate? {
        guard !curve.isPeriodic, !surface.isUPeriodic, !surface.isVPeriodic,
              case let .closed(lower, upper) = curve.domain else { return nil }
        guard curve.controlPointCount <= options.maximumSubdivisionCells,
              surface.uControlPointCount <= options.maximumSubdivisionCells,
              surface.vControlPointCount <= options.maximumSubdivisionCells else {
            throw failure(.resourceLimitExceeded, "Isoparametric control storage exceeds the work policy.", tolerance)
        }
        for reversed in [false, true] {
            try CurrentTaskCancellationChecker().checkCancellation()
            if reversed {
                // The reflected knot vector must represent the exact affine chart
                // map, rather than a nearby map produced by rounded knot arithmetic.
                guard exactSum(lower, upper), curve.knots.allSatisfy({ exactSum(lower + upper, -$0) }) else { continue }
            }
            let source = reversed ? try curve.reversed(tolerance: tolerance, using: &execution) : curve
            for variesU in [true, false] {
                let degree = variesU ? surface.uDegree : surface.vDegree
                let knots = variesU ? surface.uKnots : surface.vKnots
                guard source.degree == degree, source.knots == knots,
                      source.controlPointCount == (variesU ? surface.uControlPointCount : surface.vControlPointCount),
                      case let .closed(fixedLower, fixedUpper) = (variesU ? surface.vDomain : surface.uDomain) else { continue }
                guard degree <= options.maximumPolynomialDegree else {
                    throw failure(.resourceLimitExceeded, "Isoparametric membership exceeds the degree policy.", tolerance)
                }
                var fixedCandidates = try CertifiedAnalyticCurveEvaluation.values(fixedLower, fixedUpper, using: &execution)
                var fixedCandidatesCapacity = 2
                var projected = false
                var index = 0
                while index < fixedCandidates.count || !projected {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    if index == fixedCandidates.count {
                        projected = true
                        // This station supplies a trial coordinate only. Every admitted
                        // trial still proves all homogeneous controls below.
                        let point = try Curve3D.bSpline(curve).point(at: range.lower, tolerance: tolerance, using: &execution)
                        if case .projected(let projection) = try Surface3D.bSpline(surface)
                            .parameterProjectionResult(of: point, tolerance: tolerance, using: &execution) {
                            let fixed = variesU ? projection.v : projection.u
                            if fixed >= fixedLower, fixed <= fixedUpper, !fixedCandidates.contains(fixed) {
                                try CertifiedAnalyticCurveEvaluation.append(fixed, to: &fixedCandidates, using: &execution, capacity: &fixedCandidatesCapacity)
                            }
                        }
                        if index == fixedCandidates.count { break }
                    }
                    let fixed = fixedCandidates[index]
                    index += 1
                    let bound = try deviation(source: source, surface: surface, variesU: variesU,
                        fixed: fixed, policy: policy, options: options, tolerance: tolerance, using: &execution)
                    if bound <= tolerance.distance {
                        let sum: Double? = reversed ? lower + upper : nil
                        guard sum?.isFinite ?? true else {
                            throw failure(.resourceLimitExceeded, "Reversed isoparametric correspondence exceeded finite arithmetic.", tolerance)
                        }
                        return Certificate(correspondence: .init(variesU: variesU,
                            fixedCoordinate: fixed, reversedParameterSum: sum), deviation: bound)
                    }
                }
            }
        }
        return nil
    }

    /// Periodic membership and clipping consume the same invocation policy.
    /// The legacy nonperiodic fee contract remains in the original overload.
    // FIXME(INCOMPLETE_IMPLEMENTATION): This retained verification algorithm
    // bounds homogeneous deviation without issuing original source equality.
    // Public CS dispatch bypasses it; U4 must provide an exact source relation
    // before a successful certificate can authorize intersection publication.
    func certificate(curve: BSplineCurve3D, surface: BSplineSurface3D,
                     range: ScalarInterval, options: CurveSurfaceIntersectionOptions,
                     tolerance: ModelingTolerance, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Certificate? {
        if !curve.isPeriodic {
            return try nonperiodicCertificate(curve: curve, surface: surface, range: range,
                options: options, tolerance: tolerance, policy: policy, using: &execution)
        }
        guard surface.isUPeriodic != surface.isVPeriodic else { return nil }
        let variesU = surface.isUPeriodic
        let targetDegree = variesU ? surface.uDegree : surface.vDegree
        let targetKnots = variesU ? surface.uKnots : surface.vKnots
        let targetCount = variesU ? surface.uControlPointCount : surface.vControlPointCount
        guard curve.degree == targetDegree, curve.controlPointCount == targetCount,
              case let .closed(fixedLower, fixedUpper) = (variesU ? surface.vDomain : surface.uDomain) else { return nil }
        guard max(curve.degree, max(surface.uDegree, surface.vDegree)) <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Periodic isoparametric membership exceeds the degree policy.", tolerance)
        }
        let tensor = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
        let controls = tensor.partialValue.addingReportingOverflow(curve.controlPointCount)
        let controlWork = controls.partialValue.multipliedReportingOverflow(by: 4)
        let targetKnotCount = surface.uKnots.count.addingReportingOverflow(surface.vKnots.count)
        let knots = curve.knots.count.addingReportingOverflow(targetKnotCount.partialValue)
        let scan = controlWork.partialValue.addingReportingOverflow(knots.partialValue)
        let fee = scan.partialValue.addingReportingOverflow(8)
        guard !tensor.overflow, !controls.overflow, !controlWork.overflow, !targetKnotCount.overflow, !knots.overflow,
              !scan.overflow, !fee.overflow else {
            throw failure(.resourceLimitExceeded, "Periodic original control scan count overflowed.", tolerance)
        }
        try policy.work(fee.partialValue, using: &execution)
        try curve.validate(tolerance: tolerance, using: &execution)
        try surface.validate(tolerance: tolerance, using: &execution)
        guard let period = try exactCycle(degree: curve.degree, knots: curve.knots,
                  count: curve.controlPointCount, tolerance: tolerance, using: &execution),
              let targetPeriod = try exactCycle(degree: targetDegree, knots: targetKnots,
                  count: targetCount, tolerance: tolerance, using: &execution), period == targetPeriod,
              try exactOriginShift(curve.periodicOrigin ?? curve.knots[curve.degree],
                  (variesU ? surface.uPeriodicOrigin : surface.vPeriodicOrigin) ?? targetKnots[targetDegree],
                  period: period, using: &execution) else {
            throw failure(.unsupportedCapability, "Periodic isocurve origins or stored translations have no exact common-cycle authority.", tolerance)
        }
        guard case let .closed(lower, upper) = curve.fundamentalDomain else { return nil }
        for reversed in [false, true] {
            try policy.work(using: &execution)
            if reversed {
                guard exactSum(lower, upper), curve.knots.allSatisfy({ exactSum(lower + upper, -$0) }) else { continue }
                // Reflected controls and knots are allocated only after their work is paid.
                try policy.work(curve.controlPointCount + curve.knots.count, using: &execution)
            }
            let source = reversed ? try curve.reversed(tolerance: tolerance, using: &execution) : curve
            guard source.knots == targetKnots else { continue }
            try policy.storage(2, using: &execution)
            for fixed in [fixedLower, fixedUpper] {
                let count = variesU ? surface.vControlPointCount : surface.uControlPointCount
                let degree = variesU ? surface.vDegree : surface.uDegree
                let product = source.controlPointCount.multipliedReportingOverflow(by: count)
                let recurrence = count.multipliedReportingOverflow(by: degree + 1)
                let work = product.partialValue.addingReportingOverflow(recurrence.partialValue)
                guard !product.overflow, !recurrence.overflow, !work.overflow else {
                    throw failure(.resourceLimitExceeded, "Periodic isoparametric control work overflowed.", tolerance)
                }
                try policy.work(work.partialValue, using: &execution)
                let bound = try deviationValues(source: source, surface: surface, variesU: variesU,
                    fixed: fixed, tolerance: tolerance, using: &execution)
                if bound <= tolerance.distance {
                    try policy.storage(using: &execution)
                    return Certificate(correspondence: .init(variesU: variesU, fixedCoordinate: fixed,
                        reversedParameterSum: reversed ? lower + upper : nil,
                        periodic: .init(period: period, sourceRange: range)), deviation: bound)
                }
            }
        }
        // Candidates come from every original fixed-axis span. The complete
        // homogeneous residual remains the sole publication authority.
        let fixedKnots = variesU ? surface.vKnots : surface.uKnots
        let fixedDegree = variesU ? surface.vDegree : surface.uDegree
        let fixedCount = variesU ? surface.vControlPointCount : surface.uControlPointCount
        for reversed in [false, true] {
            try policy.work(using: &execution)
            if reversed {
                guard exactSum(lower, upper), curve.knots.allSatisfy({ exactSum(lower + upper, -$0) }) else { continue }
                try policy.work(curve.controlPointCount + curve.knots.count, using: &execution)
            }
            let source = reversed ? try curve.reversed(tolerance: tolerance, using: &execution) : curve
            guard source.knots == targetKnots else { continue }
            for span in fixedDegree..<fixedCount where fixedKnots[span] < fixedKnots[span + 1] {
                try policy.storage(using: &execution)
                var fixed = fixedKnots[span] * 0.5 + fixedKnots[span + 1] * 0.5
                guard fixed.isFinite else { throw failure(.resourceLimitExceeded, "Periodic fixed-axis seed is nonfinite.", tolerance) }
                for _ in 0..<options.maximumIterations {
                    try chargePeriodicControlProbe(source: source, fixedCount: fixedCount,
                        fixedDegree: fixedDegree, policy: policy, tolerance: tolerance, using: &execution)
                    let bound = try deviationValues(source: source, surface: surface, variesU: variesU,
                        fixed: fixed, tolerance: tolerance, using: &execution)
                    if bound <= tolerance.distance {
                        try policy.storage(using: &execution)
                        return Certificate(correspondence: .init(variesU: variesU, fixedCoordinate: fixed,
                            reversedParameterSum: reversed ? lower + upper : nil,
                            periodic: .init(period: period, sourceRange: range)), deviation: bound)
                    }
                    // The represented fixed parameter is a predictor only. The
                    // original basis and Cartesian control ratios determine its step.
                    try chargePeriodicControlProbe(source: source, fixedCount: fixedCount,
                        fixedDegree: fixedDegree, policy: policy, tolerance: tolerance, using: &execution)
                    let basis = try BSplineBasis.nonzeroDerivativeValues(parameter: fixed,
                        degree: fixedDegree, throughDerivativeOrder: 1, knots: fixedKnots,
                        count: fixedCount, owningSpan: span, tolerance: tolerance, using: &execution)
                    var gradient = 0.0, metric = 0.0
                    for index in source.controlPoints.indices {
                        var w = 0.0, dw = 0.0
                        var n = Vector3D.zero, dn = Vector3D.zero
                        for local in basis[0].values.indices {
                            let other = basis[0].startIndex + local
                            let row = variesU ? other : index, column = variesU ? index : other
                            let weight = surface.weights[row][column]
                            let a = basis[0].values[local] * weight
                            let b = basis[1].values[local] * weight
                            let point = surface.controlPoints[row][column]
                            w += a; dw += b
                            let delta = point - source.controlPoints[index]
                            n = n + delta * a; dn = dn + delta * b
                        }
                        guard w.isFinite, w > 0, dw.isFinite else {
                            throw failure(.singularGeometry, "Periodic original fixed-axis predictor has no positive denominator.", tolerance)
                        }
                        let residual = n * (1 / w)
                        let derivative = (dn + residual * (-dw)) * (1 / w)
                        gradient += residual.dot(derivative)
                        metric += derivative.dot(derivative)
                    }
                    guard gradient.isFinite, metric.isFinite else {
                        throw failure(.resourceLimitExceeded, "Periodic original predictor arithmetic is nonfinite.", tolerance)
                    }
                    guard metric > 0 else { break }
                    let proposed = fixed - gradient / metric
                    guard proposed.isFinite else { break }
                    let next = max(fixedKnots[span], min(fixedKnots[span + 1], proposed))
                    guard next != fixed else { break }
                    fixed = next
                }
            }
        }
        return nil
    }

    private func chargePeriodicControlProbe(source: BSplineCurve3D, fixedCount: Int,
        fixedDegree: Int, policy: OverlapProofPolicy, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        let controls = source.controlPointCount.multipliedReportingOverflow(by: fixedCount)
        let basis = fixedCount.multipliedReportingOverflow(by: fixedDegree + 1)
        let controlWork = controls.partialValue.multipliedReportingOverflow(by: 96)
        let basisWork = basis.partialValue.multipliedReportingOverflow(by: 64)
        let total = controlWork.partialValue.addingReportingOverflow(basisWork.partialValue)
        guard !controls.overflow, !basis.overflow, !controlWork.overflow, !basisWork.overflow, !total.overflow else {
            throw failure(.resourceLimitExceeded, "Periodic interior original control probe dimensions overflowed.", tolerance)
        }
        try policy.work(total.partialValue, using: &execution)
    }

    private func exactCycle(degree: Int, knots: [Double], count: Int,
                            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double? {
        let lower = knots[degree], upper = knots[count], period = upper - lower
        guard period.isFinite, period > 0, exactSum(upper, -lower) else { return nil }
        let independent = count - degree
        guard independent > 0 else { return nil }
        for index in 0..<(knots.count - independent) {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard exactSum(knots[index], period), knots[index] + period == knots[index + independent] else { return nil }
        }
        return period
    }

    private func exactOriginShift(_ first: Double, _ second: Double, period: Double, using execution: inout OriginalQueryExecution) throws -> Bool {
        if first == second { return true }
        let difference = second - first
        guard exactSum(second, -first), difference.isFinite else { return false }
        let cycle = difference / period
        guard cycle.isFinite, abs(cycle) <= 9_007_199_254_740_991, cycle.rounded() == cycle,
              (cycle * 134_217_729).isFinite, (period * 134_217_729).isFinite else { return false }
        let product = try FloatingPointExpansion.product([cycle], [period], using: &execution)
        return try FloatingPointExpansion.sign(FloatingPointExpansion.subtract(product, [difference], using: &execution), using: &execution) == .zero
    }

    private func deviation(source: BSplineCurve3D, surface: BSplineSurface3D, variesU: Bool,
                           fixed: Double, policy: OverlapProofPolicy,
                           options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        let count = variesU ? surface.vControlPointCount : surface.uControlPointCount
        let degree = variesU ? surface.vDegree : surface.uDegree
        guard degree <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Isoparametric fixed-axis basis exceeds the degree policy.", tolerance)
        }
        let product = source.controlPointCount.multipliedReportingOverflow(by: count)
        let recurrence = count.multipliedReportingOverflow(by: degree + 1)
        let total = product.partialValue.addingReportingOverflow(recurrence.partialValue)
        guard !product.overflow, !recurrence.overflow, !total.overflow else {
            throw failure(.resourceLimitExceeded, "Isoparametric certification exceeds the control-work policy.", tolerance)
        }
        try policy.work(total.partialValue, using: &execution)
        return try deviationValues(source: source, surface: surface, variesU: variesU,
            fixed: fixed, tolerance: tolerance, using: &execution)
    }

    private func deviationValues(source: BSplineCurve3D, surface: BSplineSurface3D,
                                 variesU: Bool, fixed: Double,
                                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        let count = variesU ? surface.vControlPointCount : surface.uControlPointCount
        let degree = variesU ? surface.vDegree : surface.uDegree
        let knots = variesU ? surface.vKnots : surface.uKnots
        let basis = try basisValues(parameter: fixed, degree: degree, knots: knots, count: count, tolerance: tolerance, using: &execution)
        let anchor = source.controlPoints[0]
        var firstWeight = OutwardScalarInterval.exact(0)
        for other in 0..<count {
            let row = variesU ? other : 0, column = variesU ? 0 : other
            firstWeight = firstWeight + basis[other] * .exact(surface.weights[row][column])
        }
        guard let homogeneousScale = firstWeight.divided(by: .exact(source.weights[0])),
              homogeneousScale.isFinite, homogeneousScale.lower > 0 else {
            throw failure(.singularGeometry, "Isoparametric original homogeneous scale is unresolved.", tolerance)
        }
        try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
        var maximumNumeratorError = [0.0, 0.0, 0.0]
        var maximumWeightError = 0.0
        var minimumWeight = Double.infinity
        let coordinate: [(Point3D) -> Double] = [{ $0.x }, { $0.y }, { $0.z }]
        for index in source.controlPoints.indices {
            try CurrentTaskCancellationChecker().checkCancellation()
            var weight = OutwardScalarInterval.exact(0)
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: 3, of: OutwardScalarInterval.self, using: &execution)
            var numerator = Array(repeating: OutwardScalarInterval.exact(0), count: 3)
            for other in 0..<count {
                let row = variesU ? other : index, column = variesU ? index : other
                let coefficient = basis[other] * .exact(surface.weights[row][column])
                weight = weight + coefficient
                for axis in 0..<3 {
                    numerator[axis] = numerator[axis] + coefficient
                        * (.exact(coordinate[axis](surface.controlPoints[row][column])) - .exact(coordinate[axis](anchor)))
                }
            }
            minimumWeight = min(minimumWeight, weight.lower)
            maximumWeightError = max(maximumWeightError, (weight - .exact(source.weights[index]) * homogeneousScale).absoluteUpperBound)
            for axis in 0..<3 {
                let authored = (.exact(coordinate[axis](source.controlPoints[index])) - .exact(coordinate[axis](anchor)))
                    * OutwardScalarInterval.exact(source.weights[index]) * homogeneousScale
                maximumNumeratorError[axis] = max(maximumNumeratorError[axis], (numerator[axis] - authored).absoluteUpperBound)
            }
        }
        guard minimumWeight.isFinite, minimumWeight > 0 else {
            throw failure(.singularGeometry, "Isoparametric target denominator has no positive enclosure.", tolerance)
        }
        var bound = OutwardScalarInterval.exact(0)
        for axis in 0..<3 {
            var magnitude = 0.0
            for point in source.controlPoints {
                try execution.consumeWork(1)
                magnitude = max(magnitude, (OutwardScalarInterval.exact(coordinate[axis](point))
                    - .exact(coordinate[axis](anchor))).absoluteUpperBound)
            }
            let residual = OutwardScalarInterval.exact(maximumNumeratorError[axis])
                + .exact(magnitude) * .exact(maximumWeightError)
            guard let quotient = residual.divided(by: .exact(minimumWeight)), quotient.isFinite else {
                throw failure(.resourceLimitExceeded, "Isoparametric residual certification exceeded finite arithmetic.", tolerance)
            }
            bound = bound + quotient
        }
        guard bound.isFinite else { throw failure(.resourceLimitExceeded, "Isoparametric spatial bound is nonfinite.", tolerance) }
        return max(0, bound.upper)
    }

    private func basisValues(parameter: Double, degree: Int, knots: [Double], count: Int,
                             tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OutwardScalarInterval] {
        let upper = knots[knots.count - degree - 1]
        let endpoint = (0..<count).reversed().first { knots[$0] < upper && knots[$0 + 1] == upper }
        try OriginalCoefficientAllocation.reserve(count: count, of: OutwardScalarInterval.self, using: &execution)
        var values = try (0..<count).map { index in
            try execution.consumeWork(1)
            return OutwardScalarInterval.exact(parameter == upper
                ? (index == endpoint ? 1 : 0)
                : (parameter >= knots[index] && parameter < knots[index + 1] ? 1 : 0))
        }
        if degree > 0 {
            for current in 1...degree {
                try CurrentTaskCancellationChecker().checkCancellation()
                try OriginalCoefficientAllocation.reserve(count: count, of: OutwardScalarInterval.self, using: &execution)
                var next = Array(repeating: OutwardScalarInterval.exact(0), count: count)
                for index in 0..<count {
                    try execution.consumeWork(1)
                    let left = OutwardScalarInterval.exact(knots[index + current]) - .exact(knots[index])
                    if knots[index + current] > knots[index] {
                        guard let quotient = (.exact(parameter) - OutwardScalarInterval.exact(knots[index])).divided(by: left) else {
                            throw failure(.singularGeometry, "Isoparametric basis denominator is unresolved.", tolerance)
                        }
                        next[index] = next[index] + quotient * values[index]
                    }
                    if index + 1 < count, knots[index + current + 1] > knots[index + 1] {
                        let right = OutwardScalarInterval.exact(knots[index + current + 1]) - .exact(knots[index + 1])
                        guard let quotient = (OutwardScalarInterval.exact(knots[index + current + 1]) - .exact(parameter)).divided(by: right) else {
                            throw failure(.singularGeometry, "Isoparametric basis denominator is unresolved.", tolerance)
                        }
                        next[index] = next[index] + quotient * values[index + 1]
                    }
                    guard next[index].isFinite else { throw failure(.resourceLimitExceeded, "Isoparametric basis arithmetic is nonfinite.", tolerance) }
                }
                values = next
            }
        }
        return values
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }

    private func exactSum(_ first: Double, _ second: Double) -> Bool {
        let sum = first + second
        guard sum.isFinite else { return false }
        let virtualSecond = sum - first
        let error = (first - (sum - virtualSecond)) + (second - virtualSecond)
        return error == 0
    }
}
