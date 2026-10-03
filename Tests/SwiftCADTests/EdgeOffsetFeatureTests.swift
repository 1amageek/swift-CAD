import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Offset Edge and Offset Face Loop imprint edges offset over faces: cut where neighbouring offsets
/// cross, joined where they part, carried to the face's boundary where a chain stops, and over the
/// surface on curved faces.
@Suite("Edge offset")
struct EdgeOffsetFeatureTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "offset"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func body(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> Body {
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: "body", ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
        }
        return body
    }

    private func faces(of body: Body, in evaluated: EvaluatedDocument) -> [FaceID] {
        body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }
    }

    /// The face of `feature` whose plane faces along `normal`.
    private func face(of feature: FeatureID, facing normal: Vector3D, in evaluated: EvaluatedDocument, builder: DocumentBuilder) throws -> StableSubshapeReference {
        let key = try #require(evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return (face.orientation == .forward ? plane.normal : plane.normal * -1).dot(normal) > 0.99
        }.keys.sorted().first)
        return try builder.stableSubshape(key)
    }

    /// The edges of `feature` whose midpoints `keep` accepts.
    private func edges(of feature: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder, where keep: (Point3D) -> Bool) throws -> [StableSubshapeReference] {
        var result: [StableSubshapeReference] = []
        for (key, value) in evaluated.subshapes.entries.sorted(by: { $0.key < $1.key }) {
            guard key.featureID == feature, case let .edge(edgeID) = value, let edge = evaluated.brep.edges[edgeID],
                  let curve = evaluated.brep.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            if keep(try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: .standard)) {
                result.append(try builder.stableSubshape(key))
            }
        }
        return result
    }

    private func bounds(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> (minimum: Point3D, maximum: Point3D) {
        let box = try BRepBodyBoundingBoxBuilder().bounds(for: try body(of: featureID, in: evaluated).id, in: evaluated.brep, tolerance: .standard)
        return (box.minimum, box.maximum)
    }

    // MARK: Offset Edge

    @Test(.timeLimit(.minutes(2)))
    func anEdgeOffsetAcrossItsFaceReachesTheFacesSides() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try evaluate(builder)
        let extent = try bounds(of: box, in: before)
        let top = try face(of: box, facing: .unitZ, in: before, builder: builder)
        let front = try edges(of: box, in: before, builder: builder) { abs($0.z - extent.maximum.z) < 1e-9 && abs($0.y - extent.minimum.y) < 1e-9 }
        #expect(front.count == 1)
        let offset = try builder.edgeOffset(target: box, edges: front, supportFaces: [top], distance: length(0.004))
        let evaluated = try evaluate(builder)
        let solid = try body(of: offset, in: evaluated)
        #expect(faces(of: solid, in: evaluated).count == 7)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
        // The new edge runs 4 mm in from the front, across the whole top.
        #expect(evaluated.brep.vertices.values.filter { abs($0.point.y - (extent.minimum.y + 0.004)) < 1e-9 && abs($0.point.z - extent.maximum.z) < 1e-9 }.count == 2)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSymmetricEdgeOffsetGoesOverBothFaces() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try evaluate(builder)
        let extent = try bounds(of: box, in: before)
        let top = try face(of: box, facing: .unitZ, in: before, builder: builder)
        let front = try edges(of: box, in: before, builder: builder) { abs($0.z - extent.maximum.z) < 1e-9 && abs($0.y - extent.minimum.y) < 1e-9 }
        let offset = try builder.edgeOffset(target: box, edges: front, supportFaces: [top], distance: length(0.004), isSymmetric: true)
        let evaluated = try evaluate(builder)
        #expect(faces(of: try body(of: offset, in: evaluated), in: evaluated).count == 8)
    }

    /// Plasticity's chain across a top and a slope: the edges between the front wall and the top
    /// and the slope offset over both faces at once, each over the one it bounds.
    @Test(.timeLimit(.minutes(2)))
    func aChainAcrossATopAndASlopeOffsetsOverBoth() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A prism along y over a section with a flat top (x 0…0.06) sloping down to x = 0.1; on
        // the ZX plane sketch x is world z and sketch y world x.
        let corners: [(x: Double, z: Double)] = [(0, 0), (0.1, 0), (0.1, 0.05), (0.06, 0.1), (0, 0.1)]
        let profile = try builder.sketch(on: .zx) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: SketchPoint(x: length(a.z), y: length(a.x)), to: SketchPoint(x: length(b.z), y: length(b.x)))
            }
        }
        let prism = try builder.extrude(profile, distance: length(0.1))
        let before = try evaluate(builder)
        let top = try face(of: prism, facing: .unitZ, in: before, builder: builder)
        let slope = try face(of: prism, facing: try Vector3D(x: 0.05, y: 0, z: 0.04).normalized(tolerance: 1e-12), in: before, builder: builder)
        // The front wall's top and sloped edges, at y = 0.
        let chain = try edges(of: prism, in: before, builder: builder) { abs($0.y) < 1e-9 && $0.z > 0.05 + 1e-9 }
        #expect(chain.count == 2)
        var refused = builder
        let offset = try builder.edgeOffset(target: prism, edges: chain, supportFaces: [top, slope], distance: length(0.01))
        let evaluated = try evaluate(builder)
        let solid = try body(of: offset, in: evaluated)
        // The top and the slope are each split: 7 faces become 9; the solid is unchanged.
        #expect(faces(of: solid, in: evaluated).count == 9)
        let area = 0.1 * 0.05 + 0.06 * 0.05 + 0.5 * 0.04 * 0.05
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - area * 0.1) < 1e-12)
        // Over the top alone, the sloped edge bounds no support face and is refused.
        _ = try refused.edgeOffset(target: prism, edges: chain, supportFaces: [top], distance: length(0.01))
        #expect(throws: (any Error).self) { _ = try evaluate(refused) }
    }

    // MARK: Offset Face Loop

    @Test(.timeLimit(.minutes(2)))
    func aFaceLoopOffsetGoesInwardOutwardOrBoth() throws {
        for (offsetSide, expected) in [(FaceLoopOffsetSide.inward, 7), (.outward, 10), (.symmetric, 11)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let box = try builder.box(width: length(side), depth: length(side), height: length(side))
            let top = try face(of: box, facing: .unitZ, in: try evaluate(builder), builder: builder)
            let offset = try builder.faceLoopOffset(target: box, faces: [top], distance: length(0.004), side: offsetSide)
            let evaluated = try evaluate(builder)
            let solid = try body(of: offset, in: evaluated)
            #expect(faces(of: solid, in: evaluated).count == expected)
            #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
        }
    }

    /// An L-shaped slab, whose top has one reflex corner where inward offsets part.
    private func lSlab(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            let points = [(0.0, 0.0), (0.04, 0.0), (0.04, 0.02), (0.02, 0.02), (0.02, 0.04), (0.0, 0.04)]
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                _ = sketch.line(
                    from: SketchPoint(x: length(a.0), y: length(a.1)),
                    to: SketchPoint(x: length(b.0), y: length(b.1))
                )
            }
        }
        return try builder.extrude(profile, distance: length(0.01))
    }

    /// An L-shaped slab whose lower arm's top is an arc about (0.03, 0), meeting the upper arm's
    /// side at the reflex corner (0.02, 0.02).
    private func arcSlab(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            let points = [(0.02, 0.02), (0.02, 0.04), (0.0, 0.04), (0.0, 0.0), (0.04, 0.0), (0.04, 0.02)]
            for index in 0..<(points.count - 1) {
                let a = points[index], b = points[index + 1]
                _ = sketch.line(from: SketchPoint(x: length(a.0), y: length(a.1)), to: SketchPoint(x: length(b.0), y: length(b.1)))
            }
            let radius = (0.01 * 0.01 + 0.02 * 0.02).squareRoot()
            _ = sketch.arc(center: SketchPoint(x: length(0.03), y: length(0)), radius: length(radius),
                           startAngle: .constant(.angle(atan2(0.02, 0.01), unit: .radian)),
                           endAngle: .constant(.angle(atan2(0.02, -0.01), unit: .radian)))
        }
        return try builder.extrude(profile, distance: length(0.01))
    }

    @Test(.timeLimit(.minutes(2)))
    func naturalCarriesACurvedOffsetOnAlongItsCircle() throws {
        var counts: [OffsetGapFill: Int] = [:]
        var corners: [Point3D] = []
        for gapFill in [OffsetGapFill.round, .natural] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let slab = try arcSlab(&builder)
            let before = try evaluate(builder)
            let extent = try bounds(of: slab, in: before)
            let up = extent.maximum.z > 0
            let top = try face(of: slab, facing: up ? .unitZ : .unitZ * -1, in: before, builder: builder)
            let offset = try builder.faceLoopOffset(target: slab, faces: [top], distance: length(0.004), gapFill: gapFill)
            let evaluated = try evaluate(builder)
            let solid = try body(of: offset, in: evaluated)
            #expect(faces(of: solid, in: evaluated).count == 9)
            counts[gapFill] = evaluated.brep.edges.count
            if gapFill == .natural {
                corners = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - (up ? extent.maximum.z : extent.minimum.z)) < 1e-9 }
            }
        }
        // Natural adds no edge at the reflex corner: the arc's offset runs on along its own circle
        // (radius r − 0.004 about (0.03, 0)) and the side's offset (x = 0.016) down to their meeting.
        #expect(counts[.natural] == (counts[.round] ?? 0) - 1)
        let radius = (0.01 * 0.01 + 0.02 * 0.02).squareRoot() - 0.004
        let meeting = (x: 0.016, y: (radius * radius - 0.014 * 0.014).squareRoot())
        #expect(corners.contains { hypot($0.x - meeting.x, $0.y - meeting.y) < 1e-5 },
                "No corner at the meeting \(meeting) among \(corners.map { ($0.x, $0.y) })")
    }

    @Test(.timeLimit(.minutes(2)))
    func gapFillJoinsOffsetsThatPartAtAReflexCorner() throws {
        var counts: [OffsetGapFill: Int] = [:]
        for gapFill in [OffsetGapFill.round, .linear, .natural] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let slab = try lSlab(&builder)
            let before = try evaluate(builder)
            let extent = try bounds(of: slab, in: before)
            let top = try face(of: slab, facing: extent.maximum.z > 0 ? .unitZ : .unitZ * -1, in: before, builder: builder)
            let offset = try builder.faceLoopOffset(target: slab, faces: [top], distance: length(0.004), gapFill: gapFill)
            let evaluated = try evaluate(builder)
            let solid = try body(of: offset, in: evaluated)
            #expect(faces(of: solid, in: evaluated).count == 9)
            counts[gapFill] = evaluated.brep.edges.count
        }
        // The reflex corner's gap is one arc (Round), two lines meeting where the offsets would
        // (Linear), or the offsets themselves run on to that point, adding no edge (Natural).
        #expect(counts[.linear] == (counts[.round] ?? 0) + 1)
        #expect(counts[.natural] == (counts[.round] ?? 0) - 1)
    }

    @Test(.timeLimit(.minutes(2)))
    func anEdgeOffsetFollowsACurvedFace() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let drum = try builder.cylinder(radius: length(side / 2), height: length(side))
        let before = try evaluate(builder)
        let extent = try bounds(of: drum, in: before)
        let sideKey = try #require(before.subshapes.entries.filter { key, value in
            guard key.featureID == drum, case let .face(faceID) = value, let face = before.brep.faces[faceID] else { return false }
            if case .plane = before.brep.geometry.surfaces[face.surfaceID] { return false }
            return true
        }.keys.sorted().first)
        // The side's own edges along the top rim.
        guard case let .face(sideFaceID) = before.subshapes[sideKey], let sideFace = before.brep.faces[sideFaceID] else {
            Issue.record("The side face is missing.")
            return
        }
        let sideEdges = Set(sideFace.loops.flatMap { before.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] })
        var rim: [StableSubshapeReference] = []
        for (key, value) in before.subshapes.entries.sorted(by: { $0.key < $1.key }) {
            guard key.featureID == drum, case let .edge(edgeID) = value, sideEdges.contains(edgeID),
                  let edge = before.brep.edges[edgeID], let curve = before.brep.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            if abs(try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: .standard).z - extent.maximum.z) < 1e-9 {
                rim.append(try builder.stableSubshape(key))
            }
        }
        #expect(rim.isEmpty == false)
        let offset = try builder.edgeOffset(target: drum, edges: rim, supportFaces: [try builder.stableSubshape(sideKey)], distance: length(0.005))
        let evaluated = try evaluate(builder)
        let solid = try body(of: offset, in: evaluated)
        #expect(faces(of: solid, in: evaluated).count == faces(of: try body(of: drum, in: before), in: before).count + 1)
        // Every new vertex lies on the side, 5 mm below the rim.
        let below = evaluated.brep.vertices.values.filter { abs($0.point.z - (extent.maximum.z - 0.005)) < 1e-6 }
        #expect(below.isEmpty == false)
    }

    @Test(.timeLimit(.minutes(2)))
    func theNativePackageKeepsBothOffsets() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try evaluate(builder)
        let extent = try bounds(of: box, in: before)
        let top = try face(of: box, facing: .unitZ, in: before, builder: builder)
        let front = try edges(of: box, in: before, builder: builder) { abs($0.z - extent.maximum.z) < 1e-9 && abs($0.y - extent.minimum.y) < 1e-9 }
        let edgeOffset = try builder.edgeOffset(target: box, edges: front, supportFaces: [top], distance: length(0.004), isSymmetric: true, gapFill: .natural)
        let loopOffset = try builder.faceLoopOffset(target: box, faces: [top], distance: length(0.002), side: .outward, gapFill: .linear, isIndividual: false)
        let document = try builder.build(name: "offset persistence")
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        for id in [edgeOffset, loopOffset] {
            #expect(loaded.designGraph.nodes[id]?.operation == document.designGraph.nodes[id]?.operation)
        }
    }
}
