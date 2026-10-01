import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Square spans four curves meeting end to end: a Coons sheet at G0, and tangent or curvature
/// continuous with the planar faces beside body edges along one side or two opposite sides.
@Suite("Square surface")
struct SquareSurfaceTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "square"))
        try evaluated.brep.validate(tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func fourLinesSpanAFlatSquareInAnyOrder() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // Selected out of order and running different ways.
        let lines = try [(point(0, 0), point(0.02, 0)), (point(0.02, 0.02), point(0, 0.02)),
                         (point(0, 0.02), point(0, 0)), (point(0.02, 0), point(0.02, 0.02))].map { start, end in
            try builder.sketch(on: .xy) { _ = $0.line(from: start, to: end) }.featureID
        }
        let square = try builder.square(sides: [lines[0], lines[1], lines[3], lines[2]].map { SquareSide(curve: CurveSectionReference(featureID: $0)) })
        let evaluated = try evaluate(builder)
        let surface = try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == square, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
        guard case let .bSpline(spline) = surface else {
            Issue.record("A Square is a B-spline sheet.")
            return
        }
        // The flat frame's Coons sheet is the square itself.
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 && $0.x > -1e-12 && $0.x < 0.02 + 1e-12 })
        let corners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try surface.point(u: $0.0, v: $0.1, tolerance: .standard) }
        #expect(Set(corners.map { "\(($0.x * 1e6).rounded()),\(($0.y * 1e6).rounded())" }) == ["0.0,0.0", "20000.0,0.0", "0.0,20000.0", "20000.0,20000.0"])
    }

    /// Box A spans [0, 20 mm]³, box B [0, 20] × [-70, -50] × [30, 50] mm; the Square runs from A's
    /// top front edge to B's bottom back edge between two rails in the planes x = 0 and x = 20 mm
    /// leaving and arriving level.
    private func boxesSquare(
        order: SurfaceEdgeContinuity.Order?, rail: [(y: Double, z: Double)]
    ) throws -> (DocumentBuilder, FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let second = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: -0.07, z: 0.03), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.02), depth: length(0.02), height: length(0.02)
        )
        let evaluated = try evaluate(builder)
        func edge(of box: FeatureID, y: Double, z: Double) throws -> StableSubshapeReference {
            let key = try #require(evaluated.subshapes.entries.first { key, value in
                guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                      let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                      let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
                return [start, end].allSatisfy { abs($0.y - y) < 1e-12 && abs($0.z - z) < 1e-12 }
            }?.key)
            return try builder.stableSubshape(key)
        }
        let firstEdge = try edge(of: first, y: 0, z: 0.02)
        let secondEdge = try edge(of: second, y: -0.05, z: 0.03)
        let firstCurve = try builder.edgeCurves(of: first, edges: [firstEdge])
        let secondCurve = try builder.edgeCurves(of: second, edges: [secondEdge])
        // Rails: sketch x is world y and sketch y is world z on planes across X.
        let rails = try [0.0, 0.02].map { x in
            try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: x, y: 0, z: 0), normal: .unitX))) { sketch in
                _ = sketch.spline(SketchSpline(controlPoints: rail.map { point($0.y, $0.z) }))
            }.featureID
        }
        let square = try builder.square(sides: [
            SquareSide(curve: CurveSectionReference(featureID: firstCurve),
                       continuity: order.map { SurfaceEdgeContinuity(source: first, bodyRole: .body, edge: firstEdge, order: $0) }),
            SquareSide(curve: CurveSectionReference(featureID: rails[1])),
            SquareSide(curve: CurveSectionReference(featureID: secondCurve),
                       continuity: order.map { SurfaceEdgeContinuity(source: second, bodyRole: .body, edge: secondEdge, order: $0) }),
            SquareSide(curve: CurveSectionReference(featureID: rails[0])),
        ])
        return (builder, square)
    }

    /// The Square's surface at points along its two continuous sides.
    private func boundary(_ evaluated: EvaluatedDocument, square: FeatureID) throws -> [(normal: Vector3D, curvature: Double)] {
        let surface = try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == square, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
        return try [0.004, 0.01, 0.016].flatMap { x in
            try [Point3D(x: x, y: 0, z: 0.02), Point3D(x: x, y: -0.05, z: 0.03)].map { point in
                let projected = try surface.parameterProjection(of: point, tolerance: .standard)
                #expect(projected.residual < 1e-9)
                let geometry = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard)
                return (geometry.normal, geometry.normalCurvatureV)
            }
        }
    }

    private let levelCubic: [(y: Double, z: Double)] = [(0, 0.02), (-0.02, 0.02), (-0.03, 0.03), (-0.05, 0.03)]
    /// Two cubic spans that leave and arrive without bending out of the faces' planes.
    private let levelTwoSpans: [(y: Double, z: Double)] = [
        (0, 0.02), (-0.01, 0.02), (-0.02, 0.02), (-0.025, 0.025), (-0.03, 0.03), (-0.04, 0.03), (-0.05, 0.03),
    ]

    @Test(.timeLimit(.minutes(2)))
    func aTangentSquareMeetsBothBoxesFacesInTheirPlanes() throws {
        let (builder, square) = try boxesSquare(order: .tangent, rail: levelCubic)
        let samples = try boundary(try evaluate(builder), square: square)
        #expect(samples.allSatisfy { abs(abs($0.normal.z) - 1) < 1e-9 })

        let document = try builder.build(name: "square")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvatureSquareIsFlatAcrossBothEdges() throws {
        let (builder, square) = try boxesSquare(order: .curvature, rail: levelTwoSpans)
        let samples = try boundary(try evaluate(builder), square: square)
        #expect(samples.allSatisfy { abs(abs($0.normal.z) - 1) < 1e-9 && abs($0.curvature) < 1e-6 })
    }

    /// A Square over the four top edges of `edges`'s frame, tangent along all four to the faces
    /// beside them.
    private func squareOverEdges(_ edges: [StableSubshapeReference], of body: FeatureID, in builder: inout DocumentBuilder) throws -> FeatureID {
        let curves = try edges.map { try builder.edgeCurves(of: body, edges: [$0]) }
        return try builder.square(sides: zip(curves, edges).map { curve, edge in
            SquareSide(curve: CurveSectionReference(featureID: curve),
                       continuity: SurfaceEdgeContinuity(source: body, bodyRole: .body, edge: edge, order: .tangent))
        })
    }

    private func topEdges(of body: FeatureID, inside: Bool, z: Double, in builder: DocumentBuilder) throws -> [StableSubshapeReference] {
        let evaluated = try evaluate(builder)
        return try evaluated.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == body, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point,
                  abs(start.z - z) < 1e-12, abs(end.z - z) < 1e-12 else { return nil }
            let reach = max(abs(start.x), abs(start.y), abs(end.x), abs(end.y))
            return (reach < 0.015) == inside ? key : nil
        }.sorted { "\($0)" < "\($1)" }.map { try builder.stableSubshape($0) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aSquareFillsAHoleTangentToItsFaceAlongAllFourSides() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 40 mm plate 10 mm thick with a 20 mm square hole through it.
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.rectangle(width: length(0.04), height: length(0.04))
            _ = sketch.rectangle(width: length(0.02), height: length(0.02))
        }.featureID
        // The sketch's region with the hole is the one extruding to the plate's volume.
        var plateBuilder: DocumentBuilder?
        var plateID: FeatureID?
        for index in 0..<2 {
            var candidate = builder
            let extruded = try candidate.extrude(ProfileReference(featureID: sketch, profileIndex: index), distance: length(0.01))
            do {
                if abs(try evaluate(candidate).brep.volume(tolerance: .standard) - (0.04 * 0.04 - 0.02 * 0.02) * 0.01) < 1e-12 {
                    (plateBuilder, plateID) = (candidate, extruded)
                }
            } catch FeatureEvaluationError.missingProfile {
                continue
            }
        }
        builder = try #require(plateBuilder)
        let plate = try #require(plateID)
        let hole = try topEdges(of: plate, inside: true, z: 0.01, in: builder)
        #expect(hole.count == 4)
        let square = try squareOverEdges(hole, of: plate, in: &builder)
        let evaluated = try evaluate(builder)
        let surface = try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == square, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
        guard case let .bSpline(spline) = surface else {
            Issue.record("A Square is a B-spline sheet.")
            return
        }
        // The plate's top face is one plane, so the patch lies in it.
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z - 0.01) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aSquareAcrossABoxsTopEdgesTangentToItsWallsIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: -0.01, y: -0.01, z: 0), axis: .unitZ, referenceDirection: .unitX),
                                  width: length(0.02), depth: length(0.02), height: length(0.02))
        let top = try topEdges(of: box, inside: true, z: 0.02, in: builder)
        #expect(top.count == 4)
        _ = try squareOverEdges(top, of: box, in: &builder)
        do {
            _ = try evaluate(builder)
            Issue.record("Walls meeting at the Square's corners are different planes; G1 along all four sides must be refused.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func railsThatBendOutOfTheFacesPlaneAreRefusedForCurvature() throws {
        let (builder, _) = try boxesSquare(order: .curvature, rail: levelCubic)
        do {
            _ = try evaluate(builder)
            Issue.record("A curvature Square with rails bending out of the faces' planes must be refused.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput && error.message.contains("bend out"))
        }
    }
}
