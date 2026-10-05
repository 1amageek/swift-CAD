import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation
import Testing

@Suite("Original framed plane signature transport", .timeLimit(.minutes(1)))
struct OriginalFramedPlaneSignatureTests {
    @Test
    func storedNativeAxisAndIdentitySurviveFaceSignatureTransport() throws {
        let surface = Surface3D.plane(Plane3D(origin: Point3D(x: 2, y: 3, z: 4),
            normal: .unitZ, uDirection: Vector3D(x: 0.6, y: 0.8, z: 0)))
        let signature = FaceGeometrySignature(surface: surface, orientation: .forward, loops: [])
        let restored = try JSONDecoder().decode(FaceGeometrySignature.self,
            from: JSONEncoder().encode(signature))
        #expect(restored == signature)
        #expect(Set([restored, signature]).count == 1)
        let point = try restored.surface.point(u: 5, v: -2, tolerance: .standard)
        #expect(abs(point.x - 6.6) < 1e-13)
        #expect(abs(point.y - 5.8) < 1e-13)
        #expect(point.z == 4)
        let legacy = FaceGeometrySignature(surface: .plane(Plane3D(
            origin: Point3D(x: 2, y: 3, z: 4), normal: .unitZ)), orientation: .forward, loops: [])
        #expect(Set([legacy, restored]).count == 2)
    }
}
