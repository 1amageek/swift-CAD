import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Original periodic and nonclamped native span composition")
struct OriginalMixedPeriodicTessellationTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v"], [0, 1, 2, 3])
    func mixedAxesRetainLiteralClosedJetsAndSelectedNormals(axis: String, continuity: Int) throws {
        let periodicC0 = continuity & 1 != 0, openC0 = continuity & 2 != 0
        let surface = fixture(axis: axis, periodicC0: periodicC0, openC0: openC0)
        let original = surface
        let open = openC0 ? (0.0, 1.0) : (2.0, 3.0)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        for periodic in [(3.5, 4.5), (0.0, 4.0), (-0.5, 0.5)] {
            let query = try box(axis == "u" ? periodic : open, axis == "u" ? open : periodic)
            let spans = try prepared.originalNativeSpans(over: query, tolerance: .standard)
            var area = 0.0
            for span in spans {
                let u0 = max(query.u.lower, span.uBounds.lower), u1 = min(query.u.upper, span.uBounds.upper)
                let v0 = max(query.v.lower, span.vBounds.lower), v1 = min(query.v.upper, span.vBounds.upper)
                area += (u1 - u0) * (v1 - v0)
                let enclosure = try span.intervalJet(overClosedBox: box((u0, u1), (v0, v1)), on: surface, tolerance: .standard)
                for u in [u0, (u0 + u1) / 2, u1] { for v in [v0, (v0 + v1) / 2, v1] {
                    let expected = literal(u: u, v: v, span: span, axis: axis, periodicC0: periodicC0, openC0: openC0)
                    let point = try span.pointJet(u: u, v: v, on: surface, tolerance: .standard)
                    check(point, contains: expected)
                    check(enclosure, contains: expected)
                    #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected.p).length <= 1e-12)
                    let normal = try expected.du.cross(expected.dv).normalized(tolerance: 1e-300)
                    #expect((try surface.normal(u: u, v: v, owning: span, tolerance: .standard) - normal).length <= 1e-12)
                    #expect((axis == "u" ? span.vCycle : span.uCycle) == 0)
                } }
            }
            #expect(area == (periodic.1 - periodic.0) * (open.1 - open.0))
        }
        let middle = openC0 ? 0.5 : 2.5
        let seam = try box(axis == "u" ? (4, 4) : (middle, middle), axis == "u" ? (middle, middle) : (4, 4))
        let owners = try prepared.originalNativeSpans(over: seam, tolerance: .standard)
        #expect(owners.count == (openC0 ? 4 : 2))
        if periodicC0 || openC0 {
            let normals = try owners.map { try surface.normal(u: seam.u.lower, v: seam.v.lower, owning: $0, tolerance: .standard) }
            #expect(normals.indices.contains { i in normals.indices.contains { j in (normals[i] - normals[j]).length > 0.1 } })
        }
        for endpoint in [open.0, open.1] {
            let corner = try box(axis == "u" ? (4, 4) : (endpoint, endpoint), axis == "u" ? (endpoint, endpoint) : (4, 4))
            #expect(try prepared.originalNativeSpans(over: corner, tolerance: .standard).count == 2)
        }
        #expect(surface == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["source", "tolerance", "outside", "roundedWidth"])
    func mixedTokensRejectForeignAndUncoveredOriginalAuthority(failure: String) throws {
        let surface = fixture(axis: "u", periodicC0: false, openC0: false)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        if failure == "roundedWidth" {
            #expect(2 - (-Double(2).nextUp) == 4)
            expectCode(.unsupportedCapability) { _ = try prepared.originalNativeSpans(over: box((-Double(2).nextUp, 2), (2, 3)), tolerance: .standard) }
            return
        }
        let token = try #require(try prepared.originalNativeSpans(over: box((3.5, 4.5), (2, 3)), tolerance: .standard).first { $0.uBounds.lower == 3 })
        var source = surface, tolerance = ModelingTolerance.standard
        if failure == "source" { source.controlPoints[0][0].z += 0.125 }
        if failure == "tolerance" { tolerance.distance *= 0.5 }
        expectCode(.invalidInput) {
            _ = try token.pointJet(u: 3.75, v: failure == "outside" ? 3.25 : 2.5, on: source, tolerance: tolerance)
        }
        expectCode(.invalidInput) {
            _ = try source.normal(u: 3.75, v: failure == "outside" ? 3.25 : 2.5, owning: token, tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mixedCoverChargesOneAggregateAndKeepsOriginalOpenDomain() throws {
        let surface = fixture(axis: "v", periodicC0: false, openC0: false)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let query = try box((2, 3), (3.5, 4.5))
        expectCode(.resourceLimitExceeded) { _ = try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 1) }
        #expect(try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 2).count == 2)
        expectCode(.invalidInput) { _ = try prepared.originalNativeSpans(over: query, tolerance: .standard, maximumSpanCount: 0) }
        expectCode(.invalidInput) { _ = try prepared.originalNativeSpans(over: box((1.5, 3), (3.5, 4.5)), tolerance: .standard) }
        // The ordinary evaluator continues to choose its original canonical seam;
        // selected ownership supplies both incident sides without changing that law.
        let point = try box((2.5, 2.5), (4, 4))
        let right = try #require(try prepared.originalNativeSpans(over: point, tolerance: .standard).first { $0.vBounds.lower == 4 })
        #expect((try surface.normal(u: 2.5, v: 4, tolerance: .standard) - surface.normal(u: 2.5, v: 4, owning: right, tolerance: .standard)).length <= 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledMixedCoverCannotPublishOriginalTokens() async throws {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: fixture(axis: "u", periodicC0: true, openC0: true), tolerance: .standard)
        let query = try box((3.5, 4.5), (0, 1))
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task { for await _ in gate { break }; return try prepared.originalNativeSpans(over: query, tolerance: .standard) }
        task.cancel(); opened.yield(); opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func fixture(axis: String, periodicC0: Bool, openC0: Bool) -> BSplineSurface3D {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0), (1.0, 0.0), (0.0, 1.0)]
        let cycle = Array(c.prefix(periodicC0 ? 5 : 6))
        let radius = openC0 ? [1.0, 1.125, 1.0] : [1.0, 1.0, 1.5]
        let height = openC0 ? [0.0, 0.5, 1.0] : [-0.5, 0.5, 1.5]
        let net = radius.indices.map { j in cycle.map { Point3D(x: radius[j] * $0.0, y: radius[j] * $0.1, z: height[j]) } }
        let pk: [Double] = periodicC0 ? [-1, 0, 1, 2, 3, 4, 5] : [-2, -1, 0, 1, 2, 3, 4, 5, 6]
        let ok: [Double] = openC0 ? [-1, 0, 0.5, 1, 2] : [0, 1, 2, 3, 4, 5]
        return BSplineSurface3D(uDegree: axis == "u" ? (periodicC0 ? 1 : 2) : (openC0 ? 1 : 2),
            vDegree: axis == "u" ? (openC0 ? 1 : 2) : (periodicC0 ? 1 : 2),
            uKnots: axis == "u" ? pk : ok, vKnots: axis == "u" ? ok : pk,
            controlPoints: axis == "u" ? net : cycle.indices.map { i in net.map { $0[i] } },
            isUPeriodic: axis == "u", isVPeriodic: axis == "v")
    }

    private struct Literal {
        let p: Point3D
        let du: Vector3D
        let dv: Vector3D
        let duv: Vector3D
    }

    private func literal(u: Double, v: Double, span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
                         axis: String, periodicC0: Bool, openC0: Bool) -> Literal {
        let bounds = axis == "u" ? span.uBounds : span.vBounds
        let degree = periodicC0 ? 1 : 2
        let index = (axis == "u" ? span.uSpanIndex : span.vSpanIndex) - degree
        let t = (axis == "u" ? u : v) - bounds.lower
        let a = periodicC0 ? (1 - t, t) : (0.5 - t, 0.5 + t - t * t)
        let d = periodicC0 ? (-1.0, 1.0) : (-1.0, 1 - 2 * t)
        func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
            switch index % 4 { case 0: return (x, y); case 1: return (-y, x); case 2: return (-x, -y); default: return (y, -x) }
        }
        let c = rotate(a.0, a.1), dc = rotate(d.0, d.1)
        let z = (axis == "u" ? v : u) - (openC0 ? 0 : 2)
        let openBounds = axis == "u" ? span.vBounds : span.uBounds
        let r = openC0 ? 1 + 0.25 * min(z, 1 - z) : 1 + 0.25 * z * z
        let dr = openC0 ? (openBounds.upper <= 0.5 ? 0.25 : -0.25) : 0.5 * z
        let dp = Vector3D(x: r * dc.0, y: r * dc.1, z: 0)
        let dz = Vector3D(x: dr * c.0, y: dr * c.1, z: 1)
        return Literal(p: Point3D(x: r * c.0, y: r * c.1, z: z), du: axis == "u" ? dp : dz,
                       dv: axis == "u" ? dz : dp, duv: Vector3D(x: dr * dc.0, y: dr * dc.1, z: 0))
    }

    private func check(_ jet: SurfaceIntervalVectorJet, contains literal: Literal) {
        for (field, p, du, dv, duv) in [(jet.x, literal.p.x, literal.du.x, literal.dv.x, literal.duv.x),
                                      (jet.y, literal.p.y, literal.du.y, literal.dv.y, literal.duv.y),
                                      (jet.z, literal.p.z, literal.du.z, literal.dv.z, literal.duv.z)] {
            #expect(field.value.lower <= p && p <= field.value.upper)
            #expect(field.derivativeU.lower <= du && du <= field.derivativeU.upper)
            #expect(field.derivativeV.lower <= dv && dv <= field.derivativeV.upper)
            #expect(field.secondDerivativeUV.lower <= duv && duv <= field.secondDerivativeUV.upper)
        }
    }

    private func box(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Unproved original mixed-axis authority was admitted.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected mixed-axis error: \(error)") }
    }
}
