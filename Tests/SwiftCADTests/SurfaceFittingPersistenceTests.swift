import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
@testable import SwiftCAD

/// Rebuild Face, Unwrap Face and Align Surface's options survive a native package round trip and
/// evaluate the same after it; invalid options are refused on encoding.
@Suite("Surface fitting persistence")
struct SurfaceFittingPersistenceTests {
    @Test(.timeLimit(.minutes(2)))
    func rebuildUnwrapAndAlignRoundTripThroughANativePackage() throws {
        let s = 0.02
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s + 0.005, y: 0, z: 0), Point3D(x: 2 * s, y: 0, z: 0)],
                            [Point3D(x: s + 0.005, y: s, z: 0), Point3D(x: 2 * s, y: s, z: 0)]]
        ))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "fit"))
        func reference(of feature: FeatureID, _ predicate: (TopologyReference) -> Bool) throws -> StableSubshapeReference {
            let key = try #require(evaluated.subshapes.entries.filter { $0.key.featureID == feature && predicate($0.value) }.map(\.key).min())
            return try builder.stableSubshape(key)
        }
        func edge(of feature: FeatureID, atX x: Double) throws -> StableSubshapeReference {
            try reference(of: feature) { value in
                guard case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                      let a = evaluated.brep.vertices[edge.startVertexID]?.point, let b = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
                return abs(a.x - x) < 1e-12 && abs(b.x - x) < 1e-12
            }
        }
        let face = try reference(of: arch) { if case .face = $0 { return true }; return false }
        _ = try builder.unwrapFace(target: arch, face: face)
        _ = try builder.alignSurface(
            target: flat, targetEdge: try edge(of: flat, atX: s + 0.005), reference: arch, referenceEdge: try edge(of: arch, atX: s),
            continuity: .curvature, blendRows: 1, inputShapeInfluence: 0.5, partialStart: 0.1, partialEnd: 0.2,
            layout: SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 2, vSpans: 4)
        )
        _ = try builder.rebuildFaces(
            target: arch, faces: [face], method: .explicit(SurfaceControlLayout(uDegree: 3, vDegree: 2, uSpans: 2, vSpans: 1)),
            extendU: 0.1, extendV: 0.2, shrinks: true
        )
        let document = try builder.build(name: "fit")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let before = try evaluator.evaluateExact(document)
        let after = try evaluator.evaluateExact(restored)
        #expect(after.brep.bodies.count == before.brep.bodies.count)
        #expect(after.brep.faces.count == before.brep.faces.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidOptionsAreRefusedOnEncoding() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try builder.bSplineSurface(.bilinearPatch(
            bottomLeft: .origin, bottomRight: Point3D(x: 0.01, y: 0, z: 0),
            topRight: Point3D(x: 0.01, y: 0.01, z: 0), topLeft: Point3D(x: 0, y: 0.01, z: 0)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "codable"))
        let key = try #require(evaluated.subshapes.entries.filter { entry in
            guard entry.key.featureID == sheet, case .face = entry.value else { return false }
            return true
        }.map(\.key).min())
        let target = PatternTargetReference(featureID: sheet)
        let face = try builder.stableSubshape(key)
        let tooWide = FaceRebuildFeature(target: target, faces: [face], method: .explicit(SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 1, vSpans: 1)), extendU: 2)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(FeatureOperation.faceRebuild(tooWide)) }
        let noDegree = FaceRebuildFeature(target: target, faces: [face], method: .explicit(SurfaceControlLayout(uDegree: 0, vDegree: 3, uSpans: 1, vSpans: 1)))
        #expect(throws: (any Error).self) { try JSONEncoder().encode(FeatureOperation.faceRebuild(noDegree)) }
        let tolerance = FaceRebuildFeature(target: target, faces: [face], method: .tolerance(.constant(.length(1e-5, unit: .meter))))
        let operation = FeatureOperation.faceRebuild(tolerance)
        #expect(try JSONDecoder().decode(FeatureOperation.self, from: try JSONEncoder().encode(operation)) == operation)
        let unwrap = FeatureOperation.faceUnwrap(FaceUnwrapFeature(target: target, face: face))
        #expect(try JSONDecoder().decode(FeatureOperation.self, from: try JSONEncoder().encode(unwrap)) == unwrap)
    }
}
