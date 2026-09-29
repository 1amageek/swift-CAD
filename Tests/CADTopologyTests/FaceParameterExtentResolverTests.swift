import Foundation
import CADCore
import CADGeometry
import Testing
@testable import CADTopology

/// A face's parameter extent holds every trimming curve and overhangs their true extremes by no
/// more than a ten-millionth of its width, where the certified bounds may overhang by far more.
@Suite("Face parameter extent resolver")
struct FaceParameterExtentResolverTests {
    private func model(_ pcurves: [SurfaceParameterCurve]) -> (FaceID, BRepModel) {
        let surfaceID = SurfaceID(), faceID = FaceID(), loopID = LoopID()
        return (faceID, BRepModel(
            geometry: GeometryStore(surfaces: [surfaceID: .plane(Plane3D(origin: .origin, normal: .unitZ))]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: pcurves.map { Coedge(edgeID: EdgeID(), surfaceParameterCurve: $0) })]
        ))
    }

    private func expectTight(_ interval: ScalarInterval, _ lower: Double, _ upper: Double) {
        let slack = (upper - lower) * 1e-7 + 1e-12
        #expect(interval.lower <= lower && interval.lower >= lower - slack)
        #expect(interval.upper >= upper && interval.upper <= upper + slack)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDiskFacesExtentIsItsCircle() throws {
        // A circle of radius 0.3 about (0.1, -0.2), which the certified bounds enclose loosely.
        let (faceID, model) = model([
            .harmonic(center: Point2D(x: 0.1, y: -0.2), cosine: Point2D(x: 0.3, y: 0), sine: Point2D(x: 0, y: 0.3),
                      startParameter: 0, endParameter: .pi),
            .harmonic(center: Point2D(x: 0.1, y: -0.2), cosine: Point2D(x: 0.3, y: 0), sine: Point2D(x: 0, y: 0.3),
                      startParameter: .pi, endParameter: 2 * .pi),
        ])
        let extent = try FaceParameterExtentResolver().bounds(for: faceID, in: model, tolerance: .standard)
        expectTight(extent.u, -0.2, 0.4)
        expectTight(extent.v, -0.5, 0.1)
        let certified = try DefaultFaceParameterBoundsResolver().bounds(for: faceID, in: model, tolerance: .standard)
        #expect(certified.u.width > extent.u.width * 1.01)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPolylineOutlineIsEnclosedAlongItsOwnSides() throws {
        // Each side a two-point polyline, which runs along one parameter only.
        let corners = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.03), (0.0, 0.03)].map { SurfaceParameter(u: $0.0, v: $0.1) }
        let (faceID, model) = model((0..<4).map { .polyline([corners[$0], corners[($0 + 1) % 4]]) })
        let extent = try FaceParameterExtentResolver().bounds(for: faceID, in: model, tolerance: .standard)
        expectTight(extent.u, 0, 0.02)
        expectTight(extent.v, 0, 0.03)
        // The certified bounds of a polyline running along one parameter no longer spread across.
        let certified = try DefaultFaceParameterBoundsResolver().bounds(for: faceID, in: model, tolerance: .standard)
        expectTight(certified.u, 0, 0.02)
        expectTight(certified.v, 0, 0.03)
    }
}
