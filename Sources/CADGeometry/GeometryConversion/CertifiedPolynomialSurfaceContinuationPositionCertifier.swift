import CADCore

/// Position evidence for the unique continuation of original polynomial tensor coefficients.
public struct CertifiedPolynomialSurfaceContinuationPositionCertifier: GeometryPolynomialSurfaceContinuationPositionCertifying {
    private typealias Net = PolynomialSurfacePositionDifferenceNet
    private typealias Budget = Net.Budget

    private struct Cell {
        let net: Net
        let uWidth: Double
        let vWidth: Double
    }

    public init() {}

    public func certifyContinuationPosition(source: BSplineSurface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate {
        let prepared = try prepareContinuationRequest(source: source, over: parameters,
            maximumPositionError: maximumPositionError, limits: limits, tolerance: tolerance)
        return try certifyContinuationPosition(preparedRequest: prepared, candidate: candidate)
    }

    public func prepareContinuationRequest(source: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> PreparedPolynomialSurfaceContinuationPositionRequest {
        try CurrentTaskCancellationChecker().checkCancellation()
        try limits.validate()
        try tolerance.validate()
        guard maximumPositionError.isFinite, maximumPositionError > 0,
              parameters.u.width.isFinite, parameters.u.width > 0,
              parameters.v.width.isFinite, parameters.v.width > 0 else {
            throw GeometryConversionError.invalidInput("Polynomial continuation requires a finite positive distance and rectangle.")
        }
        var budget = Budget(limits: limits)
        let singleSource = try admit(source, tolerance: tolerance, budget: &budget)
        let originalLaw = singleSource ? nil : try PreparedPolynomialSurfaceContinuationLaw(validated: source, budget: &budget)
        // Reserve the actual concrete receipt payload, including COW owner words.
        // Original coefficient/knot buffers are retained rather than materialized again.
        let wordSize = MemoryLayout<Double>.stride
        let words = try Budget.add(MemoryLayout<PreparedPolynomialSurfaceContinuationPositionRequest>.stride,
            wordSize - 1) / wordSize
        try budget.charge(scalars: words, work: Budget.add(Budget.multiply(words, 2), 12))
        try CurrentTaskCancellationChecker().checkCancellation()
        return PreparedPolynomialSurfaceContinuationPositionRequest(source: source,
            parameters: parameters, maximumPositionError: maximumPositionError,
            tolerance: tolerance, originalLaw: originalLaw, budget: budget)
    }

    public func certifyContinuationPosition(preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
        candidate: BSplineSurface3D) throws -> NativeSurfacePositionCertificate {
        try CurrentTaskCancellationChecker().checkCancellation()
        let source = preparedRequest.source, parameters = preparedRequest.parameters
        let maximumPositionError = preparedRequest.maximumPositionError, tolerance = preparedRequest.tolerance
        // The producer-only immutable receipt already owns complete original admission.
        // Resume its prefix; do not rescan the source or create another allowance.
        var budget = Budget(preparedRequest: preparedRequest)
        let singleCandidate = try admit(candidate, tolerance: tolerance, budget: &budget)
        try budget.charge(work: 32)
        try parameters.validateAssumingSurfaceValidated(for: .bSpline(candidate), tolerance: tolerance)

        if preparedRequest.originalLaw != nil || !singleCandidate {
            let original = try preparedRequest.originalLaw ?? PreparedPolynomialSurfaceContinuationLaw(validated: source, budget: &budget)
            return try certifyMultipleSpans(source: source, candidate: candidate, law: original,
                parameters: parameters, maximumPositionError: maximumPositionError,
                tolerance: tolerance, budget: &budget)
        }

        let sourceU = try ratios(parameters.u, knots: source.uKnots, degree: source.uDegree, budget: &budget)
        let sourceV = try ratios(parameters.v, knots: source.vKnots, degree: source.vDegree, budget: &budget)
        let targetU = try ratios(parameters.u, knots: candidate.uKnots, degree: candidate.uDegree, budget: &budget)
        let targetV = try ratios(parameters.v, knots: candidate.vKnots, degree: candidate.vDegree, budget: &budget)
        try budget.charge(work: 8)
        let origin = source.controlPoints[0][0]
        let sourceNet = try Net(original: source, origin: origin, budget: &budget)
            .transformed(uLower: sourceU.0, uUpper: sourceU.1,
                vLower: sourceV.0, vUpper: sourceV.1, budget: &budget)
        let targetNet = try Net(original: candidate, origin: origin, budget: &budget)
            .transformed(uLower: targetU.0, uUpper: targetU.1,
                vLower: targetV.0, vUpper: targetV.1, budget: &budget)
        let uCount = max(sourceNet.uCount, targetNet.uCount)
        let vCount = max(sourceNet.vCount, targetNet.vCount)
        let elevatedSource = try sourceNet.elevated(toUCount: uCount, vCount: vCount, budget: &budget)
        let elevatedTarget = try targetNet.elevated(toUCount: uCount, vCount: vCount, budget: &budget)
        let difference = try elevatedSource.subtracting(elevatedTarget, budget: &budget)
        // Seven scalar/word fields per stack record. Four times the pushed fields
        // conservatively includes geometric backing growth and retained COW buffers.
        try budget.charge(scalars: 28, work: 4)
        var stack = [Cell(net: difference, uWidth: 1, vWidth: 1)]
        var maximumBound = 0.0
        while let cell = stack.popLast() {
            try budget.visit()
            let bound = try cell.net.maximumCoefficientNorm(budget: &budget)
            if bound <= maximumPositionError {
                maximumBound = max(maximumBound, bound)
                continue
            }
            if try cell.net.centerNormLowerBound(budget: &budget) > maximumPositionError {
                throw GeometryConversionError.toleranceRejected
            }
            try budget.charge(scalars: 56, work: 12)
            let alongU = cell.uWidth >= cell.vWidth
            let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
            guard half > 0, half.isFinite else { throw Budget.exhausted() }
            let children = try cell.net.subdivided(u: alongU, budget: &budget)
            // Cells are dyadic ranges of the shared normalized chart. Their exact
            // coefficient split covers the parent; rounded native midpoints are unused.
            let uWidth = alongU ? half : cell.uWidth
            let vWidth = alongU ? cell.vWidth : half
            stack.append(Cell(net: children.1, uWidth: uWidth, vWidth: vWidth))
            stack.append(Cell(net: children.0, uWidth: uWidth, vWidth: vWidth))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return NativeSurfacePositionCertificate(coveredParameters: parameters,
            positionErrorUpperBound: maximumBound, certifiedBoxCount: budget.boxes,
            scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func certifyMultipleSpans(source: BSplineSurface3D, candidate: BSplineSurface3D,
        law: PreparedPolynomialSurfaceContinuationLaw, parameters: SurfaceParameterBox,
        maximumPositionError: Double, tolerance: ModelingTolerance,
        budget: inout Budget) throws -> NativeSurfacePositionCertificate {
        typealias Preparation = NativePolynomialSurfacePositionPreparation
        typealias Law = PreparedPolynomialSurfaceContinuationLaw
        let targetLaw = try Law(validated: candidate, budget: &budget)
        let us = try law.commonCells(candidate: targetLaw, u: true, interval: parameters.u, budget: &budget)
        let vs = try law.commonCells(candidate: targetLaw, u: false, interval: parameters.v, budget: &budget)
        let originalUs = try law.originalCells(u: true, budget: &budget)
        let originalVs = try law.originalCells(u: false, budget: &budget)
        let targetUs = try law.candidateCells(us, u: true, budget: &budget)
        let targetVs = try law.candidateCells(vs, u: false, budget: &budget)
        try budget.charge(work: 8)
        let origin = source.controlPoints[0][0]
        let original = try Preparation(surface: source, origin: origin, uCells: originalUs, vCells: originalVs,
            candidate: false, uDegree: source.uDegree, vDegree: source.vDegree,
            tolerance: tolerance, budget: &budget)
        let uCount = max(source.uDegree, candidate.uDegree) + 1
        let vCount = max(source.vDegree, candidate.vDegree) + 1
        let target = try Preparation(surface: candidate, origin: origin, uCells: targetUs, vCells: targetVs,
            candidate: true, uDegree: uCount - 1, vDegree: vCount - 1,
            tolerance: tolerance, budget: &budget)
        let nativeCount = try Budget.multiply(originalUs.count, originalVs.count)
        let netWords = (MemoryLayout<Net>.stride + 7) / 8
        // The extraction pays coefficient storage; this reservation owns only the
        // array of retained immutable net payloads, not duplicate coefficient buffers.
        try budget.charge(scalars: Budget.multiply(nativeCount, netWords), work: Budget.multiply(nativeCount, 4))
        var nativeNets: [Net] = []
        nativeNets.reserveCapacity(nativeCount)
        for uIndex in originalUs.indices {
            let section = try original.section(uIndex: uIndex, budget: &budget)
            for vIndex in originalVs.indices {
                nativeNets.append(try section.net(vIndex: vIndex, budget: &budget))
            }
        }
        var pending: [Cell] = []
        var maximumBound = 0.0
        func admitCell(_ net: Net, uWidth: Double, vWidth: Double,
            budget: inout Budget, pending: inout [Cell], maximum: inout Double) throws {
            try budget.visit()
            let bound = try net.maximumCoefficientNorm(budget: &budget)
            if bound <= maximumPositionError {
                maximum = max(maximum, bound)
                return
            }
            if try net.centerNormLowerBound(budget: &budget) > maximumPositionError {
                throw GeometryConversionError.toleranceRejected
            }
            try budget.charge(scalars: 28, work: 4)
            pending.append(Cell(net: net, uWidth: uWidth, vWidth: vWidth))
        }
        // Every common closed cell receives its own original-law hull/witness
        // before adaptive work can starve a later cell's definite excess witness.
        for uIndex in us.indices {
            let u = us[uIndex]
            let sourceU = try Law.ratios(cell: u, span: law.uSpans[u.sourceIndex], budget: &budget)
            let targetSection = try target.section(uIndex: uIndex, budget: &budget)
            for vIndex in vs.indices {
                let v = vs[vIndex]
                let sourceV = try Law.ratios(cell: v, span: law.vSpans[v.sourceIndex], budget: &budget)
                try budget.charge(work: 8)
                let index = try Budget.add(Budget.multiply(u.sourceIndex, originalVs.count), v.sourceIndex)
                let sourceNet = try nativeNets[index]
                    .transformed(uLower: sourceU.0, uUpper: sourceU.1,
                        vLower: sourceV.0, vUpper: sourceV.1, budget: &budget)
                    .elevated(toUCount: uCount, vCount: vCount, budget: &budget)
                let targetNet = try targetSection.net(vIndex: vIndex, budget: &budget)
                let residual = try sourceNet.subtracting(targetNet, budget: &budget)
                try admitCell(residual, uWidth: 1, vWidth: 1, budget: &budget,
                    pending: &pending, maximum: &maximumBound)
            }
        }
        while let cell = pending.popLast() {
            try budget.charge(work: 12)
            let alongU = cell.uWidth >= cell.vWidth
            let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
            guard half.isFinite, half > 0 else { throw Budget.exhausted() }
            let children = try cell.net.subdivided(u: alongU, budget: &budget)
            let uWidth = alongU ? half : cell.uWidth, vWidth = alongU ? cell.vWidth : half
            try admitCell(children.0, uWidth: uWidth, vWidth: vWidth, budget: &budget,
                pending: &pending, maximum: &maximumBound)
            try admitCell(children.1, uWidth: uWidth, vWidth: vWidth, budget: &budget,
                pending: &pending, maximum: &maximumBound)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return NativeSurfacePositionCertificate(coveredParameters: parameters,
            positionErrorUpperBound: maximumBound, certifiedBoxCount: budget.boxes,
            scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func admit(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
        budget: inout Budget) throws -> Bool {
        try budget.charge(work: 4)
        guard !surface.isUPeriodic, !surface.isVPeriodic else { throw unsupported(tolerance) }
        let rows = try Budget.add(surface.controlPoints.count, surface.weights.count)
        try budget.charge(work: Budget.multiply(rows, 4))
        var controls = 0, weights = 0
        for row in surface.controlPoints {
            try CurrentTaskCancellationChecker().checkCancellation()
            controls = try Budget.add(controls, row.count)
        }
        for row in surface.weights {
            try CurrentTaskCancellationChecker().checkCancellation()
            weights = try Budget.add(weights, row.count)
        }
        let knots = try Budget.add(surface.uKnots.count, surface.vKnots.count)
        // These reservations cover original validation and the additional exact
        // common-weight/clamping scans; malformed rows are counted before validation.
        let pointWork = try Budget.multiply(controls, 8)
        let weightWork = try Budget.multiply(weights, 5)
        let knotWork = try Budget.multiply(knots, 16)
        try budget.charge(work: Budget.add(Budget.add(pointWork, weightWork),
            Budget.add(knotWork, Budget.add(rows, 64))))
        try surface.validate(tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        let uCount = try Budget.add(surface.uDegree, 1)
        let vCount = try Budget.add(surface.vDegree, 1)
        let uLower = surface.uKnots[surface.uDegree], uUpper = surface.uKnots[surface.uControlPointCount]
        let vLower = surface.vKnots[surface.vDegree], vUpper = surface.vKnots[surface.vControlPointCount]
        for index in 0..<uCount {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard surface.uKnots[index] == uLower,
                  surface.uKnots[surface.uKnots.count - 1 - index] == uUpper else { throw unsupported(tolerance) }
        }
        for index in 0..<vCount {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard surface.vKnots[index] == vLower,
                  surface.vKnots[surface.vKnots.count - 1 - index] == vUpper else { throw unsupported(tolerance) }
        }
        let weight = surface.weights[0][0]
        for row in surface.weights {
            try CurrentTaskCancellationChecker().checkCancellation()
            for value in row where value != weight { throw unsupported(tolerance) }
        }
        return surface.uControlPointCount == uCount && surface.vControlPointCount == vCount
    }

    private func ratios(_ interval: ScalarInterval, knots: [Double], degree: Int,
        budget: inout Budget) throws -> (OutwardScalarInterval, OutwardScalarInterval) {
        // Stored endpoints, three outward differences and two outward divisions.
        try budget.charge(scalars: 12, work: 64)
        let lower = OutwardScalarInterval.exact(knots[degree])
        let width = OutwardScalarInterval.exact(knots[degree + 1]) - lower
        guard let a = (OutwardScalarInterval.exact(interval.lower) - lower).divided(by: width),
              let b = (OutwardScalarInterval.exact(interval.upper) - lower).divided(by: width),
              a.isFinite, b.isFinite else { throw Budget.exhausted() }
        return (a, b)
    }

    private func unsupported(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Polynomial continuation certification requires original nonperiodic exact-clamped polynomial tensors with exactly common positive weights.")
    }
}
