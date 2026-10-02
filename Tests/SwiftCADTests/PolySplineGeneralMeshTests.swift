import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// PolySplines of meshes no rectangular grid spans: a cube's quads (every corner of valence
/// three) and a tetrahedron's triangles (refined once by Catmull–Clark) each close into a solid of
/// bicubic patches sharing their edges exactly, every corner at its Catmull–Clark limit position.
@Suite("PolySplines of general meshes")
struct PolySplineGeneralMeshTests {
    private func evaluate(_ mesh: Mesh) throws -> (EvaluatedDocument, FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let feature = try builder.polySpline(sourceMesh: mesh, options: PolySplineOptions(mergePatches: false))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "poly"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return (evaluated, feature)
    }

    /// The cube [−s, s]³ as twelve triangles wound outward.
    private func cube(_ s: Double) -> Mesh {
        var positions: [Point3D] = []
        for x in [-s, s] { for y in [-s, s] { for z in [-s, s] { positions.append(Point3D(x: x, y: y, z: z)) } } }
        // index = 4·(x>0) + 2·(y>0) + (z>0)
        let quads: [[UInt32]] = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
        let indices = quads.flatMap { q in [q[0], q[1], q[2], q[0], q[2], q[3]] }
        return Mesh(positions: positions, indices: indices)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCubesQuadsCloseIntoASolidAtTheirLimitCorners() throws {
        let s = 0.01
        let (evaluated, _) = try evaluate(cube(s))
        #expect(evaluated.brep.faces.count == 6)
        // A corner of valence three: (9v + 4Σe + Σf)/24 = v/2 for the cube.
        let corners = evaluated.brep.vertices.values.map(\.point)
        #expect(corners.count == 8)
        #expect(corners.allSatisfy { abs(abs($0.x) - s / 2) < 1e-12 && abs(abs($0.y) - s / 2) < 1e-12 && abs(abs($0.z) - s / 2) < 1e-12 })
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(volume > 0 && volume < 8 * s * s * s, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aTetrahedronsTrianglesAreRefinedIntoQuadPatches() throws {
        let s = 0.01
        let positions = [Point3D(x: s, y: s, z: s), Point3D(x: s, y: -s, z: -s), Point3D(x: -s, y: s, z: -s), Point3D(x: -s, y: -s, z: s)]
        // Wound outward: each face's normal away from the centroid.
        var indices: [UInt32] = []
        for face in [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]] {
            let (a, b, c) = (positions[face[0]], positions[face[1]], positions[face[2]])
            let center = Point3D.origin + ((a - .origin) + (b - .origin) + (c - .origin)) * (1.0 / 3)
            let outward = (b - a).cross(c - a).dot(center - .origin) > 0
            indices += (outward ? face : [face[0], face[2], face[1]]).map(UInt32.init)
        }
        let (evaluated, _) = try evaluate(Mesh(positions: positions, indices: indices))
        // Four triangles, each split into three quads.
        #expect(evaluated.brep.faces.count == 12)
        #expect(try evaluated.brep.volume(tolerance: .standard) > 0)
    }
}
