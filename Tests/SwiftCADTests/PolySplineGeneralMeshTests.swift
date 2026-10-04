import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
import CADGeometry
@testable import CADKernel
@testable import SwiftCAD

/// PolySplines of meshes no rectangular grid spans: a cube's quads (every corner of valence
/// three), a tetrahedron's and an icosahedron's triangles (valences three and five) each close
/// into a solid, and a fan of six quads into a sheet, refined by Catmull–Clark until each
/// extraordinary vertex is isolated: bicubic patches where the mesh is regular and a G2 cap of
/// degree-eight patches around each extraordinary vertex, held at its Catmull–Clark limit
/// position, the whole surface curvature continuous across every edge.
@Suite("PolySplines of general meshes")
struct PolySplineGeneralMeshTests {
    private func evaluate(_ mesh: Mesh) throws -> (EvaluatedDocument, FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let feature = try builder.polySpline(sourceMesh: mesh, options: PolySplineOptions(mergePatches: false))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "poly"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return (evaluated, feature)
    }

    /// Along every edge two faces share, at eleven points, both faces' oriented normals and
    /// curvature tensors (the shape operator as a 3 × 3 tensor) agree: the surface is G2 there.
    private func expectCurvatureContinuous(_ model: BRepModel) throws {
        var uses: [EdgeID: [(face: Face, coedge: Coedge)]] = [:]
        for face in model.faces.values {
            for loopID in face.loops {
                for coedge in model.loops[loopID]?.coedges ?? [] { uses[coedge.edgeID, default: []].append((face, coedge)) }
            }
        }
        func geometry(_ use: (face: Face, coedge: Coedge), _ fraction: Double) throws -> (point: Point3D, normal: Vector3D, tensor: [[Double]]) {
            guard case let .bSpline(surface)? = model.geometry.surfaces[use.face.surfaceID],
                  let pcurve = use.coedge.surfaceParameterCurve else {
                throw TopologyError.missingReference("A PolySplines face lacks its spline or a pcurve.")
            }
            let uv = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: .standard)
            let d = try surface.differentialGeometry(u: uv.u, v: uv.v, tolerance: .standard)
            let normal = d.normal * (use.face.orientation == .forward ? 1 : -1)
            let (e, f, g) = (d.tangentU.dot(d.tangentU), d.tangentU.dot(d.tangentV), d.tangentV.dot(d.tangentV))
            let (l, m, n) = (d.secondDerivativeUU.dot(normal), d.secondDerivativeUV.dot(normal), d.secondDerivativeVV.dot(normal))
            let det = e * g - f * f
            let inverse = [[g / det, -f / det], [-f / det, e / det]]
            let second = [[l, m], [m, n]]
            func product(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
                (0..<2).map { i in (0..<2).map { j in a[i][0] * b[0][j] + a[i][1] * b[1][j] } }
            }
            let inner = product(product(inverse, second), inverse)
            let columns = [d.tangentU, d.tangentV]
            let tensor = (0..<3).map { r in
                (0..<3).map { c in
                    var value = 0.0
                    for i in 0..<2 {
                        for j in 0..<2 {
                            let (a, b) = ([columns[i].x, columns[i].y, columns[i].z][r], [columns[j].x, columns[j].y, columns[j].z][c])
                            value += a * inner[i][j] * b
                        }
                    }
                    return value
                }
            }
            return (d.position, normal, tensor)
        }
        var (normalJump, tensorJump, scale) = (0.0, 0.0, 0.0)
        for pair in uses.values where pair.count == 2 {
            for step in 0...10 {
                let t = Double(step) / 10
                let a = try geometry(pair[0], t)
                let (forward, backward) = (try geometry(pair[1], t), try geometry(pair[1], 1 - t))
                let b = (forward.point - a.point).length < (backward.point - a.point).length ? forward : backward
                #expect((b.point - a.point).length < 1e-9)
                normalJump = max(normalJump, (a.normal - b.normal).length)
                for r in 0..<3 {
                    for c in 0..<3 {
                        tensorJump = max(tensorJump, abs(a.tensor[r][c] - b.tensor[r][c]))
                        scale = max(scale, abs(a.tensor[r][c]))
                    }
                }
            }
        }
        #expect(normalJump < 1e-9, "normal jump \(normalJump)")
        #expect(tensorJump < 1e-7 * scale, "curvature jump \(tensorJump) of \(scale)")
    }

    /// The faces of a G2 cap: Bézier patches of degree eight.
    private func capFaces(_ model: BRepModel) -> Int {
        model.faces.values.filter { face in
            if case let .bSpline(surface)? = model.geometry.surfaces[face.surfaceID] { return surface.uDegree == 8 }
            return false
        }.count
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
        // Refined twice (the corners four quads apart), 96 patches: three cap patches at each of
        // the eight corners.
        #expect(evaluated.brep.faces.count == 96)
        #expect(capFaces(evaluated.brep) == 24)
        // A corner of valence three: (9v + 4Σe + Σf)/24 = v/2 for the cube, where its cap holds it.
        let limits = evaluated.brep.vertices.values.map(\.point).filter {
            abs(abs($0.x) - s / 2) < 1e-12 && abs(abs($0.y) - s / 2) < 1e-12 && abs(abs($0.z) - s / 2) < 1e-12
        }
        #expect(limits.count == 8)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(volume > 0 && volume < 8 * s * s * s, "\(volume)")
        try expectCurvatureContinuous(evaluated.brep)
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
        // Four triangles, each split into three quads, refined twice more (a face centre lies
        // diagonally across a corner's cap after one): a cap at each of the four corners and four
        // face centres, all of valence three.
        #expect(evaluated.brep.faces.count == 192)
        #expect(capFaces(evaluated.brep) == 24)
        #expect(try evaluated.brep.volume(tolerance: .standard) > 0)
        try expectCurvatureContinuous(evaluated.brep)
    }

    @Test(.timeLimit(.minutes(4)))
    func anIcosahedronsFiveFoldCornersAreCurvatureContinuous() throws {
        let s = 0.01
        let phi = (1 + 5.0.squareRoot()) / 2
        var positions: [Point3D] = []
        for a in [-1.0, 1.0] {
            for b in [-phi, phi] {
                positions += [Point3D(x: 0, y: a * s, z: b * s), Point3D(x: a * s, y: b * s, z: 0), Point3D(x: b * s, y: 0, z: a * s)]
            }
        }
        // Its faces: the triples two units apart pairwise, wound outward.
        var indices: [UInt32] = []
        let edge = 2 * s
        for i in positions.indices {
            for j in positions.indices where j > i && abs((positions[i] - positions[j]).length - edge) < 1e-9 {
                for k in positions.indices where k > j && abs((positions[i] - positions[k]).length - edge) < 1e-9
                    && abs((positions[j] - positions[k]).length - edge) < 1e-9 {
                    let (a, b, c) = (positions[i], positions[j], positions[k])
                    let center = (a - .origin) + (b - .origin) + (c - .origin)
                    indices += ((b - a).cross(c - a).dot(center) > 0 ? [i, j, k] : [i, k, j]).map(UInt32.init)
                }
            }
        }
        #expect(indices.count == 60)
        let (evaluated, _) = try evaluate(Mesh(positions: positions, indices: indices))
        #expect(capFaces(evaluated.brep) > 0)
        #expect(try evaluated.brep.volume(tolerance: .standard) > 0)
        try expectCurvatureContinuous(evaluated.brep)
    }

    @Test(.timeLimit(.minutes(4)))
    func aFanOfSixQuadsIsCurvatureContinuousAtItsCentre() throws {
        // Six quads around a raised centre, an open sheet: its centre of valence six capped.
        let s = 0.01
        var positions = [Point3D(x: 0, y: 0, z: 0.4 * s)]
        for k in 0..<6 {
            let spoke = Double(k) * Double.pi / 3
            positions.append(Point3D(x: s * cos(spoke), y: s * sin(spoke), z: 0))
            positions.append(Point3D(x: 1.5 * s * cos(spoke + Double.pi / 6), y: 1.5 * s * sin(spoke + Double.pi / 6), z: -0.2 * s))
        }
        var indices: [UInt32] = []
        for k in 0..<6 {
            let quad: [UInt32] = [0, UInt32(1 + 2 * k), UInt32(2 + 2 * k), UInt32(1 + 2 * ((k + 1) % 6))]
            indices += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
        }
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try builder.polySpline(sourceMesh: Mesh(positions: positions, indices: indices), options: PolySplineOptions(mergePatches: false))
        let model = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "poly")).brep
        try model.validate(level: .exact, tolerance: .standard)
        #expect(capFaces(model) == 6)
        try expectCurvatureContinuous(model)
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

    @Test(.timeLimit(.minutes(5)))
    func mergePatchesMakesOneFacePerRegularBlock() throws {
        // A cube cut into 2 × 2 quads a side, refined once to isolate its corners: unmerged, 96
        // patches; merged, the 24 cap patches stay faces of their own and the regular patches
        // between them join into blocks, the same solid.
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
        #expect(unmerged.faces.count == 96)
        #expect(capFaces(unmerged) == 24 && capFaces(merged) == 24)
        #expect(merged.faces.count < unmerged.faces.count)
        // Each merged block is the uniform bicubic B-spline over regular patches: every joint
        // knot comes down to a simple one.
        let blocks = merged.faces.values.compactMap { face -> BSplineSurface3D? in
            if case let .bSpline(surface)? = merged.geometry.surfaces[face.surfaceID], surface.uDegree == 3 { return surface }
            return nil
        }
        func simple(_ knots: [Double]) -> Bool {
            let inner = knots.dropFirst(4).dropLast(4)
            return Set(inner).allSatisfy { knot in inner.filter { $0 == knot }.count == 1 }
        }
        #expect(blocks.isEmpty == false)
        #expect(blocks.allSatisfy { simple($0.uKnots) && simple($0.vKnots) })
        try expectCurvatureContinuous(merged)
        let volumes = try (unmerged.volume(tolerance: .standard), merged.volume(tolerance: .standard))
        #expect(abs(volumes.0 - volumes.1) < 1e-12, "\(volumes)")
    }
}
