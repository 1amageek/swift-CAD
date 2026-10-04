import CADCore

/// Whole-rectangle position evidence from original native homogeneous interval authority.
public struct CertifiedNativeSurfacePositionCertifier: GeometrySurfacePositionCertifying {
    public init() {}

    public func certifyPosition(source: BSplineSurface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate {
        try Task.checkCancellation()
        try limits.validate()
        try tolerance.validate()
        guard maximumPositionError.isFinite, maximumPositionError > 0,
              parameters.u.width.isFinite, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Native position certification requires a finite positive distance and finite native rectangle.")
        }
        var budget = PreparedBSplineSurfaceDifferentialCost.Budget(limits: limits)
        let sourceComparison = try admit(source, over: parameters, tolerance: tolerance, budget: &budget)
        let targetComparison = try admit(candidate, over: parameters, tolerance: tolerance, budget: &budget)
        // Complete stored equality is exact native position identity, not sampled agreement.
        try budget.charge(work: PreparedBSplineSurfaceDifferentialCost.Budget.sum(sourceComparison, targetComparison))
        if source == candidate {
            try Task.checkCancellation()
            return certificate(parameters, bound: 0, budget: budget)
        }

        let sourcePolynomial = try NativePolynomialSurfacePositionPreparation.hasCommonWeight(source, budget: &budget)
        let candidatePolynomial = try NativePolynomialSurfacePositionPreparation.hasCommonWeight(candidate, budget: &budget)
        if sourcePolynomial && candidatePolynomial {
            return try polynomialCertificate(source: source, candidate: candidate, parameters: parameters,
                maximumPositionError: maximumPositionError, tolerance: tolerance, admittedBudget: budget)
        }

        let sourceCost = try PreparedBSplineSurfaceDifferentialCost(surface: source, budget: &budget)
        let targetCost = try PreparedBSplineSurfaceDifferentialCost(surface: candidate, budget: &budget)
        // Admit both complete preparations before either creates a retained coefficient net.
        try sourceCost.chargePreparation(budget: &budget)
        try targetCost.chargePreparation(budget: &budget)
        let original = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let target = try PreparedBSplineSurfaceDifferentialEncloser(surface: candidate, tolerance: tolerance)
        try budget.charge(scalars: 16)
        var stack = [parameters]
        var maximumBound = 0.0
        while let box = stack.popLast() {
            try budget.visit()
            // Two stored knot/index reads and comparisons plus midpoint arithmetic per axis.
            try budget.charge(work: 2 * (2 + 2 + 2 + 3))
            let midpointU = box.u.midpoint, midpointV = box.v.midpoint
            let nativeU = source.uKnots[source.uDegree + (source.uControlPointCount - source.uDegree) / 2]
            let nativeV = source.vKnots[source.vDegree + (source.vControlPointCount - source.vDegree) / 2]
            let u = nativeU > box.u.lower && nativeU < box.u.upper ? nativeU : midpointU
            let v = nativeV > box.v.lower && nativeV < box.v.upper ? nativeV : midpointV
            let anchor = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                v: try ScalarInterval(lower: v, upper: v))
            try sourceCost.chargeProbe(over: anchor, pointOnly: true, budget: &budget)
            try targetCost.chargeProbe(over: anchor, pointOnly: true, budget: &budget)
            let sourceAnchor = try original.pointValue(u: u, v: v, tolerance: tolerance)
            let targetAnchor = try target.pointValue(u: u, v: v, tolerance: tolerance)
            // Three subtractions and interval norm arithmetic, including multiply scratch.
            try budget.charge(scalars: 3 * 4, work: 3 * 4 + 3 * 12 + 2 * 4 + 4)
            let difference = vector(sourceAnchor) - vector(targetAnchor)
            let anchorNorm = difference.norm
            guard anchorNorm.isFinite else { throw arithmeticFailure() }
            if anchorNorm.lower > maximumPositionError { throw GeometryConversionError.toleranceRejected }

            try sourceCost.chargeProbe(over: box, pointOnly: false, budget: &budget)
            try targetCost.chargeProbe(over: box, pointOnly: false, budget: &budget)
            let a = try original.intervalJet(over: box, tolerance: tolerance)
            let b = try target.intervalJet(over: box, tolerance: tolerance)
            try budget.charge(scalars: 9 * 4, work: 6 * 4 + 4 * 4 + 6 * 12 + 6 * 4 + 3 * 12 + 2 * 4 + 4)
            // C0 native spans are piecewise differentiable; the complete interval union
            // contains every first derivative and both knot sides on the integration paths.
            let du = vector(a, uDerivative: true) - vector(b, uDerivative: true)
            let dv = vector(a, uDerivative: false) - vector(b, uDerivative: false)
            let offsetU = OutwardScalarInterval.exact(box.u.lower) - .exact(u)
            let upperU = OutwardScalarInterval.exact(box.u.upper) - .exact(u)
            let offsetV = OutwardScalarInterval.exact(box.v.lower) - .exact(v)
            let upperV = OutwardScalarInterval.exact(box.v.upper) - .exact(v)
            let whole = difference
                + du * OutwardScalarInterval(lower: offsetU.lower, upper: upperU.upper)
                + dv * OutwardScalarInterval(lower: offsetV.lower, upper: upperV.upper)
            let bound = whole.norm.upper
            guard bound.isFinite else { throw arithmeticFailure() }
            if bound <= maximumPositionError {
                maximumBound = max(maximumBound, bound)
                continue
            }
            // Four numeric fields per cell; sixteen slots bound cumulative geometric
            // backing-buffer growth across all pushes, including retained/copied buffers.
            try budget.charge(scalars: 2 * 16, work: 2 * 4 + 8)
            if box.u.width / parameters.u.width >= box.v.width / parameters.v.width {
                guard midpointU > box.u.lower, midpointU < box.u.upper else { throw arithmeticFailure() }
                stack.append(SurfaceParameterBox(u: try ScalarInterval(lower: midpointU, upper: box.u.upper), v: box.v))
                stack.append(SurfaceParameterBox(u: try ScalarInterval(lower: box.u.lower, upper: midpointU), v: box.v))
            } else {
                guard midpointV > box.v.lower, midpointV < box.v.upper else { throw arithmeticFailure() }
                stack.append(SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: midpointV, upper: box.v.upper)))
                stack.append(SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: box.v.lower, upper: midpointV)))
            }
        }
        try Task.checkCancellation()
        return certificate(parameters, bound: maximumBound, budget: budget)
    }

    private func polynomialCertificate(source: BSplineSurface3D, candidate: BSplineSurface3D,
        parameters: SurfaceParameterBox, maximumPositionError: Double, tolerance: ModelingTolerance,
        admittedBudget: PreparedBSplineSurfaceDifferentialCost.Budget) throws -> NativeSurfacePositionCertificate {
        typealias Preparation = NativePolynomialSurfacePositionPreparation
        typealias Net = PolynomialSurfacePositionDifferenceNet
        struct Cell {
            let net: Net
            let uWidth: Double
            let vWidth: Double
        }
        var budget = Net.Budget(adopting: admittedBudget)
        let us = try Preparation.commonCells(sourceKnots: source.uKnots, sourceDegree: source.uDegree,
            sourceCount: source.uControlPointCount, candidateKnots: candidate.uKnots,
            candidateDegree: candidate.uDegree, candidateCount: candidate.uControlPointCount,
            interval: parameters.u, budget: &budget)
        let vs = try Preparation.commonCells(sourceKnots: source.vKnots, sourceDegree: source.vDegree,
            sourceCount: source.vControlPointCount, candidateKnots: candidate.vKnots,
            candidateDegree: candidate.vDegree, candidateCount: candidate.vControlPointCount,
            interval: parameters.v, budget: &budget)
        try budget.charge(work: 8)
        let origin = source.controlPoints[0][0]
        let uDegree = max(source.uDegree, candidate.uDegree), vDegree = max(source.vDegree, candidate.vDegree)
        let original = try Preparation(surface: source, origin: origin, uCells: us, vCells: vs,
            candidate: false, uDegree: uDegree, vDegree: vDegree, tolerance: tolerance, budget: &budget)
        let target = try Preparation(surface: candidate, origin: origin, uCells: us, vCells: vs,
            candidate: true, uDegree: uDegree, vDegree: vDegree, tolerance: tolerance, budget: &budget)
        var maximumBound = 0.0
        var pending: [Cell] = []
        func admit(_ net: Net, uWidth: Double, vWidth: Double,
            budget: inout Net.Budget, pending: inout [Cell], maximum: inout Double) throws {
            try budget.visit()
            let bound = try net.maximumCoefficientNorm(budget: &budget)
            if bound <= maximumPositionError {
                maximum = max(maximum, bound)
                return
            }
            if try net.centerNormLowerBound(budget: &budget) > maximumPositionError {
                throw GeometryConversionError.toleranceRejected
            }
            // Seven fields; fourfold cumulative reservation includes retained net
            // owners and stack backing/COW growth before each unresolved append.
            try budget.charge(scalars: 28, work: 4)
            pending.append(Cell(net: net, uWidth: uWidth, vWidth: vWidth))
        }
        // First inspect every common native cell. An early threshold-boundary cell
        // must not consume the allowance before later original cells' excess witnesses.
        for uIndex in us.indices {
            let a = try original.section(uIndex: uIndex, budget: &budget)
            let b = try target.section(uIndex: uIndex, budget: &budget)
            for vIndex in vs.indices {
                let sourceNet = try a.net(vIndex: vIndex, budget: &budget)
                let targetNet = try b.net(vIndex: vIndex, budget: &budget)
                let residual = try sourceNet.subtracting(targetNet, budget: &budget)
                try admit(residual, uWidth: 1, vWidth: 1, budget: &budget,
                    pending: &pending, maximum: &maximumBound)
            }
        }
        while let cell = pending.popLast() {
            // Its initial hull and witness have already been paid and inspected.
            // Subdivide that same retained residual, without duplicate parent probes.
            try budget.charge(work: 12)
            let alongU = cell.uWidth >= cell.vWidth
            let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
            guard half > 0, half.isFinite else { throw Net.Budget.exhausted() }
            let children = try cell.net.subdivided(u: alongU, budget: &budget)
            let uWidth = alongU ? half : cell.uWidth, vWidth = alongU ? cell.vWidth : half
            try admit(children.0, uWidth: uWidth, vWidth: vWidth, budget: &budget,
                pending: &pending, maximum: &maximumBound)
            try admit(children.1, uWidth: uWidth, vWidth: vWidth, budget: &budget,
                pending: &pending, maximum: &maximumBound)
        }
        try Task.checkCancellation()
        return NativeSurfacePositionCertificate(coveredParameters: parameters, positionErrorUpperBound: maximumBound,
            certifiedBoxCount: budget.boxes, scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func admit(_ surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, budget: inout PreparedBSplineSurfaceDifferentialCost.Budget) throws -> Int {
        guard !surface.isUPeriodic, !surface.isVPeriodic else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Native position certification currently requires nonperiodic original axes.")
        }
        let comparison = try PreparedBSplineSurfaceDifferentialCost.chargeValidation(of: surface, budget: &budget)
        // Native validation rejects internal multiplicity above the degree: C0 continuity
        // is an admission requirement, independent of metric regularity or curvature.
        try surface.validate(tolerance: tolerance)
        try parameters.validateAssumingSurfaceValidated(for: .bSpline(surface), tolerance: tolerance)
        return comparison
    }

    private func vector(_ value: IntervalVector3DBounds) -> GeometryConversionCertification.VectorBounds {
        .init(x: value.x, y: value.y, z: value.z)
    }

    private func vector(_ jet: SurfaceIntervalVectorJet, uDerivative: Bool) -> GeometryConversionCertification.VectorBounds {
        if uDerivative { return .init(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU) }
        return .init(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV)
    }

    private func certificate(_ parameters: SurfaceParameterBox, bound: Double,
        budget: PreparedBSplineSurfaceDifferentialCost.Budget) -> NativeSurfacePositionCertificate {
        NativeSurfacePositionCertificate(coveredParameters: parameters, positionErrorUpperBound: bound,
            certifiedBoxCount: budget.boxes, scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func arithmeticFailure() -> GeometryConversionError {
        .resourceLimitExceeded("Native position certification could not resolve a finite bound or representable subdivision.")
    }
}
