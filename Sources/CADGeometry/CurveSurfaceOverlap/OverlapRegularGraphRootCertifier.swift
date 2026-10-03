import CADCore
import Foundation

/// Two dependent UV variables; source t is never solved as an isolated root.
struct OverlapRegularGraphRootCertifier: Sendable {
    typealias Interval = OutwardScalarInterval
    typealias Pair = OverlapRegularGraphCell.Pair
    let curve: PreparedCurveDifferentialEncloser
    let surface: PreparedBSplineSurfaceDifferentialEncloser
    let tolerance: ModelingTolerance

    var originalSurface: Surface3D { .bSpline(surface.surface) }

    var jetWork: Int {
        // preparation checked these products and charged original storage first.
        guard case .bSpline(let c) = curve.curve else { return 1 }
        let s = surface.surface
        return c.controlPointCount * (c.degree + 1) + s.uControlPointCount * s.vControlPointCount * (s.uDegree + 1) * (s.vDegree + 1)
    }

    struct Proof {
        let box: SurfaceParameterBox
        let u: [Interval]
        let v: [Interval]
        let residual: [Interval]
    }

    func seed(at t: Double, pair: Pair, initial: SurfaceParameter,
              budget: inout OverlapProofBudget) throws -> SurfaceParameter? {
        try budget.work(jetWork)
        let point = try curve.curve.point(at: t, tolerance: tolerance)
        guard case let .closed(ul, uh) = originalSurface.uDomain,
              case let .closed(vl, vh) = originalSurface.vDomain else { return nil }
        var uv = initial
        for _ in 0..<budget.options.maximumIterations {
            try budget.work(jetWork)
            let jet = try surface.intervalJet(over: narrowBox(uv), tolerance: tolerance)
            let f = OverlapRegularGraphCell.component(jet, pair.first), g = OverlapRegularGraphCell.component(jet, pair.second)
            let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
            let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
            let determinant = a * d - b * c
            guard determinant.isFinite, determinant != 0 else { return nil }
            let targetPoint = try originalSurface.point(u: uv.u, v: uv.v, tolerance: tolerance)
            let first = OverlapRegularGraphCell.coordinate(targetPoint, pair.first) - OverlapRegularGraphCell.coordinate(point, pair.first)
            let second = OverlapRegularGraphCell.coordinate(targetPoint, pair.second) - OverlapRegularGraphCell.coordinate(point, pair.second)
            let du = (d * first - b * second) / determinant
            let dv = (a * second - c * first) / determinant
            guard du.isFinite, dv.isFinite else { return nil }
            if hypot(first, second) <= tolerance.distance * tolerance.relative { return uv }
            var scale = 1.0
            var accepted: SurfaceParameter?
            for _ in 0..<budget.options.maximumIterations {
                try budget.work(jetWork)
                let next = SurfaceParameter(u: uv.u - du * scale, v: uv.v - dv * scale)
                if next.u >= ul, next.u <= uh, next.v >= vl, next.v <= vh {
                    let target = try originalSurface.point(u: next.u, v: next.v, tolerance: tolerance)
                    let f = OverlapRegularGraphCell.coordinate(target, pair.first) - OverlapRegularGraphCell.coordinate(point, pair.first)
                    let g = OverlapRegularGraphCell.coordinate(target, pair.second) - OverlapRegularGraphCell.coordinate(point, pair.second)
                    if hypot(f, g) < hypot(first, second) { accepted = next; break }
                }
                scale *= 0.5
            }
            guard let next = accepted else { return uv }
            if next == uv { return uv }
            uv = next
        }
        return uv
    }

