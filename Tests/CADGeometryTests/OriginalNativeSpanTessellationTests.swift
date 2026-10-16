import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Original native-span tessellation authority")
struct OriginalNativeSpanTessellationTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func selectedOriginalKnotSidesRetainLiteralJetsAndNormals(transposed: Bool, quadratic: Bool) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = literalSurface(transposed: transposed, quadratic: quadratic)
        let original = surface
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let spans = try prepared.originalNativeSpans(over: unitBox(), tolerance: .standard, using: &execution)
        #expect(spans.count == 2)
        let u = transposed ? 0.25 : 0.5, v = transposed ? 0.5 : 0.25
        let slopeMagnitude = quadratic ? 1.0 : 0.5
        for span in spans {
            let left = (transposed ? span.vBounds.lower : span.uBounds.lower) == 0
            let slope = left ? slopeMagnitude : -slopeMagnitude
            let jet = try span.pointJet(u: u, v: v, on: surface, tolerance: .standard, using: &execution)
            #expect(contains(jet.x.value, u) && contains(jet.y.value, v) && contains(jet.z.value, 0.25))
            #expect(contains(transposed ? jet.z.derivativeV : jet.z.derivativeU, slope))
            #expect(contains(transposed ? jet.z.derivativeU : jet.z.derivativeV, 0))
            #expect(contains(transposed ? jet.z.secondDerivativeVV : jet.z.secondDerivativeUU, quadratic ? 2 : 0))
            let expected = try Vector3D(x: transposed ? 0 : -slope,
                y: transposed ? -slope : 0, z: 1).normalized(tolerance: 1e-300)
            let normal = try surface.normal(u: u, v: v, owning: span, tolerance: .standard, using: &execution)
            #expect((normal - expected).length <= 1e-12)
            let closed = try SurfaceParameterBox(u: span.uBounds, v: span.vBounds)
            let whole = try span.intervalJet(overClosedBox: closed, on: surface, tolerance: .standard, using: &execution)
            let derivative = transposed ? whole.z.derivativeV : whole.z.derivativeU
            #expect(contains(derivative, slope))
            #expect(contains(derivative, quadratic ? 0 : slope))
        }
        let ordinary = try surface.normal(u: u, v: v, tolerance: .standard)
        let right = try Vector3D(x: transposed ? 0 : slopeMagnitude,
            y: transposed ? slopeMagnitude : 0, z: 1).normalized(tolerance: 1e-300)
        #expect((ordinary - right).length <= 1e-12)
        let allOwning = try prepared.pointJet(u: u, v: v, tolerance: .standard, using: &execution)
        let union = transposed ? allOwning.z.derivativeV : allOwning.z.derivativeU
        #expect(contains(union, -slopeMagnitude) && contains(union, slopeMagnitude))
        #expect(surface == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectedOriginalTensorCornerKeepsFourClosedOwners() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let coordinates = [0.0, 0.5, 1.0]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 0.5, 1, 1],
            controlPoints: coordinates.map { y in coordinates.map { x in
                Point3D(x: x, y: y, z: 0.5 * min(x, 1 - x) + 0.5 * min(y, 1 - y))
            } })
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let knot = try SurfaceParameterBox(u: ScalarInterval(lower: 0.5, upper: 0.5),
                                          v: ScalarInterval(lower: 0.5, upper: 0.5))
        let spans = try prepared.originalNativeSpans(over: knot, tolerance: .standard, using: &execution)
        #expect(spans.count == 4)
        for span in spans {
            let du = span.uBounds.lower == 0 ? 0.5 : -0.5
            let dv = span.vBounds.lower == 0 ? 0.5 : -0.5
            let jet = try span.pointJet(u: 0.5, v: 0.5, on: surface, tolerance: .standard, using: &execution)
            #expect(contains(jet.z.value, 0.5))
            #expect(contains(jet.z.derivativeU, du) && contains(jet.z.derivativeV, dv))
            let expected = try Vector3D(x: -du, y: -dv, z: 1).normalized(tolerance: 1e-300)
            #expect((try surface.normal(u: 0.5, v: 0.5, owning: span, tolerance: .standard, using: &execution) - expected).length <= 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectedOriginalRationalControlsKeepBothNativeLimits() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        var surface = literalSurface()
        surface.weights = [[1, 2, 1], [1, 2, 1]]
        let spans = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
            .originalNativeSpans(over: unitBox(), tolerance: .standard, using: &execution)
        for span in spans {
            let slope = span.uBounds.lower == 0 ? 0.25 : -0.25
            let jet = try span.pointJet(u: 0.5, v: 0.25, on: surface, tolerance: .standard, using: &execution)
            #expect(contains(jet.x.value, 0.5) && contains(jet.y.value, 0.25) && contains(jet.z.value, 0.25))
            #expect(contains(jet.x.derivativeU, 0.5) && contains(jet.z.derivativeU, slope))
            #expect(contains(jet.x.derivativeV, 0) && contains(jet.y.derivativeV, 1))
            let expected = try Vector3D(x: -2 * slope, y: 0, z: 1).normalized(tolerance: 1e-300)
            #expect((try surface.normal(u: 0.5, v: 0.25, owning: span, tolerance: .standard, using: &execution) - expected).length <= 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["source", "tolerance", "domain"])
    func originalSpanRefusesOtherSupportToleranceOrSide(failure: String) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = literalSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let span = try geometryTestRequire(try prepared.originalNativeSpans(over: unitBox(), tolerance: .standard, using: &execution)
            .first { $0.uBounds.lower == 0 })
        var requested = surface
        var tolerance = ModelingTolerance.standard
        if failure == "source" { requested.controlPoints[0][0].z = 1 }
        if failure == "tolerance" { tolerance.distance *= 0.5 }
        let u = failure == "domain" ? 0.75 : 0.25
        expectCode(.invalidInput) {
            _ = try span.pointJet(u: u, v: 0.25, on: requested, tolerance: tolerance, using: &execution)
        }
        expectCode(.invalidInput) {
            _ = try requested.normal(u: u, v: 0.25, owning: span, tolerance: tolerance, using: &execution)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPanelsConsumeOneAggregateProofCeiling() throws {
        let surface = literalSurface()
        let encloser = DefaultSurfaceDifferentialEncloser()
        expectCode(.resourceLimitExceeded) {
            _ = try encloser.originalNativeSpanTessellationBounds(of: surface, over: unitBox(),
                tolerance: .standard, maximumCellCount: 1)
        }
        let panels = try encloser.originalNativeSpanTessellationBounds(of: surface, over: unitBox(),
            tolerance: .standard, maximumCellCount: 2)
        #expect(panels.count == 2)
        for panel in panels {
            #expect(panel.bounds.tangentUMagnitudeUpperBound >= sqrt(1.25))
            #expect(panel.bounds.tangentVMagnitudeUpperBound >= 1)
        }
        for maximum in [0, 262_145] {
            expectCode(.invalidInput) {
                _ = try encloser.originalNativeSpanTessellationBounds(of: surface, over: unitBox(),
                    tolerance: .standard, maximumCellCount: maximum)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledOriginalSpanProofDoesNotPublishPanels() async throws {
        let surface = literalSurface()
        let original = surface
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: surface, over: unitBox(), tolerance: .standard)
        }
        task.cancel()
        opened.yield()
        opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(surface == original)
    }

    private func literalSurface(transposed: Bool = false, quadratic: Bool = false) -> BSplineSurface3D {
        let xs: [Double] = quadratic ? [0, 0.25, 0.5, 0.75, 1] : [0, 0.5, 1]
        let zs: [Double] = quadratic ? [0, 0, 0.25, 0, 0] : [0, 0.25, 0]
        let knots: [Double] = quadratic ? [0, 0, 0, 0.5, 0.5, 1, 1, 1] : [0, 0, 0.5, 1, 1]
        let rows = [0.0, 1.0].map { y in xs.indices.map { Point3D(x: xs[$0], y: y, z: zs[$0]) } }
        if !transposed {
            return BSplineSurface3D(uDegree: quadratic ? 2 : 1, vDegree: 1,
                uKnots: knots, vKnots: [0, 0, 1, 1], controlPoints: rows)
        }
        return BSplineSurface3D(uDegree: 1, vDegree: quadratic ? 2 : 1,
            uKnots: [0, 0, 1, 1], vKnots: knots,
            controlPoints: xs.indices.map { index in rows.map { Point3D(x: $0[index].y, y: $0[index].x, z: $0[index].z) } })
    }

    private func unitBox() throws -> SurfaceParameterBox {
        try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
    }

    private func contains(_ interval: OutwardScalarInterval, _ value: Double) -> Bool {
        interval.lower <= value && interval.upper >= value
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        #expect(throws: KernelError.self) {
            do { try operation() }
            catch let error as KernelError {
                #expect(error.code == code)
                throw error
            }
        }
    }
}
