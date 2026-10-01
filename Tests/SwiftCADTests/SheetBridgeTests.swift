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
    private func sheets(in builder: inout DocumentBuilder) throws -> (FeatureID, FeatureID) {
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
        let wall = try square(on: .zx, [(0.01, 0), (0.01, 0.04), (0.04, 0.04), (0.04, 0)])
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
        _ = try builder.bridgeSurface(SheetBridgeFeature(first: floor, second: wall, width: length(0.02), trimWalls: .both))
        do {
            _ = try evaluate(builder)
            Issue.record("Trimming walls is not built yet.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }
}