    func trialBox(range: ScalarInterval, pair: Pair, seed: SurfaceParameter,
                  budget: inout OverlapProofBudget) throws -> SurfaceParameterBox? {
        try budget.work(jetWork)
        let source = try curve.thirdOrderIntervalJet(over: range, tolerance: tolerance)
        let point = try surface.pointJet(u: seed.u, v: seed.v, tolerance: tolerance)
        let f = OverlapRegularGraphCell.component(point, pair.first), g = OverlapRegularGraphCell.component(point, pair.second)
        let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
        let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0,
              case let .closed(ul, uh) = originalSurface.uDomain,
              case let .closed(vl, vh) = originalSurface.vDomain else { return nil }
        let first = OverlapRegularGraphCell.component(source, pair.first).derivativeU
        let second = OverlapRegularGraphCell.component(source, pair.second).derivativeU
        let uMotion = (Interval.exact(d / determinant) * first - .exact(b / determinant) * second).absoluteUpperBound
        let vMotion = (Interval.exact(a / determinant) * second - .exact(c / determinant) * first).absoluteUpperBound
        let firstValue = f.value - OverlapRegularGraphCell.component(source, pair.first).value
        let secondValue = g.value - OverlapRegularGraphCell.component(source, pair.second).value
        let uCorrection = Interval.exact(d / determinant) * firstValue - .exact(b / determinant) * secondValue
        let vCorrection = Interval.exact(a / determinant) * secondValue - .exact(c / determinant) * firstValue
        // Independent homogeneous value intervals can exceed true derivative
        // motion, even after subdivision or on a constant rational coordinate.
        // This padding is only a candidate; strict root inclusion remains authority.
        let uRadius = max(uMotion * range.width, uCorrection.absoluteUpperBound * 2,
            max(abs(seed.u), 1) * Double.ulpOfOne * 128)
        let vRadius = max(vMotion * range.width, vCorrection.absoluteUpperBound * 2,
            max(abs(seed.v), 1) * Double.ulpOfOne * 128)
        guard uRadius.isFinite, vRadius.isFinite else {
            throw failure(.resourceLimitExceeded, "A regular graph trial tube exceeds finite candidate arithmetic.")
        }
        let u = try ScalarInterval(lower: max(ul, (seed.u - uRadius).nextDown), upper: min(uh, (seed.u + uRadius).nextUp))
        let v = try ScalarInterval(lower: max(vl, (seed.v - vRadius).nextDown), upper: min(vh, (seed.v + vRadius).nextUp))
        guard u.width > 0, v.width > 0 else { return nil }
        return SurfaceParameterBox(u: u, v: v)
    }

    func proof(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
               budget: inout OverlapProofBudget) throws -> Proof? {
        try budget.work(jetWork * 3)
        try validateSmoothChart(box)
        let source = try curve.thirdOrderIntervalJet(over: range, tolerance: tolerance)
        let target = try surface.intervalJet(over: box, tolerance: tolerance)
        let center = SurfaceParameter(u: box.u.midpoint, v: box.v.midpoint)
        let centerJet = try surface.pointJet(u: center.u, v: center.v, tolerance: tolerance)
        let f = OverlapRegularGraphCell.component(target, pair.first)
        let g = OverlapRegularGraphCell.component(target, pair.second)
        let determinant = f.derivativeU * g.derivativeV - f.derivativeV * g.derivativeU
        guard (determinant.lower > 0 || determinant.upper < 0), determinant.isFinite else { return nil }
        let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
        let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
        let middleDeterminant = a * d - b * c
        guard middleDeterminant.isFinite, middleDeterminant != 0 else { return nil }
        let inverse = [[d / middleDeterminant, -b / middleDeterminant], [-c / middleDeterminant, a / middleDeterminant]]
        guard inverse.joined().allSatisfy(\.isFinite) else { return nil }
        let jacobian = [[f.derivativeU, f.derivativeV], [g.derivativeU, g.derivativeV]]
        let values = [OverlapRegularGraphCell.component(centerJet, pair.first).value - OverlapRegularGraphCell.component(source, pair.first).value,
            OverlapRegularGraphCell.component(centerJet, pair.second).value - OverlapRegularGraphCell.component(source, pair.second).value]
        let widths = [Interval(lower: box.u.lower, upper: box.u.upper) - .exact(center.u),
            Interval(lower: box.v.lower, upper: box.v.upper) - .exact(center.v)]
        var contracted: [Interval] = []
        for row in 0..<2 {
            var value = Interval.exact(row == 0 ? center.u : center.v)
            for index in 0..<2 { value = value - .exact(inverse[row][index]) * values[index] }
            var contraction = Interval.exact(0)
            for column in 0..<2 {
                var entry = Interval.exact(row == column ? 1 : 0)
                for index in 0..<2 { entry = entry - .exact(inverse[row][index]) * jacobian[index][column] }
                contraction = contraction + .exact(entry.absoluteUpperBound)
                value = value + entry * widths[column]
            }
            let original = row == 0 ? box.u : box.v
            guard contraction.upper < 1, value.isFinite,
                  value.lower > original.lower, value.upper < original.upper else { return nil }
            contracted.append(value)
        }
        let rootBox = SurfaceParameterBox(u: try ScalarInterval(lower: contracted[0].lower, upper: contracted[0].upper),
            v: try ScalarInterval(lower: contracted[1].lower, upper: contracted[1].upper))
        let derivatives = try graphDerivatives(source: source, target: target, pair: pair, determinant: determinant)
        var residual = residualJet(source: source, target: target, axis: pair.remaining, u: derivatives.u, v: derivatives.v)
        try budget.work(jetWork)
        let imageTarget = try surface.intervalJet(over: rootBox, tolerance: tolerance)
        // Strict inclusion already proves every original-box root lies in this
        // image. Localize only the residual value; all derivative bounds retain
        // the original chart and its certified positive minor.
        residual[0] = OverlapRegularGraphCell.component(source, pair.remaining).value
            - OverlapRegularGraphCell.component(imageTarget, pair.remaining).value
        guard residual[0].isFinite else {
            throw failure(.resourceLimitExceeded, "A certified root image exceeds finite residual arithmetic.")
        }
        return Proof(box: rootBox, u: derivatives.u, v: derivatives.v, residual: residual)
    }

