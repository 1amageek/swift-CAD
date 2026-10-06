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
    // lower closed-jet temporary byte callbacks, must close before full-family
    // accounting or correspondence completeness can be reported.
    static func deviationBound(curve: Curve3D, from start: Double, to end: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil)
        throws -> Double {
        try consumeWork(); try Task.checkCancellation(); try options.validate(tolerance: tolerance)
        guard start.isFinite, end.isFinite, start != end, maximumSpanCount > 0,
              maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original bounded correspondence needs a finite directed trim and caller ceilings.")
        }
        let depthLimit = min(options.maximumSubdivisionDepth, maximumSubdivisionDepth)
        let acceptance = options.maximumDeviation ?? tolerance.distance
        try curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: depthLimit, consumeWork: { _ in try consumeWork() },
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: depthLimit, consumeWork: { _ in try consumeWork() },
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try parameterCurve.validateOriginalSource(on: surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        func charge(_ count: Int) throws {
            for _ in 0..<count { try consumeWork() }
        }
        if case .surfaceLift(let hosted) = curve, start == 0, end == 1 {
            try GeometryStructuralComparisonWork.charge(surface: hosted.surface, using: charge)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: charge)
            try GeometryStructuralComparisonWork.charge(parameterCurve: hosted.parameterCurve, using: charge)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: charge)
            if hosted.surface == surface, hosted.parameterCurve == parameterCurve { return 0 }
        }
        if case .originalAffineWord(let spatial) = curve,
           case .procedural(.originalAffineWord(let support)) = surface,
           case .originalAffineWord(let chart) = parameterCurve,
           chart.startFraction == 0, chart.endFraction == 1 {
            try GeometryStructuralComparisonWork.charge(curve: curve, using: charge)
            try GeometryStructuralComparisonWork.charge(surface: surface, using: charge)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: charge)
            if chart.target == support, chart.source.surface == support.source,
               spatial.operationWord == support.operationWord {
                guard remainingSourceDepth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original word correspondence exhausted caller source depth.")
                }
                if case .surfaceLift(let hosted) = spatial.source, start == 0, end == 1 {
                    try GeometryStructuralComparisonWork.charge(surface: hosted.surface, using: charge)
                    try GeometryStructuralComparisonWork.charge(parameterCurve: hosted.parameterCurve, using: charge)
                    if hosted == chart.source { return 0 }
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original word correspondence
                // reaches this path from manual BRep/coedge validation. Without
                // caller storage admission, its temporary norm proof is not paid;
                // refuse until that caller supplies the original byte ledger.
                guard let consumeStorage else {
                    throw KernelError(phase: .geometry, code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Original word correspondence requires caller storage admission for its norm proof.")
                }
                let norm = try OriginalAffineWordJetTransport.linearNormUpper(support.preparedWord,
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
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
                    consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
                let transported = original == 0 ? 0 : (OutwardScalarInterval.exact(original) * .exact(norm)).upper
                guard transported <= acceptance else {
                    throw KernelError(phase: .validation, code: .topologyFailure, residual: transported,
                        tolerance: tolerance, message: "Original word coedge residual exceeds the requested junction bound.")
                }
                return transported
            }
        }
        if case .affineImage(let spatial) = curve,
           case .procedural(.originalImage(let support)) = surface,
           case .originalImage(let chart) = parameterCurve,
           chart.startFraction == 0, chart.endFraction == 1 {
            try GeometryStructuralComparisonWork.charge(surface: surface, using: charge)
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: charge)
            try charge(24)
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
                    consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
                let transported = (OutwardScalarInterval.exact(original) * .exact(norm.upper)).upper
                guard transported <= acceptance else {
                    throw KernelError(phase: .validation, code: .topologyFailure, residual: transported,
                        tolerance: tolerance, message: "Original affine coedge residual exceeds the requested junction bound.")
                }
                return transported
            }
        }
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original correspondence lift exhausted source depth.")
        }
        let source = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let liftedCurve = Curve3D.surfaceLift(.init(surface: surface, parameterCurve: parameterCurve))
        let lift = try PreparedCurveDifferentialEncloser(curve: liftedCurve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depthLimit,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let smooth = try (admittedContinuity(source, over: .init(lower: min(start,end), upper: max(start,end)),
            maximumSubdivisionDepth: depthLimit, remainingSourceDepth: remainingSourceDepth,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
            && admittedContinuity(lift, over: .init(lower:0,upper:1), maximumSubdivisionDepth: depthLimit,
                remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
        let slope = OutwardScalarInterval.exact(end) - .exact(start)
        func native(_ fraction: ScalarInterval) throws -> ScalarInterval {
            let image = .exact(start) + slope * OutwardScalarInterval(lower: fraction.lower, upper: fraction.upper)
            guard let contained = image.intersection(with: .init(lower: min(start, end), upper: max(start, end))) else {
                throw GeometryConversionError.invalidInput("Original directed correspondence interval is empty.")
            }
            return .init(lower: contained.lower, upper: contained.upper)
        }
        func positions(_ prepared: PreparedCurveDifferentialEncloser, _ range: ScalarInterval,
            _ depth: Int) throws -> IntervalVector3DBounds {
            try prepared.positionBounds(over: range, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: depthLimit - depth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func derivative(_ prepared: PreparedCurveDifferentialEncloser, _ range: ScalarInterval,
            _ depth: Int) throws -> IntervalVector3DBounds {
            let receipt = try prepared.closedNativeJets(over: range, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: depthLimit - depth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage)
            var result: IntervalVector3DBounds?
            for owner in receipt.spans {
                try consumeWork()
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
        try OriginalCoefficientAllocation.reserve(count: capacity.partialValue, of: Cell.self, consumeStorage: consumeStorage)
        var stack: [Cell] = []
        stack.reserveCapacity(capacity.partialValue)
        stack.append(.init(lower: 0, upper: 1, depth: 0))
        var visited = 0, result = 0.0
        while let cell = stack.popLast() {
            try Task.checkCancellation(); try consumeWork()
            guard visited < options.maximumCellCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original correspondence exhausted the requested cell count.")
            }
            visited += 1
            let range = ScalarInterval(lower: cell.lower, upper: cell.upper)
            let residual = try positions(source, native(range), cell.depth) - positions(lift, range, cell.depth)
            var upper = residual.lengthUpperBound
            let midpoint = cell.lower + (cell.upper - cell.lower) * 0.5
            if smooth, midpoint > cell.lower, midpoint < cell.upper {
                let station = ScalarInterval(lower: midpoint, upper: midpoint)
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
            try consumeWork()
            stack.append(.init(lower: midpoint, upper: cell.upper, depth: cell.depth + 1))
            stack.append(.init(lower: cell.lower, upper: midpoint, depth: cell.depth + 1))
        }
        return result
    }

    private struct ContinuityAdmission: RationalAlgebraAdmitting {
        let work: () throws -> Void
        let storage: (@Sendable (Int) throws -> Void)?
        let maximumAlgebraicDepth: Int?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original correspondence work count is invalid.") }
            for _ in 0..<count { try Task.checkCancellation(); try work() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original correspondence exact storage overflows.")
            }
            try storage?(bytes.partialValue)
            try consumeExactWork(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, maximumAlgebraicDepth.map({ depth <= $0 }) ?? true else {
                throw GeometryConversionError.resourceLimitExceeded("Original correspondence exhausted caller algebra depth.")
            }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    }

    private static func admittedContinuity(_ prepared: PreparedCurveDifferentialEncloser,
        over range: ScalarInterval, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> Bool {
        try withoutActuallyEscaping(consumeWork) { work in
            var usage = ContinuityAdmission(work: work, storage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try prepared.admittingContinuousFirstOrder(over: range, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                usage: &usage) != nil
        }
    }
}
