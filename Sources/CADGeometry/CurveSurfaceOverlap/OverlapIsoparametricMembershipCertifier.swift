import CADCore

/// Certifies native-basis isocurves without treating projection as proof.
struct OverlapIsoparametricMembershipCertifier {
    struct Certificate {
        let correspondence: OverlapIsoparametricCorrespondence
        let deviation: Double
    }

    func certificate(curve: BSplineCurve3D, surface: BSplineSurface3D,
                     range: ScalarInterval, options: CurveSurfaceIntersectionOptions,
                     tolerance: ModelingTolerance) throws -> Certificate? {
        guard !curve.isPeriodic, !surface.isUPeriodic, !surface.isVPeriodic,
              case let .closed(lower, upper) = curve.domain else { return nil }
        guard curve.controlPointCount <= options.maximumSubdivisionCells,
              surface.uControlPointCount <= options.maximumSubdivisionCells,
              surface.vControlPointCount <= options.maximumSubdivisionCells else {
            throw failure(.resourceLimitExceeded, "Isoparametric control storage exceeds the work budget.", tolerance)
        }
        var remainingWork = options.maximumSubdivisionCells
        for reversed in [false, true] {
            try Task.checkCancellation()
            if reversed {
                // The reflected knot vector must represent the exact affine chart
                // map, rather than a nearby map produced by rounded knot arithmetic.
                guard exactSum(lower, upper), curve.knots.allSatisfy({ exactSum(lower + upper, -$0) }) else { continue }
            }
            let source = reversed ? try curve.reversed(tolerance: tolerance) : curve
            for variesU in [true, false] {
                let degree = variesU ? surface.uDegree : surface.vDegree
                let knots = variesU ? surface.uKnots : surface.vKnots
                guard source.degree == degree, source.knots == knots,
                      source.controlPointCount == (variesU ? surface.uControlPointCount : surface.vControlPointCount),
                      case let .closed(fixedLower, fixedUpper) = (variesU ? surface.vDomain : surface.uDomain) else { continue }
                guard degree <= options.maximumPolynomialDegree else {
                    throw failure(.resourceLimitExceeded, "Isoparametric membership exceeds the degree budget.", tolerance)
                }
                var fixedCandidates = [fixedLower, fixedUpper]
                var projected = false
                var index = 0
                while index < fixedCandidates.count || !projected {
                    try Task.checkCancellation()
                    if index == fixedCandidates.count {
                        projected = true
                        // This station supplies a trial coordinate only. Every admitted
                        // trial still proves all homogeneous controls below.
                        let point = try Curve3D.bSpline(curve).point(at: range.lower, tolerance: tolerance)
                        if case .projected(let projection) = try Surface3D.bSpline(surface)
                            .parameterProjectionResult(of: point, tolerance: tolerance) {
                            let fixed = variesU ? projection.v : projection.u
                            if fixed >= fixedLower, fixed <= fixedUpper, !fixedCandidates.contains(fixed) {
                                fixedCandidates.append(fixed)
                            }
                        }
                        if index == fixedCandidates.count { break }
                    }
                    let fixed = fixedCandidates[index]
                    index += 1
                    let bound = try deviation(source: source, surface: surface, variesU: variesU,
                        fixed: fixed, remainingWork: &remainingWork, options: options, tolerance: tolerance)
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

    private func deviation(source: BSplineCurve3D, surface: BSplineSurface3D, variesU: Bool,
                           fixed: Double, remainingWork: inout Int,
                           options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> Double {
        let count = variesU ? surface.vControlPointCount : surface.uControlPointCount
        let degree = variesU ? surface.vDegree : surface.uDegree
        let knots = variesU ? surface.vKnots : surface.uKnots
        guard degree <= options.maximumPolynomialDegree else {
            throw failure(.resourceLimitExceeded, "Isoparametric fixed-axis basis exceeds the degree budget.", tolerance)
        }
        let product = source.controlPointCount.multipliedReportingOverflow(by: count)
        let recurrence = count.multipliedReportingOverflow(by: degree + 1)
        let total = product.partialValue.addingReportingOverflow(recurrence.partialValue)
        guard !product.overflow, !recurrence.overflow, !total.overflow,
              total.partialValue <= remainingWork else {
            throw failure(.resourceLimitExceeded, "Isoparametric certification exceeds the control-work budget.", tolerance)
        }
        remainingWork -= total.partialValue
        let basis = try basisValues(parameter: fixed, degree: degree, knots: knots, count: count, tolerance: tolerance)
        let anchor = source.controlPoints[0]
        var maximumNumeratorError = [0.0, 0.0, 0.0]
        var maximumWeightError = 0.0
        var minimumWeight = Double.infinity
        let coordinate: [(Point3D) -> Double] = [{ $0.x }, { $0.y }, { $0.z }]
        for index in source.controlPoints.indices {
            try Task.checkCancellation()
            var weight = OutwardScalarInterval.exact(0)
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
            maximumWeightError = max(maximumWeightError, (weight - .exact(source.weights[index])).absoluteUpperBound)
            for axis in 0..<3 {
                let authored = (.exact(coordinate[axis](source.controlPoints[index])) - .exact(coordinate[axis](anchor)))
                    * OutwardScalarInterval.exact(source.weights[index])
                maximumNumeratorError[axis] = max(maximumNumeratorError[axis], (numerator[axis] - authored).absoluteUpperBound)
            }
        }
        guard minimumWeight.isFinite, minimumWeight > 0 else {
            throw failure(.singularGeometry, "Isoparametric target denominator has no positive enclosure.", tolerance)
        }
        var bound = OutwardScalarInterval.exact(0)
        for axis in 0..<3 {
            let magnitude = source.controlPoints.map {
                (OutwardScalarInterval.exact(coordinate[axis]($0)) - .exact(coordinate[axis](anchor))).absoluteUpperBound
            }.max() ?? .infinity
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
                             tolerance: ModelingTolerance) throws -> [OutwardScalarInterval] {
        let upper = knots[knots.count - degree - 1]
        let endpoint = (0..<count).reversed().first { knots[$0] < upper && knots[$0 + 1] == upper }
        var values = (0..<count).map { index in
            OutwardScalarInterval.exact(parameter == upper
                ? (index == endpoint ? 1 : 0)
                : (parameter >= knots[index] && parameter < knots[index + 1] ? 1 : 0))
        }
        if degree > 0 {
            for current in 1...degree {
                try Task.checkCancellation()
                var next = Array(repeating: OutwardScalarInterval.exact(0), count: count)
                for index in 0..<count {
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
