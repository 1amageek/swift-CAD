import CADCore
@testable import CADGeometry
import Testing

@Suite("Original periodic surface homogeneous jets")
struct OriginalPeriodicSurfaceJetTests {
    private let tolerance = ModelingTolerance.standard
    private let cardinal = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]

    private func fixture(axes: String, rational: Bool) throws -> BSplineSurface3D {
        let uPeriodic = axes != "v", vPeriodic = axes != "u"
        let uWeights = rational ? [1.0, 2, 3, 4] : [1.0, 1, 1, 1]
        let vWeights = rational ? [4.0, 3, 2, 1] : [1.0, 1, 1, 1]
        var points: [[Point3D]] = [], weights: [[Double]] = []
        for j in 0..<(vPeriodic ? 4 : 2) {
            var row: [Point3D] = [], weightRow: [Double] = []
            for i in 0..<(uPeriodic ? 4 : 2) {
                if axes == "uv" {
                    let radius = 2 + 0.5 * cardinal[j].0
                    row.append(Point3D(x: radius * cardinal[i].0, y: radius * cardinal[i].1,
                                       z: 0.5 * cardinal[j].1))
                    weightRow.append(uWeights[i] * vWeights[j])
                } else {
                    let index = uPeriodic ? i : j
                    row.append(Point3D(x: cardinal[index].0, y: cardinal[index].1,
                                       z: Double(uPeriodic ? j : i)))
                    weightRow.append(uPeriodic ? uWeights[index] : vWeights[index])
                }
            }
            points.append(row)
            weights.append(weightRow)
        }
        return try .periodic(uDegree: uPeriodic ? 2 : 1, vDegree: vPeriodic ? 2 : 1,
            uKnots: uPeriodic ? [0, 1, 2, 3, 4] : [0, 0, 1, 1],
            vKnots: vPeriodic ? [0, 1, 2, 3, 4] : [0, 0, 1, 1],
            controlPoints: points, weights: weights, isUPeriodic: uPeriodic,
            isVPeriodic: vPeriodic, tolerance: tolerance)
    }

    /// Literal uniform quadratic cardinal pieces and their weighted quotient.
    /// No production basis, extraction, scalar evaluator or jet algebra supplies the oracle.
    private func curve(_ parameter: Double, weights: [Double], incoming: Bool) -> [[Double]] {
        var span = Int(parameter.rounded(.down))
        if incoming && parameter == Double(span) { span -= 1 }
        let t = parameter - Double(span)
        if weights.allSatisfy({ $0 == 1 }) {
            // Partition of unity makes the literal denominator exactly one. Each
            // rotated quadratic piece has an exactly zero third derivative.
            let x = [0.5 - t, -1.0, 0, 0]
            let y = [0.5 + t - t * t, 1 - 2 * t, -2, 0]
            switch (span % 4 + 4) % 4 {
            case 0: return [x, y]
            case 1: return [y.map { -$0 }, x]
            case 2: return [x.map { -$0 }, y.map { -$0 }]
            default: return [y, x.map { -$0 }]
            }
        }
        let indices = (0..<3).map { ((span + $0) % 4 + 4) % 4 }
        let basis = [0.5 * (1 - t) * (1 - t), 0.5 + t - t * t, 0.5 * t * t]
        let first = [t - 1, 1 - 2 * t, t]
        let second = [1.0, -2, 1]
        let w = indices.enumerated().reduce(0.0) { $0 + basis[$1.offset] * weights[$1.element] }
        let dw = indices.enumerated().reduce(0.0) { $0 + first[$1.offset] * weights[$1.element] }
        let ddw = indices.enumerated().reduce(0.0) { $0 + second[$1.offset] * weights[$1.element] }
        return (0..<2).map { coordinate in
            let controls = indices.map { coordinate == 0 ? cardinal[$0].0 : cardinal[$0].1 }
            let numerator = (0..<3).reduce(0.0) { $0 + basis[$1] * weights[indices[$1]] * controls[$1] }
            let derivative = (0..<3).reduce(0.0) { $0 + first[$1] * weights[indices[$1]] * controls[$1] }
            let secondDerivative = (0..<3).reduce(0.0) { $0 + second[$1] * weights[indices[$1]] * controls[$1] }
            let value = numerator / w
            let d = (derivative - dw * value) / w
            let dd = (secondDerivative - 2 * dw * d - ddw * value) / w
            let ddd = (-3 * dw * dd - 3 * ddw * d) / w
            return [value, d, dd, ddd]
        }
    }

    private func fields(_ jet: SurfaceIntervalJet) -> [OutwardScalarInterval] {
        [jet.value, jet.derivativeU, jet.derivativeV, jet.secondDerivativeUU,
         jet.secondDerivativeUV, jet.secondDerivativeVV, jet.thirdDerivativeUUU,
         jet.thirdDerivativeUUV, jet.thirdDerivativeUVV, jet.thirdDerivativeVVV]
    }

    private func literal(axes: String, rational: Bool, u: Double, v: Double,
                         incomingU: Bool, incomingV: Bool) -> [[Double]] {
        let a = curve(u, weights: rational ? [1, 2, 3, 4] : [1, 1, 1, 1], incoming: incomingU)
        let b = curve(v, weights: rational ? [4, 3, 2, 1] : [1, 1, 1, 1], incoming: incomingV)
        if axes == "uv" {
            let r = [2 + 0.5 * b[0][0], 0.5 * b[0][1], 0.5 * b[0][2], 0.5 * b[0][3]]
            func product(_ x: [Double]) -> [Double] {
                [x[0] * r[0], x[1] * r[0], x[0] * r[1], x[2] * r[0], x[1] * r[1],
                 x[0] * r[2], x[3] * r[0], x[2] * r[1], x[1] * r[2], x[0] * r[3]]
            }
            return [product(a[0]), product(a[1]),
                    [0.5 * b[1][0], 0, 0.5 * b[1][1], 0, 0, 0.5 * b[1][2], 0, 0, 0, 0.5 * b[1][3]]]
        }
        if axes == "u" {
            return [a[0], a[1]].map { [$0[0], $0[1], 0, $0[2], 0, 0, $0[3], 0, 0, 0] }
                + [[v, 0, 1, 0, 0, 0, 0, 0, 0, 0]]
        }
        return [b[0], b[1]].map { [$0[0], 0, $0[1], 0, 0, $0[2], 0, 0, 0, $0[3]] }
            + [[u, 1, 0, 0, 0, 0, 0, 0, 0, 0]]
    }

    private func verify(_ jet: SurfaceIntervalVectorJet, axes: String, rational: Bool,
                        u: Double, v: Double) {
        let uSides = axes != "v" && u == u.rounded(.down) ? [false, true] : [false]
        let vSides = axes != "u" && v == v.rounded(.down) ? [false, true] : [false]
        // A closed native knot owns both incident jets, including opposite seam endpoints.
        for incomingU in uSides {
            for incomingV in vSides {
                let expected = literal(axes: axes, rational: rational, u: u, v: v,
                                       incomingU: incomingU, incomingV: incomingV)
                for (coordinate, values) in zip([jet.x, jet.y, jet.z], expected) {
                    for (field, value) in zip(fields(coordinate), values) {
                        #expect(field.lower.isFinite && field.upper.isFinite)
                        #expect(field.contains(value))
                    }
                }
            }
        }
    }

    private func box(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1),
                            v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func verifyQueries(axes: String, rational: Bool) throws {
        let source = try fixture(axes: axes, rational: rational)
        let original = source
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let cyclicRanges = [(0.3103448275862068, 0.3103448275862069), (3.8, 4.2),
                            (-4.2, -3.8), (0.0, 4.0)]
        for range in cyclicRanges {
            let parameters = try box(axes == "v" ? (0.3, 0.7) : range,
                                     axes == "u" ? (0.3, 0.7) : range)
            let jet = try prepared.intervalJet(over: parameters, tolerance: tolerance)
            for u in [parameters.u.lower, parameters.u.midpoint, parameters.u.upper] {
                for v in [parameters.v.lower, parameters.v.midpoint, parameters.v.upper] {
                    verify(jet, axes: axes, rational: rational, u: u, v: v)
                }
            }
        }
        for parameter in [0.0, 0.375, 1, 1.375, 2, 2.375, 3, 3.375, 4] {
            let u = axes == "v" ? 0.375 : parameter
            let v = axes == "u" ? 0.375 : parameter
            verify(try prepared.pointJet(u: u, v: v, tolerance: tolerance),
                   axes: axes, rational: rational, u: u, v: v)
        }
        let local = try prepared.pointJet(u: 0.375, v: 0.375, tolerance: tolerance)
        let whole = try prepared.intervalJet(over: box(axes == "v" ? (0, 1) : (0, 4),
                                                       axes == "u" ? (0, 1) : (0, 4)), tolerance: tolerance)
        #expect(local.x.value.upper - local.x.value.lower < whole.x.value.upper - whole.x.value.lower)
        // Changed representative origins must not change the prepared original coefficient net.
        var shifted = source
        if axes != "v" { shifted = try shifted.changingPeriodicOrigin(direction: .u, to: 2.25, tolerance: tolerance) }
        if axes != "u" { shifted = try shifted.changingPeriodicOrigin(direction: .v, to: -1.25, tolerance: tolerance) }
        let shiftedPrepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: shifted, tolerance: tolerance)
        verify(try shiftedPrepared.pointJet(u: 0.375, v: 0.375, tolerance: tolerance),
               axes: axes, rational: rational, u: 0.375, v: 0.375)
        #expect(prepared.surface == original && source == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "uv"])
    func cardinalOriginalCyclesContainFirstThroughThirdJets(axes: String) throws {
        try verifyQueries(axes: axes, rational: false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "uv"])
    func rationalOriginalCyclesContainIndependentQuotientJets(axes: String) throws {
        try verifyQueries(axes: axes, rational: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPeriodicGrevilleExtrusionKeepsExactIndependentDerivatives() throws {
        let greville = [0.0, 0.125, 0.3125, 0.6875, 1.0]
        let source = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 2,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 0, 0, 0.25, 0.375, 1, 1, 1],
            controlPoints: greville.map { z in cardinal.map { Point3D(x: $0.0, y: $0.1, z: z) } },
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let interval = try box((0.3103448275862068, 0.3103448275862069),
                               (0.3103448275862068, 0.3103448275862069))
        let jet = try prepared.intervalJet(over: interval, tolerance: tolerance)
        verify(jet, axes: "u", rational: false, u: interval.u.midpoint, v: interval.v.midpoint)
        for v in [interval.v.midpoint, 0.25, 0.375] {
            verify(try prepared.pointJet(u: 0.375, v: v, tolerance: tolerance),
                   axes: "u", rational: false, u: 0.375, v: v)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicPreparationPreservesExistingToleranceDomainAndTokenFailures() throws {
        let source = try fixture(axes: "u", rational: false)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        var invalidTolerance = tolerance
        invalidTolerance.distance = -1
        #expect(throws: GeometryError.self) {
            _ = try prepared.pointJet(u: 0.375, v: 0.5, tolerance: invalidTolerance)
        }
        var differentTolerance = tolerance
        differentTolerance.distance *= 2
        verify(try prepared.pointJet(u: 0.375, v: 0.5, tolerance: differentTolerance),
               axes: "u", rational: false, u: 0.375, v: 0.5)
        for (u, v) in [(0.375, -0.1), (0.375, 1.1), (Double.infinity, 0.5)] {
            do {
                _ = try prepared.pointJet(u: u, v: v, tolerance: tolerance)
                Issue.record("A periodic prepared query accepted invalid original support.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        do {
            _ = try prepared.originalNativeSpans(over: box((0.375, 0.375), (0.5, 0.5)), tolerance: tolerance)
            Issue.record("A cyclic surface minted one-sided nonperiodic authority.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        var invalid = source
        invalid.uKnots.removeLast()
        #expect(throws: GeometryError.self) {
            _ = try PreparedBSplineSurfaceDifferentialEncloser(surface: invalid, tolerance: tolerance)
        }
        invalid = source
        invalid.controlPoints[0][0].x = .infinity
        #expect(throws: GeometryError.self) {
            _ = try PreparedBSplineSurfaceDifferentialEncloser(surface: invalid, tolerance: tolerance)
        }
        #expect(prepared.surface == source)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPeriodicPreparationAndQueriesRespectCancellation() async throws {
        let source = try fixture(axes: "uv", rational: true)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        for operation in 0...2 {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let task = Task {
                for await _ in stream { break }
                switch operation {
                case 0:
                    _ = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
                case 1:
                    _ = try prepared.pointJet(u: 4, v: 4, tolerance: tolerance)
                default:
                    _ = try prepared.intervalJet(over: box((3.8, 4.2), (3.8, 4.2)), tolerance: tolerance)
                }
            }
            task.cancel()
            continuation.yield(())
            continuation.finish()
            do {
                try await task.value
                Issue.record("Cancelled original periodic preparation or query succeeded.")
            } catch is CancellationError {}
        }
    }
}
