import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Imprinting splits faces along curves that lie on them, keeping every piece and the body's
/// kind: parameter lines (Isoparam), a tool's crossing (Imprint Body Body), and an untrimmed
/// face's own boundary (Untrim).
@Suite("Imprint")
struct ImprintFeatureTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "imprint"))
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

    private func faceCount(_ body: Body, in evaluated: EvaluatedDocument) -> Int {
        body.shellIDs.reduce(0) { $0 + (evaluated.brep.shells[$1]?.faceIDs.count ?? 0) }
    }

    private func bounds(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> (minimum: Point3D, maximum: Point3D) {
        let box = try BRepBodyBoundingBoxBuilder().bounds(for: try body(of: featureID, in: evaluated).id, in: evaluated.brep, tolerance: .standard)
        return (box.minimum, box.maximum)
    }

    /// The stable reference of the face of `feature` whose plane faces along `normal`.
    private func face(of feature: FeatureID, facing normal: Vector3D, in evaluated: EvaluatedDocument, builder: DocumentBuilder) throws -> StableSubshapeReference {
        let key = try #require(evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            let outward = face.orientation == .forward ? plane.normal : plane.normal * -1
            return outward.dot(normal) > 0.99
        }.keys.sorted().first)
        return try builder.stableSubshape(key)
    }

    private func bilinear(_ builder: inout DocumentBuilder, domain: SurfaceParameterDomain2D? = nil) throws -> FeatureID {
        try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: side, y: 0, z: 0)],
                            [Point3D(x: 0, y: side, z: 0.005), Point3D(x: side, y: side, z: 0)]]
        ), parameterDomain: domain)
    }

    private func onlyFace(of featureID: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder) throws -> StableSubshapeReference {
        let key = try #require(evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == featureID, case .face = value else { return false }
            return true
        }.keys.sorted().first)
        return try builder.stableSubshape(key)
    }

    // MARK: Isoparam

    @Test(.timeLimit(.minutes(2)))
    func isoparamSplitsASheetAlongItsParameterLines() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try bilinear(&builder)
        let face = try onlyFace(of: sheet, in: try evaluate(builder), builder: builder)
        let lines = try builder.isoparam(sheet, face: face, direction: .u, fractions: [0.25, 0.5])
        let evaluated = try evaluate(builder)
        let split = try body(of: lines, in: evaluated)
        #expect(split.kind == .sheet)
        #expect(faceCount(split, in: evaluated) == 3)
        // Two sides split in three, two sides whole, two new lines.
        #expect(evaluated.brep.edges.count == 10)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test(.timeLimit(.minutes(2)))
    func isoparamOnASolidsFaceSplitsItsNeighboursEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try evaluate(builder)
        let top = try face(of: box, facing: .unitZ, in: before, builder: builder)
        let lines = try builder.isoparam(box, face: top, direction: .v, fractions: [0.5])
        let evaluated = try evaluate(builder)
        let solid = try body(of: lines, in: evaluated)
        #expect(solid.kind == .solid)
        #expect(faceCount(solid, in: evaluated) == 7)
        // The line and the two halves of the edges it meets on the neighbouring sides.
        #expect(evaluated.brep.edges.count == 12 + 1 + 2)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func isoparamSubdividesAControlNetWithoutChangingItsShape() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try bilinear(&builder)
        let sheetFace = try onlyFace(of: sheet, in: try evaluate(builder), builder: builder)
        let lines = try builder.isoparam(sheet, face: sheetFace, direction: .u, fractions: [0.5], subdividesControlNet: true)
        let evaluated = try evaluate(builder)
        let split = try body(of: lines, in: evaluated)
        #expect(faceCount(split, in: evaluated) == 2)
        let surfaces = Set(split.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }.compactMap { evaluated.brep.faces[$0]?.surfaceID })
        for surfaceID in surfaces {
            guard case let .bSpline(spline) = try #require(evaluated.brep.geometry.surfaces[surfaceID]) else {
                Issue.record("The subdivided surface stays a B-spline.")
                continue
            }
            #expect(spline.uKnots.filter { abs($0 - 0.5) < 1e-12 }.count == 1)
            #expect(abs(try spline.point(u: 0.3, v: 0.7, tolerance: .standard).z - 0.005 * 0.7 * 0.7) < 1e-12)
        }
        var planar = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try planar.box(width: length(side), depth: length(side), height: length(side))
        let top = try face(of: box, facing: .unitZ, in: try evaluate(planar), builder: planar)
        _ = try planar.isoparam(box, face: top, direction: .u, fractions: [0.5], subdividesControlNet: true)
        #expect(throws: KernelError.self) { try evaluate(planar) }
    }

    // MARK: Imprint Body Body

    @Test(.timeLimit(.minutes(2)))
    func aCrossingToolImprintsItsOutlineAndStaysAsItIs() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let target = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try evaluate(builder)
        let targetBounds = try bounds(of: target, in: before)
        // A smaller box standing through the target's top, centred on it: measured where it is
        // built, then placed so its centre is at the middle of the top.
        var probe = DocumentBuilder(units: .meters, tolerance: .standard)
        let probed = try probe.box(width: length(side / 2), depth: length(side / 2), height: length(side))
        let probeBounds = try bounds(of: probed, in: try evaluate(probe))
        let tool = try builder.box(
            placement: PrimitivePlacement(
                origin: Point3D(
                    x: (targetBounds.minimum.x + targetBounds.maximum.x) / 2 - (probeBounds.minimum.x + probeBounds.maximum.x) / 2,
                    y: (targetBounds.minimum.y + targetBounds.maximum.y) / 2 - (probeBounds.minimum.y + probeBounds.maximum.y) / 2,
                    z: targetBounds.maximum.z - (probeBounds.minimum.z + probeBounds.maximum.z) / 2
                ),
                axis: .unitZ, referenceDirection: .unitX
            ),
            width: length(side / 2), depth: length(side / 2), height: length(side)
        )
        let imprinted = try builder.imprintBody(target, tool: tool)
        let evaluated = try evaluate(builder)
        let solid = try body(of: imprinted, in: evaluated)
        // The top gains the tool's square as a face of its own.
        #expect(faceCount(solid, in: evaluated) == 7)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
        let toolBody = try body(of: tool, in: evaluated)
        #expect(faceCount(toolBody, in: evaluated) == 6)
        #expect(evaluated.brep.bodies.count == 2)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetEndingInsideAFaceNeedsEdgeCompletion() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let target = try builder.box(width: length(side), depth: length(side), height: length(side))
        let targetBounds = try bounds(of: target, in: try evaluate(builder))
        let midX = (targetBounds.minimum.x + targetBounds.maximum.x) / 2
        let top = targetBounds.maximum.z
        // A vertical sheet crossing the top from one side to its middle only.
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: midX, y: targetBounds.minimum.y - side, z: top - side / 4),
                             Point3D(x: midX, y: (targetBounds.minimum.y + targetBounds.maximum.y) / 2, z: top - side / 4)],
                            [Point3D(x: midX, y: targetBounds.minimum.y - side, z: top + side / 4),
                             Point3D(x: midX, y: (targetBounds.minimum.y + targetBounds.maximum.y) / 2, z: top + side / 4)]]
        ))
        var none = builder
        _ = try none.imprintBody(target, tool: sheet, completion: .none)
        #expect(throws: KernelError.self) { try evaluate(none) }
        let completed = try builder.imprintBody(target, tool: sheet, completion: .edge)
        let evaluated = try evaluate(builder)
        let solid = try body(of: completed, in: evaluated)
        // The top is cut across; the front face is cut from its top edge down to where the sheet stops,
        // and carried on down to its bottom edge.
        #expect(faceCount(solid, in: evaluated) == 8)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    // MARK: Imprint Curve Body

    private func sketchPoint(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
    }

    /// A box lifted clear of the XY plane, and its bounds.
    private func liftedBox(_ builder: inout DocumentBuilder) throws -> (FeatureID, (minimum: Point3D, maximum: Point3D)) {
        let box = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: 0.05), axis: .unitZ, referenceDirection: .unitX),
            width: length(side), depth: length(side), height: length(side)
        )
        return (box, try bounds(of: box, in: try evaluate(builder)))
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurveSweptThroughASolidImprintsWhatItCrossesOrOnlyWhatItSeesFirst() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, extent) = try liftedBox(&builder)
        let midX = (extent.minimum.x + extent.maximum.x) / 2
        // A line under the box, longer than it, swept up through it.
        let sketch = try builder.sketch(on: .xy, named: "Line") { sketch in
            _ = sketch.line(from: sketchPoint(midX, extent.minimum.y - side), to: sketchPoint(midX, extent.maximum.y + side))
        }
        var through = builder
        let crossed = try through.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: false))
        let all = try evaluate(through)
        // Bottom, top and the two faces the line passes under are each cut in two.
        #expect(faceCount(try body(of: crossed, in: all), in: all) == 10)
        let seen = try builder.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: true))
        let first = try evaluate(builder)
        // Only the bottom, which the line meets first.
        #expect(faceCount(try body(of: seen, in: first), in: first) == 7)
        #expect(abs(try first.brep.volume(of: try body(of: seen, in: first).id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aShortCurveReachesTheEdgesOnlyWithCompletion() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, extent) = try liftedBox(&builder)
        let midX = (extent.minimum.x + extent.maximum.x) / 2
        let midY = (extent.minimum.y + extent.maximum.y) / 2
        let sketch = try builder.sketch(on: .xy, named: "Short") { sketch in
            _ = sketch.line(from: sketchPoint(midX, midY - side / 4), to: sketchPoint(midX, midY + side / 4))
        }
        var bare = builder
        _ = try bare.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: true), completion: .none)
        #expect(throws: KernelError.self) { try evaluate(bare) }
        let completed = try builder.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: true), completion: .edge)
        let evaluated = try evaluate(builder)
        #expect(faceCount(try body(of: completed, in: evaluated), in: evaluated) == 7)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurveProjectedAlongTheNormalLandsOnTheNearestFace() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, extent) = try liftedBox(&builder)
        let midX = (extent.minimum.x + extent.maximum.x) / 2
        let midY = (extent.minimum.y + extent.maximum.y) / 2
        // A circle under the box lands on its bottom as a disc.
        let sketch = try builder.sketch(on: .xy, named: "Circle") { sketch in
            _ = sketch.circle(center: sketchPoint(midX, midY), radius: length(side / 4))
        }
        let imprinted = try builder.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))], projection: .normal)
        let evaluated = try evaluate(builder)
        let solid = try body(of: imprinted, in: evaluated)
        #expect(faceCount(solid, in: evaluated) == 7)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
        // Every new edge lies on the bottom, at the circle's radius from its centre.
        let bottom = extent.minimum.z
        var rim = 0
        for edge in evaluated.brep.edges.values {
            guard let curve = evaluated.brep.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            let point = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: .standard)
            let radius = ((point.x - midX) * (point.x - midX) + (point.y - midY) * (point.y - midY)).squareRoot()
            if abs(point.z - bottom) < 1e-9 && abs(radius - side / 4) < 1e-6 { rim += 1 }
        }
        #expect(rim == 2)
    }

    @Test(.timeLimit(.minutes(2)))
    func aPlacedToolAndAPlacedCurveImprintWhereTheyArePlaced() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, extent) = try liftedBox(&builder)
        let midX = (extent.minimum.x + extent.maximum.x) / 2
        let back = try RigidTransform3D(
            basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: Vector3D(x: -0.1, y: 0, z: 0), tolerance: .standard
        )
        // A line built a tenth of a metre away and placed back under the box.
        let far = try builder.sketch(on: .xy, named: "Far line") { sketch in
            _ = sketch.line(from: sketchPoint(midX + 0.1, extent.minimum.y - side), to: sketchPoint(midX + 0.1, extent.maximum.y + side))
        }
        var curveBuilder = builder
        let placedCurve = try curveBuilder.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: far.featureID), placement: back)],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: false))
        let curved = try evaluate(curveBuilder)
        #expect(faceCount(try body(of: placedCurve, in: curved), in: curved) == 10)
        // Unplaced, the same line misses the box.
        var missing = builder
        _ = try missing.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: far.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: false))
        #expect(throws: KernelError.self) { try evaluate(missing) }

        // A sheet built as far away and placed back across the box's top.
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: midX + 0.1, y: extent.minimum.y - side, z: extent.minimum.z - side), Point3D(x: midX + 0.1, y: extent.maximum.y + side, z: extent.minimum.z - side)],
                            [Point3D(x: midX + 0.1, y: extent.minimum.y - side, z: extent.maximum.z + side), Point3D(x: midX + 0.1, y: extent.maximum.y + side, z: extent.maximum.z + side)]]
        ))
        let placedTool = try builder.imprintBody(box, tool: sheet, toolPlacement: back)
        let tooled = try evaluate(builder)
        #expect(faceCount(try body(of: placedTool, in: tooled), in: tooled) == 10)
        // Nothing of the moved sheet is published.
        #expect(tooled.subshapes.entries.keys.allSatisfy { tooled.document.designGraph.nodes[$0.featureID] != nil })
    }

    @Test(.timeLimit(.minutes(2)))
    func aClosedCurveSweptOntoAFaceImprintsWhole() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, extent) = try liftedBox(&builder)
        let sketch = try builder.sketch(on: .xy, named: "Circle") { sketch in
            _ = sketch.circle(center: sketchPoint((extent.minimum.x + extent.maximum.x) / 2, (extent.minimum.y + extent.maximum.y) / 2), radius: length(side / 4))
        }
        let imprinted = try builder.imprintCurves(box, curves: [ImprintCurveReference(curve: CurveOutputReference(featureID: sketch.featureID))],
            projection: .vector(direction: .unitZ, bidirectional: false, hidesOcclusion: true))
        let evaluated = try evaluate(builder)
        let solid = try body(of: imprinted, in: evaluated)
        #expect(faceCount(solid, in: evaluated) == 7)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    // MARK: Untrim

    @Test(.timeLimit(.minutes(2)))
    func untrimSpansTheSurfacesDomainAndCanKeepTheFacesEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try bilinear(&builder, domain: SurfaceParameterDomain2D(uLowerBound: 0.25, uUpperBound: 0.75, vLowerBound: 0, vUpperBound: 1))
        let face = try onlyFace(of: sheet, in: try evaluate(builder), builder: builder)
        let bare = try builder.untrimFace(sheet, face: face)
        let kept = try builder.untrimFace(sheet, face: face, keepsEdges: true)
        let evaluated = try evaluate(builder)
        // The sheet stays; each untrimmed copy spans the whole domain.
        #expect(evaluated.brep.bodies.count == 3)
        #expect(faceCount(try body(of: bare, in: evaluated), in: evaluated) == 1)
        // The face's own sides at u = 0.25 and 0.75 are imprinted; its sides at v = 0 and 1 lie on
        // the sheet's edge already.
        #expect(faceCount(try body(of: kept, in: evaluated), in: evaluated) == 3)
    }

    @Test(.timeLimit(.minutes(2)))
    func untrimOfACylindersSideIsTheWholeBand() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let drum = try builder.cylinder(radius: length(side / 2), height: length(side))
        let before = try evaluate(builder)
        let sideKey = try #require(before.subshapes.entries.filter { key, value in
            guard key.featureID == drum, case let .face(faceID) = value, let face = before.brep.faces[faceID] else { return false }
            if case .plane = before.brep.geometry.surfaces[face.surfaceID] { return false }
            return true
        }.keys.sorted().first)
        let band = try builder.untrimFace(drum, face: try builder.stableSubshape(sideKey))
        let evaluated = try evaluate(builder)
        let sheet = try body(of: band, in: evaluated)
        #expect(sheet.kind == .sheet)
        #expect(faceCount(sheet, in: evaluated) == 1)
    }

    @Test(.timeLimit(.minutes(2)))
    func theNativePackageKeepsEveryImprint() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let other = try builder.box(width: length(side / 2), depth: length(side / 2), height: length(side * 2))
        let top = try face(of: box, facing: .unitZ, in: try evaluate(builder), builder: builder)
        let lines = try builder.isoparam(box, face: top, direction: .u, fractions: [0.4], subdividesControlNet: false)
        let crossing = try builder.imprintBody(other, tool: lines, completion: .edge)
        let untrim = try builder.untrimFace(box, face: top, keepsEdges: true)
        let document = try builder.build(name: "imprint persistence")
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        for id in [lines, crossing, untrim] {
            #expect(loaded.designGraph.nodes[id]?.operation == document.designGraph.nodes[id]?.operation)
        }
    }
}
