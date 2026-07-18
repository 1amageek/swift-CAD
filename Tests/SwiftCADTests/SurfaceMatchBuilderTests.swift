import Testing
@testable import SwiftCAD

@Suite("Surface match builder")
struct SurfaceMatchBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveVerifiedSurfaceMatch() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let sourceSheetID = try appendSheet(to: &builder)
        let targetSheetID = try appendSheet(to: &builder)
        let offsetTargetID = try builder.offsetSurface(
            target: targetSheetID,
            distance: .constant(.length(50.0, unit: .millimeter))
        )
        let matchID = try builder.matchSurface(
            source: sourceSheetID,
            sourceParameter: SurfaceParameter(u: -0.020, v: 0.010),
            target: offsetTargetID,
            targetParameter: SurfaceParameter(u: -0.020, v: 0.010),
            continuity: .curvature
        )
        let document = try builder.build(name: "Exact planar surface match")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.vertices.count == 4)
        guard case .surfaceMatch = loaded.designGraph.nodes[matchID]?.operation else {
            Issue.record("Native package must preserve surface match operations.")
            return
        }
    }

    private func appendSheet(to builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(profile, distance: .constant(.length(10.0, unit: .millimeter)))
        var removedFaces = [try builder.stableSubshape(generatedBy: extrudeID, selector: .generated(role: .endFace))]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: index)
            ))
        }
        return try builder.faceDelete(target: extrudeID, faces: removedFaces)
    }
}