    func pointProof(at t: Double, cell: OverlapRegularGraphCell,
                    budget: inout OverlapProofBudget) throws -> Proof {
        let lower = max(cell.range.lower, t.nextDown), upper = min(cell.range.upper, t.nextUp)
        let range = try ScalarInterval(lower: lower, upper: upper)
        guard range.width > 0 else { throw failure(.resourceLimitExceeded, "A graph root has no representable source enclosure.") }
        var box = cell.box
        var last: Proof?
        for _ in 0..<budget.options.maximumIterations {
            guard let value = try proof(range: range, box: box, pair: cell.pair, budget: &budget) else {
                if let last { return last }
                throw failure(.intersectionFailure, "An owned graph could not reproduce its point root certificate.")
            }
            last = value
            let next = try padded(value.box)
            if next.u.width >= box.u.width && next.v.width >= box.v.width { break }
            box = next
        }
        guard let last else { throw failure(.intersectionFailure, "An owned graph has no certified point root.") }
        return last
    }

    func narrowBox(_ center: SurfaceParameter) throws -> SurfaceParameterBox {
        try box(u: center.u.nextDown, center.u.nextUp, v: center.v.nextDown, center.v.nextUp)
    }

    func padded(_ value: SurfaceParameterBox) throws -> SurfaceParameterBox {
        try box(u: value.u.lower.nextDown, value.u.upper.nextUp, v: value.v.lower.nextDown, value.v.upper.nextUp)
    }

    private func box(u ul: Double, _ uh: Double, v vl: Double, _ vh: Double) throws -> SurfaceParameterBox {
        guard case let .closed(u0, u1) = originalSurface.uDomain,
              case let .closed(v0, v1) = originalSurface.vDomain else { throw failure(.unsupportedCapability, "Regular graph charts require finite closed axes.") }
        return SurfaceParameterBox(u: try ScalarInterval(lower: max(u0, ul), upper: min(u1, uh)),
            v: try ScalarInterval(lower: max(v0, vl), upper: min(v1, vh)))
    }

