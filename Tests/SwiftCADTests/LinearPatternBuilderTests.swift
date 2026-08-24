import Testing
@testable import SwiftCAD

@Suite("Linear pattern builder")
struct LinearPatternBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedLinearPatternCommand() throws {
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
        let patternID = try builder.linearPattern(
            target: extrudeID,
            direction: .unitX,
            spacing: .constant(.length(60.0, unit: .millimeter)),
            count: 3
        )
        let document = try builder.build(name: "Linear pattern parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 3)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .linearPattern = loaded.designGraph.nodes[patternID]?.operation else {
            Issue.record("Native package persistence must preserve the shared linear pattern operation.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedPatternPreservesOuterAndVoidShellOwnership() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let outerID = try builder.box(
            width: .constant(.length(0.040, unit: .meter)),
            depth: .constant(.length(0.030, unit: .meter)),
            height: .constant(.length(0.020, unit: .meter))
        )
        let cavityID = try builder.box(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.010, y: 0.010, z: 0.004),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            width: .constant(.length(0.020, unit: .meter)),
            depth: .constant(.length(0.010, unit: .meter)),
            height: .constant(.length(0.010, unit: .meter))
        )
        let cavitySolidID = try builder.boolean(
            targets: [outerID],
            tool: cavityID,
            operation: .difference
        )
        _ = try builder.linearPattern(
            target: cavitySolidID,
            direction: .unitX,
            spacing: .constant(.length(0.100, unit: .meter)),
            count: 2
        )

        let evaluated = try CADPipeline(tolerance: .standard).evaluate(
            builder.build(name: "Cavity pattern ownership")
        )

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let body = try #require(evaluated.brep.bodies.values.first)
        let components = try #require(body.solidComponents)
        #expect(components.count == 2)
        #expect(components.allSatisfy { $0.voidShellIDs.count == 1 })
        #expect(body.shellIDs.count == 4)
        let expectedVolume = 2.0 * (
            0.040 * 0.030 * 0.020
                - 0.020 * 0.010 * 0.010
        )
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard) - expectedVolume
        ) <= 1.0e-12)
    }
}
