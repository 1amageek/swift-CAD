import Foundation
import Testing
@testable import SwiftCAD

@Suite("Mirror feature integration")
struct MirrorFeatureIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func mirrorDuplicatesBoxAcrossSeparatedPlaneAndRoundTripsNativePackage() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let mirrorID = try builder.mirror(
            extrudeID,
            planeOrigin: Point3D(x: 0.05, y: 0.0, z: 0.0),
            planeNormal: .unitX
        )
        let document = try builder.build(name: "Mirror parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .mirror = loaded.designGraph.nodes[mirrorID]?.operation else {
            Issue.record("Native package persistence must preserve the shared mirror operation.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mirrorDuplicatesSphereWithMappedGreatCirclePcurves() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let sphereID = try builder.sphere(
            radius: .constant(.length(10.0, unit: .millimeter))
        )
        _ = try builder.mirror(
            sphereID,
            planeOrigin: Point3D(x: 0.05, y: 0.0, z: 0.0),
            planeNormal: Vector3D(x: 1.0, y: 1.0, z: 0.5)
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(
            builder.build(name: "Spherical mirror")
        )

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 2.0 * 4.0 * Double.pi * 0.010 * 0.010 * 0.010 / 3.0
        ) <= 1.0e-12)
        #expect(evaluated.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func mirrorUnionsOverlappingBoxExactly() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let mirrorID = try builder.mirror(
            extrudeID,
            planeOrigin: Point3D(x: 0.010, y: 0.0, z: 0.0),
            planeNormal: .unitX
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(
            builder.build(name: "Overlapping mirror")
        )

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 0.060 * 0.020 * 0.010
        ) <= 1.0e-12)
        let lineage = evaluated.lineage.values.filter {
            $0.output.featureID == mirrorID
        }
        #expect(lineage.isEmpty == false)
        #expect(lineage.flatMap(\.parents).allSatisfy {
            $0.featureID == extrudeID
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func cutMirrorKeepsTheSideOppositeTheNormalAndJoinsItsReflection() throws {
        // The box spans x ∈ [−20, 20] mm. Normal −X keeps x ≥ 10 mm, reflected onto [0, 10] mm.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let mirrorID = try builder.mirror(
            extrudeID,
            planeOrigin: Point3D(x: 0.010, y: 0.0, z: 0.0),
            planeNormal: Vector3D(x: -1, y: 0, z: 0),
            cutsAtPlane: true
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build(name: "Cut mirror"))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.020 * 0.020 * 0.010) <= 1.0e-12)
        let xs = evaluated.brep.vertices.values.map(\.point.x)
        #expect(abs((xs.min() ?? .nan) - 0.0) <= 1.0e-9)
        #expect(abs((xs.max() ?? .nan) - 0.020) <= 1.0e-9)
        let lineage = evaluated.lineage.values.filter { $0.output.featureID == mirrorID }
        #expect(lineage.isEmpty == false)
        #expect(lineage.flatMap(\.parents).allSatisfy { $0.featureID == extrudeID })
        #expect(evaluated.subshapes.entries.keys.allSatisfy { $0.featureID == mirrorID || $0.featureID != extrudeID })
    }

    @Test(.timeLimit(.minutes(1)))
    func mirrorOutputsTheReflectionAloneOrTheKeptHalfAlone() throws {
        var reflected = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try reflected.mirror(
            try appendBox(to: &reflected),
            planeOrigin: Point3D(x: 0.050, y: 0.0, z: 0.0),
            planeNormal: .unitX,
            output: .reflection
        )
        let reflection = try CADPipeline(tolerance: .standard).evaluate(reflected.build(name: "Reflection"))
        try reflection.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(reflection.brep.shells.count == 1)
        #expect(abs(try reflection.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let reflectedXs = reflection.brep.vertices.values.map(\.point.x)
        #expect(abs((reflectedXs.min() ?? .nan) - 0.080) <= 1.0e-9)
        #expect(abs((reflectedXs.max() ?? .nan) - 0.120) <= 1.0e-9)

        var kept = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try kept.mirror(
            try appendBox(to: &kept),
            planeOrigin: Point3D(x: 0.010, y: 0.0, z: 0.0),
            planeNormal: .unitX,
            output: .kept,
            cutsAtPlane: true
        )
        let half = try CADPipeline(tolerance: .standard).evaluate(kept.build(name: "Kept half"))
        try half.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try half.brep.volume(tolerance: .standard) - 0.030 * 0.020 * 0.010) <= 1.0e-12)
        let keptXs = half.brep.vertices.values.map(\.point.x)
        #expect(abs((keptXs.max() ?? .nan) - 0.010) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func cutMirrorRefusesATargetEntirelyOnTheDiscardedSideAndKeepOnlyWithoutACut() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.mirror(
            try appendBox(to: &builder),
            planeOrigin: Point3D(x: -0.050, y: 0.0, z: 0.0),
            planeNormal: .unitX,
            cutsAtPlane: true
        )
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build(name: "Nothing kept"))
        }
        #expect(throws: (any Error).self) {
            try MirrorFeature(
                target: PatternTargetReference(featureID: FeatureID()),
                planeOrigin: .origin, planeNormal: .unitX, output: .kept
            ).validate(tolerance: .standard)
        }
    }

    @Test func mirrorsWrittenBeforeTheOptionsDecodeAsCombinedAndUncut() throws {
        let legacy = MirrorFeature(
            target: PatternTargetReference(featureID: FeatureID()),
            planeOrigin: .origin,
            planeNormal: .unitX
        )
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "output")
        object.removeValue(forKey: "cutsAtPlane")
        let decoded = try JSONDecoder().decode(MirrorFeature.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == legacy)
        #expect(decoded.output == .combined)
        #expect(decoded.cutsAtPlane == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageKeepsMirrorOptionsAndAPlacedBooleanTool() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let target = try appendBox(to: &builder)
        let tool = try appendBox(to: &builder)
        let mirrorID = try builder.mirror(
            target,
            planeOrigin: Point3D(x: 0.010, y: 0.0, z: 0.0),
            planeNormal: .unitX,
            output: .reflection,
            cutsAtPlane: true
        )
        var document = try builder.build(name: "Package options")
        let booleanID = FeatureID()
        try document.appendFeatures([
            FeatureNode(
                id: booleanID,
                operation: .boolean(BooleanFeature(
                    targets: [BooleanTargetReference(featureID: mirrorID)],
                    tool: BooleanToolReference(featureID: tool),
                    operation: .union,
                    toolPlacement: .translated(by: Vector3D(x: 0.020, y: 0, z: 0))
                )),
                inputs: [FeatureInput(featureID: mirrorID, role: .target), FeatureInput(featureID: tool, role: .body)],
                outputs: [FeatureOutput(role: .body)]
            ),
        ], tolerance: .standard)
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))
        guard case .mirror(let mirror) = loaded.designGraph.nodes[mirrorID]?.operation,
              case .boolean(let boolean) = loaded.designGraph.nodes[booleanID]?.operation else {
            Issue.record("The native package must keep the mirror and the Boolean.")
            return
        }
        #expect(mirror.output == .reflection)
        #expect(mirror.cutsAtPlane)
        #expect(boolean.toolPlacement == .translated(by: Vector3D(x: 0.020, y: 0, z: 0)))
    }

    @Test(.timeLimit(.minutes(1)))
    func cutMirrorOfACylinderAcrossItsAxisRebuildsTheWholeCylinder() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(
            radius: .constant(.length(10.0, unit: .millimeter)),
            height: .constant(.length(20.0, unit: .millimeter))
        )
        _ = try builder.mirror(cylinderID, planeOrigin: .origin, planeNormal: .unitX, cutsAtPlane: true)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build(name: "Cylinder cut mirror"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * 0.010 * 0.010 * 0.020) <= 1.0e-12)
    }

    private func appendBox(to builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        return try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
    }
}