    private func graphDerivatives(source: SurfaceIntervalVectorJet, target: SurfaceIntervalVectorJet,
                                  pair: Pair, determinant: Interval) throws -> (u: [Interval], v: [Interval]) {
        let first = OverlapRegularGraphCell.component(target, pair.first)
        let second = OverlapRegularGraphCell.component(target, pair.second)
        func solve(_ a: Interval, _ b: Interval) throws -> (Interval, Interval) {
            guard let u = (second.derivativeV * a - first.derivativeV * b).divided(by: determinant),
                  let v = (first.derivativeU * b - second.derivativeU * a).divided(by: determinant), u.isFinite, v.isFinite else {
                throw failure(.resourceLimitExceeded, "Implicit graph derivatives exceeded finite arithmetic.")
            }
            return (u, v)
        }
        let a = OverlapRegularGraphCell.component(source, pair.first)
        let b = OverlapRegularGraphCell.component(source, pair.second)
        let p = try solve(a.derivativeU, b.derivativeU)
        func secondChain(_ jet: SurfaceIntervalJet) -> Interval {
            jet.secondDerivativeUU * p.0 * p.0 + .exact(2) * jet.secondDerivativeUV * p.0 * p.1 + jet.secondDerivativeVV * p.1 * p.1
        }
        let q = try solve(a.secondDerivativeUU - secondChain(first), b.secondDerivativeUU - secondChain(second))
        func thirdChain(_ jet: SurfaceIntervalJet) -> Interval {
            jet.thirdDerivativeUUU * p.0 * p.0 * p.0
                + .exact(3) * jet.thirdDerivativeUUV * p.0 * p.0 * p.1
                + .exact(3) * jet.thirdDerivativeUVV * p.0 * p.1 * p.1
                + jet.thirdDerivativeVVV * p.1 * p.1 * p.1
                + .exact(3) * (jet.secondDerivativeUU * p.0 * q.0
                    + jet.secondDerivativeUV * (p.0 * q.1 + p.1 * q.0) + jet.secondDerivativeVV * p.1 * q.1)
        }
        let r = try solve(a.thirdDerivativeUUU - thirdChain(first), b.thirdDerivativeUUU - thirdChain(second))
        return ([p.0, q.0, r.0], [p.1, q.1, r.1])
    }

    private func residualJet(source: SurfaceIntervalVectorJet, target: SurfaceIntervalVectorJet,
                             axis: Int, u: [Interval], v: [Interval]) -> [Interval] {
        let c = OverlapRegularGraphCell.component(source, axis), s = OverlapRegularGraphCell.component(target, axis)
        return [c.value - s.value,
            c.derivativeU - s.derivativeU * u[0] - s.derivativeV * v[0],
            c.secondDerivativeUU - s.derivativeU * u[1] - s.derivativeV * v[1]
                - s.secondDerivativeUU * u[0] * u[0] - .exact(2) * s.secondDerivativeUV * u[0] * v[0] - s.secondDerivativeVV * v[0] * v[0],
            c.thirdDerivativeUUU - s.derivativeU * u[2] - s.derivativeV * v[2]
                - s.thirdDerivativeUUU * u[0] * u[0] * u[0] - .exact(3) * s.thirdDerivativeUUV * u[0] * u[0] * v[0]
                - .exact(3) * s.thirdDerivativeUVV * u[0] * v[0] * v[0] - s.thirdDerivativeVVV * v[0] * v[0] * v[0]
                - .exact(3) * (s.secondDerivativeUU * u[0] * u[1] + s.secondDerivativeUV * (u[0] * v[1] + v[0] * u[1]) + s.secondDerivativeVV * v[0] * v[1])]
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }

    private func validateSmoothChart(_ box: SurfaceParameterBox) throws {
        let spline = surface.surface
        for (knots, degree, interval) in [(spline.uKnots, spline.uDegree, box.u), (spline.vKnots, spline.vDegree, box.v)] {
            var index = degree + 1
            while index < knots.count - degree - 1 {
                let value = knots[index]
                var end = index + 1
                while end < knots.count, knots[end] == value { end += 1 }
                // FIXME(INCOMPLETE_IMPLEMENTATION): graph Taylor certification across
                // a nonsmooth target knot has no one-sided atlas proof yet. The public
                // regular-graph route must refuse it until joins and residual bounds
                // on both sides of every such knot are independently certified.
                if value > interval.lower, value < interval.upper, degree - (end - index) < 2 {
                    throw failure(.unsupportedCapability, "A graph residual chart crosses a target knot without certified second-order continuity.")
                }
                index = end
            }
        }
    }
}
