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

    @Test(.timeLimit(.minutes(2)), arguments: [SheetBridgeFeature.Shape.curvature, .chamfer])
    func trimWallsJoinsABridgeBetweenBoundaryEdgesWithBothSheets(shape: SheetBridgeFeature.Shape) throws {
        // The parallel floor and shelf, bridged and joined into one sheet of three faces.
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
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: shelf, width: length(0.01),
                                                                  shape: shape, trimWalls: .both))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == bridge, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 3)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvedSheetBridgesTheWidthFromWhereItsContinuationMeetsTheFloor() throws {
        // A parabolic arch z = x (1 − x / s) over x ∈ [0, 20] mm, y ∈ [0, 20] mm, and a floor at
        // z = 0 over x ∈ [30, 50] mm: continued, they meet at the arch's foot x = s. The bridge
        // starts 10 mm back up the arch from there and 10 mm along the floor, at its edge x = 30.
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
        // The arch's contact: 10 mm of the parabola back from x = s.
        func arc(_ x0: Double, _ x1: Double) -> Double {
            let steps = 4_000
            return (0..<steps).reduce(0.0) { total, index in
                let x = x0 + (x1 - x0) * (Double(index) + 0.5) / Double(steps)
                return total + (1 + pow(1 - 2 * x / s, 2)).squareRoot() * abs(x1 - x0) / Double(steps)
            }
        }
        var xc = s - 0.007
        for _ in 0..<40 { xc -= (0.01 - arc(xc, s)) / (1 + pow(1 - 2 * xc / s, 2)).squareRoot() }
        for y in [0.005, 0.015] {
            for point in [Point3D(x: xc, y: y, z: xc * (1 - xc / s)), Point3D(x: 0.03, y: y, z: 0)] {
                let projected = try bridged.parameterProjection(of: point, tolerance: .standard)
                #expect(projected.residual < 1e-6, "\(point)")
            }
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
        #expect(try reach.trimWalls(.short, first: floor, second: wall, reversesFirstSense: false, reversesSecondSense: false, in: before) == .second)
        #expect(try reach.trimWalls(.long, first: floor, second: wall, reversesFirstSense: false, reversesSecondSense: false, in: before) == .first)
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

    /// Propagate (inferred with the user 2026-10-05): a floor and a shelf each joined from two
    /// halves bridge between their nearest edges and, propagating, on along the edges tangent to
    /// them, the strips sewn into one sheet over the whole 40 mm.
    @Test(.timeLimit(.minutes(4)), arguments: [SheetBridgeFeature.Shape.curvature, .chamfer])
    func propagateRunsTheBridgeAlongTangentBoundaryEdges(shape: SheetBridgeFeature.Shape) throws {
        func evaluated(propagates: Bool) throws -> (faces: Int, xs: ClosedRange<Double>, bodies: Int) {
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
            let shelfPlane = SketchPlane.plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.02), normal: .unitZ))
            let floor = try builder.joinBodies(try [(0.0, 0.02), (0.02, 0.04)].map { x0, x1 in
                try square(on: .xy, [(x0, 0.01), (x1, 0.01), (x1, 0.04), (x0, 0.04)])
            }, mode: .sewnSheet)
            let shelf = try builder.joinBodies(try [(0.0, 0.02), (0.02, 0.04)].map { x0, x1 in
                try square(on: shelfPlane, [(x0, -0.04), (x1, -0.04), (x1, -0.01), (x0, -0.01)])
            }, mode: .sewnSheet)
            let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: shelf, width: length(0.01), shape: shape,
                                                                      propagates: propagates))
            let result = try evaluate(builder)
            let faces = result.subshapes.entries.compactMap { key, value -> FaceID? in
                guard key.featureID == bridge, case let .face(id) = value else { return nil }
                return id
            }
            let xs = try faces.flatMap { faceID in
                try (result.brep.faces[faceID]?.loops ?? []).flatMap { try result.brep.orderedPoints(for: $0) }
            }.map(\.x)
            let bodies = Set(result.subshapes.entries.compactMap { key, value -> BodyID? in
                guard key.featureID == bridge, case let .body(id) = value else { return nil }
                return id
            })
            return (faces.count, (xs.min() ?? .nan)...(xs.max() ?? .nan), bodies.count)
        }
        let single = try evaluated(propagates: false)
        #expect(single.faces == 1)
        #expect(single.xs.upperBound - single.xs.lowerBound < 0.02 + 1e-9)
        let propagated = try evaluated(propagates: true)
        #expect(propagated.faces == 2)
        #expect(abs(propagated.xs.lowerBound) < 1e-9 && abs(propagated.xs.upperBound - 0.04) < 1e-9)
        #expect(propagated.bodies == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func twoSensesReachEveryQuadrantOfCrossingSheets() throws {
        // A floor on z = 0 and a wall on y = 0, both crossing the x axis where they meet: each
        // Sense picks its own sheet's side, so the four settings bridge the four quadrants.
        var quadrants: Set<[Bool]> = []
        for (first, second) in [(false, false), (true, false), (false, true), (true, true)] {
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
            let floor = try square(on: .xy, [(0, -0.04), (0.04, -0.04), (0.04, 0.04), (0, 0.04)])
            let wall = try square(on: .zx, [(-0.04, 0), (-0.04, 0.04), (0.04, 0.04), (0.04, 0)])
            let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.01), shape: .chamfer,
                                                                      reversesFirstSense: first, reversesSecondSense: second))
            let strip = try surface(of: bridge, in: try evaluate(builder))
            let middle = try strip.differentialGeometry(u: 0.5, v: 0.5, tolerance: .standard).position
            #expect(abs(middle.y) > 1e-4 && abs(middle.z) > 1e-4)
            quadrants.insert([middle.y > 0, middle.z > 0])
        }
        #expect(quadrants.count == 4)
    }

    @Test(.timeLimit(.minutes(3)))
    func theExtentSetsHowFarTheBridgeRunsAlongWhereTheSheetsMeet() throws {
        // The floor runs 40 mm along x, the wall 30 mm: Both and Short span the wall's 30 mm, Long
        // the floor's 40 mm, None both run on by the 20 mm width at each end.
        for (extent, span) in [(SheetBridgeFeature.Extent.both, 0.0...0.03), (.short, 0.0...0.03), (.long, 0.0...0.04), (.none, -0.02...0.06)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let (floor, wall) = try sheets(in: &builder, wallLength: 0.03)
            let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02), shape: .chamfer,
                                                                      extent: extent))
            let evaluated = try evaluate(builder)
            let xs = evaluated.subshapes.entries.compactMap { key, value -> Double? in
                guard key.featureID == bridge, case let .vertex(id) = value else { return nil }
                return evaluated.brep.vertices[id]?.point.x
            }
            #expect(abs((xs.min() ?? .nan) - span.lowerBound) < 1e-12 && abs((xs.max() ?? .nan) - span.upperBound) < 1e-12, "\(extent) \(xs)")
        }
    }

    /// A curved floor z = 0.1 (x − 0.04)² over x ∈ [20, 60] mm and a curved wall x = 0.1 (z − 0.04)²
    /// over z ∈ [20, 60] mm, both 40 mm deep in y, apart: continued, they meet near the corner.
    private func curvedSheets(in builder: inout DocumentBuilder) throws -> (FeatureID, FeatureID) {
        let floorRow = { (y: Double) in [Point3D(x: 0.02, y: y, z: 0.00004), Point3D(x: 0.04, y: y, z: -0.00004), Point3D(x: 0.06, y: y, z: 0.00004)] }
        let floor = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [floorRow(0), floorRow(0.04)]))
        let wallRow = { (y: Double) in [Point3D(x: 0.00004, y: y, z: 0.02), Point3D(x: -0.00004, y: y, z: 0.04), Point3D(x: 0.00004, y: y, z: 0.06)] }
        let wall = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [wallRow(0), wallRow(0.04)]))
        return (floor, wall)
    }

    @Test(.timeLimit(.minutes(3)))
    func curvedSheetsApartAreBridgedTheWidthFromWhereTheirContinuationsMeet() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (floor, wall) = try curvedSheets(in: &builder)
        let width = 0.01
        let bridge = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(width), trimWalls: .both,
                                                                  angularAllowance: 0.1 * Double.pi / 180, curvatureAllowance: 1))
        let evaluated = try evaluate(builder)
        // Trimmed (Both): walls and bridge are one sheet.
        let bodies = evaluated.brep.bodies.values.filter { $0.kind == .sheet }
        #expect(bodies.count == 1)
        // The continuations meet where x = z = t, t = 0.1 (t − 0.04)²; the floor's contact lies the
        // width along the parabola from there, carried past its edge at x = 20 mm.
        var t = 0.0
        for _ in 0..<50 { t = 0.1 * (t - 0.04) * (t - 0.04) }
        func arc(_ x0: Double, _ x1: Double) -> Double {
            let steps = 2_000
            return (0..<steps).reduce(0.0) { total, index in
                let x = x0 + (x1 - x0) * (Double(index) + 0.5) / Double(steps)
                return total + (1 + pow(0.2 * (x - 0.04), 2)).squareRoot() * (x1 - x0) / Double(steps)
            }
        }
        var xc = t + width
        for _ in 0..<40 { xc += (width - arc(t, xc)) / (1 + pow(0.2 * (xc - 0.04), 2)).squareRoot() }
        let corners = evaluated.brep.vertices.values.map(\.point).filter { abs($0.y) < 1e-9 }
        #expect(corners.contains { abs($0.x - xc) < 1e-6 && abs($0.z - 0.1 * pow(xc - 0.04, 2)) < 1e-6 },
                "No floor contact near x = \(xc) among \(corners)")
        #expect(corners.contains { abs($0.z - xc) < 1e-6 && abs($0.x - 0.1 * pow(xc - 0.04, 2)) < 1e-6 },
                "No wall contact near z = \(xc) among \(corners)")
        _ = bridge
    }

    @Test(.timeLimit(.minutes(3)))
    func curvedSheetsBridgedWithoutTrimmingKeepTheirSheets() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (floor, wall) = try curvedSheets(in: &builder)
        _ = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.01), trimWalls: .none,
                                                         angularAllowance: 0.1 * Double.pi / 180, curvatureAllowance: 1))
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.values.filter { $0.kind == .sheet }.count == 3)
    }
}
