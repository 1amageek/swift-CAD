import CADCore
import CADGeometry

/// An affine map of a surface's parameter plane, (u, v) ↦ A (u, v) + b, and its exact action on
/// parameter curves. A rigid motion of a plane or a cylinder that carries a face acts on the face's
/// parameters this way, so the face keeps exact parameter curves without projecting its edges.
package struct SurfaceParameterAffineMap: Sendable {
    package var uu: Double, uv: Double, vu: Double, vv: Double
    package var du: Double, dv: Double

    package init(uu: Double, uv: Double, vu: Double, vv: Double, du: Double, dv: Double) {
        (self.uu, self.uv, self.vu, self.vv, self.du, self.dv) = (uu, uv, vu, vv, du, dv)
    }

    package var isTranslation: Bool { uu == 1 && uv == 0 && vu == 0 && vv == 1 }

    package func applying(to point: Point2D) -> Point2D {
        Point2D(x: uu * point.x + uv * point.y + du, y: vu * point.x + vv * point.y + dv)
    }

    private func applyingLinear(to vector: Point2D) -> Point2D {
        Point2D(x: uu * vector.x + uv * vector.y, y: vu * vector.x + vv * vector.y)
    }

    /// `curve` under the map, with its parameterization kept, or `nil` for a curve kind the map
    /// does not act on exactly.
    package func applying(to curve: SurfaceParameterCurve) -> SurfaceParameterCurve? {
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: applying(to: origin), direction: applyingLinear(to: direction),
                startParameter: startParameter, endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            if isTranslation { return .constantU(u: u + du, vStart: vStart + dv, vEnd: vEnd + dv) }
            return .affine(
                origin: applying(to: Point2D(x: u, y: 0)), direction: applyingLinear(to: Point2D(x: 0, y: 1)),
                startParameter: vStart, endParameter: vEnd
            )
        case let .constantV(v, uStart, uEnd):
            if isTranslation { return .constantV(v: v + dv, uStart: uStart + du, uEnd: uEnd + du) }
            return .affine(
                origin: applying(to: Point2D(x: 0, y: v)), direction: applyingLinear(to: Point2D(x: 1, y: 0)),
                startParameter: uStart, endParameter: uEnd
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: applying(to: center), cosine: applyingLinear(to: cosine), sine: applyingLinear(to: sine),
                startParameter: startParameter, endParameter: endParameter
            )
        case let .polyline(points):
            return .polyline(points.map { point in
                let mapped = applying(to: Point2D(x: point.u, y: point.v))
                return SurfaceParameter(u: mapped.x, v: mapped.y)
            })
        case var .bSpline(spline):
            // An affine map of a rational curve's control points, weights kept, is the curve's image.
            spline.controlPoints = spline.controlPoints.map(applying(to:))
            return .bSpline(spline)
        default:
            return nil
        }
    }
}
