import CADCore

/// Caller-admitted original whole-use residual proof for the void facade.
struct OriginalBoundedCurveSurfaceCorrespondence {
    private struct Cell {
        let lower: Double
        let upper: Double
        let depth: Int
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded manual BRep and transformed
    // coedge validation consume this original fixed-fraction/structural proof.
    // Nonlinear correspondence and critical/global branch coverage, along with
    // required nonlinear source laws, must close before full-family
    // accounting or correspondence completeness can be reported.
    @inline(never)
    static func deviationBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution)
        throws -> Double {
        try execution.consumeWork(1); try execution.checkpoint(); try options.validate(tolerance: tolerance)
        guard start.isFinite, end.isFinite, start != end, maximumSpanCount > 0,
              maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original bounded correspondence needs a finite directed trim and caller ceilings.")
        }
        let depthLimit = min(options.maximumSubdivisionDepth, maximumSubdivisionDepth)
        let acceptance = options.maximumDeviation ?? tolerance.distance
        try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: depthLimit, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: depthLimit, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try parameterCurve.validateOriginalSource(on: surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        if let bound = try exactSourceBound(curve: curve, from: start, to: end,
            surface: surface, parameterCurve: parameterCurve, using: &execution) { return bound }
        if let bound = try wordTransportBound(curve: curve, from: start, to: end,
            surface: surface, parameterCurve: parameterCurve, options: options, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, depthLimit: depthLimit, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, acceptance: acceptance, using: &execution) { return bound }
        if let bound = try affineTransportBound(curve: curve, from: start, to: end,
            surface: surface, parameterCurve: parameterCurve, options: options, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, depthLimit: depthLimit, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, acceptance: acceptance, using: &execution) { return bound }
        return try residualBound(curve: curve, from: start, to: end,
            surface: surface, parameterCurve: parameterCurve, options: options, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, depthLimit: depthLimit, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, acceptance: acceptance, using: &execution)
    }

