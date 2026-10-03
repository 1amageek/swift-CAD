import CADCore

/// Original single-cell implicit root authority composed into a retained trim chart.
struct SurfaceAreaImplicitParameterChartEncloser: Sendable {
    private let curve: CertifiedImplicitSurfaceParameterCurve
    private let prepared: ImplicitCurveIntervalJetEncloser

    init(curve: CertifiedImplicitSurfaceParameterCurve, tolerance: ModelingTolerance,
         consumeWork: () throws -> Void) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Rational, multicell, closed and procedural
        // implicit charts lack this caller-owned localization contract on face-area
        // queries. Complete only after original root/jet coverage and shared-budget
        // area/centroid evidence is established for every owning piece.
        guard Self.supports(curve) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Nonlinear area charts require one open polynomial B-spline graph cell.")
        }
        try consumeWork()
        self.curve = curve
        prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve.intersection, tolerance: tolerance)
    }

    /// Admission only; the retained lower owner supplies every root and derivative proof.
    private static func supports(_ curve: CertifiedImplicitSurfaceParameterCurve) -> Bool {
        guard !curve.intersection.isClosed, curve.intersection.cells.count == 1,
              case .bSpline(let first) = curve.intersection.firstSurface,
              case .bSpline(let second) = curve.intersection.secondSurface else { return false }
        func polynomial(_ surface: BSplineSurface3D) -> Bool {
            guard !surface.isUPeriodic, !surface.isVPeriodic,
                  surface.controlPoints.count == surface.vDegree + 1,
                  surface.controlPoints.first?.count == surface.uDegree + 1,
                  let weight = surface.weights.first?.first, weight.isFinite, weight > 0,
                  surface.weights.allSatisfy({ $0.allSatisfy { $0 == weight } }) else { return false }
            func clamped(_ knots: [Double], _ degree: Int) -> Bool {
                guard knots.count == 2 * (degree + 1), let lower = knots.first,
                      let upper = knots.last, lower < upper else { return false }
                return knots.prefix(degree + 1).allSatisfy { $0 == lower }
                    && knots.suffix(degree + 1).allSatisfy { $0 == upper }
            }
            return clamped(surface.uKnots, surface.uDegree) && clamped(surface.vKnots, surface.vDegree)
        }
        return polynomial(first) && polynomial(second)
    }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                       consumeWork: () throws -> Void) throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        let slope = OutwardScalarInterval.exact(curve.endFraction) - .exact(curve.startFraction)
        let source = OutwardScalarInterval.exact(curve.startFraction)
            + slope * OutwardScalarInterval(lower: fraction.lower, upper: fraction.upper)
        // Validated original trim endpoints prove this source domain. Intersection
        // removes outward arithmetic overhang only; it cannot admit invalid fractions.
        let interval: ScalarInterval
        if fraction.lower == fraction.upper, fraction.lower == 0 || fraction.lower == 1 {
            let endpoint = fraction.lower == 0 ? curve.startFraction : curve.endFraction
            interval = try ScalarInterval(lower:endpoint,upper:endpoint)
        } else {
            interval = try ScalarInterval(lower: max(0, source.lower), upper: min(1, source.upper))
        }
        try consumeWork()
        var state = try prepared.prepareParameterEnclosure(of: curve.intersection, cellIndex: 0,
            overClosedInterval: interval, tolerance: tolerance)
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
                return .smooth(u: compose(jet.coordinates[base]), v: compose(jet.coordinates[base + 1]))
            }
        }
    }
}
