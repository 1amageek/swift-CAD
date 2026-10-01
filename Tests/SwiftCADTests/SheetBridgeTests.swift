import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Bridge Surface blends two planar sheets set back by the width from where their planes meet:
/// tangent and curvature continuous with both (G2), or a straight chamfer.
@Suite("Sheet bridge")
struct SheetBridgeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    /// A floor sheet on z = 0 over x ∈ [0, 40], y ∈ [10, 40] mm and a wall sheet on y = 0 over
    /// x ∈ [0, 40], z ∈ [10, 40] mm (sketch x is world z and sketch y world x on the ZX plane).
    private func sheets(in builder: inout DocumentBuilder, wallTop: Double = 0.04, wallLength: Double = 0.04) throws -> (FeatureID, FeatureID) {
        func square(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                try builder.sketch(on: plane) { sketch in
                    let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                    _ = sketch.line(from: point(start.0, start.1), to: point(end.0, end.1))
                }.featureID
            }
            return try builder.patch(curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        let floor = try square(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let wall = try square(on: .zx, [(0.01, 0), (0.01, wallLength), (wallTop, wallLength), (wallTop, 0)])
        return (floor, wall)
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bridge"))
        try evaluated.brep.validate(tolerance: .standard)
        return evaluated
    }

    private func surface(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Surface3D {
        try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
    }

    @Test(.timeLimit(.minutes(2)))
    func aG2BridgeMeetsBothSheetsTangentWithoutCurvature() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (floor, wall) = try sheets(in: &builder)
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02)))
        let evaluated = try evaluate(builder)
        let surface = try surface(of: bridge, in: evaluated)
        // Along the floor contact (y = 20 mm) the bridge lies flat in the floor's plane; along the
        // wall contact (z = 20 mm) in the wall's.
        for x in [0.005, 0.02, 0.035] {
            for (point, normalAxis) in [(Point3D(x: x, y: 0.02, z: 0), 2), (Point3D(x: x, y: 0, z: 0.02), 1)] {
                let projected = try surface.parameterProjection(of: point, tolerance: .standard)
                #expect(projected.residual < 1e-9)
                let geometry = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard)
                let normal = [geometry.normal.x, geometry.normal.y, geometry.normal.z]
                #expect(abs(abs(normal[normalAxis]) - 1) < 1e-9)
                #expect(abs(geometry.normalCurvatureU) < 1e-6 && abs(geometry.normalCurvatureV) < 1e-6)
            }
        }
        let document = try builder.build(name: "bridge")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        #expect(try store.loadDocument(from: BorrowedBytes(sink.bytes)).designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func parallelSheetsBridgeBetweenTheirNearestEdges() throws {
        // A floor on z = 0 over y ∈ [10, 40] mm and a shelf on z = 20 mm over y ∈ [-40, -10] mm: the
        // bridge spans from the floor's edge at y = 10 mm to the shelf's at y = -10 mm.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        func square(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                try builder.sketch(on: plane) { sketch in
                    let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                    _ = sketch.line(from: point(start.0, start.1), to: point(end.0, end.1))
                }.featureID
            }
            return try builder.patch(curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        let floor = try square(on: .xy, [(0, 0.01), (0.04, 0.01), (0.04, 0.04), (0, 0.04)])
        let shelf = try square(on: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.02), normal: .unitZ)),
                               [(0, -0.04), (0.04, -0.04), (0.04, -0.01), (0, -0.01)])
        var chamfered = builder
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: shelf, width: length(0.01)))
        let evaluated = try evaluate(builder)
        let bridged = try surface(of: bridge, in: evaluated)
        // G2: flat along both contacts, level with each sheet.
        for x in [0.005, 0.02, 0.035] {
            for point in [Point3D(x: x, y: 0.01, z: 0), Point3D(x: x, y: -0.01, z: 0.02)] {
                let projected = try bridged.parameterProjection(of: point, tolerance: .standard)
                #expect(projected.residual < 1e-9)
                let geometry = try bridged.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard)
                #expect(abs(abs(geometry.normal.z) - 1) < 1e-9)
            }
        }
        // A chamfer: the flat strip between the edges.
        let strip = try chamfered.bridgeSurface(SheetBridgeFeature(first: floor, second: shelf, width: length(0.01), shape: .chamfer))
        let flat = try evaluate(chamfered)
        let ruled = try surface(of: strip, in: flat)
        for point in [Point3D(x: 0.01, y: 0, z: 0.01), Point3D(x: 0.03, y: 0.005, z: 0.005)] {
            let projected = try ruled.parameterProjection(of: point, tolerance: .standard)
            #expect(projected.residual < 1e-9)
            let normal = try ruled.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard).normal
            #expect(abs(abs(normal.y + normal.z) - 2.0.squareRoot()) < 1e-9 && abs(normal.x) < 1e-9)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvedSheetBridgesFromItsEdgeTangentToIt() throws {
        // A parabolic arch over x ∈ [0, 20] mm, y ∈ [0, 20] mm, and a floor at z = 0 over x ∈ [30, 50]
        // mm: the bridge leaves the arch's edge at x = 20 mm along the arch, and reaches the floor's
        // edge at x = 30 mm level with it.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let s = 0.02
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]))
        let floorRow = { (y: Double) in [Point3D(x: 0.03, y: y, z: 0), Point3D(x: 0.05, y: y, z: 0)] }
        let floor = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [floorRow(0), floorRow(s)]))
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: arch, second: floor, width: length(0.01),
                                                                  angularAllowance: 0.1 * Double.pi / 180, curvatureAllowance: 1))
        let evaluated = try evaluate(builder)
        let bridged = try surface(of: bridge, in: evaluated)
        // The arch leaves x = s heading down at 45°: its normal there is (1, 0, 1)/√2.
        for y in [0.005, 0.015] {
            let projected = try bridged.parameterProjection(of: Point3D(x: s, y: y, z: 0), tolerance: .standard)
            #expect(projected.residual < 1e-9)
            let normal = try bridged.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard).normal
            #expect(abs(abs(normal.x + normal.z) - 2.0.squareRoot()) < 1e-6 && abs(normal.y) < 1e-6, "\(normal)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aChamferBridgeIsAFlatStripAndTrimmingIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (floor, wall) = try sheets(in: &builder)
        var chamfer = builder
        let strip = try chamfer.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02), shape: .chamfer))
        let evaluated = try evaluate(chamfer)
        guard case let .bSpline(spline) = try surface(of: strip, in: evaluated) else {
            Issue.record("A chamfer bridge is a B-spline strip.")
            return
        }
        // Every control point on the plane y + z = 20 mm.
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.y + $0.z - 0.02) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(3)))
    func trimmedWallsJoinTheBridgeIntoOneSheet() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (floor, wall) = try sheets(in: &builder)
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02),
                                                                  shape: .chamfer, trimWalls: .both))
        let evaluated = try evaluate(builder)
        // One sheet: the floor from y = 20 to 40 mm, the chamfer strip and the wall from z = 20 to
        // 40 mm, each 40 mm long.
        let bodies = Set(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == bridge, case let .body(id) = value else { return nil }
            return id
        })
        #expect(bodies.count == 1)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == bridge, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 3)
        let vertices = try #require(bodies.first).flatMap { bodyID in
            try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep).references.compactMap { reference -> Point3D? in
                if case let .vertex(id) = reference { return evaluated.brep.vertices[id]?.point }
                return nil
            }
        } ?? []
        #expect(vertices.allSatisfy { $0.y >= 0.02 - 1e-9 || $0.z >= 0.02 - 1e-9 })
        // The untrimmed floor and wall are gone.
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func theShortWallIsTheOneReachingLessAndOnlyItIsTrimmed() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The floor reaches 40 mm from where the planes meet, the wall 30 mm.
        let (floor, wall) = try sheets(in: &builder, wallTop: 0.03)
        let before = try evaluate(builder)
        let reach = SheetBridgeWallReach()
        #expect(try reach.trimWalls(.short, first: floor, second: wall, reversesSense: false, in: before) == .second)
        #expect(try reach.trimWalls(.long, first: floor, second: wall, reversesSense: false, in: before) == .first)
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02),
                                                                  shape: .chamfer, trimWalls: .second))
        let evaluated = try evaluate(builder)
        // The bridge's sheet: the chamfer strip and the wall above z = 20 mm; the floor stays whole.
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == bridge, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 2)
        #expect(evaluated.brep.bodies.count == 2)
        let floorBody = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == floor, case let .body(id) = value else { return nil }
            return id
        }.first)
        #expect(evaluated.brep.bodies[floorBody] != nil)
    }

    @Test(.timeLimit(.minutes(3)))
    func aTrimmedWallLongerThanTheBridgeJoinsAlongItsShare() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The wall covers x from 0 to 30 mm, so the bridge does; the trimmed floor runs to 40 mm.
        let (floor, wall) = try sheets(in: &builder, wallLength: 0.03)
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02),
                                                                  shape: .chamfer, trimWalls: .first))
        let evaluated = try evaluate(builder)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == bridge, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 2)
        // The joined sheet and the untrimmed wall.
        #expect(evaluated.brep.bodies.count == 2)
        // The floor beyond y = 20 mm keeps its 40 mm, its cut edge split where the 30 mm strip ends:
        // five floor edges and three more of the strip.
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == bridge, case let .body(id) = value else { return nil }
            return id
        }.first)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep)
        let points = scope.references.compactMap { reference -> Point3D? in
            if case let .vertex(id) = reference { return evaluated.brep.vertices[id]?.point }
            return nil
        }
        #expect(scope.references.filter { if case .edge = $0 { return true } else { return false } }.count == 8)
        #expect(points.contains { abs($0.x - 0.04) < 1e-12 && abs($0.y - 0.02) < 1e-12 && abs($0.z) < 1e-12 })
        #expect(points.contains { abs($0.x - 0.03) < 1e-12 && abs($0.y - 0.02) < 1e-12 && abs($0.z) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(3)))
    func aFloorJoinedFromTwoPiecesBridgesAndTrimsAsOne() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        func square(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                try builder.sketch(on: plane) { sketch in
                    let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                    _ = sketch.line(from: point(start.0, start.1), to: point(end.0, end.1))
                }.featureID
            }
            return try builder.patch(curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        // The floor of the other tests in two halves along X, joined into one sheet of two faces.
        let halves = try [(0.0, 0.02), (0.02, 0.04)].map { x0, x1 in
            try square(on: .xy, [(x0, 0.01), (x1, 0.01), (x1, 0.04), (x0, 0.04)])
        }
        let floor = try builder.joinBodies(halves, mode: .sewnSheet)
        let wall = try square(on: .zx, [(0.01, 0), (0.01, 0.04), (0.04, 0.04), (0.04, 0)])
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02),
                                                                  shape: .chamfer, trimWalls: .both))
        let evaluated = try evaluate(builder)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == bridge, case let .face(id) = value else { return nil }
            return id
        }
        // Both floor halves cut back, the strip and the wall: one sheet of four faces.
        #expect(faces.count == 4)
        #expect(evaluated.brep.bodies.count == 1)
    }
}
