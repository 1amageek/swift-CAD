import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Two dependent UV variables; source t is never solved as an isolated root.
struct OverlapRegularGraphRootCertifier: Sendable {
    typealias Interval = OutwardScalarInterval
    typealias Pair = OverlapRegularGraphCell.Pair
    let curve: PreparedCurveDifferentialEncloser
    let surface: PreparedBSplineSurfaceDifferentialEncloser
    let tolerance: ModelingTolerance
    let coordinateIndependence: OverlapRegularGraphClosedDomainAuthority.TargetIndependence?

    init(curve: PreparedCurveDifferentialEncloser, surface: PreparedBSplineSurfaceDifferentialEncloser,
         tolerance: ModelingTolerance) {
        self.curve = curve; self.surface = surface; self.tolerance = tolerance
        coordinateIndependence = nil
    }

    init(curve: PreparedCurveDifferentialEncloser,
         coordinateIndependence: OverlapRegularGraphClosedDomainAuthority.TargetIndependence,
         tolerance: ModelingTolerance) {
        self.curve = curve; self.surface = coordinateIndependence.prepared; self.tolerance = tolerance
        self.coordinateIndependence = coordinateIndependence
    }

    func targetJet(over box: SurfaceParameterBox, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        let original = try surface.intervalJet(over: box, tolerance: tolerance, using: &execution)
        if let coordinateIndependence { return try coordinateIndependence.intersecting(original, tolerance: tolerance) }
        return original
    }

    private func targetPointJet(u: Double, v: Double, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        let original = try surface.pointJet(u: u, v: v, tolerance: tolerance, using: &execution)
        if let coordinateIndependence { return try coordinateIndependence.intersecting(original, tolerance: tolerance) }
        return original
    }

    var originalSurface: Surface3D { .bSpline(surface.surface) }

    var jetWork: Int {
        // preparation checked these products and charged original storage first.
        guard case .bSpline(let c) = curve.curve else { return 1 }
        let s = surface.surface
        return c.controlPointCount * (c.degree + 1) + s.uControlPointCount * s.vControlPointCount * (s.uDegree + 1) * (s.vDegree + 1)
    }

    struct Proof {
        let range: ScalarInterval
        let pair: Pair
        let box: SurfaceParameterBox
        let authority: OverlapRegularGraphAtlas
        // Collars retain only first derivatives and a residual value.
        let u: [Interval]
        let v: [Interval]
        let residual: [Interval]
        let firstResidualDerivative: Interval?
        let sourcePositionWidthLowerBound: Double
        let closedDomain: OverlapRegularGraphClosedDomainAuthority?

        var stationaryParameters: (u: Double?, v: Double?) {
            closedDomain?.stationaryParameters ?? (nil, nil)
        }
    }

    /// Minted only after strict K inclusion or exact closed-domain IVT existence.
    private struct KnownRootAuthority {
        let range: ScalarInterval
        let pair: Pair
        let initial: Proof
        let retainsCollar: Bool
    }

