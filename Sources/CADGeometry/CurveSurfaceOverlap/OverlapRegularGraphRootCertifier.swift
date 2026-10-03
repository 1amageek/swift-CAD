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
        let authority: OverlapRegularGraphAtlas
        // Collars retain only first derivatives and a residual value.
        let u: [Interval]
        let v: [Interval]
        let residual: [Interval]
    }

    /// Minted only after a strict proof in this point-refinement invocation.
    private struct PointRootAuthority {
        let range: ScalarInterval
        let pair: Pair
        let initial: Proof
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
        let candidate = SurfaceParameterBox(u: u, v: v)
        let authority = try OverlapRegularGraphAtlas.authority(over: candidate, surface: surface.surface,
            tolerance: tolerance, budget: &budget)
        if authority.isSmooth { return candidate }
        return try collarTrialBox(candidate, seed: seed, firstValue: firstValue,
            secondValue: secondValue, pair: pair, budget: &budget)
    }

    private func collarTrialBox(_ candidate: SurfaceParameterBox, seed: SurfaceParameter,
                               firstValue: Interval, secondValue: Interval, pair: Pair,
                               budget: inout OverlapProofBudget) throws -> SurfaceParameterBox? {
        try budget.work(jetWork)
        let target = try surface.intervalJet(over: candidate, tolerance: tolerance)
        let first = OverlapRegularGraphCell.component(target, pair.first)
        let second = OverlapRegularGraphCell.component(target, pair.second)
        let a = first.derivativeU.midpoint, b = first.derivativeV.midpoint
        let c = second.derivativeU.midpoint, d = second.derivativeV.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0 else { return nil }
        let inverse = [[d / determinant, -b / determinant], [-c / determinant, a / determinant]]
        guard inverse.joined().allSatisfy(\.isFinite) else { return nil }
        let jacobian = [[first.derivativeU, first.derivativeV], [second.derivativeU, second.derivativeV]]
        var q = 0.0
        for row in 0..<2 {
            var sum = Interval.exact(0)
            for column in 0..<2 {
                var entry = Interval.exact(row == column ? 1 : 0)
                for index in 0..<2 { entry = entry - .exact(inverse[row][index]) * jacobian[index][column] }
                sum = sum + .exact(entry.absoluteUpperBound)
            }
            q = max(q, sum.upper)
        }
        guard q.isFinite, q < 1 else { return nil }
        let uCorrection = Interval.exact(inverse[0][0]) * firstValue + .exact(inverse[0][1]) * secondValue
        let vCorrection = Interval.exact(inverse[1][0]) * firstValue + .exact(inverse[1][1]) * secondValue
        guard let padding = (Interval.exact(max(uCorrection.absoluteUpperBound, vCorrection.absoluteUpperBound)) * .exact(2))
            .divided(by: Interval.exact(1) - .exact(q)), padding.isFinite else {
            throw failure(.resourceLimitExceeded, "A knot collar has no finite candidate contraction margin.")
        }
        // One union preconditioner contains both one-sided motions. This is a
        // candidate only; the final box must reproduce strict Krawczyk inclusion.
        let padded = try box(u: (seed.u - padding.upper).nextDown, (seed.u + padding.upper).nextUp,
            v: (seed.v - padding.upper).nextDown, (seed.v + padding.upper).nextUp)
        return SurfaceParameterBox(
            u: try ScalarInterval(lower: min(candidate.u.lower, padded.u.lower), upper: max(candidate.u.upper, padded.u.upper)),
            v: try ScalarInterval(lower: min(candidate.v.lower, padded.v.lower), upper: max(candidate.v.upper, padded.v.upper)))
    }

    func proof(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
               budget: inout OverlapProofBudget) throws -> Proof? {
        try rootProof(range: range, box: box, pair: pair, existingRoot: nil, budget: &budget)
    }

    private func rootProof(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
                           existingRoot: PointRootAuthority?,
                           budget: inout OverlapProofBudget) throws -> Proof? {
        if let existingRoot {
            guard range == existingRoot.range, pair == existingRoot.pair,
                  box.u.lower >= existingRoot.initial.box.u.lower,
                  box.u.upper <= existingRoot.initial.box.u.upper,
                  box.v.lower >= existingRoot.initial.box.v.lower,
                  box.v.upper <= existingRoot.initial.box.v.upper else {
                throw failure(.intersectionFailure, "Point localization changed its original root authority.")
            }
        }
        try budget.work(jetWork * 3)
        let authority = try OverlapRegularGraphAtlas.authority(over: box, surface: surface.surface,
            tolerance: tolerance, budget: &budget)
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
            guard contraction.upper < 1, value.isFinite else { return nil }
            if existingRoot == nil {
                guard value.lower > original.lower, value.upper < original.upper else { return nil }
            } else {
                // The first strict proof owns an existing unique root. Every such
                // root in this box belongs to its K image even without new strict
                // inclusion, so intersection preserves that same root.
                let lower = max(value.lower, original.lower), upper = min(value.upper, original.upper)
                guard lower < upper else {
                    throw failure(.intersectionFailure, "An existing point root lost its finite positive-width localization.")
                }
                value = Interval(lower: lower, upper: upper)
            }
            contracted.append(value)
        }
        let rootBox = SurfaceParameterBox(u: try ScalarInterval(lower: contracted[0].lower, upper: contracted[0].upper),
            v: try ScalarInterval(lower: contracted[1].lower, upper: contracted[1].upper))
        let derivatives = try graphDerivatives(source: source, target: target, pair: pair, determinant: determinant,
            thirdOrder: authority.isSmooth)
        if case .collar(let axis, _) = authority {
            let derivative = axis == .u ? derivatives.u[0] : derivatives.v[0]
            // FIXME(INCOMPLETE_IMPLEMENTATION): continuous or non-transverse native
            // knot coincidence lacks complete atlas classification. The public graph
            // route must refuse until all boundary intervals and root identities can
            // be certified without a higher-derivative continuity assumption.
            guard derivative.lower > 0 || derivative.upper < 0 else {
                throw failure(.unsupportedCapability, "A knot collar requires a proved transverse native-knot passage.")
            }
        }
        try budget.work(jetWork)
        let imageTarget = try surface.intervalJet(over: rootBox, tolerance: tolerance)
        // Strict inclusion, or the retained point-root authority, puts every
        // relevant root in this image. Only the residual value uses imageTarget;
        // derivative bounds retain the evaluated chart and its positive minor.
        let residualValue = OverlapRegularGraphCell.component(source, pair.remaining).value
            - OverlapRegularGraphCell.component(imageTarget, pair.remaining).value
        guard residualValue.isFinite else {
            throw failure(.resourceLimitExceeded, "A certified root image exceeds finite residual arithmetic.")
        }
        let residual: [Interval]
        if authority.isSmooth {
            var jet = residualJet(source: source, target: target, axis: pair.remaining, u: derivatives.u, v: derivatives.v)
            jet[0] = residualValue
            residual = jet
        } else { residual = [residualValue] }
        return Proof(box: rootBox, authority: authority, u: derivatives.u, v: derivatives.v, residual: residual)
    }

    func pointProof(at t: Double, cell: OverlapRegularGraphCell,
                    budget: inout OverlapProofBudget) throws -> Proof {
        let lower = max(cell.range.lower, t.nextDown), upper = min(cell.range.upper, t.nextUp)
        let range = try ScalarInterval(lower: lower, upper: upper)
        guard range.width > 0 else { throw failure(.resourceLimitExceeded, "A graph root has no representable source enclosure.") }
        guard let first = try proof(range: range, box: cell.box, pair: cell.pair, budget: &budget) else {
            throw failure(.intersectionFailure, "An owned graph could not reproduce its point root certificate.")
        }
        let owner = PointRootAuthority(range: range, pair: cell.pair, initial: first)
        var last = first
        for _ in 1..<budget.options.maximumIterations {
            guard let value = try rootProof(range: owner.range, box: last.box, pair: owner.pair,
                existingRoot: owner, budget: &budget) else { return last }
            let stationary = value.box.u.width >= last.box.u.width && value.box.v.width >= last.box.v.width
            last = value
            if stationary { break }
        }
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
                                  pair: Pair, determinant: Interval, thirdOrder: Bool) throws -> (u: [Interval], v: [Interval]) {
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
        if !thirdOrder { return ([p.0], [p.1]) }
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

}
