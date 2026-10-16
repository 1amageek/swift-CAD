import CADCore
import Testing
@testable import CADGeometry

struct ConvexHullSeparationTests {
    @Test(.timeLimit(.minutes(1)))
    func filteredPlanePredicateMatchesExpansionReference() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let normals = [Vector3D(x: 1, y: 0, z: 0), Vector3D(x: 1, y: 1, z: -1),
                       Vector3D(x: 1e-12, y: -1e-12, z: 1e-12)]
        let values = [-1.0, -1e-12, 0, 1e-12, 1.0.nextDown, 1, 1.0.nextUp]
        for normal in normals {
            for value in values {
                let point = Vector3D(x: value, y: -value, z: value.nextUp)
                for tolerance in [0.0, 1e-12, 1.0] {
                    let threshold = try FloatingPointExpansion.product([tolerance], [normal.length.nextUp], using: &execution)
                    let x = try FloatingPointExpansion.product([normal.x], [point.x], using: &execution)
                    let y = try FloatingPointExpansion.product([normal.y], [point.y], using: &execution)
                    let z = try FloatingPointExpansion.product([normal.z], [point.z], using: &execution)
                    let xy = try FloatingPointExpansion.sum(x, y, using: &execution)
                    let dot = try FloatingPointExpansion.sum(xy, z, using: &execution)
                    let difference = try FloatingPointExpansion.subtract(dot, threshold, using: &execution)
                    let expected = try FloatingPointExpansion.sign(difference, using: &execution) == .positive
                    #expect(try ConvexHullSeparation3D.provesSeparatingPlane(
                        normal: normal, points: [point], tolerance: tolerance, using: &execution) == expected)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func hullSearchPreservesSeparationAndOverlap() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        let triangle = [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0),
                        Point3D(x: 0, y: 0, z: 1)]
        #expect(try ConvexHullSeparation3D.provesSeparated(first: triangle, second: [.origin], tolerance: 0.1, using: &execution))
        #expect(try !ConvexHullSeparation3D.provesSeparated(
            first: triangle + [Point3D(x: -1, y: -1, z: -1)], second: [.origin], tolerance: 0.1, using: &execution))
    }
}
