import CADCore
import Testing
@testable import CADGeometry

@Suite("Original selected surface first-order authority")
struct OriginalSurfaceFirstOrderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func rationalClosedBoxesContainLiteralOriginalValuesAndTangents(point: Bool) throws {
        let source = literalSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let box = try query(point ? (0.25, 0.25) : (0.1, 0.8), point ? (0.3, 0.3) : (0.2, 0.9))
        let span = try #require(try prepared.originalNativeSpans(over: box, tolerance: tolerance).first)
        let result = try span.firstOrderEnclosure(overClosedBox: box, on: source, tolerance: tolerance)
        for u in [box.u.lower, box.u.midpoint, box.u.upper] {
            for v in [box.v.lower, box.v.midpoint, box.v.upper] {
                // The original literal tensor has W=1+uv, N=(u+uv,v+uv,2uv).
                let d = 1 + u*v
                let n = Vector3D(x: u + u*v, y: v + u*v, z: 2*u*v)
                let nu = Vector3D(x: 1 + v, y: v, z: 2*v)
                let nv = Vector3D(x: u, y: 1 + u, z: 2*u)
                contains(result.value, n / d)
                contains(result.derivativeU, (nu * d - n * v) / (d*d))
                contains(result.derivativeV, (nv * d - n * u) / (d*d))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["source", "tolerance", "box"])
    func originalSelectedFirstOrderRefusesForeignAuthority(failure: String) throws {
        let source = literalSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let box = try query((0.25, 0.25), (0.3, 0.3))
        let span = try #require(try prepared.originalNativeSpans(over: box, tolerance: tolerance).first)
        var foreign = source, changed = tolerance
        if failure == "source" { foreign.controlPoints[1][1].z += 0.01 }
        if failure == "tolerance" { changed.distance *= 0.5 }
        let requested = failure == "box" ? try query((0.25, 0.25), (0.3, 1.0.nextUp)) : box
        #expect(throws: KernelError.self) {
            _ = try span.firstOrderEnclosure(overClosedBox: requested, on: foreign, tolerance: changed)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledFirstOrderCannotPublishOriginalValues() async throws {
        let source = literalSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        let box = try query((0.25, 0.25), (0.3, 0.3))
        let span = try #require(try prepared.originalNativeSpans(over: box, tolerance: tolerance).first)
        let task = Task {
            while Task.isCancelled == false { await Task.yield() }
            return try span.firstOrderEnclosure(overClosedBox: box, on: source, tolerance: tolerance)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func literalSurface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)],
                            [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 1)]],
            weights: [[1,1], [1,2]])
    }

    private func query(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        try SurfaceParameterBox(u: ScalarInterval(lower: u.0, upper: u.1),
                                v: ScalarInterval(lower: v.0, upper: v.1))
    }

    private func contains(_ bounds: IntervalVector3DBounds, _ literal: Vector3D) {
        #expect(bounds.x.lower <= literal.x && literal.x <= bounds.x.upper)
        #expect(bounds.y.lower <= literal.y && literal.y <= bounds.y.upper)
        #expect(bounds.z.lower <= literal.z && literal.z <= bounds.z.upper)
    }
}
