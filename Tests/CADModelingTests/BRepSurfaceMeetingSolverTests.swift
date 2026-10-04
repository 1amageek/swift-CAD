import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADModeling

@Suite("Unbounded surface meeting nearest points")
struct BRepSurfaceMeetingSolverTests {
    private func parabola(focalLength: Double) -> Curve3D {
        .analytic(.parabola(Parabola3D(vertex: .origin, normal: .unitZ,
                                     axis: .unitY, focalLength: focalLength)))
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedWindowCannotPublishItsBoundaryAsNearest() throws {
        let curve = parabola(focalLength: 1e12)
        let query = Point3D(x: -3_000_000, y: 2.25, z: 0)
        #expect(throws: KernelError.self) {
            do {
                _ = try BRepSurfaceMeetingSolver(tolerance: .standard).closest(to: query, on: curve)
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
                #expect(error.message.contains("exhausted its envelope"))
                throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func interiorNearestSurvivesWindowExpansion() throws {
        let curve = parabola(focalLength: 1)
        // The original parabola parameter 3 gives x=-3, y=9/4 exactly.
        let query = Point3D(x: -3, y: 2.25, z: 0)
        let result = try BRepSurfaceMeetingSolver(tolerance: .standard).closest(to: query, on: curve)
        #expect(abs(result.parameter - 3) <= 1e-7)
        #expect((result.point - query).length <= ModelingTolerance.standard.distance)
    }
}
