import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Extract copies one component of a body, or chosen faces, as a body of its own beside the
/// source, which stays as it is.
@Suite("Extract")
struct ExtractFeatureTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let cube = 0.02 * 0.02 * 0.02

    /// A 20 mm cube sliced in two by a horizontal sheet 5 mm up.
    private func slicedCube() throws -> (builder: DocumentBuilder, box: FeatureID, slice: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let plain = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: try #require(plain.brep.bodies.keys.first), in: plain.brep, tolerance: .standard)
        let z = bounds.minimum.z + 0.005
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [-1.0, 1.0].map { y in [-1.0, 1.0].map { Point3D(x: $0, y: y, z: z) } }
        ))
        let slice = try builder.boolean(targets: [box], tool: sheet, operation: .slice)
        return (builder, box, slice)
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "extract"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func bodyID(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> BodyID {
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: "body", ordinal: 0)] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
        }
        return bodyID
    }

    private func volume(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        try evaluated.brep.volume(of: try bodyID(of: featureID, in: evaluated), tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(2)))
    func eachComponentOfASliceBecomesItsOwnBody() throws {
        var fixture = try slicedCube()
        let first = try fixture.builder.extract(fixture.slice, selection: .component(index: 0, count: 2))
        let second = try fixture.builder.extract(fixture.slice, selection: .component(index: 1, count: 2))
        let evaluated = try evaluate(fixture.builder)
        // The two copies and the slice they came from.
        #expect(evaluated.brep.bodies.count == 3)
        let volumes = [try volume(of: first, in: evaluated), try volume(of: second, in: evaluated)]
        #expect(abs(volumes.reduce(0, +) - cube) < 1e-12)
        #expect(Set(volumes.map { ($0 / cube * 4).rounded() }) == [1, 3])
        #expect(abs(try volume(of: fixture.slice, in: evaluated) - cube) < 1e-12)
        #expect(evaluated.lineage.values.contains { $0.output.featureID == first && $0.parents.contains { $0.featureID == fixture.slice } })
        // The order is the same on every evaluation.
        let again = try evaluate(fixture.builder)
        #expect(abs(try volume(of: first, in: again) - volumes[0]) < 1e-15)
    }

    @Test(.timeLimit(.minutes(2)))
    func aChangedComponentCountIsRefused() throws {
        var fixture = try slicedCube()
        _ = try fixture.builder.extract(fixture.slice, selection: .component(index: 0, count: 3))
        #expect(throws: KernelError.self) { try evaluate(fixture.builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func chosenFacesBecomeASheet() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluatedBox = try evaluate(builder)
        let faces = try evaluatedBox.subshapes.entries.filter { key, value in
            guard key.featureID == box, case let .face(faceID) = value, let face = evaluatedBox.brep.faces[faceID],
                  case let .plane(plane) = evaluatedBox.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9
        }.keys.sorted().map { try builder.stableSubshape($0) }
        #expect(faces.count == 2)
        let lids = try builder.extract(box, selection: .faces(faces))
        let evaluated = try evaluate(builder)
        let lidBody = try #require(evaluated.brep.bodies[try bodyID(of: lids, in: evaluated)])
        #expect(lidBody.kind == .sheet)
        #expect(lidBody.shellIDs.count == 2)
        #expect(abs(try volume(of: box, in: evaluated) - cube) < 1e-12)
    }

    /// The stable references of `feature`'s faces that `keep` accepts.
    private func faces(
        of feature: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder,
        where keep: (Face) -> Bool = { _ in true }
    ) throws -> [StableSubshapeReference] {
        try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID] else { return false }
            return keep(face)
        }.keys.sorted().map { try builder.stableSubshape($0) }
    }

    @Test(.timeLimit(.minutes(2)))
    func everyFaceOfASolidClosesIntoASolid() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluatedBox = try evaluate(builder)
        let all = try faces(of: box, in: evaluatedBox, builder: builder)
        #expect(all.count == 6)
        #expect(try ExtractFaceClosure().closes(faces: all, source: box, in: evaluatedBox))
        #expect(try ExtractFaceClosure().closes(faces: Array(all.prefix(5)), source: box, in: evaluatedBox) == false)
        let copy = try builder.extract(box, selection: .solidFaces(all))
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies[try bodyID(of: copy, in: evaluated)]?.kind == .solid)
        #expect(abs(try volume(of: copy, in: evaluated) - cube) < 1e-12)
        #expect(abs(try volume(of: box, in: evaluated) - cube) < 1e-12)
    }

    /// Five faces of a box: the one face left cannot grow over them, so they bound nothing.
    @Test(.timeLimit(.minutes(2)))
    func facesThatDoNotCloseAreRefusedAsASolid() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let some = try Array(faces(of: box, in: try evaluate(builder), builder: builder).prefix(5))
        #expect(try ExtractFaceClosure().makesSolid(faces: some, source: box, in: try evaluate(builder)) == false)
        _ = try builder.extract(box, selection: .solidFaces(some))
        #expect(throws: KernelError.self) { try evaluate(builder) }
    }

    /// Plasticity's Alternative Duplicate: a round pocket's wall and floor do not close, so they
    /// make the plug filling the pocket, capped by the top it was cut into; the block stays as it
    /// is. A 20 mm cube with a 6 mm wide, 4 mm deep pocket: a plug of π · 3² · 4 mm³.
    @Test(.timeLimit(.minutes(2)))
    func aPocketsFacesMakeThePlugFillingIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cube = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let top = try #require(try evaluate(builder).brep.vertices.values.map(\.point.z).max())
        let center = try evaluate(builder).brep.vertices.values.reduce(Vector3D.zero) { $0 + ($1.point - .origin) } * 0.125
        let floor = top - 0.004
        let drill = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: center.x, y: center.y, z: floor), axis: .unitZ, referenceDirection: .unitX),
            radius: length(0.003), height: length(0.008)
        )
        let pocketed = try builder.boolean(targets: [cube], tool: drill, operation: .difference)
        let before = try evaluate(builder)
        func inPocket(_ faceID: FaceID) -> Bool {
            guard let face = before.brep.faces[faceID] else { return false }
            if case .cylinder = before.brep.geometry.surfaces[face.surfaceID] { return true }
            let heights = face.loops.flatMap { before.brep.loops[$0]?.coedges ?? [] }.compactMap { coedge in
                before.brep.edges[coedge.edgeID].flatMap { before.brep.vertices[$0.startVertexID]?.point.z }
            }
            return heights.isEmpty == false && heights.allSatisfy { abs($0 - floor) < 1e-9 }
        }
        let pocket = try before.subshapes.entries.filter { key, value in
            guard key.featureID == pocketed, case let .face(faceID) = value else { return false }
            return inPocket(faceID)
        }.keys.sorted().map { try builder.stableSubshape($0) }
        #expect(pocket.count >= 2)
        #expect(try ExtractFaceClosure().closes(faces: pocket, source: pocketed, in: before) == false)
        #expect(try ExtractFaceClosure().makesSolid(faces: pocket, source: pocketed, in: before))
        let plug = try builder.extract(pocketed, selection: .solidFaces(pocket))
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies[try bodyID(of: plug, in: evaluated)]?.kind == .solid)
        let expected = Double.pi * 0.003 * 0.003 * 0.004
        let plugVolume = try volume(of: plug, in: evaluated)
        #expect(abs(plugVolume - expected) < 1e-11, "\(plugVolume) vs \(expected)")
        #expect(abs(try volume(of: pocketed, in: evaluated) - (0.02 * 0.02 * 0.02 - expected)) < 1e-11)
    }

    /// A boss's wall and top do not close either: they make the block standing on the face they
    /// rise from, its base the top of the cube under it. A 6 mm wide, 4 mm high round boss.
    @Test(.timeLimit(.minutes(2)))
    func aBosssFacesMakeTheBlockItStandsAs() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cube = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let top = try #require(try evaluate(builder).brep.vertices.values.map(\.point.z).max())
        let center = try evaluate(builder).brep.vertices.values.reduce(Vector3D.zero) { $0 + ($1.point - .origin) } * 0.125
        let post = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: center.x, y: center.y, z: top - 0.001), axis: .unitZ, referenceDirection: .unitX),
            radius: length(0.003), height: length(0.005)
        )
        let bossed = try builder.boolean(targets: [cube], tool: post, operation: .union)
        let before = try evaluate(builder)
        func onBoss(_ faceID: FaceID) -> Bool {
            guard let face = before.brep.faces[faceID] else { return false }
            if case .cylinder = before.brep.geometry.surfaces[face.surfaceID] { return true }
            let heights = face.loops.flatMap { before.brep.loops[$0]?.coedges ?? [] }.compactMap { coedge in
                before.brep.edges[coedge.edgeID].flatMap { before.brep.vertices[$0.startVertexID]?.point.z }
            }
            return heights.isEmpty == false && heights.allSatisfy { abs($0 - (top + 0.004)) < 1e-9 }
        }
        let boss = try before.subshapes.entries.filter { key, value in
            guard key.featureID == bossed, case let .face(faceID) = value else { return false }
            return onBoss(faceID)
        }.keys.sorted().map { try builder.stableSubshape($0) }
        #expect(boss.count >= 2)
        let block = try builder.extract(bossed, selection: .solidFaces(boss))
        let evaluated = try evaluate(builder)
        let expected = Double.pi * 0.003 * 0.003 * 0.004
        let blockVolume = try volume(of: block, in: evaluated)
        #expect(abs(blockVolume - expected) < 1e-11, "\(blockVolume) vs \(expected)")
        #expect(abs(try volume(of: bossed, in: evaluated) - (0.02 * 0.02 * 0.02 + expected)) < 1e-11)
    }

    /// A notch's wall and ledge (Plasticity's Alternative Duplicate video): the block filling the
    /// notch, bounded by the top and the front grown back over it. A 20 mm cube notched 5 mm deep
    /// and 4 mm down along one top edge: a block of 20 · 5 · 4 mm³.
    @Test(.timeLimit(.minutes(2)))
    func aNotchsWallAndLedgeMakeTheBlockFillingIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cube = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let corners = try evaluate(builder).brep.vertices.values.map(\.point)
        let (x0, y0, top) = (try #require(corners.map(\.x).min()), try #require(corners.map(\.y).min()), try #require(corners.map(\.z).max()))
        // Where a box's placement origin lies on it, measured on a box of its own.
        var probe = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try probe.box(width: length(0.024), depth: length(0.006), height: length(0.005))
        let probeCorners = try evaluate(probe).brep.vertices.values.map(\.point)
        let lowCorner = Vector3D(x: try #require(probeCorners.map(\.x).min()), y: try #require(probeCorners.map(\.y).min()), z: try #require(probeCorners.map(\.z).min()))
        let cutter = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: x0 - 0.002 - lowCorner.x, y: y0 - 0.001 - lowCorner.y, z: top - 0.004 - lowCorner.z), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.024), depth: length(0.006), height: length(0.005)
        )
        let notched = try builder.boolean(targets: [cube], tool: cutter, operation: .difference)
        let before = try evaluate(builder)
        let notch = try before.subshapes.entries.filter { key, value in
            guard key.featureID == notched, case let .face(faceID) = value, let face = before.brep.faces[faceID] else { return false }
            let points = face.loops.flatMap { before.brep.loops[$0]?.coedges ?? [] }
                .compactMap { before.brep.edges[$0.edgeID].flatMap { before.brep.vertices[$0.startVertexID]?.point } }
            return points.allSatisfy { abs($0.y - (y0 + 0.005)) < 1e-9 } || points.allSatisfy { abs($0.z - (top - 0.004)) < 1e-9 }
        }.keys.sorted().map { try builder.stableSubshape($0) }
        #expect(notch.count == 2)
        #expect(try ExtractFaceClosure().makesSolid(faces: notch, source: notched, in: before))
        let block = try builder.extract(notched, selection: .solidFaces(notch))
        let evaluated = try evaluate(builder)
        let expected = 0.02 * 0.005 * 0.004
        let blockVolume = try volume(of: block, in: evaluated)
        #expect(abs(blockVolume - expected) < 1e-11, "\(blockVolume) vs \(expected)")
        #expect(abs(try volume(of: notched, in: evaluated) - (0.02 * 0.02 * 0.02 - expected)) < 1e-11)
    }

    /// A 20 mm cube with a 10 mm cavity: its cavity's faces alone are a solid of the cavity's
    /// shape, and all its faces the cube with its cavity.
    @Test(.timeLimit(.minutes(2)))
    func aCavityAloneIsASolidOfItsShapeAndWithItsOuterShellKeepsIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let outer = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let inner = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0.005, y: 0.005, z: 0.005), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.01), depth: length(0.01), height: length(0.01)
        )
        let hollow = try builder.boolean(targets: [outer], tool: inner, operation: .difference)
        let evaluatedHollow = try evaluate(builder)
        let body = try #require(evaluatedHollow.brep.bodies[try bodyID(of: hollow, in: evaluatedHollow)])
        let voidShell = try #require(body.solidComponents?.first?.voidShellIDs.first)
        let voidFaces = Set(evaluatedHollow.brep.shells[voidShell]?.faceIDs ?? [])
        let cavityFaces = try faces(of: hollow, in: evaluatedHollow, builder: builder) { voidFaces.contains($0.id) }
        let all = try faces(of: hollow, in: evaluatedHollow, builder: builder)
        #expect(cavityFaces.count == 6 && all.count == 12)
        let cavity = try builder.extract(hollow, selection: .solidFaces(cavityFaces))
        let whole = try builder.extract(hollow, selection: .solidFaces(all))
        let evaluated = try evaluate(builder)
        #expect(abs(try volume(of: cavity, in: evaluated) - 0.001 * 0.001) < 1e-12)
        #expect(abs(try volume(of: whole, in: evaluated) - (cube - 1e-6)) < 1e-12)
    }

    @Test func theFeatureRoundTripsAndRefusesMalformedSelections() throws {
        let feature = ExtractFeature(target: PatternTargetReference(featureID: FeatureID()), selection: .component(index: 1, count: 2))
        #expect(try JSONDecoder().decode(ExtractFeature.self, from: JSONEncoder().encode(feature)) == feature)
        #expect(throws: FeatureEvaluationError.self) { try ExtractSelection.component(index: 2, count: 2).validate() }
        #expect(throws: FeatureEvaluationError.self) { try ExtractSelection.faces([]).validate() }
        #expect(try feature.resultPort(sourcePort: .sheet) == .sheet)
        #expect(try feature.resultPort(sourcePort: .body) == .body)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let face = try #require(try faces(of: box, in: try evaluate(builder), builder: builder).first)
        let solid = ExtractFeature(target: PatternTargetReference(featureID: box), selection: .solidFaces([face]))
        #expect(try JSONDecoder().decode(ExtractFeature.self, from: JSONEncoder().encode(solid)) == solid)
        #expect(try solid.resultPort(sourcePort: .body) == .body)
        #expect(throws: FeatureEvaluationError.self) { try solid.resultPort(sourcePort: .sheet) }
    }

    @Test(.timeLimit(.minutes(2)))
    func theNativePackageKeepsExtractions() throws {
        var fixture = try slicedCube()
        let piece = try fixture.builder.extract(fixture.slice, selection: .component(index: 1, count: 2))
        let document = try fixture.builder.build(name: "extract package")
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        guard case let .extract(extract) = loaded.designGraph.nodes[piece]?.operation else {
            Issue.record("The native package must keep the extraction.")
            return
        }
        #expect(extract.selection == .component(index: 1, count: 2))
        #expect(loaded.designGraph.nodes[piece]?.outputs.map(\.role) == [.body])
    }
}
