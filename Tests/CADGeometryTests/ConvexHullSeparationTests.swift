import CADCore
import Testing
@testable import CADGeometry

struct ConvexHullSeparationTests {
    @Test(.timeLimit(.minutes(1)))
    func filteredPlanePredicateMatchesExpansionReference() {
        let normals = [Vector3D(x: 1, y: 0, z: 0), Vector3D(x: 1, y: 1, z: -1),
                       Vector3D(x: 1e-12, y: -1e-12, z: 1e-12)]
        let values = [-1.0, -1e-12, 0, 1e-12, 1.0.nextDown, 1, 1.0.nextUp]
        for normal in normals {
            for value in values {
                let point = Vector3D(x: value, y: -value, z: value.nextUp)
                for tolerance in [0.0, 1e-12, 1.0] {
                    let threshold = FloatingPointExpansion.product([tolerance], [normal.length.nextUp])
                    let dot = FloatingPointExpansion.sum(
                        FloatingPointExpansion.sum(
                            FloatingPointExpansion.product([normal.x], [point.x]),
                            FloatingPointExpansion.product([normal.y], [point.y])),
                        FloatingPointExpansion.product([normal.z], [point.z]))
                    let expected = FloatingPointExpansion.sign(
                        FloatingPointExpansion.subtract(dot, threshold)) == .positive
                    #expect(ConvexHullSeparation3D.provesSeparatingPlane(
                        normal: normal, points: [point], tolerance: tolerance) == expected)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func hullSearchPreservesSeparationAndOverlap() {
        let triangle = [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0),
                        Point3D(x: 0, y: 0, z: 1)]
        #expect(ConvexHullSeparation3D.provesSeparated(first: triangle, second: [.origin], tolerance: 0.1))
        #expect(!ConvexHullSeparation3D.provesSeparated(
            first: triangle + [Point3D(x: -1, y: -1, z: -1)], second: [.origin], tolerance: 0.1))
    }
}
