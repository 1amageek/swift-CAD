import CADCore

/// Original plane/cylinder position evidence without an intermediate source spline.
public struct CertifiedAnalyticSurfacePositionCertifier: GeometryAnalyticSurfacePositionCertifying {
    private typealias Budget = PreparedBSplineSurfaceDifferentialCost.Budget
    private typealias Vector = GeometryConversionCertification.VectorBounds

    private struct CubicWholeBounds {
        let originalFourthU: Vector
        let firstVResidual: Vector
        let parent: SurfaceParameterBox
        let nativePiece: SurfaceParameterBox
    }

    private struct WorkCell {
        let parameters: SurfaceParameterBox
        let nativePiece: SurfaceParameterBox
        let bounds: CubicWholeBounds?
    }

    public init() {}

    public func certifyPosition(source: Surface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate {
        try Task.checkCancellation()
        try limits.validate()
        try tolerance.validate()
        guard maximumPositionError.isFinite, maximumPositionError > 0,
              parameters.u.width.isFinite, parameters.v.width.isFinite,
              parameters.u.width > 0, parameters.v.width > 0 else {
            throw GeometryConversionError.invalidInput("Analytic position certification requires a finite positive distance and native rectangle.")
        }
        switch source {
        case .plane, .cylinder, .analytic(.plane), .analytic(.cylinder): break
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Other original analytic/procedural families
            // cannot use the public Rebuild position producer yet. Completion requires their
            // original native whole-law bounds, resource/cancellation and consumer evidence.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Analytic Rebuild position certification currently admits original planes and cylinders.")
        }
        guard !candidate.isUPeriodic, !candidate.isVPeriodic else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Analytic Rebuild candidates require nonperiodic original spline axes.")
        }
        var budget = Budget(limits: limits)
        // Fixed analytic representations have at most ten numeric stored fields. Charge
        // validation, parameter containment and basis normalization before invoking them.
        try budget.charge(scalars: 32, work: 256)
        try source.validate(tolerance: tolerance)
        try parameters.validateAssumingSurfaceValidated(for: source, tolerance: tolerance)
        _ = try PreparedBSplineSurfaceDifferentialCost.chargeValidation(of: candidate, budget: &budget)
        try candidate.validate(tolerance: tolerance)
        try parameters.validateAssumingSurfaceValidated(for: .bSpline(candidate), tolerance: tolerance)
        guard parameters.u.lower >= candidate.uKnots[candidate.uDegree],
              parameters.u.upper <= candidate.uKnots[candidate.uControlPointCount],
              parameters.v.lower >= candidate.vKnots[candidate.vDegree],
              parameters.v.upper <= candidate.vKnots[candidate.vControlPointCount] else {
            throw GeometryConversionError.invalidInput("The candidate must contain the exact requested native rectangle.")
        }
        let targetCost = try PreparedBSplineSurfaceDifferentialCost(surface: candidate, budget: &budget)
        try targetCost.chargePreparation(budget: &budget)
        let target = try PreparedBSplineSurfaceDifferentialEncloser(surface: candidate, tolerance: tolerance)
        let original = DefaultSurfaceDifferentialEncloser()
        try budget.charge(work: Budget.product(candidate.uControlPointCount, candidate.vControlPointCount, 2))
        let commonWeight = candidate.weights[0][0]
        // Only original common-weight correlation proves a polynomial candidate;
        // a varying-weight rational cubic can have a nonzero fourth derivative.
        let cubicU = candidate.uDegree <= 3
            && candidate.weights.allSatisfy { $0.allSatisfy { $0 == commonWeight } }
        var stack: [WorkCell] = []
        // Every Taylor path lies within one original candidate smooth piece. A C0 join
        // retains both closed endpoint owners; it is never treated as a smooth interior.
        for j in candidate.vDegree..<candidate.vControlPointCount {
            for i in candidate.uDegree..<candidate.uControlPointCount {
                try budget.charge(work: 16)
                let u0 = max(parameters.u.lower, candidate.uKnots[i])
                let u1 = min(parameters.u.upper, candidate.uKnots[i + 1])
                let v0 = max(parameters.v.lower, candidate.vKnots[j])
                let v1 = min(parameters.v.upper, candidate.vKnots[j + 1])
                guard u0 < u1, v0 < v1 else { continue }
                // A work cell has at most 32 numeric/tag/padding slots. Four
                // times that payload covers stack backing growth and moves.
                try budget.charge(scalars: 128, work: 32)
                let piece = SurfaceParameterBox(u: try ScalarInterval(lower: u0, upper: u1),
                    v: try ScalarInterval(lower: v0, upper: v1))
                stack.append(WorkCell(parameters: piece, nativePiece: piece, bounds: nil))
            }
        }
        guard !stack.isEmpty else {
            throw GeometryConversionError.invalidInput("The candidate has no native cell over the requested rectangle.")
        }
        var maximumBound = 0.0
        while let cell = stack.popLast() {
            let box = cell.parameters
            try budget.visit()
            try budget.charge(work: 16)
            let u = box.u.midpoint, v = box.v.midpoint
            let anchor = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                v: try ScalarInterval(lower: v, upper: v))
            try chargeAnalyticProbe(budget: &budget)
            let a0 = try original.intervalJetAssumingSurfaceValidated(of: source, over: anchor, tolerance: tolerance)
            try Task.checkCancellation()
            try chargeCandidatePointJet(of: candidate, at: anchor, budget: &budget)
            let b0 = try target.intervalJet(overClosedBox: anchor, tolerance: tolerance)
            try Task.checkCancellation()
            try budget.charge(scalars: 16, work: 128)
            let value = vector(a0, at: \.value) - vector(b0, at: \.value)
            guard value.norm.isFinite else { throw precisionFailure() }
            if value.norm.lower > maximumPositionError { throw GeometryConversionError.toleranceRejected }

            let retainedBounds: CubicWholeBounds?
            let genericJets: (original: SurfaceIntervalVectorJet, candidate: SurfaceIntervalVectorJet)?
            if cubicU, let inherited = cell.bounds {
                try budget.charge(work: 32)
                guard inherited.nativePiece == cell.nativePiece,
                      contains(box, in: inherited.parent),
                      contains(inherited.parent, in: inherited.nativePiece) else {
                    throw GeometryConversionError.invalidInput("Retained analytic bounds must own this same native piece and contain its child rectangle.")
                }
                retainedBounds = inherited
                genericJets = nil
            } else {
                try chargeAnalyticProbe(budget: &budget)
                let a = try original.intervalJetAssumingSurfaceValidated(of: source, over: box, tolerance: tolerance)
                try Task.checkCancellation()
                try targetCost.chargeProbe(over: box, pointOnly: false, budget: &budget)
                let b = try target.intervalJet(overClosedBox: box, tolerance: tolerance)
                try Task.checkCancellation()
                if cubicU {
                    // Twenty numeric fields in the immutable receipt, including
                    // both owner rectangles, are paid before extraction/creation.
                    try budget.charge(scalars: 80, work: 128)
                    let originalFourthU: Vector
                    switch source {
                    case .plane, .analytic(.plane):
                        originalFourthU = Vector(x: .exact(0), y: .exact(0), z: .exact(0))
                    case .cylinder, .analytic(.cylinder):
                        originalFourthU = Vector(x: .exact(0), y: .exact(0), z: .exact(0))
                            - vector(a, at: \.secondDerivativeUU)
                    default: throw precisionFailure()
                    }
                    retainedBounds = CubicWholeBounds(originalFourthU: originalFourthU,
                        firstVResidual: vector(a, at: \.derivativeV) - vector(b, at: \.derivativeV),
                        parent: box, nativePiece: cell.nativePiece)
                    genericJets = nil
                } else {
                    retainedBounds = nil
                    genericJets = (a, b)
                }
            }
            // Ten vector differences, offset monomials, vector scaling/addition and
            // all multiplication scratch arrays are charged before bound arithmetic.
            try budget.charge(scalars: 1_024, work: 8_192)
            let du = offset(box.u, from: u), dv = offset(box.v, from: v)
            let du2 = du * du, dv2 = dv * dv
            let firstU = (vector(a0, at: \.derivativeU) - vector(b0, at: \.derivativeU)) * du
            let secondU = (vector(a0, at: \.secondDerivativeUU) - vector(b0, at: \.secondDerivativeUU)) * (du2 * .exact(0.5))
            guard let sixth = OutwardScalarInterval.exact(1).divided(by: .exact(6)) else { throw precisionFailure() }
            let whole: Vector
            let alongU: Bool
            if cubicU {
                // Follow U at the anchor V, then V at the actual U. This does
                // not assume that the candidate has vanishing mixed derivatives.
                let thirdU = (vector(a0, at: \.thirdDerivativeUUU) - vector(b0, at: \.thirdDerivativeUUU)) * (du2 * du * sixth)
                guard let retainedBounds else { throw precisionFailure() }
                guard let twentyFourth = OutwardScalarInterval.exact(1).divided(by: .exact(24)) else { throw precisionFailure() }
                let fourthU = retainedBounds.originalFourthU * (du2 * du2 * twentyFourth)
                let alongV = retainedBounds.firstVResidual * dv
                let uTerms = firstU + secondU + thirdU + fourthU
                whole = value + uTerms + alongV
                alongU = uTerms.norm.upper >= alongV.norm.upper
            } else {
                guard let genericJets else { throw precisionFailure() }
                let a = genericJets.original, b = genericJets.candidate
                let firstV = (vector(a0, at: \.derivativeV) - vector(b0, at: \.derivativeV)) * dv
                let secondUV = (vector(a0, at: \.secondDerivativeUV) - vector(b0, at: \.secondDerivativeUV)) * (du * dv)
                let secondV = (vector(a0, at: \.secondDerivativeVV) - vector(b0, at: \.secondDerivativeVV)) * (dv2 * .exact(0.5))
                // Generic tensor Taylor retains original third derivatives and
                // their exact multinomial coefficients on this native piece.
                let thirdU = (vector(a, at: \.thirdDerivativeUUU) - vector(b, at: \.thirdDerivativeUUU)) * (du2 * du * sixth)
                let thirdUUV = (vector(a, at: \.thirdDerivativeUUV) - vector(b, at: \.thirdDerivativeUUV)) * (du2 * dv * .exact(0.5))
                let thirdUVV = (vector(a, at: \.thirdDerivativeUVV) - vector(b, at: \.thirdDerivativeUVV)) * (du * dv2 * .exact(0.5))
                let thirdV = (vector(a, at: \.thirdDerivativeVVV) - vector(b, at: \.thirdDerivativeVVV)) * (dv2 * dv * sixth)
                whole = value + firstU + firstV + secondU + secondUV + secondV
                    + thirdU + thirdUUV + thirdUVV + thirdV
                alongU = (firstU + secondU + secondUV + thirdU + thirdUUV + thirdUVV).norm.upper
                    >= (firstV + secondV + secondUV + thirdV + thirdUUV + thirdUVV).norm.upper
            }
            let bound = whole.norm.upper
            guard bound.isFinite else { throw precisionFailure() }
            if bound <= maximumPositionError {
                maximumBound = max(maximumBound, bound)
                continue
            }
            // Actual directional contributions choose refinement; a long exact
            // axial coordinate must not cause needless cylinder V subdivision.
            try budget.charge(scalars: 256, work: 64)
            if alongU {
                guard u > box.u.lower, u < box.u.upper else { throw precisionFailure() }
                stack.append(WorkCell(parameters: SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: box.u.upper), v: box.v),
                    nativePiece: cell.nativePiece, bounds: retainedBounds))
                stack.append(WorkCell(parameters: SurfaceParameterBox(u: try ScalarInterval(lower: box.u.lower, upper: u), v: box.v),
                    nativePiece: cell.nativePiece, bounds: retainedBounds))
            } else {
                guard v > box.v.lower, v < box.v.upper else { throw precisionFailure() }
                stack.append(WorkCell(parameters: SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: v, upper: box.v.upper)),
                    nativePiece: cell.nativePiece, bounds: retainedBounds))
                stack.append(WorkCell(parameters: SurfaceParameterBox(u: box.u, v: try ScalarInterval(lower: box.v.lower, upper: v)),
                    nativePiece: cell.nativePiece, bounds: retainedBounds))
            }
        }
        try Task.checkCancellation()
        return NativeSurfacePositionCertificate(coveredParameters: parameters,
            positionErrorUpperBound: maximumBound, certifiedBoxCount: budget.boxes,
            scalarCount: budget.scalars, workUnits: budget.work)
    }

    private func contains(_ child: SurfaceParameterBox, in parent: SurfaceParameterBox) -> Bool {
        child.u.lower >= parent.u.lower && child.u.upper <= parent.u.upper
            && child.v.lower >= parent.v.lower && child.v.upper <= parent.v.upper
    }

    private func chargeCandidatePointJet(of surface: BSplineSurface3D,
        at point: SurfaceParameterBox, budget: inout Budget) throws {
        try budget.charge(work: Budget.sum(Budget.product(surface.uControlPointCount,
            surface.vControlPointCount, 4), surface.uKnots.count, surface.vKnots.count))
        let n = try Budget.sum(surface.uDegree, 1), m = try Budget.sum(surface.vDegree, 1)
        let singleBezier = surface.uControlPointCount == n && surface.vControlPointCount == m
        // Additional polynomial-coordinate nets exist only for a single Bezier
        // patch with a nonunit stored weight; common-weight correlation stays lower-owned.
        let groups = singleBezier && !surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) ? 4 : 1
        var spans = 0
        for j in surface.vDegree..<surface.vControlPointCount where surface.vKnots[j] < surface.vKnots[j + 1] {
            for i in surface.uDegree..<surface.uControlPointCount where surface.uKnots[i] < surface.uKnots[i + 1] {
                spans = try Budget.sum(spans, 1)
            }
        }
        try budget.charge(work: Budget.sum(Budget.product(spans, 16),
            surface.uKnots.count, surface.vKnots.count))
        for j in surface.vDegree..<surface.vControlPointCount where surface.vKnots[j] < surface.vKnots[j + 1] {
            for i in surface.uDegree..<surface.uControlPointCount where surface.uKnots[i] < surface.uKnots[i + 1] {
                guard point.u.lower >= surface.uKnots[i], point.u.upper <= surface.uKnots[i + 1],
                      point.v.lower >= surface.vKnots[j], point.v.upper <= surface.vKnots[j + 1] else { continue }
                // Original-ratio expansion witnesses and outward normalization have
                // bounded two-component inputs. Reserve their scratch before the query.
                var scalars = 256, work = 2_048
                for uOrder in 0...3 {
                    for vOrder in 0...(3 - uOrder) {
                        let a = max(1, n - uOrder), b = max(1, m - vOrder)
                        let count = try Budget.product(a, b)
                        let uSteps = try Budget.product(a - 1, a) / 2
                        let vSteps = try Budget.product(b - 1, b) / 2
                        let steps = try Budget.sum(Budget.product(b, uSteps), vSteps)
                        // Each interpolation creates eight result doubles and two
                        // four-product scratch arrays for each of four coordinates.
                        // Each U-row and final V hull creates component/lower/upper
                        // arrays: six doubles per homogeneous coordinate/input.
                        scalars = try Budget.sum(scalars, Budget.product(steps, 40, groups),
                            Budget.product(Budget.sum(count, b), 24, groups),
                            Budget.product(Budget.sum(b, 1), 8, groups))
                        work = try Budget.sum(work, Budget.product(steps, 4 + 8 * 12 + 4 * 4, groups),
                            Budget.product(Budget.sum(count, b), 4, 4, groups))
                    }
                }
                // Localized scalar hulls, reciprocal and Cartesian product rules
                // retain the full ten fields, including derivatives through order three.
                scalars = try Budget.sum(scalars, Budget.product(4, 10, 6, groups),
                    Budget.product(4, 10, 6, 3, 4), Budget.product(4, 10, 2))
                work = try Budget.sum(work, Budget.product(4, 10, 4, groups),
                    Budget.product(4, 10, 6, 3 * 12 + 4), Budget.product(4, 10, 4))
                try budget.charge(scalars: scalars, work: work)
            }
        }
    }

    private func chargeAnalyticProbe(budget: inout Budget) throws {
        // DefaultSurfaceDifferentialEncloser.cylinderJet performs four vector
        // products (radialJet: two, radius: one, axial V: one); planes use two.
        // SurfaceIntervalJet.* has 45 interval products across its ten fields:
        // 1+2+2+4+4+4+6+8+8+6. applyingUnaryFunction has 41: 2 first,
        // 9 second and 30 third-order products. Two trig unary jets therefore
        // give 4*3*45+2*41 = 622 products. OutwardIntervalArithmetic allocates
        // four scratch slots each: 2,488. Eight trig hulls have two endpoints
        // and at most two extrema; backing growth/extrema records and fixed
        // basis/parameter metadata fit within 512 further slots. Reserve
        // 3,072 before either admitted visitor; the existing work bound stays.
        try budget.charge(scalars: 3_072, work: 65_536)
    }

    private func vector(_ jet: SurfaceIntervalVectorJet,
        at key: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) -> Vector {
        Vector(x: jet.x[keyPath: key], y: jet.y[keyPath: key], z: jet.z[keyPath: key])
    }

    private func offset(_ interval: ScalarInterval, from anchor: Double) -> OutwardScalarInterval {
        let lower = OutwardScalarInterval.exact(interval.lower) - .exact(anchor)
        let upper = OutwardScalarInterval.exact(interval.upper) - .exact(anchor)
        return .init(lower: lower.lower, upper: upper.upper)
    }

    private func precisionFailure() -> GeometryConversionError {
        .resourceLimitExceeded("Analytic position certification could not resolve a finite bound or representable subdivision.")
    }
}
