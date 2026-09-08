import CADCore
import Foundation
import Testing
@testable import CADIR

@Suite("Mesh face-run provenance")
struct MeshFaceRunTests {
    // MARK: - Fixtures

    /// A unit quad in the XY plane, wound so every face normal is `+Z`.
    ///
    /// The quad is two triangles, which is the smallest emission that can be
    /// partitioned between two faces as well as owned by one.
    private static func quad(faceRuns: [Mesh.FaceRun]) -> Mesh {
        Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            normals: Array(repeating: Vector3D.unitZ, count: 4),
            indices: [0, 1, 2, 0, 2, 3],
            faceRuns: faceRuns
        )
    }

    // MARK: - Value contract

    @Test(.timeLimit(.minutes(1)))
    func aMeshWithoutProvenanceValidates() throws {
        let mesh = Self.quad(faceRuns: [])

        try mesh.validate(tolerance: .standard)

        #expect(mesh.faceRuns.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCompletePartitionValidates() throws {
        let firstFace = FaceID()
        let secondFace = FaceID()
        let mesh = Self.quad(faceRuns: [
            Mesh.FaceRun(faceID: firstFace, triangleCount: 1),
            Mesh.FaceRun(faceID: secondFace, triangleCount: 1),
        ])

        try mesh.validate(tolerance: .standard)

        #expect(mesh.faceRuns.map(\.faceID) == [firstFace, secondFace])
    }

    @Test(.timeLimit(.minutes(1)))
    func anEmptyRunIsRejected() {
        let mesh = Self.quad(faceRuns: [
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 2),
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 0),
        ])

        #expect(throws: ExportError.self) {
            try mesh.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aRepeatedFaceIsRejected() {
        let faceID = FaceID()
        let mesh = Self.quad(faceRuns: [
            Mesh.FaceRun(faceID: faceID, triangleCount: 1),
            Mesh.FaceRun(faceID: faceID, triangleCount: 1),
        ])

        #expect(throws: ExportError.self) {
            try mesh.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aShortPartitionIsRejected() {
        let mesh = Self.quad(faceRuns: [
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 1),
        ])

        #expect(throws: ExportError.self) {
            try mesh.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aLongPartitionIsRejected() {
        let mesh = Self.quad(faceRuns: [
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 2),
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 1),
        ])

        #expect(throws: ExportError.self) {
            try mesh.validate(tolerance: .standard)
        }
    }

    // MARK: - Serialization

    @Test(.timeLimit(.minutes(1)))
    func provenanceSurvivesAJSONRoundTrip() throws {
        let runs = [
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 1),
            Mesh.FaceRun(faceID: FaceID(), triangleCount: 1),
        ]
        let mesh = Self.quad(faceRuns: runs)

        let data = try JSONEncoder().encode(mesh)
        let decoded = try JSONDecoder().decode(Mesh.self, from: data)

        #expect(decoded == mesh)
        #expect(decoded.faceRuns == runs)
    }

    @Test(.timeLimit(.minutes(1)))
    func anAbsentFieldDecodesAsNoProvenance() throws {
        let mesh = Self.quad(faceRuns: [])

        let data = try JSONEncoder().encode(mesh)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["faceRuns"] == nil)

        let decoded = try JSONDecoder().decode(Mesh.self, from: data)
        #expect(decoded.faceRuns.isEmpty)
    }
}