    @inline(never)
    private static func exactSourceBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        if case .bSpline(let nativeCurve) = curve,
           case .bSpline(let nativeSurface) = surface,
           try hasExactUnitNativeBoundaryLaw(curve: nativeCurve, from: start, to: end,
               surface: nativeSurface, parameterCurve: parameterCurve, using: &execution) {
            try execution.checkpoint()
            return 0
        }
        if case .surfaceLift(let hosted) = curve, start == 0, end == 1 {
            try GeometryStructuralComparisonWork.charge(surface: hosted.surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(parameterCurve: hosted.parameterCurve, using: &execution)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &execution)
            if hosted.surface == surface, hosted.parameterCurve == parameterCurve { return 0 }
        }
        return nil
    }

    @inline(never)
    private static func wordTransportBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, depthLimit: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, acceptance: Double, using execution: inout OriginalQueryExecution)
        throws -> Double? {
        if case .originalAffineWord(let spatial) = curve,
           case .procedural(.originalAffineWord(let support)) = surface,
           case .originalAffineWord(let chart) = parameterCurve,
           chart.startFraction == 0, chart.endFraction == 1 {
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &execution)
            if chart.target == support, chart.source.surface == support.source,
               spatial.operationWord == support.operationWord {
                guard remainingSourceDepth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original word correspondence exhausted caller source depth.")
                }
                if case .surfaceLift(let hosted) = spatial.source, start == 0, end == 1 {
                    try GeometryStructuralComparisonWork.charge(surface: hosted.surface, using: &execution)
                    try GeometryStructuralComparisonWork.charge(parameterCurve: hosted.parameterCurve, using: &execution)
                    if hosted == chart.source { return 0 }
                }
                let norm = try OriginalAffineWordJetTransport.linearNormUpper(support.preparedWord,
                    using: &execution)
                guard norm.isFinite, norm > 0,
                      let sourceAcceptance = OutwardScalarInterval.exact(acceptance).divided(by: .exact(norm)),
                      sourceAcceptance.lower > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original word correspondence cannot enclose its acceptance transport.")
                }
                let original = try deviationBound(curve: spatial.source, from: start, to: end,
                    surface: support.source, parameterCurve: chart.source.parameterCurve,
                    options: .init(maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        maximumCellCount: options.maximumCellCount, maximumDeviation: sourceAcceptance.lower),
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: depthLimit, remainingSourceDepth: remainingSourceDepth - 1,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                let transported = original == 0 ? 0 : (OutwardScalarInterval.exact(original) * .exact(norm)).upper
                guard transported <= acceptance else {
                    throw KernelError(phase: .validation, code: .topologyFailure, residual: transported,
                        tolerance: tolerance, message: "Original word coedge residual exceeds the requested junction bound.")
                }
                return transported
            }
        }
        return nil
    }

    @inline(never)
    private static func affineTransportBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, depthLimit: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, acceptance: Double, using execution: inout OriginalQueryExecution)
        throws -> Double? {
        if case .affineImage(let spatial) = curve,
           case .procedural(.originalImage(let support)) = surface,
           case .originalImage(let chart) = parameterCurve,
           chart.startFraction == 0, chart.endFraction == 1 {
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &execution)
            try execution.consumeWork(24)
            if chart.targetImage == support, chart.source.surface == support.source,
               spatial.transform == support.transform {
                guard remainingSourceDepth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original affine correspondence exhausted caller source depth.")
                }
                func column(_ value: Vector3D) -> IntervalVector3DBounds {
                    .init(x: .exact(value.x), y: .exact(value.y), z: .exact(value.z))
                }
                let norm = OutwardScalarInterval.exact(column(support.transform.basisX).lengthUpperBound)
                    + .exact(column(support.transform.basisY).lengthUpperBound)
                    + .exact(column(support.transform.basisZ).lengthUpperBound)
                guard norm.upper.isFinite, norm.upper > 0,
                      let sourceAcceptance = OutwardScalarInterval.exact(acceptance).divided(by: .exact(norm.upper)),
                      sourceAcceptance.lower > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original affine correspondence cannot enclose its acceptance transport.")
                }
                let original = try deviationBound(curve: spatial.source, from: start, to: end,
                    surface: support.source, parameterCurve: chart.source.parameterCurve,
                    options: .init(maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        maximumCellCount: options.maximumCellCount, maximumDeviation: sourceAcceptance.lower),
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: depthLimit, remainingSourceDepth: remainingSourceDepth - 1,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                let transported = (OutwardScalarInterval.exact(original) * .exact(norm.upper)).upper
                guard transported <= acceptance else {
                    throw KernelError(phase: .validation, code: .topologyFailure, residual: transported,
                        tolerance: tolerance, message: "Original affine coedge residual exceeds the requested junction bound.")
                }
                return transported
            }
        }
        return nil
    }

    @inline(never)
    private static func residualBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, depthLimit: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, acceptance: Double, using execution: inout OriginalQueryExecution)
        throws -> Double {
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original correspondence lift exhausted source depth.")
        }
        let source = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let liftedCurve = Curve3D.surfaceLift(.init(surface: surface, parameterCurve: parameterCurve))
        let lift = try PreparedCurveDifferentialEncloser(curve: liftedCurve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let smooth = try (admittedContinuity(source, over: .init(lower: min(start,end), upper: max(start,end)),
            maximumSubdivisionDepth: depthLimit, remainingSourceDepth: remainingSourceDepth,
            tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            && admittedContinuity(lift, over: .init(lower:0,upper:1), maximumSubdivisionDepth: depthLimit,
                remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution))
        let slope = OutwardScalarInterval.exact(end) - .exact(start)
        func native(_ fraction: ScalarInterval) throws -> ScalarInterval {
            let image = .exact(start) + slope * OutwardScalarInterval(lower: fraction.lower, upper: fraction.upper)
            guard let contained = image.intersection(with: .init(lower: min(start, end), upper: max(start, end))) else {
                throw GeometryConversionError.invalidInput("Original directed correspondence interval is empty.")
            }
            return try .init(lower: contained.lower, upper: contained.upper)
        }
        func positions(_ prepared: PreparedCurveDifferentialEncloser, _ range: ScalarInterval,
            _ depth: Int) throws -> IntervalVector3DBounds {
            try prepared.positionBounds(over: range, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: depthLimit - depth, remainingSourceDepth: remainingSourceDepth,
                using: &execution)
        }
        func derivative(_ prepared: PreparedCurveDifferentialEncloser, _ range: ScalarInterval,
            _ depth: Int) throws -> IntervalVector3DBounds {
            let receipt = try prepared.closedNativeJets(over: range, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: depthLimit - depth,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
            var result: IntervalVector3DBounds?
            for owner in receipt.spans {
                try execution.consumeWork(1)
                let next = IntervalVector3DBounds(x: owner.jet.x.derivativeU,
                    y: owner.jet.y.derivativeU, z: owner.jet.z.derivativeU)
                if let old = result {
                    result = .init(x: .init(lower: min(old.x.lower, next.x.lower), upper: max(old.x.upper, next.x.upper)),
                        y: .init(lower: min(old.y.lower, next.y.lower), upper: max(old.y.upper, next.y.upper)),
                        z: .init(lower: min(old.z.lower, next.z.lower), upper: max(old.z.upper, next.z.upper)))
                } else { result = next }
            }
            guard let result else { throw GeometryConversionError.invalidInput("Original correspondence derivative cover is empty.") }
            return result
        }
        let capacity = depthLimit.addingReportingOverflow(2)
        guard !capacity.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original correspondence stack capacity overflowed.") }
        try OriginalCoefficientAllocation.reserve(count: capacity.partialValue, of: Cell.self, using: &execution)
        var stack: [Cell] = []
        stack.reserveCapacity(capacity.partialValue)
        stack.append(.init(lower: 0, upper: 1, depth: 0))
        var visited = 0, result = 0.0
        while let cell = stack.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            try execution.checkpoint(); try execution.consumeWork(1)
            guard visited < options.maximumCellCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original correspondence exhausted the requested cell count.")
            }
            visited += 1
            let range = try ScalarInterval(lower: cell.lower, upper: cell.upper)
            let residual = try positions(source, native(range), cell.depth) - positions(lift, range, cell.depth)
            var upper = residual.lengthUpperBound
            let midpoint = cell.lower + (cell.upper - cell.lower) * 0.5
            if smooth, midpoint > cell.lower, midpoint < cell.upper {
                let station = try ScalarInterval(lower: midpoint, upper: midpoint)
                let center = try positions(source, native(station), cell.depth) - positions(lift, station, cell.depth)
                let first = try derivative(source, native(range), cell.depth) * slope
                    - derivative(lift, range, cell.depth)
                let delta = OutwardScalarInterval(lower: cell.lower, upper: cell.upper) - .exact(midpoint)
                upper = min(upper, (center + first * delta).lengthUpperBound)
                guard center.lengthLowerBound <= acceptance else {
                    throw KernelError(phase: .validation, code: .topologyFailure,
                        residual: center.lengthLowerBound, tolerance: tolerance,
                        message: "Original coedge correspondence has a station beyond the requested junction bound.")
                }
            }
            if upper.isFinite, upper <= acceptance { result = max(result, upper); continue }
            guard cell.depth < depthLimit, midpoint > cell.lower, midpoint < cell.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original correspondence has unresolved complete residual coverage.")
            }
            try execution.consumeWork(1)
            stack.append(.init(lower: midpoint, upper: cell.upper, depth: cell.depth + 1))
            stack.append(.init(lower: cell.lower, upper: midpoint, depth: cell.depth + 1))
        }
        return result
    }

    /// Source validation and independent depth admission precede this private law check.
    @inline(never)
    private static func hasExactUnitNativeBoundaryLaw(curve: BSplineCurve3D,
        from start: Double, to end: Double, surface: BSplineSurface3D,
        parameterCurve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard (surface.uDegree == 1 || surface.uDegree == 2), surface.vDegree == 1,
              !surface.isUPeriodic, !surface.isVPeriodic,
              surface.uPeriodicOrigin == nil, surface.vPeriodicOrigin == nil,
              !curve.isPeriodic, curve.periodicOrigin == nil,
              (start == 0 && end == 1) || (start == 1 && end == 0) else { return false }
        try execution.consumeWork(1)
        guard surface.uControlPointCount == surface.uDegree + 1,
              surface.vControlPointCount == 2,
              surface.uKnots.count == 2 * (surface.uDegree + 1), surface.vKnots.count == 4,
              surface.uDomain == .closed(0, 1), surface.vDomain == .closed(0, 1),
              curve.domain == .closed(0, 1) else { return false }
        for index in surface.uKnots.indices {
            try execution.consumeWork(1)
            guard surface.uKnots[index] == (index <= surface.uDegree ? 0 : 1) else { return false }
        }
        for index in surface.vKnots.indices {
            try execution.consumeWork(1)
            guard surface.vKnots[index] == (index <= surface.vDegree ? 0 : 1) else { return false }
        }
        for row in surface.weights.indices {
            for column in surface.weights[row].indices {
                try execution.consumeWork(1)
                guard surface.weights[row][column] == 1 else { return false }
            }
        }
        let varyingU: Bool
        let boundary: Int
        let chartStart: Double
        let chartEnd: Double
        try execution.consumeWork(1)
        switch parameterCurve {
        case .constantV(let v, let uStart, let uEnd):
            guard v == 0 || v == 1 else { return false }
            varyingU = true
            boundary = v == 0 ? 0 : surface.vControlPointCount - 1
            chartStart = uStart; chartEnd = uEnd
        case .constantU(let u, let vStart, let vEnd):
            guard u == 0 || u == 1 else { return false }
            varyingU = false
            boundary = u == 0 ? 0 : surface.uControlPointCount - 1
            chartStart = vStart; chartEnd = vEnd
        default: return false
        }
        let count = varyingU ? surface.uControlPointCount : surface.vControlPointCount
        let degree = varyingU ? surface.uDegree : surface.vDegree
        try execution.consumeWork(1)
        guard curve.degree == degree, curve.controlPointCount == count,
              curve.weights.count == count, curve.knots.count == count + degree + 1,
              (chartStart == 0 && chartEnd == 1) || (chartStart == 1 && chartEnd == 0) else { return false }
        for index in curve.knots.indices {
            try execution.consumeWork(1)
            let knot = varyingU ? surface.uKnots[index] : surface.vKnots[index]
            guard curve.knots[index] == knot else { return false }
        }
        var forward = true, reversed = true
        for index in 0..<count {
            // One weight and both three-coordinate comparisons share the caller work owner.
            try execution.consumeWork(7)
            guard curve.weights[index] == 1 else { return false }
            let first = varyingU ? surface.controlPoints[boundary][index] : surface.controlPoints[index][boundary]
            let last = varyingU ? surface.controlPoints[boundary][count - index - 1] : surface.controlPoints[count - index - 1][boundary]
            let matchesForward = curve.controlPoints[index] == first
            let matchesReversed = curve.controlPoints[index] == last
            forward = forward && matchesForward
            reversed = reversed && matchesReversed
        }
        return (forward && chartStart == start && chartEnd == end)
            || (reversed && chartStart == end && chartEnd == start)
    }

    private static func admittedContinuity(_ prepared: PreparedCurveDifferentialEncloser,
        over range: ScalarInterval, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int?,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        let maximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: maximum) { execution in
            try prepared.admittingContinuousFirstOrder(over: range, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                using: &execution) != nil
        }
    }
}
