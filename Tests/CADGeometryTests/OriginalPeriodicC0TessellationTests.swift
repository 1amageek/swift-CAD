import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Original periodic C0 selected span authority")
struct OriginalPeriodicC0TessellationTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "both"], ["base", "negative", "crossing", "shifted", "full"])
    func originalDiamondTensorRetainsEveryLiftAndClosedSide(axes: String, chart: String) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        var surface = try fixture(axes: axes)
        if chart == "shifted" {
            if surface.isUPeriodic { surface.uPeriodicOrigin = 8 }
            if surface.isVPeriodic { surface.vPeriodicOrigin = 8 }
        }
        let original = surface
        let interval: (Double, Double)
        switch chart {
        case "negative": interval = (-0.5, 0.5)
        case "crossing": interval = (3.5, 4.5)
        case "shifted": interval = (7.5, 8.5)
        case "full": interval = (0, 4)
        default: interval = (0.25, 1.75)
        }
        let query = try box(surface.isUPeriodic ? interval : (0, 1),
                            surface.isVPeriodic ? interval : (0, 1))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let spans = try prepared.originalNativeSpans(over: query, tolerance: .standard, using: &execution)
        let positive = spans.filter {
            min(query.u.upper, $0.uBounds.upper) > max(query.u.lower, $0.uBounds.lower)
                && min(query.v.upper, $0.vBounds.upper) > max(query.v.lower, $0.vBounds.lower)
        }
        let intervalCount = chart == "full" ? 4 : 2
        #expect(positive.count == (axes == "both" ? intervalCount * intervalCount : intervalCount))
        var area = 0.0
        for span in spans {
            let u0 = max(query.u.lower, span.uBounds.lower), u1 = min(query.u.upper, span.uBounds.upper)
            let v0 = max(query.v.lower, span.vBounds.lower), v1 = min(query.v.upper, span.vBounds.upper)
            area += (u1 - u0) * (v1 - v0)
            let closed = try box((u0, u1), (v0, v1))
            let enclosure = try span.intervalJet(overClosedBox: closed, on: surface, tolerance: .standard, using: &execution)
            for u in [u0, (u0 + u1) / 2, u1] {
                for v in [v0, (v0 + v1) / 2, v1] {
                    let expected = literal(u: u, v: v, span: span, axes: axes)
                    let jet = try span.pointJet(u: u, v: v, on: surface, tolerance: .standard, using: &execution)
                    check(jet, contains: expected)
                    check(enclosure, contains: expected)
                    let n = try expected.du.cross(expected.dv).normalized(tolerance: 1e-300)
                    #expect((try surface.normal(u: u, v: v, owning: span, tolerance: .standard, using: &execution) - n).length <= 1e-12)
                    #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected.point).length <= 1e-12)
                    let value = try span.pointValue(u: u, v: v, on: surface, tolerance: .standard, using: &execution)
                    #expect(contains(value.x, expected.point.x) && contains(value.y, expected.point.y) && contains(value.z, expected.point.z))
                }
            }
        }
        #expect(abs(area - query.u.width * query.v.width) <= 1e-12)
        // The closed seam retains two sides per periodic direction, including a
        // full-cycle upper/left span whose base station is exactly 4 rather than 0.
        if chart != "base" {
            let seam = chart == "negative" || chart == "full" ? 0.0 : (chart == "shifted" ? 8.0 : 4.0)
            let corner = try box(surface.isUPeriodic ? (seam, seam) : (0.5, 0.5),
                                 surface.isVPeriodic ? (seam, seam) : (0.5, 0.5))
            let owners = try prepared.originalNativeSpans(over: corner, tolerance: .standard, using: &execution)
            #expect(owners.count == (axes == "both" ? 4 : 2))
            let normals = try owners.map {
                try surface.normal(u: corner.u.lower, v: corner.v.lower, owning: $0, tolerance: .standard, using: &execution)
            }
            for i in normals.indices { for j in normals.indices where j > i {
                #expect((normals[i] - normals[j]).length > 0.1)
            } }
        }
        #expect(surface == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "both"])
    func ordinaryNormalStillChoosesCanonicalRightSeam(axes: String) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = try fixture(axes: axes)
        let u = surface.isUPeriodic ? 4.0 : 0.5, v = surface.isVPeriodic ? 4.0 : 0.5
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let owners = try prepared.originalNativeSpans(over: box((u, u), (v, v)), tolerance: .standard, using: &execution)
        let right = try #require(owners.first {
            (!surface.isUPeriodic || $0.uBounds.lower == u) && (!surface.isVPeriodic || $0.vBounds.lower == v)
        })
        #expect((try surface.normal(u: u, v: v, tolerance: .standard)
            - surface.normal(u: u, v: v, owning: right, tolerance: .standard, using: &execution)).length <= 1e-12)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["source", "tolerance", "outside", "cycle"])
    func tokensRefuseForeignAuthorityWithoutSelectingNearbySide(failure: String) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = try fixture(axes: "both")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let token = try geometryTestRequire(try prepared.originalNativeSpans(over: box((3.5, 4.5), (-0.5, 0.5)), tolerance: .standard, using: &execution)
            .first { $0.uBounds.lower == 3 && $0.vBounds.lower == -1 })
        var requested = surface, tolerance = ModelingTolerance.standard
        if failure == "source" { requested.controlPoints[0][0].z = 0.125 }
        if failure == "tolerance" { tolerance.distance *= 0.5 }
        let u = failure == "outside" ? 4.25 : (failure == "cycle" ? -0.25 : 3.75)
        expectCode(.invalidInput) {
            _ = try token.pointJet(u: u, v: -0.25, on: requested, tolerance: tolerance, using: &execution)
        }
        expectCode(.invalidInput) {
            _ = try requested.normal(u: u, v: -0.25, owning: token, tolerance: tolerance, using: &execution)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v"], ["translation", "tail", "discontinuous", "excess", "rounded"])
    func periodicSourceAndWidthFailuresRemainTyped(axis: String, failure: String) throws {
        if failure == "discontinuous" {
            // Original periodic source validation rejects multiplicity greater than
            // degree before preparation can mint any selected-side authority.
            #expect(throws: GeometryError.invalidDistance(2.0)) {
                _ = try fixture(axes: axis, discontinuous: true)
            }
            return
        }
        var surface = try fixture(axes: axis)
        if failure == "translation" {
            if axis == "u" { surface.uKnots[0] = surface.uKnots[0].nextUp }
            else { surface.vKnots[0] = surface.vKnots[0].nextUp }
        }
        if failure == "tail" {
            if axis == "u" { surface.controlPoints[0][4].x += 0.125 }
            else { surface.controlPoints[4][0].x += 0.125 }
        }
        let range = failure == "excess" ? (0.0, 4.5)
            : failure == "rounded" ? (-Double(2).nextUp, 2.0) : (0.0, 4.0)
        if failure == "rounded" { #expect(range.1 - range.0 == 4 && range.0 < -2) }
        if failure != "tail" { try surface.validate(tolerance: .standard) }
        expectCode(failure == "tail" ? .invalidInput : .unsupportedCapability) {
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
            _ = try prepared.originalNativeSpans(over: box(axis == "u" ? range : (0, 1),
                axis == "v" ? range : (0, 1)), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func allLiftedOwnersShareOneCoverCeilingAndUnrepresentableCycleRefuses() throws {
        let surface = try fixture(axes: "both")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let query = try box((3.5, 4.5), (-0.5, 0.5))
        expectCode(.resourceLimitExceeded) {
            _ = try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 3)
        }
        #expect(try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 4).count == 4)
        expectCode(.resourceLimitExceeded) {
            _ = try prepared.originalNativeSpans(over: box((1e20, 1e20), (0, 1)), tolerance: .standard)
        }
        expectCode(.invalidInput) {
            _ = try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func collapsedOriginalPanelHasNoInventedSelectedNormal() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        var surface = try fixture(axes: "both")
        surface.controlPoints = surface.controlPoints.map { $0.map { _ in Point3D.origin } }
        try surface.validate(tolerance: .standard)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &execution)
        let token = try geometryTestRequire(try prepared.originalNativeSpans(over: box((3.5, 4.5), (-0.5, 0.5)), tolerance: .standard, using: &execution)
            .first { $0.uBounds.lower == 3 && $0.vBounds.lower == -1 })
        expectCode(.singularSystem) {
            _ = try surface.normal(u: 3.75, v: -0.25, owning: token, tolerance: .standard, using: &execution)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledLiftCoverCannotPublishTokens() async throws {
        let surface = try fixture(axes: "both")
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let query = try box((3.5, 4.5), (-0.5, 0.5))
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try prepared.originalNativeSpans(over: query, tolerance: .standard)
        }
        task.cancel(); opened.yield(); opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(surface == prepared.surface)
    }

    private func fixture(axes: String, discontinuous: Bool = false) throws -> BSplineSurface3D {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let knots: [Double] = discontinuous ? [0, 1, 1, 3, 4] : [0, 1, 2, 3, 4]
        if axes == "both" {
            let net = c.map { b in c.map { a in Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1) } }
            return try .periodic(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: net, isUPeriodic: true, isVPeriodic: true, tolerance: .standard)
        }
        let net = axes == "u" ? [0.0, 1.0].map { z in c.map { Point3D(x: $0.0, y: $0.1, z: z) } }
            : c.map { a in [0.0, 1.0].map { z in Point3D(x: a.0, y: a.1, z: z) } }
        return try .periodic(uDegree: 1, vDegree: 1,
            uKnots: axes == "u" ? knots : [0, 0, 1, 1],
            vKnots: axes == "v" ? knots : [0, 0, 1, 1],
            controlPoints: net, isUPeriodic: axes == "u", isVPeriodic: axes == "v", tolerance: .standard)
    }

    private struct Literal {
        let point: Point3D
        let du: Vector3D
        let dv: Vector3D
        let duv: Vector3D
    }

    private func literal(u: Double, v: Double, span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
                         axes: String) -> Literal {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        func piece(_ index: Int, _ fraction: Double) -> (x: Double, y: Double, dx: Double, dy: Double) {
            let a = c[index - 1], b = c[index % 4]
            return (a.0 + (b.0 - a.0) * fraction, a.1 + (b.1 - a.1) * fraction, b.0 - a.0, b.1 - a.1)
        }
        if axes == "both" {
            let a = piece(span.uSpanIndex, u - span.uBounds.lower)
            let b = piece(span.vSpanIndex, v - span.vBounds.lower), r = 3 + b.x
            return Literal(point: Point3D(x: r * a.x, y: r * a.y, z: b.y),
                du: Vector3D(x: r * a.dx, y: r * a.dy, z: 0),
                dv: Vector3D(x: b.dx * a.x, y: b.dx * a.y, z: b.dy),
                duv: Vector3D(x: b.dx * a.dx, y: b.dx * a.dy, z: 0))
        }
        let a = piece(axes == "u" ? span.uSpanIndex : span.vSpanIndex,
                      axes == "u" ? u - span.uBounds.lower : v - span.vBounds.lower)
        let tangent = Vector3D(x: a.dx, y: a.dy, z: 0), axial = Vector3D(x: 0, y: 0, z: 1)
        return Literal(point: Point3D(x: a.x, y: a.y, z: axes == "u" ? v : u),
                       du: axes == "u" ? tangent : axial, dv: axes == "u" ? axial : tangent, duv: .zero)
    }

    private func check(_ jet: SurfaceIntervalVectorJet, contains expected: Literal) {
        for (component, position, du, dv, duv) in [
            (jet.x, expected.point.x, expected.du.x, expected.dv.x, expected.duv.x),
            (jet.y, expected.point.y, expected.du.y, expected.dv.y, expected.duv.y),
            (jet.z, expected.point.z, expected.du.z, expected.dv.z, expected.duv.z)] {
            #expect(contains(component.value, position))
            #expect(contains(component.derivativeU, du) && contains(component.derivativeV, dv))
            #expect(contains(component.secondDerivativeUU, 0) && contains(component.secondDerivativeVV, 0))
            #expect(contains(component.secondDerivativeUV, duv))
        }
    }

    private func contains(_ interval: OutwardScalarInterval, _ value: Double) -> Bool {
        interval.lower <= value && value <= interval.upper
    }

    private func box(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Unproved periodic selected span authority was admitted.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected periodic selected span error: \(error)") }
    }
}
