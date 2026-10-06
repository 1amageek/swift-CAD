import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Square's Refit: a face replaced by an untrimmed four-sided sheet on its own edges — a box's
/// top, a pentagonal prism's top split at its four sharpest corners, and a sheet's face tangent
/// to the curved face beside it — the body keeping its edges, validity and volume.
@Suite("Square refit")
struct SquareRefitTests {
    private let s = 0.02
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "refit"))
    }

    private func face(of feature: FeatureID, in builder: DocumentBuilder, where predicate: (Surface3D) -> Bool) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID], predicate(surface) else { return nil }
            return key
        }.sorted().first)
        return try builder.stableSubshape(key)
    }

    private func refitted(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> [BSplineSurface3D] {
        evaluated.subshapes.entries.compactMap { key, value -> BSplineSurface3D? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .bSpline(spline)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return spline
        }
    }

    private func volume(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    private func isTop(_ surface: Surface3D) -> Bool {
        guard case let .plane(plane) = surface else { return false }
        return plane.normal.z > 0.99
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopIsRefitFlatOnItsEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let top = try face(of: box, in: builder, where: isTop)
        let refit = try builder.rebuildFaces(target: box, faces: [top], method: .square(SquareRefit(
            options: SquareFitOptions(uDegree: 4, vDegree: 3, uSpans: 2, vSpans: 1)
        )))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        #expect(sheets.count == 1)
        #expect(sheets.allSatisfy { Set([$0.uDegree, $0.vDegree]) == [3, 4] && $0.controlPoints.joined().allSatisfy { abs($0.z - s) < 1e-12 } })
        #expect(abs(try volume(refit, in: evaluated) - s * s * s) < s * s * s * 1e-9)
        // Its Analysis: each of the top's four edges on the new boundary, shown at its middle.
        let sides = try FaceRefitAnalyzer().analyze(refit, in: evaluated)
        #expect(sides.count == 4)
        #expect(sides.allSatisfy { $0.position < 1e-9 && $0.isWithin && abs(($0.point?.z ?? 0) - s) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func narrowNativeEdgeBulgesRequireCertifiedRefitAndPreserveBothVertexParents() throws {
        let tolerance = ModelingTolerance.standard, delta = tolerance.distance
        let axis = [0.0, 1.0 / 64, 1.0 / 32, 3.0 / 64, 1.0]
        let heights = [0.0, 0.0, 4 * delta, 0.0, 0.0]
        let knots = [0.0, 0.0, 1.0 / 64, 1.0 / 32, 3.0 / 64, 1.0, 1.0]
        let controls = axis.indices.map { v in
            axis.indices.map { u in Point3D(x: 0.01 * axis[u], y: 0.01 * axis[v],
                z: (1 + axis[v]) * heights[u] + (1.5 + axis[u]) * heights[v]) }
        }
        var builder = DocumentBuilder(units: .meters, tolerance: tolerance)
        let sheet = try builder.bSplineSurface(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: knots, vKnots: knots, controlPoints: controls))
        let original = try evaluate(builder)
        try original.brep.validate(level: .exact, tolerance: tolerance)
        var originalVertices: [SubshapeID: Point3D] = [:]
        for (key, topology) in original.subshapes.entries where key.featureID == sheet {
            if case let .vertex(id) = topology { originalVertices[key] = try #require(original.brep.vertices[id]).point }
        }
        #expect(originalVertices.count == 4)
        let originalFace = try #require(original.brep.faces.values.first)
        let originalLoopID = try #require(originalFace.loops.first)
        let originalLoop = try #require(original.brep.loops[originalLoopID])
        #expect(originalLoop.coedges.count == 4)
        let certification = CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
            maximumCellCount: 1_048_576, maximumDeviation: delta)
        for coedge in originalLoop.coedges {
            let edge = try #require(original.brep.edges[coedge.edgeID]), trim = try #require(edge.trim)
            let curve = try #require(original.brep.geometry.curves[edge.curveID])
            let start = coedge.orientation == .forward ? trim.startParameter : trim.endParameter
            let end = coedge.orientation == .forward ? trim.endParameter : trim.startParameter
            // These witnesses establish the adversarial source; acceptance below requires the continuous public validator.
            for station in 0...16 {
                #expect(abs(try curve.point(at: start + (end - start) * Double(station) / 16, tolerance: tolerance).z) < delta / 100)
            }
            let peaks = try (0...32).map { try curve.point(at: start + (end - start) * Double($0) / 32, tolerance: tolerance).z }
            #expect(try #require(peaks.max()) > 3.9 * delta)
            try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: curve, from: start, to: end,
                surface: try #require(original.brep.geometry.surfaces[originalFace.surfaceID]),
                parameterCurve: try #require(coedge.surfaceParameterCurve), options: certification, tolerance: tolerance)
        }
        let selected = try face(of: sheet, in: builder) { if case .bSpline = $0 { return true }; return false }
        let refit = try builder.rebuildFaces(target: sheet, faces: [selected], method: .square(SquareRefit(
            options: SquareFitOptions(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1))))
        let evaluated = try evaluate(builder)
        let surfaces = try refitted(refit, in: evaluated)
        #expect(surfaces.count == 1 && surfaces.allSatisfy {
            $0.uDegree == 1 && $0.vDegree == 1 && $0.uControlPointCount == 2 && $0.vControlPointCount == 2
                && $0.controlPoints.joined().allSatisfy { abs($0.z) < delta / 100 }
        })
        let faceID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == refit, case .face = value else { return false }; return true
        }.flatMap { if case let .face(id) = $0.value { return id }; return nil })
        let face = try #require(evaluated.brep.faces[faceID]), surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        #expect(loop.coedges.count == 4)
        for coedge in loop.coedges {
            let edge = try #require(evaluated.brep.edges[coedge.edgeID]), trim = try #require(edge.trim)
            let curve = try #require(evaluated.brep.geometry.curves[edge.curveID])
            let start = coedge.orientation == .forward ? trim.startParameter : trim.endParameter
            let end = coedge.orientation == .forward ? trim.endParameter : trim.startParameter
            // Check the native knot witness independently of the continuous validator's certificate.
            let witnessParameter = min(start, end) + abs(end - start) / 32
            let witnessFraction = (witnessParameter - start) / (end - start)
            let witnessPoint = try curve.point(at: witnessParameter, tolerance: tolerance)
            let witnessUV = try #require(coedge.surfaceParameterCurve).parameter(atNormalizedFraction: witnessFraction, tolerance: tolerance)
            let witnessTarget = try surface.point(u: witnessUV.u, v: witnessUV.v, tolerance: tolerance)
            #expect((witnessPoint - witnessTarget).length <= delta)
            do {
                try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: curve, from: start, to: end,
                    surface: surface, parameterCurve: try #require(coedge.surfaceParameterCurve), options: certification, tolerance: tolerance)
            } catch { Issue.record("Refit kept an edge without a full distance-tolerance certificate: \(error)") }
            // All four sides stray, so no retained neighbour can supply a missing regenerated endpoint parent.
            for vertexID in [edge.startVertexID, edge.endVertexID] {
                let point = try #require(evaluated.brep.vertices[vertexID]).point
                let originalKey = try #require(originalVertices.first { ($0.value - point).length <= delta }?.key)
                let key = try #require(evaluated.subshapes.entries.first { $0.key.featureID == refit && $0.value == .vertex(vertexID) }?.key)
                #expect(try #require(evaluated.lineage[key]).parents.contains(originalKey))
            }
        }
        let analysis = try FaceRefitAnalyzer().analyze(refit, in: evaluated)
        // The stable selection resolves through current lineage to the final edges; source peaks are witnessed above.
        #expect(analysis.count == 4 && analysis.allSatisfy { $0.isWithin })
    }

    /// A square prism with one corner cut at a shallow angle: its top's sharpest corners are the
    /// other three and the cut's sharper end, so one side runs over two edges meeting at a corner.
    private func pentagonalPrism(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let corners = [(0.0, 0.0), (s, 0.0), (s, 0.6 * s), (0.8 * s, s), (0.0, s)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: SketchPoint(x: length(a.0), y: length(a.1)), to: SketchPoint(x: length(b.0), y: length(b.1)))
            }
        }
        return try builder.extrude(ProfileReference(featureID: profile.featureID, profileIndex: 0), distance: length(s))
    }

    @Test(.timeLimit(.minutes(2)))
    func aPentagonsTopIsSplitAtItsFourSharpestCornersAndItsBentSideStrays() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let prism = try pentagonalPrism(&builder)
        // The net is exactly the one asked for (3 × 3, three spans), which cannot bend where the
        // side's two edges meet: on the solid that side would leave it open, so it is refused.
        let top = try face(of: prism, in: builder, where: isTop)
        var solid = builder
        _ = try solid.rebuildFaces(target: prism, faces: [top], method: .square(SquareRefit()))
        #expect(throws: KernelError.self) { _ = try evaluate(solid) }
        // The prism's top and walls as a sheet: the bent side strays from the walls' edges and runs
        // along the refit face's own boundary, the other sides keeping theirs.
        let walls = try evaluate(builder).subshapes.entries.filter { key, value in
            guard key.featureID == prism, case .face = value else { return false }
            return true
        }.map { try builder.stableSubshape($0.key) }
        let sheet = try builder.extract(prism, selection: .faces(walls.filter { $0.subshapeID != top.subshapeID } + [top]))
        let sheetTop = try face(of: sheet, in: builder, where: isTop)
        let refit = try builder.rebuildFaces(target: sheet, faces: [sheetTop], method: .square(SquareRefit()))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        #expect(sheets.count == 1 && sheets.allSatisfy {
            $0.uDegree == 3 && $0.vDegree == 3 && $0.uControlPointCount == 6 && $0.vControlPointCount == 6
                && $0.controlPoints.joined().allSatisfy { abs($0.z - s) < 1e-12 }
        })
        // The top's straying edges and the walls' edges they left are open; the rest are shared.
        var uses: [EdgeID: Int] = [:]
        for face in evaluated.brep.faces.values {
            for loopID in face.loops { for coedge in evaluated.brep.loops[loopID]?.coedges ?? [] { uses[coedge.edgeID, default: 0] += 1 } }
        }
        let open = uses.filter { $0.value == 1 }.compactMap { evaluated.brep.edges[$0.key] }
        let atTop = open.filter { edge in
            [edge.startVertexID, edge.endVertexID].allSatisfy { abs((evaluated.brep.vertices[$0]?.point.z ?? 0) - s) < 1e-9 }
        }
        #expect(atTop.count >= 3)
        // Free follows the sides loosely and strays too, on a sheet.
        var free = builder
        _ = try free.rebuildFaces(target: refit, faces: [try face(of: refit, in: free) { if case .bSpline = $0 { return true }; return false }],
                                  method: .square(SquareRefit(isFree: true)))
        try evaluate(free).brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetsFaceIsRefitTangentToTheCurvedFaceBesideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A flat floor and, beyond its edge y = 0, a ramp leaving it level and curving up.
        let floor = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: s, y: 0, z: 0)], [Point3D(x: 0, y: s, z: 0), Point3D(x: s, y: s, z: 0)]]
        ))
        let row = { (y: Double, z: Double) in [Point3D(x: 0, y: y, z: z), Point3D(x: s, y: y, z: z)] }
        let ramp = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 2, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: [row(0, 0), row(-s / 2, 0), row(-s, s / 2)]
        ))
        let sheet = try builder.joinBodies([floor, ramp], mode: .sewnSheet)
        let flat = try face(of: sheet, in: builder) { surface in
            guard case let .bSpline(spline) = surface else { return false }
            return spline.controlPoints.joined().allSatisfy { $0.z == 0 }
        }
        let refit = try builder.rebuildFaces(target: sheet, faces: [flat], method: .square(SquareRefit(
            order: .tangent, angularAllowance: 1e-3
        )))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        // Level where the ramp leaves it, the floor stays flat.
        let floorSheet = try #require(sheets.first { $0.controlPoints.joined().allSatisfy { $0.y >= -1e-12 } })
        #expect(floorSheet.controlPoints.joined().allSatisfy { abs($0.z) < 1e-9 })
    }
}
