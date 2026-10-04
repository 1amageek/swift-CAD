import Foundation
import CADCore
import CADGeometry

/// The trimming curve of an edge on a face whose surface has no exact one for the edge's curve
/// (a spline edge on a spline face): a cubic spline through the surface parameters of the curve's
/// points at even steps of its own parameter between `start` and `end`, a periodic angle unwrapped
/// along it. It follows the edge as its parameter does, so the edge's correspondence with the face
/// is certified against it within the validator's bound. The fewest samples (8, 16, 32 or 64)
/// whose spline's image stays within a thousandth of the distance tolerance of the curve between
/// the samples are taken: every span multiplies the work of the certified checks and integrals
/// that read the face, and an image near the tolerance makes them subdivide far.
package struct SampledPcurveFitter {
    private static let sampleCounts = [8, 16, 32, 64]

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func pcurve(of curve: Curve3D, from start: Double, to end: Double, on surface: Surface3D) throws -> BSplineCurve2D {
        var fitted: BSplineCurve2D?
        for count in Self.sampleCounts {
            let candidate = try pcurve(of: curve, from: start, to: end, on: surface, samples: count)
            fitted = candidate
            // The image between samples, against the curve there.
            var worst = 0.0
            for k in 0..<(2 * count) {
                let fraction = (Double(k) + 0.5) / Double(2 * count)
                let uv = try candidate.point(at: fraction, tolerance: tolerance)
                let image = try surface.point(u: uv.x, v: uv.y, tolerance: tolerance)
                let target = try curve.point(at: start + (end - start) * fraction, tolerance: tolerance)
                worst = max(worst, (image - target).length)
            }
            if worst <= tolerance.distance * 1e-3 { return candidate }
        }
        // Past the densest sampling the validator judges the spline against its own bound.
        guard let fitted else { throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "No pcurve samples.") }
        return fitted
    }

    private func pcurve(of curve: Curve3D, from start: Double, to end: Double, on surface: Surface3D, samples count: Int) throws -> BSplineCurve2D {
        let degree = 3
        let knots = Array(repeating: 0.0, count: degree + 1)
            + (1..<(count - degree)).map { Double($0) / Double(count - degree) }
            + Array(repeating: 1.0, count: degree + 1)
        let grevilles = (0..<count).map { knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        var chart: [Point2D] = []
        for g in grevilles {
            let point = try curve.point(at: start + (end - start) * g, tolerance: tolerance)
            // Each sample is refined from the last one's parameters (the first from the nearest
            // point of a coarse grid over a bounded surface), the curve running on along the
            // surface; one the refinement does not settle is projected afresh.
            let seed = try chart.last.map { ($0.x, $0.y) } ?? coarseSeed(point, on: surface)
            let uv: (u: Double, v: Double)
            if let seed, let refined = try refined(point, from: seed, on: surface) {
                uv = refined
            } else {
                let projected = try surface.parameterProjection(of: point, tolerance: tolerance)
                uv = (projected.u, projected.v)
            }
            var next = Point2D(x: uv.u, y: uv.v)
            if let previous = chart.last {
                if case let .periodic(period) = surface.uDomain { next.x += ((previous.x - next.x) / period).rounded() * period }
                if case let .periodic(period) = surface.vDomain { next.y += ((previous.y - next.y) / period).rounded() * period }
            }
            chart.append(next)
        }
        var matrix: [Double] = []
        for g in grevilles {
            for column in 0..<count {
                let unit = BSplineCurve3D(degree: degree, knots: knots,
                                          controlPoints: (0..<count).map { $0 == column ? Point3D(x: 1, y: 0, z: 0) : .origin })
                matrix.append(try Curve3D.bSpline(unit).point(at: g, tolerance: tolerance).x)
            }
        }
        let qr = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count,
                                      relativeRankTolerance: 1e-12, maximumElements: 1 << 20)
        let x = try qr.solveFullRankLeastSquares(chart.map(\.x))
        let y = try qr.solveFullRankLeastSquares(chart.map(\.y))
        return BSplineCurve2D(degree: degree, knots: knots, controlPoints: zip(x, y).map { Point2D(x: $0, y: $1) })
    }

    /// The parameters of the grid point nearest `point` on a surface bounded in both directions;
    /// nil on an unbounded or periodic one.
    private func coarseSeed(_ point: Point3D, on surface: Surface3D) throws -> (u: Double, v: Double)? {
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(v0, v1) = surface.vDomain else { return nil }
        var best: (u: Double, v: Double, distance: Double)?
        for i in 0...32 {
            for j in 0...32 {
                let (u, v) = (u0 + (u1 - u0) * Double(i) / 32, v0 + (v1 - v0) * Double(j) / 32)
                let distance = (try surface.point(u: u, v: v, tolerance: tolerance) - point).length
                if best.map({ distance < $0.distance }) ?? true { best = (u, v, distance) }
            }
        }
        return best.map { ($0.u, $0.v) }
    }

    /// Gauss–Newton steps from `seed` toward the foot of `point` on the surface: nil unless they
    /// settle (the step moving the surface by a thousandth of the distance tolerance) inside the
    /// domain with the point within the distance tolerance of its foot.
    private func refined(_ point: Point3D, from seed: (u: Double, v: Double), on surface: Surface3D) throws -> (u: Double, v: Double)? {
        var (u, v) = seed
        for _ in 0..<12 {
            let here = try surface.point(u: u, v: v, tolerance: tolerance)
            let miss = point - here
            // The difference steps inward at a closed domain's upper end, so the surface is only
            // evaluated within its domain.
            func step(_ value: Double, in domain: ParameterDomain) -> Double {
                if case let .closed(_, upper) = domain, value + 1e-7 > upper { return -1e-7 }
                return 1e-7
            }
            let (hu, hv) = (step(u, in: surface.uDomain), step(v, in: surface.vDomain))
            let su = (try surface.point(u: u + hu, v: v, tolerance: tolerance) - here) * (1 / hu)
            let sv = (try surface.point(u: u, v: v + hv, tolerance: tolerance) - here) * (1 / hv)
            let (a, b, c) = (su.dot(su), su.dot(sv), sv.dot(sv))
            let determinant = a * c - b * b
            guard determinant > 0 else { return nil }
            let (p, q) = (su.dot(miss), sv.dot(miss))
            let (du, dv) = ((c * p - b * q) / determinant, (a * q - b * p) / determinant)
            u += du
            v += dv
            for (value, domain) in [(u, surface.uDomain), (v, surface.vDomain)] {
                if case let .closed(lower, upper) = domain, value < lower - 1e-9 || value > upper + 1e-9 { return nil }
            }
            if case let .closed(lower, upper) = surface.uDomain { u = min(max(u, lower), upper) }
            if case let .closed(lower, upper) = surface.vDomain { v = min(max(v, lower), upper) }
            if (su * du + sv * dv).length <= tolerance.distance * 1e-3 {
                return miss.length <= tolerance.distance ? (u, v) : nil
            }
        }
        return nil
    }
}