    func seed(at t: Double, pair: Pair, initial: SurfaceParameter,
              policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter? {
        try policy.work(jetWork, using: &execution)
        let point = try curve.curve.point(at: t, tolerance: tolerance, using: &execution)
        guard case let .closed(ul, uh) = originalSurface.uDomain,
              case let .closed(vl, vh) = originalSurface.vDomain else { return nil }
        var uv = initial
        for _ in 0..<policy.options.maximumIterations {
            try policy.work(jetWork, using: &execution)
            let jet = try targetJet(over: narrowBox(uv), using: &execution)
            let f = OverlapRegularGraphCell.component(jet, pair.first), g = OverlapRegularGraphCell.component(jet, pair.second)
            let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
            let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
            let determinant = a * d - b * c
            guard determinant.isFinite, determinant != 0 else { return nil }
            let targetPoint = try originalSurface.point(u: uv.u, v: uv.v, tolerance: tolerance, using: &execution)
            let first = OverlapRegularGraphCell.coordinate(targetPoint, pair.first) - OverlapRegularGraphCell.coordinate(point, pair.first)
            let second = OverlapRegularGraphCell.coordinate(targetPoint, pair.second) - OverlapRegularGraphCell.coordinate(point, pair.second)
            let du = (d * first - b * second) / determinant
            let dv = (a * second - c * first) / determinant
            guard du.isFinite, dv.isFinite else { return nil }
            if hypot(first, second) <= tolerance.distance * tolerance.relative { return uv }
            var scale = 1.0
            var accepted: SurfaceParameter?
            for _ in 0..<policy.options.maximumIterations {
                try policy.work(jetWork, using: &execution)
                let next = SurfaceParameter(u: uv.u - du * scale, v: uv.v - dv * scale)
                if next.u >= ul, next.u <= uh, next.v >= vl, next.v <= vh {
                    let target = try originalSurface.point(u: next.u, v: next.v, tolerance: tolerance, using: &execution)
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
                  policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox? {
        try policy.work(jetWork, using: &execution)
        let source = try curve.thirdOrderIntervalJet(over: range, tolerance: tolerance, using: &execution)
        let point = try targetPointJet(u: seed.u, v: seed.v, using: &execution)
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
            tolerance: tolerance, policy: policy, using: &execution)
        if authority.isSmooth { return candidate }
        return try collarTrialBox(candidate, seed: seed, firstValue: firstValue,
            secondValue: secondValue, pair: pair, policy: policy, using: &execution)
    }

    private func collarTrialBox(_ candidate: SurfaceParameterBox, seed: SurfaceParameter,
                               firstValue: Interval, secondValue: Interval, pair: Pair,
                               policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox? {
        try policy.work(jetWork, using: &execution)
        let target = try targetJet(over: candidate, using: &execution)
        let first = OverlapRegularGraphCell.component(target, pair.first)
        let second = OverlapRegularGraphCell.component(target, pair.second)
        let a = first.derivativeU.midpoint, b = first.derivativeV.midpoint
        let c = second.derivativeU.midpoint, d = second.derivativeV.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0 else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
        let inverse = [[d / determinant, -b / determinant], [-c / determinant, a / determinant]]
        guard inverse.joined().allSatisfy({ $0.isFinite }) else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Interval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Interval].self, using: &execution)
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
               policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Proof? {
        guard let first = try freshProof(range: range, box: box, pair: pair, policy: policy, using: &execution) else { return nil }
        if first.closedDomain != nil {
            let owner = KnownRootAuthority(range: range, pair: pair, initial: first, retainsCollar: !first.authority.isSmooth)
            var last = first
            for _ in 1..<policy.options.maximumIterations {
                guard let value = try rootProof(range: range, box: last.box, pair: pair,
                    existingRoot: owner, policy: policy, using: &execution) else { break }
                let stationary = value.box.u.width >= last.box.u.width && value.box.v.width >= last.box.v.width
                last = value
                if stationary { break }
            }
            return contained(last.box, in: box) ? last : nil
        }
        guard !first.authority.isSmooth,
              first.residual[0].absoluteUpperBound > tolerance.distance,
              first.residual[0].absoluteLowerBound <= tolerance.distance,
              first.sourcePositionWidthLowerBound <= (Interval.exact(tolerance.distance) * .exact(2)).upper else { return first }
        let owner = KnownRootAuthority(range: range, pair: pair, initial: first, retainsCollar: true)
        var last = first
        for _ in 1..<policy.options.maximumIterations {
            guard let value = try rootProof(range: owner.range, box: last.box, pair: owner.pair,
                existingRoot: owner, policy: policy, using: &execution) else { return last }
            let stationary = value.box.u.width >= last.box.u.width && value.box.v.width >= last.box.v.width
            last = value
            if stationary || value.residual[0].absoluteUpperBound <= tolerance.distance
                || value.residual[0].absoluteLowerBound > tolerance.distance { break }
        }
        return last
    }

    private func freshProof(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
                            policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Proof? {
        if let strict = try rootProof(range: range, box: box, pair: pair, existingRoot: nil, policy: policy, using: &execution) { return strict }
        guard case .bSpline(let source) = curve.curve else { return nil }
        let touchesSourceEndpoint = range.lower == source.knots[source.degree] || range.upper == source.knots[source.controlPointCount]
        let domain = try originalBox()
        guard box.u.lower == domain.u.lower || box.u.upper == domain.u.upper
            || box.v.lower == domain.v.lower || box.v.upper == domain.v.upper else { return nil }
        // FIXME(INCOMPLETE_IMPLEMENTATION): General intrinsic endpoint coincidence
        // has no closed-domain existence authority. The public regular graph route
        // may admit these roots only after whole-interval existence, uniqueness,
        // membership and endpoint correspondence are certified on original geometry.
        guard let closed = try closedAuthority(range: range, pair: pair, policy: policy, using: &execution) else {
            if let rectangle = try rectangleAuthority(range: range, box: box, pair: pair, policy: policy, using: &execution) {
                return try rootProof(range: range, box: box, pair: pair, existingRoot: nil,
                    closedDomain: rectangle, policy: policy, using: &execution)
            }
            if !touchesSourceEndpoint { return nil }
            throw failure(.unsupportedCapability, "This original-domain endpoint has no certified closed coordinate inverse.")
        }
        return try rootProof(range: range, box: domain, pair: pair, existingRoot: nil,
            closedDomain: closed, policy: policy, using: &execution)
    }

    func exactEndpoint(at t: Double, pair: Pair, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> SurfaceParameter? {
        guard case .bSpline(let source) = curve.curve,
              t == source.knots[source.degree] || t == source.knots[source.controlPointCount] else { return nil }
        let range = try ScalarInterval(lower: t, upper: t)
        if let endpoint = try closedAuthority(range: range, pair: pair, policy: policy, using: &execution)?.exactEndpoint(at: t) { return endpoint }
        return try rectangleAuthority(range: range, box: originalBox(), pair: pair, policy: policy, using: &execution)?.exactEndpoint(at: t)
    }

    private func rectangleAuthority(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
                                    policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> OverlapRegularGraphClosedDomainAuthority? {
        guard let certificate = try OverlapClosedRectangleRootAuthority.certificate(curve: curve,
            surface: surface, range: range, pair: pair, box: box, jetWork: jetWork, policy: policy, using: &execution) else { return nil }
        return OverlapRegularGraphClosedDomainAuthority(curve: certificate.curve, surface: certificate.surface,
            range: range, pair: pair, box: box, mapping: .rectangle(certificate))
    }

    private func closedAuthority(range: ScalarInterval, pair: Pair,
                                 policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> OverlapRegularGraphClosedDomainAuthority? {
        let domain = try originalBox()
        try policy.work(jetWork, using: &execution)
        let target = try targetJet(over: domain, using: &execution)
        if let coordinateIndependence {
            return try OverlapRegularGraphClosedDomainAuthority.certificate(curve: curve.curve,
                independence: coordinateIndependence, range: range, pair: pair, box: domain, target: target, policy: policy, using: &execution)
        }
        return try OverlapRegularGraphClosedDomainAuthority.certificate(curve: curve.curve, surface: surface.surface,
            range: range, pair: pair, box: domain, target: target, policy: policy, using: &execution)
    }

    private func originalBox() throws -> SurfaceParameterBox {
        guard case let .closed(ul, uh) = originalSurface.uDomain,
              case let .closed(vl, vh) = originalSurface.vDomain else {
            throw failure(.unsupportedCapability, "Closed endpoint authority requires original finite axes.")
        }
        return SurfaceParameterBox(u: try ScalarInterval(lower: ul, upper: uh), v: try ScalarInterval(lower: vl, upper: vh))
    }

    private func contained(_ value: SurfaceParameterBox, in box: SurfaceParameterBox) -> Bool {
        value.u.lower >= box.u.lower && value.u.upper <= box.u.upper
            && value.v.lower >= box.v.lower && value.v.upper <= box.v.upper
    }

    private func rootProof(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
                           existingRoot: KnownRootAuthority?,
                           closedDomain: OverlapRegularGraphClosedDomainAuthority? = nil,
                           policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Proof? {
        try policy.work(jetWork * 3, using: &execution)
        if let closedDomain {
            guard closedDomain.range == range, closedDomain.pair == pair, closedDomain.box == box,
                  curve.curve == .bSpline(closedDomain.curve), surface.surface == closedDomain.surface else {
                throw failure(.intersectionFailure, "Closed-domain localization changed its original existence authority.")
            }
        }
        if let existingRoot {
            guard range == existingRoot.range, pair == existingRoot.pair,
                  box.u.lower >= existingRoot.initial.box.u.lower,
                  box.u.upper <= existingRoot.initial.box.u.upper,
                  box.v.lower >= existingRoot.initial.box.v.lower,
                  box.v.upper <= existingRoot.initial.box.v.upper else {
                throw failure(.intersectionFailure, "Root localization changed its original interval authority.")
            }
        }
        let evaluatedAuthority = try OverlapRegularGraphAtlas.authority(over: box, surface: surface.surface,
            tolerance: tolerance, policy: policy, using: &execution)
        let authority: OverlapRegularGraphAtlas
        if let existingRoot, existingRoot.retainsCollar { authority = existingRoot.initial.authority }
        else { authority = evaluatedAuthority }
        let source = try curve.thirdOrderIntervalJet(over: range, tolerance: tolerance, using: &execution)
        var target = try targetJet(over: box, using: &execution)
        target = try refinedTargetFirstDerivatives(over: box, original: target,
            pair: pair, policy: policy, using: &execution)
        let center = SurfaceParameter(u: box.u.midpoint, v: box.v.midpoint)
        let centerJet = try targetPointJet(u: center.u, v: center.v, using: &execution)
        let f = OverlapRegularGraphCell.component(target, pair.first)
        let g = OverlapRegularGraphCell.component(target, pair.second)
        let determinant = f.derivativeU * g.derivativeV - f.derivativeV * g.derivativeU
        guard (determinant.lower > 0 || determinant.upper < 0), determinant.isFinite else { return nil }
        var rootSource = source
        var initialDerivatives = try graphDerivatives(source: source, target: target,
            pair: pair, determinant: determinant, thirdOrder: authority.isSmooth, using: &execution)
        if case .collar(let uKnots, let vKnots) = authority,
            !transverse(initialDerivatives, uKnots: uKnots, vKnots: vKnots) {
            let refined = try refinedCollarSource(range: range, source: source, target: target,
                pair: pair, determinant: determinant, initial: initialDerivatives,
                uKnots: uKnots, vKnots: vKnots, policy: policy, using: &execution)
            rootSource = refined.source
            initialDerivatives = refined.derivatives
        }
        let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
        let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
        let middleDeterminant = a * d - b * c
        guard middleDeterminant.isFinite, middleDeterminant != 0 else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
        let inverse = [[d / middleDeterminant, -b / middleDeterminant], [-c / middleDeterminant, a / middleDeterminant]]
        guard inverse.joined().allSatisfy({ $0.isFinite }) else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Interval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Interval].self, using: &execution)
        let jacobian = [[f.derivativeU, f.derivativeV], [g.derivativeU, g.derivativeV]]
        try OriginalCoefficientAllocation.reserve(count: 4, of: Interval.self, using: &execution)
        let values = [OverlapRegularGraphCell.component(centerJet, pair.first).value - OverlapRegularGraphCell.component(rootSource, pair.first).value,
            OverlapRegularGraphCell.component(centerJet, pair.second).value - OverlapRegularGraphCell.component(rootSource, pair.second).value]
        let widths = [Interval(lower: box.u.lower, upper: box.u.upper) - .exact(center.u),
            Interval(lower: box.v.lower, upper: box.v.upper) - .exact(center.v)]
        var contracted: [Interval] = []
        var contractedCapacity = 0
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
            if existingRoot == nil && closedDomain == nil {
                guard value.lower > original.lower, value.upper < original.upper else { return nil }
            } else {
                // Strict K or closed-domain IVT owns every existing unique root. Every such
                // root in this box belongs to its K image even without new strict
                // inclusion, so intersection preserves that same root.
                let lower = max(value.lower, original.lower), upper = min(value.upper, original.upper)
                guard lower < upper else {
                    throw failure(.intersectionFailure, "An existing interval root lost its finite positive-width localization.")
                }
                value = Interval(lower: lower, upper: upper)
            }
            try CertifiedAnalyticCurveEvaluation.append(value, to: &contracted, using: &execution, capacity: &contractedCapacity)
        }
        let rootBox = SurfaceParameterBox(u: try ScalarInterval(lower: contracted[0].lower, upper: contracted[0].upper),
            v: try ScalarInterval(lower: contracted[1].lower, upper: contracted[1].upper))
        var derivatives: (u: [Interval], v: [Interval])
        if let existingRoot, existingRoot.retainsCollar {
            // The original collar already bounds every first UV derivative.
            // Range localization changes only the root box and position residual.
            derivatives = (existingRoot.initial.u, existingRoot.initial.v)
        } else {
            derivatives = initialDerivatives
        }
        var retainedClosed = closedDomain ?? existingRoot?.initial.closedDomain
        if case .collar(let uKnots, let vKnots) = authority {
            if !transverse(derivatives, uKnots: uKnots, vKnots: vKnots), retainedClosed == nil {
                // The strict K image already owns these roots. A separate paid
                // original-coefficient identity may now prove that one unique
                // inverse axis remains exactly on an original native knot.
                retainedClosed = try closedAuthority(range: range, pair: pair, policy: policy, using: &execution)
            }
            let stationary = retainedClosed?.stationaryParameters ?? (nil, nil)
            func stationaryDerivative(_ original: [Interval], parameter: Double?,
                                      box: ScalarInterval) throws -> [Interval] {
                guard let parameter else { return original }
                guard box.contains(parameter), let zero = original[0].intersection(with: .exact(0)) else {
                    throw failure(.intersectionFailure, "An exact stationary native axis contradicts its original root or derivative enclosure.")
                }
                return try CertifiedAnalyticCurveEvaluation.values(zero, using: &execution)
            }
            derivatives = (try stationaryDerivative(derivatives.u, parameter: stationary.0, box: rootBox.u),
                try stationaryDerivative(derivatives.v, parameter: stationary.1, box: rootBox.v))
            // Strict K inclusion plus the same uniform contraction on the
            // complete C0/C1 native Jacobian hull gives a unique Lipschitz inverse.
            // Its derivatives exist almost everywhere even at a stationary knot
            // contact. The retained first hull bounds the absolute-continuity
            // residual; transversality is needed only when isolating clipping cuts.
            guard derivatives.u.count == 1, derivatives.v.count == 1,
                  derivatives.u[0].isFinite, derivatives.v[0].isFinite else {
                throw failure(.intersectionFailure, "An original native contact lost its whole Lipschitz inverse derivative hull.")
            }
        }
        try policy.work(jetWork, using: &execution)
        let imageTarget: SurfaceIntervalVectorJet
        let stationary = retainedClosed?.stationaryParameters ?? (nil, nil)
        if stationary.0 != nil || stationary.1 != nil {
            guard stationary.0.map({ rootBox.u.contains($0) }) ?? true,
                  stationary.1.map({ rootBox.v.contains($0) }) ?? true else {
                throw failure(.intersectionFailure, "An original stationary parameter left its retained root image.")
            }
            let image = SurfaceParameterBox(
                u: try stationary.0.map { try ScalarInterval(lower: $0, upper: $0) } ?? rootBox.u,
                v: try stationary.1.map { try ScalarInterval(lower: $0, upper: $0) } ?? rootBox.v)
            let original = try surface.intervalJet(overClosedBox: image, tolerance: tolerance, using: &execution)
            imageTarget = try coordinateIndependence.map { try $0.intersecting(original, tolerance: tolerance) } ?? original
        } else { imageTarget = try targetJet(over: rootBox, using: &execution) }
        // Strict inclusion, or the retained interval-root authority, puts every
        // relevant root in this image. Only the residual value uses imageTarget;
        // derivative bounds retain the evaluated chart and its positive minor.
        let sourcePosition = OverlapRegularGraphCell.component(source, pair.remaining).value
        let residualValue = sourcePosition - OverlapRegularGraphCell.component(imageTarget, pair.remaining).value
        guard residualValue.isFinite else {
            throw failure(.resourceLimitExceeded, "A certified root image exceeds finite residual arithmetic.")
        }
        let residual: [Interval]
        let firstResidualDerivative: Interval?
        if authority.isSmooth {
            var jet = try residualJet(source: source, target: target, axis: pair.remaining, u: derivatives.u, v: derivatives.v, using: &execution)
            jet[0] = residualValue
            residual = jet
            firstResidualDerivative = nil
        } else {
            let c = OverlapRegularGraphCell.component(source, pair.remaining)
            let s = OverlapRegularGraphCell.component(target, pair.remaining)
            let derivative = c.derivativeU - s.derivativeU * derivatives.u[0] - s.derivativeV * derivatives.v[0]
            guard derivative.isFinite else {
                throw failure(.resourceLimitExceeded, "A collar residual derivative exceeds finite arithmetic.")
            }
            residual = try CertifiedAnalyticCurveEvaluation.values(residualValue, using: &execution)
            firstResidualDerivative = derivative
        }
        let sourceWidth = Interval.exact(sourcePosition.upper) - .exact(sourcePosition.lower)
        return Proof(range: range, pair: pair, box: rootBox, authority: authority, u: derivatives.u, v: derivatives.v,
            residual: residual, firstResidualDerivative: firstResidualDerivative,
            sourcePositionWidthLowerBound: sourceWidth.lower,
            closedDomain: retainedClosed)
    }

    /// The original proof and complete coefficient transfer own every retained root.
    struct ComposedTransfer {
        let residual: Interval
        fileprivate let proof: Proof
        fileprivate let coefficient: OverlapAffineComposedResidualAuthority
        fileprivate let distance: Double

        fileprivate init(residual: Interval, proof: Proof,
                         coefficient: OverlapAffineComposedResidualAuthority, distance: Double) {
            self.residual = residual; self.proof = proof
            self.coefficient = coefficient; self.distance = distance
        }
    }

    /// Transfers a complete original coefficient error to the already proved UV root.
    func composedResidual(proof: Proof, coefficient: OverlapAffineComposedResidualAuthority,
                          policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> ComposedTransfer? {
        try policy.work(64, using: &execution)
        guard curve.curve == .bSpline(coefficient.source), surface.surface == coefficient.target,
              proof.pair == coefficient.pair, coefficient.errors.count == 3,
              coefficient.errors.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw failure(.intersectionFailure, "A composed residual changed its original root operands or pair.")
        }
        let candidate = try coefficient.candidateBox(over: proof.range, policy: policy, using: &execution)
        let union = SurfaceParameterBox(
            u: try ScalarInterval(lower: min(candidate.u.lower, proof.box.u.lower), upper: max(candidate.u.upper, proof.box.u.upper)),
            v: try ScalarInterval(lower: min(candidate.v.lower, proof.box.v.lower), upper: max(candidate.v.upper, proof.box.v.upper)))
        guard contained(union, in: try originalBox()) else {
            throw failure(.intersectionFailure, "A composed residual left the original convex native chart.")
        }
        try policy.work(jetWork, using: &execution)
        let target = try targetJet(over: union, using: &execution)
        let f = OverlapRegularGraphCell.component(target, proof.pair.first)
        let g = OverlapRegularGraphCell.component(target, proof.pair.second)
        let minor = f.derivativeU * g.derivativeV - f.derivativeV * g.derivativeU
        guard minor.isFinite, minor.lower > 0 || minor.upper < 0 else { return nil }
        let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint
        let c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0 else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
        let inverse = [[d / determinant, -b / determinant], [-c / determinant, a / determinant]]
        guard inverse.joined().allSatisfy({ $0.isFinite }) else { return nil }
        try OriginalCoefficientAllocation.reserve(count: 4, of: Interval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Interval].self, using: &execution)
        let jacobian = [[f.derivativeU, f.derivativeV], [g.derivativeU, g.derivativeV]]
        var q = 0.0, preconditionedError = 0.0
        for row in 0..<2 {
            var contraction = Interval.exact(0), error = Interval.exact(0)
            for column in 0..<2 {
                var entry = Interval.exact(row == column ? 1 : 0)
                for index in 0..<2 { entry = entry - .exact(inverse[row][index]) * jacobian[index][column] }
                contraction = contraction + .exact(entry.absoluteUpperBound)
                let axis = column == 0 ? proof.pair.first : proof.pair.second
                let eta = coefficient.errors[axis]
                error = error + .exact(inverse[row][column]) * Interval(lower: -eta, upper: eta)
            }
            q = max(q, contraction.upper)
            preconditionedError = max(preconditionedError, error.absoluteUpperBound)
        }
        guard q.isFinite, q < 1 else { return nil }
        guard let distance = Interval.exact(preconditionedError).divided(by: Interval.exact(1) - .exact(q)), distance.isFinite else {
            throw failure(.resourceLimitExceeded, "A composed residual has no finite root-distance transfer.")
        }
        let remaining = OverlapRegularGraphCell.component(target, proof.pair.remaining)
        let lipschitz = Interval.exact(remaining.derivativeU.absoluteUpperBound)
            + .exact(remaining.derivativeV.absoluteUpperBound)
        let upper = Interval.exact(coefficient.errors[proof.pair.remaining]) + lipschitz * distance
        guard upper.isFinite else { throw failure(.resourceLimitExceeded, "A composed residual transfer exceeds finite arithmetic.") }
        let transferred = Interval(lower: -upper.upper, upper: upper.upper)
        guard let intersection = proof.residual[0].intersection(with: transferred) else {
            throw failure(.intersectionFailure, "Original position and composed-root residuals have no common enclosure.")
        }
        return ComposedTransfer(residual: intersection, proof: proof,
            coefficient: coefficient, distance: distance.upper)
    }

    /// Each complete source piece retains its original root in a correlated UV tube.
    func composedFirstDerivatives(_ transfer: ComposedTransfer,
                                  policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> (u: Interval, v: Interval) {
        try policy.work(32, using: &execution)
        let proof = transfer.proof, coefficient = transfer.coefficient
        guard curve.curve == .bSpline(coefficient.source), surface.surface == coefficient.target,
              proof.pair == coefficient.pair, transfer.distance.isFinite, transfer.distance >= 0,
              proof.range.lower >= coefficient.sourceDomain.lower,
              proof.range.upper <= coefficient.sourceDomain.upper else {
            throw failure(.intersectionFailure, "A derivative tube changed its original coefficient/root owner.")
        }
        var best = (u: proof.u[0], v: proof.v[0])
        func transverse(_ value: (u: Interval, v: Interval)) -> Bool {
            (value.u.lower > 0 || value.u.upper < 0) && (value.v.lower > 0 || value.v.upper < 0)
        }
        if transverse(best) { return best }
        var parts = 2, depth = 1
        while parts <= policy.options.maximumIterations {
            try policy.depth(depth, using: &execution)
            try policy.work(parts, using: &execution)
            // Validate every retained closed endpoint before any lower evaluation.
            var previous = proof.range.lower
            var available = true
            for index in 1...parts {
                let endpoint = index == parts ? proof.range.upper
                    : proof.range.lower + proof.range.width * (Double(index) / Double(parts))
                if !endpoint.isFinite || endpoint <= previous || endpoint > proof.range.upper { available = false; break }
                previous = endpoint
            }
            if !available { return best }
            var unionU: Interval?, unionV: Interval?
            var lower = proof.range.lower
            for index in 1...parts {
                try policy.work(64, using: &execution)
                let upper = index == parts ? proof.range.upper
                    : proof.range.lower + proof.range.width * (Double(index) / Double(parts))
                let range = try ScalarInterval(lower: lower, upper: upper)
                let candidate = try coefficient.candidateBox(over: range, policy: policy, using: &execution)
                func axis(_ value: ScalarInterval, root: ScalarInterval) throws -> ScalarInterval {
                    let lower = (Interval.exact(value.lower) - .exact(transfer.distance)).lower
                    let upper = (Interval.exact(value.upper) + .exact(transfer.distance)).upper
                    guard lower.isFinite, upper.isFinite,
                          max(lower, root.lower) <= min(upper, root.upper) else {
                        throw failure(.intersectionFailure, "A correlated derivative tube lost an originally proved root.")
                    }
                    return try ScalarInterval(lower: max(lower, root.lower), upper: min(upper, root.upper))
                }
                let tube = SurfaceParameterBox(u: try axis(candidate.u, root: proof.box.u),
                    v: try axis(candidate.v, root: proof.box.v))
                guard contained(tube, in: proof.box), contained(tube, in: try originalBox()) else {
                    throw failure(.intersectionFailure, "A derivative tube left its original closed native chart.")
                }
                try policy.work(jetWork * 2, using: &execution)
                let source = try curve.thirdOrderIntervalJet(over: range, tolerance: tolerance, using: &execution)
                let original = try surface.intervalJet(overClosedBox: tube, tolerance: tolerance, using: &execution)
                let target: SurfaceIntervalVectorJet
                if let coordinateIndependence { target = try coordinateIndependence.intersecting(original, tolerance: tolerance) }
                else { target = original }
                let f = OverlapRegularGraphCell.component(target, proof.pair.first)
                let g = OverlapRegularGraphCell.component(target, proof.pair.second)
                let determinant = f.derivativeU * g.derivativeV - f.derivativeV * g.derivativeU
                guard determinant.isFinite, determinant.lower > 0 || determinant.upper < 0 else { return best }
                let derivative = try graphDerivatives(source: source, target: target,
                    pair: proof.pair, determinant: determinant, thirdOrder: false, using: &execution)
                unionU = unionU.map { $0.union(derivative.u[0]) } ?? derivative.u[0]
                unionV = unionV.map { $0.union(derivative.v[0]) } ?? derivative.v[0]
                lower = upper
            }
            guard lower == proof.range.upper, let unionU, let unionV,
                  let u = best.u.intersection(with: unionU), let v = best.v.intersection(with: unionV),
                  u.isFinite, v.isFinite else {
                throw failure(.intersectionFailure, "Complete derivative tubes contradict the original graph first bounds.")
            }
            best = (u, v)
            if transverse(best) { return best }
            if parts > policy.options.maximumIterations / 2 { break }
            parts *= 2
            depth += 1
        }
        return best
    }

    /// Absolute continuity carries the complete first-derivative bound across native knots.
    func collarResidual(cell: OverlapRegularGraphCell, proof: Proof,
                        policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Interval {
        try policy.work(using: &execution)
        guard !proof.authority.isSmooth, cell.range == proof.range, cell.pair == proof.pair,
              cell.authority == proof.authority,
              contained(proof.box, in: cell.box), proof.u.count == 1, proof.v.count == 1,
              proof.residual.count == 1, let derivative = proof.firstResidualDerivative else {
            throw failure(.intersectionFailure, "A first-order residual lost its owned whole-cell collar authority.")
        }
        let t = cell.range.midpoint
        let center = try pointProof(at: t, cell: cell, policy: policy, using: &execution)
        // Center existence is reproduced on the original cell/pair; no spatial sample
        // or higher-order continuity is used to extend its residual over the cell.
        let left = Interval.exact(t) - .exact(cell.range.lower)
        let right = Interval.exact(cell.range.upper) - .exact(t)
        let half = Interval.exact(max(left.upper, right.upper))
        let radius = Interval.exact(derivative.absoluteUpperBound) * half
        let enclosure = center.residual[0] + Interval(lower: -radius.upper, upper: radius.upper)
        guard derivative.isFinite, half.isFinite, radius.isFinite, enclosure.isFinite else {
            throw failure(.resourceLimitExceeded, "A first-order collar residual exceeds finite arithmetic.")
        }
        guard let intersection = proof.residual[0].intersection(with: enclosure) else {
            throw failure(.intersectionFailure, "Whole-position and first-order collar residuals have no common enclosure.")
        }
        return intersection
    }

    private func transverse(_ derivatives: (u: [Interval], v: [Interval]),
                            uKnots: OverlapRegularGraphAtlas.AxisKnots?,
                            vKnots: OverlapRegularGraphAtlas.AxisKnots?) -> Bool {
        let uTransverse = derivatives.u[0].lower > 0 || derivatives.u[0].upper < 0
        let vTransverse = derivatives.v[0].lower > 0 || derivatives.v[0].upper < 0
        return (uKnots == nil || uTransverse) && (vKnots == nil || vTransverse)
    }

    private func refinedTargetFirstDerivatives(over box: SurfaceParameterBox,
        original: SurfaceIntervalVectorJet, pair: Pair, policy: OverlapProofPolicy,
        using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        func regular(_ jet: SurfaceIntervalVectorJet) -> Bool {
            let f = OverlapRegularGraphCell.component(jet, pair.first)
            let g = OverlapRegularGraphCell.component(jet, pair.second)
            let determinant = f.derivativeU * g.derivativeV - f.derivativeV * g.derivativeU
            return determinant.isFinite && (determinant.lower > 0 || determinant.upper < 0)
        }
        if regular(original) { return original }
        var best = original, parts = 2, depth = 1
        while parts <= policy.options.maximumIterations / parts {
            try policy.depth(depth, using: &execution)
            func cuts(_ axis: ScalarInterval) throws -> [Double]? {
                var result: [Double] = []
                var capacity = 0
                try CertifiedAnalyticCurveEvaluation.append(axis.lower, to: &result,
                    using: &execution, capacity: &capacity)
                for index in 1...parts {
                    let cut = index == parts ? axis.upper
                        : axis.lower + axis.width * (Double(index) / Double(parts))
                    guard cut.isFinite, cut > result[result.count - 1], cut <= axis.upper else { return nil }
                    try CertifiedAnalyticCurveEvaluation.append(cut, to: &result,
                        using: &execution, capacity: &capacity)
                }
                return result
            }
            guard let u = try cuts(box.u), let v = try cuts(box.v) else { break }
            var cover: SurfaceIntervalVectorJet?
            for row in 0..<parts {
                for column in 0..<parts {
                    try policy.work(jetWork, using: &execution)
                    let piece = SurfaceParameterBox(
                        u: try ScalarInterval(lower: u[column], upper: u[column + 1]),
                        v: try ScalarInterval(lower: v[row], upper: v[row + 1]))
                    let jet = try targetJet(over: piece, using: &execution)
                    cover = cover.map { $0.union(jet) } ?? jet
                }
            }
            guard let cover else { throw failure(.intersectionFailure, "Target derivative refinement lost its complete rectangle cover.") }
            func intersect(_ old: SurfaceIntervalJet, _ covered: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
                guard let du = old.derivativeU.intersection(with: covered.derivativeU),
                    let dv = old.derivativeV.intersection(with: covered.derivativeV), du.isFinite, dv.isFinite else {
                    throw failure(.intersectionFailure, "Complete target derivatives contradict their original enclosure.")
                }
                return SurfaceIntervalJet(value: old.value, derivativeU: du, derivativeV: dv,
                    secondDerivativeUU: old.secondDerivativeUU, secondDerivativeUV: old.secondDerivativeUV,
                    secondDerivativeVV: old.secondDerivativeVV, thirdDerivativeUUU: old.thirdDerivativeUUU,
                    thirdDerivativeUUV: old.thirdDerivativeUUV, thirdDerivativeUVV: old.thirdDerivativeUVV,
                    thirdDerivativeVVV: old.thirdDerivativeVVV)
            }
            best = try SurfaceIntervalVectorJet(x: intersect(best.x, cover.x),
                y: intersect(best.y, cover.y), z: intersect(best.z, cover.z))
            if regular(best) { return best }
            if parts > policy.options.maximumIterations / 2 { break }
            parts *= 2; depth += 1
        }
        return best
    }

    private func refinedCollarSource(range: ScalarInterval, source: SurfaceIntervalVectorJet,
                                         target: SurfaceIntervalVectorJet, pair: Pair, determinant: Interval,
                                         initial: (u: [Interval], v: [Interval]),
                                         uKnots: OverlapRegularGraphAtlas.AxisKnots?,
                                         vKnots: OverlapRegularGraphAtlas.AxisKnots?,
                                         policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws
        -> (source: SurfaceIntervalVectorJet, derivatives: (u: [Interval], v: [Interval])) {
        var best = initial, boundedSource = source
        var parts = 2, depth = 1
        while parts <= policy.options.maximumIterations {
            try policy.depth(depth, using: &execution)
            try policy.work(parts, using: &execution)
            // Verify the complete cover before consuming any partial union.
            var previous = range.lower
            var available = true
            for index in 1...parts {
                let cut = index == parts ? range.upper : range.lower + range.width * (Double(index) / Double(parts))
                if !cut.isFinite || cut <= previous || cut > range.upper { available = false; break }
                previous = cut
            }
            if !available { break }
            var cover: SurfaceIntervalVectorJet?
            var lower = range.lower
            for index in 1...parts {
                let upper = index == parts ? range.upper : range.lower + range.width * (Double(index) / Double(parts))
                try policy.work(jetWork, using: &execution)
                let piece = try curve.thirdOrderIntervalJet(over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance, using: &execution)
                cover = cover.map { $0.union(piece) } ?? piece
                lower = upper
            }
            guard let cover else { throw failure(.intersectionFailure, "A source derivative refinement lost its complete interval cover.") }
            boundedSource = try sourceReplacingCoveredValuesAndFirstDerivatives(boundedSource, with: cover)
            best = try graphDerivatives(source: boundedSource, target: target, pair: pair,
                determinant: determinant, thirdOrder: false, using: &execution)
            if transverse(best, uKnots: uKnots, vKnots: vKnots) { return (boundedSource, best) }
            if parts > policy.options.maximumIterations / 2 { break }
            parts *= 2
            depth += 1
        }
        return (boundedSource, best)
    }

    private func sourceReplacingCoveredValuesAndFirstDerivatives(_ source: SurfaceIntervalVectorJet,
                                                with cover: SurfaceIntervalVectorJet) throws -> SurfaceIntervalVectorJet {
        func replaced(_ original: SurfaceIntervalJet, _ refined: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
            let lower = max(original.derivativeU.lower, refined.derivativeU.lower)
            let upper = min(original.derivativeU.upper, refined.derivativeU.upper)
            guard lower.isFinite, upper.isFinite, lower <= upper else {
                throw failure(.intersectionFailure, "Complete original-source derivative bounds have no finite common enclosure.")
            }
            guard let position = original.value.intersection(with: refined.value), position.isFinite else {
                throw failure(.intersectionFailure, "Complete original-source position bounds have no finite common enclosure.")
            }
            return SurfaceIntervalJet(value: position,
                derivativeU: Interval(lower: lower, upper: upper), derivativeV: original.derivativeV,
                secondDerivativeUU: original.secondDerivativeUU, secondDerivativeUV: original.secondDerivativeUV,
                secondDerivativeVV: original.secondDerivativeVV, thirdDerivativeUUU: original.thirdDerivativeUUU,
                thirdDerivativeUUV: original.thirdDerivativeUUV, thirdDerivativeUVV: original.thirdDerivativeUVV,
                thirdDerivativeVVV: original.thirdDerivativeVVV)
        }
        return try SurfaceIntervalVectorJet(x: replaced(source.x, cover.x),
            y: replaced(source.y, cover.y), z: replaced(source.z, cover.z))
    }

    func pointProof(at t: Double, cell: OverlapRegularGraphCell,
                    policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Proof {
        let lower = max(cell.range.lower, t.nextDown), upper = min(cell.range.upper, t.nextUp)
        let range = try ScalarInterval(lower: lower, upper: upper)
        guard range.width > 0 else { throw failure(.resourceLimitExceeded, "A graph root has no representable source enclosure.") }
        guard let first = try freshProof(range: range, box: cell.box, pair: cell.pair,
            policy: policy, using: &execution) else {
            throw failure(.intersectionFailure, "An owned graph could not reproduce its point root certificate.")
        }
        let owner = KnownRootAuthority(range: range, pair: cell.pair, initial: first, retainsCollar: false)
        var last = first
        for _ in 1..<policy.options.maximumIterations {
            guard let value = try rootProof(range: owner.range, box: last.box, pair: owner.pair,
                existingRoot: owner, policy: policy, using: &execution) else { break }
            let stationary = value.box.u.width >= last.box.u.width && value.box.v.width >= last.box.v.width
            last = value
            if stationary { break }
        }
        guard contained(last.box, in: cell.box) else {
            throw failure(.intersectionFailure, "Point localization did not retain its original owned cell root box.")
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
                                  pair: Pair, determinant: Interval, thirdOrder: Bool, using execution: inout OriginalQueryExecution) throws -> (u: [Interval], v: [Interval]) {
        try OriginalCoefficientAllocation.reserve(count: thirdOrder ? 6 : 2, of: Interval.self, using: &execution)
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
                             axis: Int, u: [Interval], v: [Interval], using execution: inout OriginalQueryExecution) throws -> [Interval] {
        try OriginalCoefficientAllocation.reserve(count: 4, of: Interval.self, using: &execution)
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
