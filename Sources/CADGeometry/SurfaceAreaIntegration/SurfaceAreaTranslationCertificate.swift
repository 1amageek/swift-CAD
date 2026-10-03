import CADCore

/// A structurally proved affine translation along one native parameter.
/// Equal control differences are proved with exact floating-point expansions,
/// independently of modeling tolerance and sampled derivatives.
package enum SurfaceAreaTranslationCertificate: Sendable, Equatable {
    case u
    case v

    static func direction(of surface: Surface3D) -> Self? {
        switch surface {
        case .plane, .analytic(.plane), .cylinder, .analytic(.cylinder): return .v
        case .bSpline(let spline):
            if !spline.isVPeriodic, spline.vDegree == 1, spline.controlPoints.count == 2,
               spline.vKnots.count == 4, spline.vKnots[0] == spline.vKnots[1],
               spline.vKnots[2] == spline.vKnots[3],
               spline.weights[0] == spline.weights[1],
               translated(spline.controlPoints[0], spline.controlPoints[1]) { return .v }
            if !spline.isUPeriodic, spline.uDegree == 1, spline.controlPoints.first?.count == 2,
               spline.uKnots.count == 4, spline.uKnots[0] == spline.uKnots[1],
               spline.uKnots[2] == spline.uKnots[3],
               spline.weights.allSatisfy({ $0[0] == $0[1] }),
               translated(spline.controlPoints.map { $0[0] }, spline.controlPoints.map { $0[1] }) { return .u }
            return nil
        case .procedural(.offset(let offset)): return direction(of: offset.source)
        case .procedural(.ruled(let ruled)):
            guard case .bSpline(let start) = ruled.startBoundary,
                  case .bSpline(let end) = ruled.endBoundary,
                  start.degree == end.degree, start.knots == end.knots, start.weights == end.weights,
                  start.isPeriodic == end.isPeriodic, start.periodicOrigin == end.periodicOrigin, translated(start.controlPoints, end.controlPoints) else { return nil }
            return .v
        case .procedural(.rollingBall(let blend)):
            guard let center = linearControlPair(blend.centerSpine),
                  let first = linearControlPair(blend.firstContact),
                  let second = linearControlPair(blend.secondContact),
                  sameDifference(center.1, center.0, first.1, first.0),
                  sameDifference(center.1, center.0, second.1, second.0) else { return nil }
            return .u
        default: return nil
        }
    }

    /// Exact fourth derivatives of these globally smooth polynomial supports vanish.
    static func fourthDerivativesAreExactlyZero(of surface: Surface3D) -> Bool {
        func polynomialLine(_ curve: Curve3D) -> Bool {
            guard case .bSpline(let spline) = curve, !spline.isPeriodic,
                  spline.degree == 1, spline.controlPoints.count == 2,
                  spline.knots.count == 4, spline.knots[0] == spline.knots[1],
                  spline.knots[2] == spline.knots[3], spline.weights[0] == spline.weights[1] else { return false }
            return true
        }
        switch surface {
        case .plane, .analytic(.plane): return true
        case .bSpline(let spline):
            guard !spline.isUPeriodic, !spline.isVPeriodic,
                  spline.uDegree + spline.vDegree <= 3,
                  spline.controlPoints.count == spline.vDegree + 1,
                  spline.controlPoints.first?.count == spline.uDegree + 1,
                  let weight = spline.weights.first?.first,
                  spline.weights.allSatisfy({ $0.allSatisfy { $0 == weight } }),
                  let uLow = spline.uKnots.first, let uHigh = spline.uKnots.last,
                  let vLow = spline.vKnots.first, let vHigh = spline.vKnots.last else { return false }
            return spline.uKnots.prefix(spline.uDegree + 1).allSatisfy { $0 == uLow }
                && spline.uKnots.suffix(spline.uDegree + 1).allSatisfy { $0 == uHigh }
                && spline.vKnots.prefix(spline.vDegree + 1).allSatisfy { $0 == vLow }
                && spline.vKnots.suffix(spline.vDegree + 1).allSatisfy { $0 == vHigh }
        case .procedural(.ruled(let ruled)):
            return polynomialLine(ruled.startBoundary) && polynomialLine(ruled.endBoundary)
        default: return false
        }
    }

    private static func linearControlPair(_ curve: Curve3D) -> (Point3D, Point3D)? {
        guard case .bSpline(let spline) = curve, !spline.isPeriodic, spline.degree == 1,
              spline.controlPoints.count == 2, spline.knots == [0, 0, 1, 1],
              spline.weights.count == 2, spline.weights[0] == spline.weights[1] else { return nil }
        return (spline.controlPoints[0], spline.controlPoints[1])
    }

    private static func translated(_ start: [Point3D], _ end: [Point3D]) -> Bool {
        guard start.count == end.count, let a = start.first, let b = end.first else { return false }
        return start.indices.allSatisfy { sameDifference(end[$0], start[$0], b, a) }
    }

    private static func sameDifference(_ a: Point3D, _ b: Point3D, _ c: Point3D, _ d: Point3D) -> Bool {
        for (av, bv, cv, dv) in [(a.x,b.x,c.x,d.x),(a.y,b.y,c.y,d.y),(a.z,b.z,c.z,d.z)] {
            let first = FloatingPointExpansion.difference(av, bv)
            let second = FloatingPointExpansion.difference(cv, dv)
            if FloatingPointExpansion.sign(FloatingPointExpansion.subtract(first, second)) != .zero { return false }
        }
        return true
    }
}
