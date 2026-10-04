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
        try Task.checkCancellation()
        try limits.validate()
        try tolerance.validate()
        guard maximumPositionError.isFinite, maximumPositionError > 0,
              parameters.u.width.isFinite, parameters.u.width > 0,
              parameters.v.width.isFinite, parameters.v.width > 0 else {
            throw GeometryConversionError.invalidInput("Polynomial continuation requires a finite positive distance and rectangle.")
        }
        var budget = Budget(limits: limits)
        try admit(source, tolerance: tolerance, budget: &budget)
        // Reserve the actual concrete receipt payload, including COW owner words.
        // Original coefficient/knot buffers are retained rather than materialized again.
        let wordSize = MemoryLayout<Double>.stride
        let words = try Budget.add(MemoryLayout<PreparedPolynomialSurfaceContinuationPositionRequest>.stride,
            wordSize - 1) / wordSize
        try budget.charge(scalars: words, work: Budget.add(Budget.multiply(words, 2), 12))
        try Task.checkCancellation()
        return PreparedPolynomialSurfaceContinuationPositionRequest(source: source,
            parameters: parameters, maximumPositionError: maximumPositionError,
            tolerance: tolerance, budget: budget)
    }

    public func certifyContinuationPosition(preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
        candidate: BSplineSurface3D) throws -> NativeSurfacePositionCertificate {
        try Task.checkCancellation()
        let source = preparedRequest.source, parameters = preparedRequest.parameters
        let maximumPositionError = preparedRequest.maximumPositionError, tolerance = preparedRequest.tolerance
        // The producer-only immutable receipt already owns complete original admission.
        // Resume its prefix; do not rescan the source or create another allowance.
        var budget = Budget(preparedRequest: preparedRequest)
        try admit(candidate, tolerance: tolerance, budget: &budget)
        try budget.charge(work: 32)
        try parameters.validateAssumingSurfaceValidated(for: .bSpline(candidate), tolerance: tolerance)

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
        try Task.checkCancellation()
        return NativeSurfacePositionCertificate(coveredParameters: parameters,
            positionErrorUpperBound: maximumBound, certifiedBoxCount: budget.boxes,
            scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func admit(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
        budget: inout Budget) throws {
        try budget.charge(work: 4)
        guard !surface.isUPeriodic, !surface.isVPeriodic else { throw unsupported(tolerance) }
        let rows = try Budget.add(surface.controlPoints.count, surface.weights.count)
        try budget.charge(work: Budget.multiply(rows, 4))
        var controls = 0, weights = 0
        for row in surface.controlPoints {
            try Task.checkCancellation()
            controls = try Budget.add(controls, row.count)
        }
        for row in surface.weights {
            try Task.checkCancellation()
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
        try Task.checkCancellation()
        let uCount = try Budget.add(surface.uDegree, 1)
        let vCount = try Budget.add(surface.vDegree, 1)
        guard surface.uControlPointCount == uCount, surface.vControlPointCount == vCount else {
            throw unsupported(tolerance)
        }
        let uLower = surface.uKnots[surface.uDegree], uUpper = surface.uKnots[uCount]
        let vLower = surface.vKnots[surface.vDegree], vUpper = surface.vKnots[vCount]
        for index in surface.uKnots.indices {
            try Task.checkCancellation()
            guard surface.uKnots[index] == (index < uCount ? uLower : uUpper) else { throw unsupported(tolerance) }
        }
        for index in surface.vKnots.indices {
            try Task.checkCancellation()
            guard surface.vKnots[index] == (index < vCount ? vLower : vUpper) else { throw unsupported(tolerance) }
        }
        let weight = surface.weights[0][0]
        for row in surface.weights {
            try Task.checkCancellation()
            for value in row where value != weight { throw unsupported(tolerance) }
        }
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
            message: "Polynomial continuation certification requires original nonperiodic single-clamped-Bezier tensors with exactly common positive weights.")
    }
}
