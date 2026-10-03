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

    @Test(.timeLimit(.minutes(2)))
    func roundedCornersRoundAnOpenMeshsFreeCornersOver() throws {
        // One triangle: an open general mesh, its three corners each on one face.
        let s = 0.01
        let corners = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 3 * s, y: 0, z: 0), Point3D(x: 0, y: 3 * s, z: 0)]
        let mesh = Mesh(positions: corners, indices: [0, 1, 2])
        func sheet(rounded: Bool, interpolated: Bool = false) throws -> BRepModel {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            _ = try builder.polySpline(sourceMesh: mesh, options: PolySplineOptions(
                roundedCorners: rounded, mergePatches: false, interpolateBoundaryExactly: interpolated))
            let model = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "poly")).brep
            try model.validate(level: .exact, tolerance: .standard)
            return model
        }
        func reaches(_ model: BRepModel, _ corner: Point3D) -> Bool {
            model.vertices.values.contains { ($0.point - corner).length < 1e-12 }
        }
        // Kept, the sheet runs out to every corner; rounded, it turns short of each.
        let kept = try sheet(rounded: false)
        #expect(corners.allSatisfy { reaches(kept, $0) })
        let rounded = try sheet(rounded: true)
        #expect(corners.allSatisfy { reaches(rounded, $0) == false })
        #expect(rounded.faces.count == kept.faces.count)
        // Interpolate Boundary Exactly: the rounded boundary passes through the corners again.
        let interpolated = try sheet(rounded: true, interpolated: true)
        #expect(corners.allSatisfy { corner in interpolated.vertices.values.contains { ($0.point - corner).length < 1e-12 } })
    }

    /// The cube [−s, s]³ with each side cut into n × n quads, as triangles wound outward.
    private func subdividedCube(_ s: Double, _ n: Int) -> Mesh {
        var positions: [Point3D] = []
        var index: [String: UInt32] = [:]
        func vertex(_ p: Point3D) -> UInt32 {
            let key = String(format: "%.9f,%.9f,%.9f", p.x, p.y, p.z)
            if let existing = index[key] { return existing }
            positions.append(p)
            index[key] = UInt32(positions.count - 1)
            return UInt32(positions.count - 1)
        }
        var indices: [UInt32] = []
        // Each side: a corner, two edge directions (their cross product outward).
        let sides: [(Point3D, Vector3D, Vector3D)] = [
            (Point3D(x: -s, y: -s, z: s), Vector3D(x: 2 * s, y: 0, z: 0), Vector3D(x: 0, y: 2 * s, z: 0)),
            (Point3D(x: -s, y: -s, z: -s), Vector3D(x: 0, y: 2 * s, z: 0), Vector3D(x: 2 * s, y: 0, z: 0)),
            (Point3D(x: s, y: -s, z: -s), Vector3D(x: 0, y: 2 * s, z: 0), Vector3D(x: 0, y: 0, z: 2 * s)),
            (Point3D(x: -s, y: -s, z: -s), Vector3D(x: 0, y: 0, z: 2 * s), Vector3D(x: 0, y: 2 * s, z: 0)),
            (Point3D(x: -s, y: s, z: -s), Vector3D(x: 0, y: 0, z: 2 * s), Vector3D(x: 2 * s, y: 0, z: 0)),
            (Point3D(x: -s, y: -s, z: -s), Vector3D(x: 2 * s, y: 0, z: 0), Vector3D(x: 0, y: 0, z: 2 * s)),
        ]
        for (corner, a, b) in sides {
            func at(_ i: Int, _ j: Int) -> UInt32 { vertex(corner + a * (Double(i) / Double(n)) + b * (Double(j) / Double(n))) }
            for i in 0..<n {
                for j in 0..<n {
                    let q = [at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)]
                    indices += [q[0], q[1], q[2], q[0], q[2], q[3]]
                }
            }
        }
        return Mesh(positions: positions, indices: indices)
    }

    @Test(.timeLimit(.minutes(2)))
    func mergePatchesMakesOneFacePerRegularBlock() throws {
        // A cube cut into 2 × 2 quads a side: unmerged, 24 patches; merged, each side's four
        // patches (meeting at regular vertices) one face, and the same solid.
        let s = 0.01
        func solid(merged: Bool) throws -> BRepModel {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            _ = try builder.polySpline(sourceMesh: subdividedCube(s, 2), options: PolySplineOptions(mergePatches: merged))
            let model = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "poly")).brep
            try model.validate(level: .volumetric, tolerance: .standard)
            return model
        }
        let unmerged = try solid(merged: false)
        let merged = try solid(merged: true)
        #expect(unmerged.faces.count == 24)
        #expect(merged.faces.count == 6)
        // Each merged side is the uniform bicubic B-spline over its regular middle: its middle
        // joint knots are simple.
        let surfaces = merged.faces.values.compactMap { face -> BSplineSurface3D? in
            if case let .bSpline(surface)? = merged.geometry.surfaces[face.surfaceID] { return surface }
            return nil
        }
        #expect(surfaces.count == 6)
        #expect(surfaces.allSatisfy { $0.uKnots.filter { $0 == 1 }.count < 3 || $0.vKnots.filter { $0 == 1 }.count < 3 })
        let volumes = try (unmerged.volume(tolerance: .standard), merged.volume(tolerance: .standard))
        #expect(abs(volumes.0 - volumes.1) < 1e-12, "\(volumes)")
    }
}
