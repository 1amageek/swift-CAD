import CADCore
import Foundation

/// One sketch curve as exact planar geometry in its sketch plane.
///
/// Each case defines the curve's natural parameter, which is the parameter an
/// intersection reports for it:
/// - `line`: `t` with `start + t * (end - start)`; `t` in `[0, 1]` on the authored segment.
/// - `circle`: the polar angle about the center in radians, normalized to `[0, 2π)`.
/// - `arc`: the polar angle about the center in radians, normalized to `[0, 2π)`; the arc runs
///   counterclockwise from `startAngle` through its positive sweep to `endAngle`.
/// - `cubicBezierChain`: the chain parameter in `[0, spanCount]`, span `i` covering `[i, i + 1]`,
///   the same parameterization profile extraction gives a sketch spline.
/// - `sketchSpline`: a sketch spline of any degree or knots; its B-spline parameter.
public enum SketchCurveGeometry2D: Sendable, Hashable {
    case line(start: Point2D, end: Point2D)
    case circle(center: Point2D, radius: Double)
    case arc(center: Point2D, radius: Double, startAngle: Double, endAngle: Double)
    case cubicBezierChain(controlPoints: [Point2D])
    case sketchSpline(SketchSplineCurve)
}
