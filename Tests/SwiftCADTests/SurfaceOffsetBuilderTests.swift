import Testing
@testable import SwiftCAD

@Suite("Surface offset builder")
struct SurfaceOffsetBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveExactSurfaceOffset() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
        var removedFaces = [try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .endFace)
        )]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: index)
            ))
        }
        let sheetID = try builder.faceDelete(target: extrudeID, faces: removedFaces)
        let offsetID = try builder.offsetSurface(
            target: sheetID,
            distance: .constant(.length(5.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Exact planar surface offset")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        #expect(evaluated.brep.vertices.count == 4)
        let zValues = evaluated.brep.vertices.values.map(\.point.z)
        let minimumZ = try #require(zValues.min())
        let maximumZ = try #require(zValues.max())
        #expect(minimumZ.isFinite)
        #expect(maximumZ - minimumZ <= 1.0e-12)
        #expect(abs(abs(try #require(zValues.first)) - 0.005) <= 1.0e-12)
        guard case .surfaceOffset = loaded.designGraph.nodes[offsetID]?.operation else {
            Issue.record("Native package must preserve surface offset operations.")
            return
        }
    }
}
