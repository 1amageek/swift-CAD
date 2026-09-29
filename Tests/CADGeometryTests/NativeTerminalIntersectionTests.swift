import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Native helical terminal intersection", .timeLimit(.minutes(1)))
struct NativeTerminalIntersectionTests {
    @Test func blendIntersectsOriginalNeighbor() throws {
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NativeTerminalSurfaces.json")
        let surfaces = try JSONDecoder().decode([Surface3D].self, from: Data(contentsOf: url))
        #expect(surfaces.count == 3)
        guard case .procedural(.offset(let first)) = surfaces[0],
              case .procedural(.offset(let second)) = surfaces[1] else {
            Issue.record("The captured contact supports must be offsets."); return
        }
        let contacts = try DefaultSurfaceSurfaceIntersector().intersections(
            first: surfaces[0], second: surfaces[1], tolerance: tolerance)
        guard case .curve(let contact) = try #require(contacts.first),
              case .closed(let lower, let upper) = contact.curve.parameterDomain else {
            Issue.record("The native contact must have a finite curve domain."); return
        }
        let blend = try RollingBallSectionEvaluator(first: first, second: second,
            intersection: contact, tolerance: tolerance).blendSurface(
                fromCurveParameter: lower, toCurveParameter: upper,
                options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
        let support = Surface3D.procedural(.rollingBall(blend))
        guard case .bSpline(let neighbor) = surfaces[2] else {
            Issue.record("The native neighbor must retain its spline chart."); return
        }
        let continued = try neighbor.continuedBezierSupport(
            over: SurfaceParameterBox(u: ScalarInterval(lower: -0.25, upper: 1.25),
                                      v: ScalarInterval(lower: -0.25, upper: 1.25)),
            maximumDeviation: tolerance.distance * 0.01, tolerance: tolerance)
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: support, second: .bSpline(continued.surface),
            options: .init(maximumSubdivisionCells: 4096, maximumRootAttempts: 4096), tolerance: tolerance)
        #expect(intersections.count == 1)
        guard case .curve(let trim) = try #require(intersections.first) else {
            Issue.record("A terminal requires a shared trim curve."); return
        }
        guard case .implicit(let implicit) = trim.truth else {
            Issue.record("The terminal must retain its implicit graph certificate."); return
        }
        let transfer = try implicit.transferredParameterCurve(on: .second, to: surfaces[2],
            maximumSpanCount: 4096,
            options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 16384), tolerance: tolerance)
        try transfer.validate(on: surfaces[2], tolerance: tolerance)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let a = try trim.surfaceParameter(on: .first, atNormalizedFraction: fraction, tolerance: tolerance)
            let b = try trim.surfaceParameter(on: .second, atNormalizedFraction: fraction, tolerance: tolerance)
            #expect(b.u >= -tolerance.relative && b.u <= 1 + tolerance.relative)
            #expect(b.v >= -tolerance.relative && b.v <= 1 + tolerance.relative)
            let p = try support.point(u: a.u, v: a.v, tolerance: tolerance)
            let q = try surfaces[2].point(u: b.u, v: b.v, tolerance: tolerance)
            #expect((p - q).length <= tolerance.distance)
        }
    }
}
