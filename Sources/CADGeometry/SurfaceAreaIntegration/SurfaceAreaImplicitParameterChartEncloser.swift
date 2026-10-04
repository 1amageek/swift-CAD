import CADCore

/// Original single-cell implicit root authority composed into a retained trim chart.
struct SurfaceAreaImplicitParameterChartEncloser: Sendable {
    private let curve: CertifiedImplicitSurfaceParameterCurve
    private let prepared: ImplicitCurveIntervalJetEncloser
    private let preparationTolerance: ModelingTolerance

    init(curve: CertifiedImplicitSurfaceParameterCurve, tolerance: ModelingTolerance,
         consumeWork: () throws -> Void) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic, multispan, multicell, closed and procedural
        // implicit charts lack this caller-owned localization contract on face-area
        // queries. Complete only after original root/jet coverage and shared-budget
        // area/centroid evidence is established for every owning piece.
        guard Self.supports(curve) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Nonlinear area charts require one open positive-weight single-span B-spline graph cell.")
        }
        try consumeWork()
        self.curve = curve
        preparationTolerance = tolerance
        prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve.intersection, tolerance: tolerance)
    }

    /// The original plane/extrusion equation holds for every certified root.
    /// This receipt does not derive a parameter identity from anchors or samples.
    func constantAxisAuthority(tolerance: ModelingTolerance, consumeWork: () throws -> Void)
        throws -> (axis: SurfaceAreaTranslationCertificate, parameter: Double)? {
        guard tolerance == preparationTolerance else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
                message:"Implicit iso-image authority requires its original preparation tolerance.")
        }
        guard curve.role == .second,
              case .bSpline(let plane) = curve.intersection.firstSurface,
              case .bSpline(let extrusion) = curve.intersection.secondSurface else { return nil }
        try consumeWork()
        guard
              let axis = SurfaceAreaTranslationCertificate.direction(of:.bSpline(extrusion)) else { return nil }
        let count = axis == .v ? extrusion.uControlPointCount : extrusion.vControlPointCount
        let knots = axis == .v ? extrusion.vKnots : extrusion.uKnots
        // The original degree-one axis and equal weight layers own the affine
        // interpolation. The other axis remains genuinely rational when weighted.
        guard knots.count == 4, count > 0 else { return nil }
        // This bounded recognizer admits exact midplanes. Other affine plane
        // combinations retain their original general fan algorithm.
        let candidate = knots[0] * 0.5 + knots[3] * 0.5
        func exactMidpoint(_ lower: Double, _ upper: Double, _ middle: Double) -> Bool {
            let sum = FloatingPointExpansion.sum([lower],[upper])
            let twice = FloatingPointExpansion.sum([middle],[middle])
            let residual = FloatingPointExpansion.subtract(sum,twice)
            return lower.isFinite && upper.isFinite && middle.isFinite
                && sum.allSatisfy(\.isFinite) && twice.allSatisfy(\.isFinite)
                && residual.allSatisfy(\.isFinite) && FloatingPointExpansion.sign(residual) == .zero
        }
        guard candidate > knots[0], candidate < knots[3], exactMidpoint(knots[0],knots[3],candidate) else { return nil }
        func coordinate(_ point: Point3D, _ index: Int) -> Double {
            switch index { case 0: return point.x; case 1: return point.y; default: return point.z }
        }
        func control(_ layer: Int, _ other: Int) -> Point3D {
            extrusion.controlPoints[axis == .v ? layer : other][axis == .v ? other : layer]
        }
        for component in 0..<3 {
            let planeValue = coordinate(plane.controlPoints[0][0],component)
            guard plane.controlPoints.allSatisfy({ $0.allSatisfy { coordinate($0,component) == planeValue } }) else { continue }
            let lower = coordinate(control(0,0),component)
            let upper = coordinate(control(1,0),component)
            guard lower != upper, (0..<count).allSatisfy({
                coordinate(control(0,$0),component) == lower && coordinate(control(1,$0),component) == upper
            }), exactMidpoint(lower,upper,planeValue) else { continue }
            return (axis,candidate)
        }
        return nil
    }

    /// Admission only; the retained lower owner supplies every root and derivative proof.
    private static func supports(_ curve: CertifiedImplicitSurfaceParameterCurve) -> Bool {
        guard !curve.intersection.isClosed, curve.intersection.cells.count == 1,
              case .bSpline(let first) = curve.intersection.firstSurface,
              case .bSpline(let second) = curve.intersection.secondSurface else { return false }
        func singlePositiveWeightSpan(_ surface: BSplineSurface3D) -> Bool {
            guard !surface.isUPeriodic, !surface.isVPeriodic,
                  surface.controlPoints.count == surface.vDegree + 1,
                  surface.controlPoints.first?.count == surface.uDegree + 1,
                  surface.weights.allSatisfy({ $0.allSatisfy { $0.isFinite && $0 > 0 } }) else { return false }
            func clamped(_ knots: [Double], _ degree: Int) -> Bool {
                guard knots.count == 2 * (degree + 1), let lower = knots.first,
                      let upper = knots.last, lower < upper else { return false }
                return knots.prefix(degree + 1).allSatisfy { $0 == lower }
                    && knots.suffix(degree + 1).allSatisfy { $0 == upper }
            }
            return clamped(surface.uKnots, surface.uDegree) && clamped(surface.vKnots, surface.vDegree)
        }
        return singlePositiveWeightSpan(first) && singlePositiveWeightSpan(second)
    }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                       consumeWork: () throws -> Void) throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        try intervalProofRetainingRoot(over:fraction,tolerance:tolerance,consumeWork:consumeWork).proof
    }

    func intervalProofRetainingRoot(over fraction: ScalarInterval,
        restricting parent: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState? = nil,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void)
        throws -> (proof: SurfaceAreaParameterChartEncloser.IntervalProof,
                   root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState) {
        let slope = OutwardScalarInterval.exact(curve.endFraction) - .exact(curve.startFraction)
        let source = OutwardScalarInterval.exact(curve.startFraction)
            + slope * OutwardScalarInterval(lower: fraction.lower, upper: fraction.upper)
        // Validated original trim endpoints prove this source domain. Intersection
        // removes outward arithmetic overhang only; it cannot admit invalid fractions.
        let interval: ScalarInterval
        if fraction.lower == fraction.upper, fraction.lower == 0 || fraction.lower == 1 {
            let endpoint = fraction.lower == 0 ? curve.startFraction : curve.endFraction
            interval = try ScalarInterval(lower:endpoint,upper:endpoint)
        } else if fraction.lower == fraction.upper, curve.startFraction == 0, curve.endFraction == 1 {
            // Exact identity preserves the original closed point, so its lower
            // continuation does not acquire unnecessary range endpoint phases.
            interval = fraction
        } else if fraction.lower == fraction.upper, curve.startFraction == 1, curve.endFraction == 0 {
            let candidate = 1 - fraction.lower
            let difference = FloatingPointExpansion.difference(1, fraction.lower)
            let residual = FloatingPointExpansion.subtract(difference, [candidate])
            // A rounded complement is only a candidate. Addition/subtraction
            // expansion equality proves the original reversal is this singleton.
            if candidate.isFinite, candidate >= 0, candidate <= 1,
               difference.allSatisfy(\.isFinite), residual.allSatisfy(\.isFinite),
               FloatingPointExpansion.sign(residual) == .zero {
                interval = try ScalarInterval(lower: candidate, upper: candidate)
            } else {
                interval = try ScalarInterval(lower: max(0, source.lower), upper: min(1, source.upper))
            }
        } else {
            interval = try ScalarInterval(lower: max(0, source.lower), upper: min(1, source.upper))
        }
        try consumeWork()
        var state: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        if let parent {
            state = try prepared.prepareParameterEnclosure(restricting:parent,
                overClosedInterval:interval,tolerance:tolerance)
        } else {
            state = try prepared.prepareParameterEnclosure(of:curve.intersection,cellIndex:0,
                overClosedInterval:interval,tolerance:tolerance)
        }
        while true {
            try consumeWork()
            switch try prepared.advanceParameterEnclosure(state, tolerance: tolerance) {
            case .contracted(let next): state = next
            case .subdivisionRequired: throw SurfaceAreaEnclosureRefinementRequired.implicitLocalization
            case .enclosed(let jet):
                let base = curve.role == .first ? 0 : 2
                func compose(_ coordinate: CertifiedImplicitParameterIntervalJet.Coordinate) -> SurfaceIntervalJet {
                    func outward(_ interval: ScalarInterval) -> OutwardScalarInterval {
                        OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
                    }
                    let zero = OutwardScalarInterval.exact(0)
                    return SurfaceIntervalJet(value: outward(coordinate.value),
                        derivativeU: outward(coordinate.firstDerivative) * slope, derivativeV: zero,
                        secondDerivativeUU: outward(coordinate.secondDerivative) * slope * slope,
                        secondDerivativeUV: zero, secondDerivativeVV: zero,
                        thirdDerivativeUUU: outward(coordinate.thirdDerivative) * slope * slope * slope,
                        thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
                }
                return (.smooth(u:compose(jet.coordinates[base]),v:compose(jet.coordinates[base + 1])),state)
            }
        }
    }
}
