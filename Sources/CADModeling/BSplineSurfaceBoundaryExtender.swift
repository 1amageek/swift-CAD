import Foundation
import CADCore
import CADGeometry

/// Extensions of a B-spline surface past one of its parameter boundaries, each a surface of its
/// own meeting the source along that boundary (Extend Sheet):
///
/// | Shape | Extension | Across the boundary |
/// |---|---|---|
/// | natural | the source's own polynomial continued: its last span extrapolated by blossoming | the source itself, rational or not |
/// | reflective | the source's last stretch reflected through the boundary curve, `2·S(b) − S(b − t)` | tangent, curvature mirrored |
/// | linear | the ruled strip along the source's cross-boundary derivative | tangent |
///
/// Reflective and linear need a non-rational source, whose control points combine affinely.
package struct BSplineSurfaceBoundaryExtender: Sendable {
    package enum Side: Sendable {
        case uLower, uUpper, vLower, vUpper
    }

    package enum Shape: Sendable {
        case natural, reflective, linear
    }

    package init() {}

    /// The extension of `surface` past `side` by `delta` in that parameter (for linear, `delta`
    /// scales the cross-boundary derivative). Its domain runs on from the boundary: past an upper
    /// boundary `b` it spans `[b, b + delta]`, past a lower boundary `a` it spans `[a - delta, a]`.
    package func extended(
        of surface: BSplineSurface3D, past side: Side, by delta: Double, shape: Shape, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try surface.validate(tolerance: tolerance)
        guard delta.isFinite, delta > 0 else {
            throw failure("A surface extension needs a positive parameter length.", tolerance)
        }
        // Every side is reduced to the upper U boundary by reversing and transposing.
        let transposes = side == .vLower || side == .vUpper
        let reverses = side == .uLower || side == .vLower
        var working = transposes ? transposed(surface) : surface
        if reverses { working = reversedU(working) }
        var result: BSplineSurface3D
        switch shape {
        case .natural: result = try naturalUpper(of: working, by: delta, tolerance: tolerance)
        case .reflective: result = try reflectiveUpper(of: working, by: delta, tolerance: tolerance)
        case .linear: result = try linearUpper(of: working, by: delta, tolerance: tolerance)
        }
        if reverses { result = reversedU(result) }
        if transposes { result = transposed(result) }
        try result.validate(tolerance: tolerance)
        return result
    }

    /// The source's last U span, a Bézier span in U, continued by blossoming its homogeneous
    /// control points at the extrapolated parameter.
    private func naturalUpper(of surface: BSplineSurface3D, by delta: Double, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        let degree = surface.uDegree
        guard let upper = surface.uKnots.last, let lowerV = surface.vKnots.first, let upperV = surface.vKnots.last,
              let start = surface.uKnots.last(where: { $0 < upper - tolerance.distance }) else {
            throw failure("A surface extension needs a finite U span.", tolerance)
        }
        let span = try surface.trimmed(uFrom: start, uTo: upper, vFrom: lowerV, vTo: upperV, tolerance: tolerance)
        guard span.controlPoints.allSatisfy({ $0.count == degree + 1 }) else {
            throw failure("A surface's last span did not reduce to one Bézier span.", tolerance)
        }
        let reach = (upper + delta - start) / (upper - start)
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for (row, rowWeights) in zip(span.controlPoints, span.weights) {
            let homogeneous = zip(row, rowWeights).map { point, weight in [point.x * weight, point.y * weight, point.z * weight, weight] }
            var extendedRow: [Point3D] = []
            var extendedWeights: [Double] = []
            for k in 0...degree {
                // The blossom with `degree - k` arguments at the span's end and `k` at the reach.
                let arguments = Array(repeating: 1.0, count: degree - k) + Array(repeating: reach, count: k)
                let value = blossom(homogeneous, arguments)
                guard abs(value[3]) > 1e-300 else { throw failure("An extrapolated weight vanished.", tolerance) }
                extendedRow.append(Point3D(x: value[0] / value[3], y: value[1] / value[3], z: value[2] / value[3]))
                extendedWeights.append(value[3])
            }
            points.append(extendedRow)
            weights.append(extendedWeights)
        }
        return BSplineSurface3D(
            uDegree: degree, vDegree: span.vDegree,
            uKnots: Array(repeating: upper, count: degree + 1) + Array(repeating: upper + delta, count: degree + 1),
            vKnots: span.vKnots, controlPoints: points, weights: weights
        )
    }

    /// `2·S(b, v) − S(b − t, v)` over `t ∈ [0, delta]`: the stretch before the boundary, reversed,
    /// and reflected through the boundary curve, whose control points repeat along U.
    private func reflectiveUpper(of surface: BSplineSurface3D, by delta: Double, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        try requireNonRational(surface, tolerance)
        guard let lower = surface.uKnots.first, let upper = surface.uKnots.last,
              let lowerV = surface.vKnots.first, let upperV = surface.vKnots.last, upper - delta >= lower - tolerance.distance else {
            throw failure("A reflective extension reaches no further than the surface runs.", tolerance)
        }
        let stretch = reversedU(try surface.trimmed(uFrom: max(lower, upper - delta), uTo: upper, vFrom: lowerV, vTo: upperV, tolerance: tolerance))
        // The reversed stretch runs from the boundary; its knots move on past it.
        let knots = stretch.uKnots.map { $0 - stretch.uKnots[0] + upper }
        let points = stretch.controlPoints.map { row -> [Point3D] in
            let boundary = row[0]
            return row.map { boundary + (boundary - $0) }
        }
        return BSplineSurface3D(uDegree: stretch.uDegree, vDegree: stretch.vDegree, uKnots: knots, vKnots: stretch.vKnots, controlPoints: points)
    }

    /// The ruled strip from the boundary curve along `delta` times the cross-boundary derivative,
    /// whose control points are the source's last differences.
    private func linearUpper(of surface: BSplineSurface3D, by delta: Double, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        try requireNonRational(surface, tolerance)
        let degree = surface.uDegree
        let count = surface.controlPoints.first?.count ?? 0
        guard count >= 2, let upper = surface.uKnots.last else { throw failure("A surface extension needs a U span.", tolerance) }
        let before = surface.uKnots[count - 1]
        guard upper - before > tolerance.distance else { throw failure("A surface's last U span is degenerate.", tolerance) }
        let scale = Double(degree) / (upper - before)
        let points = surface.controlPoints.map { row -> [Point3D] in
            let end = row[count - 1]
            return [end, end + (end - row[count - 2]) * (scale * delta)]
        }
        return BSplineSurface3D(
            uDegree: 1, vDegree: surface.vDegree, uKnots: [upper, upper, upper + delta, upper + delta],
            vKnots: surface.vKnots, controlPoints: points
        )
    }

    /// The blossom of a Bézier span's homogeneous control points at `arguments`, by de Casteljau's
    /// algorithm with one argument per level.
    private func blossom(_ points: [[Double]], _ arguments: [Double]) -> [Double] {
        var level = points
        for t in arguments {
            level = (0..<(level.count - 1)).map { i in (0..<4).map { level[i][$0] * (1 - t) + level[i + 1][$0] * t } }
        }
        return level[0]
    }

    private func reversedU(_ surface: BSplineSurface3D) -> BSplineSurface3D {
        let first = surface.uKnots.first ?? 0
        let last = surface.uKnots.last ?? 0
        return BSplineSurface3D(
            uDegree: surface.uDegree, vDegree: surface.vDegree,
            uKnots: surface.uKnots.reversed().map { first + last - $0 }, vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { Array($0.reversed()) }, weights: surface.weights.map { Array($0.reversed()) }
        )
    }

    private func transposed(_ surface: BSplineSurface3D) -> BSplineSurface3D {
        let rows = surface.controlPoints.count
        let columns = surface.controlPoints.first?.count ?? 0
        return BSplineSurface3D(
            uDegree: surface.vDegree, vDegree: surface.uDegree, uKnots: surface.vKnots, vKnots: surface.uKnots,
            controlPoints: (0..<columns).map { u in (0..<rows).map { surface.controlPoints[$0][u] } },
            weights: (0..<columns).map { u in (0..<rows).map { surface.weights[$0][u] } }
        )
    }

    private func requireNonRational(_ surface: BSplineSurface3D, _ tolerance: ModelingTolerance) throws {
        guard surface.weights.joined().allSatisfy({ abs($0 - 1) <= 1e-12 }) else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Reflective and linear extensions need a non-rational B-spline surface.")
        }
    }

    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
