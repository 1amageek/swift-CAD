import Foundation
import Testing
@testable import SwiftCAD

@Suite("Join and unjoin feature integration")
struct JoinUnjoinFeatureIntegrationTests {
    private let boxVolume = 0.040 * 0.020 * 0.010

    @Test(.timeLimit(.minutes(1)))
    func joinBodiesMergesSeparatedBoxesIntoOneMultiShellBody() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 100.0)
        _ = try builder.joinBodies([firstBoxID, secondBoxID])
        let document = try builder.build(name: "Join parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.shellIDs.count == 2 })
        #expect(evaluated.brep.bodies.values.allSatisfy {
            $0.solidComponents?.count == 2
                && $0.solidComponents?.allSatisfy(\.voidShellIDs.isEmpty) == true
        })
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2.0 * boxVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinBodySplitsAJoinedBodyBackIntoOneBodyPerShell() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 100.0)
        let joinID = try builder.joinBodies([firstBoxID, secondBoxID])
        _ = try builder.unjoinBody(joinID)
        let document = try builder.build(name: "Join unjoin parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 2)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.shellIDs.count == 1 })
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.solidComponents?.count == 1 })
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2.0 * boxVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func joinBodiesRejectsOverlappingBoxesWithATypedCapabilityError() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 10.0)
        _ = try builder.joinBodies([firstBoxID, secondBoxID])
        let document = try builder.build(name: "Join overlap rejection")
        let pipeline = CADPipeline(tolerance: .standard)

        do {
            _ = try pipeline.evaluate(document)
            Issue.record("Joining overlapping bodies must fail with a typed invalid-input error.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func joinAcceptsDisjointCurvedBodiesWhoseConservativeBoundsOverlap() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstSphereID = try builder.sphere(
            placement: PrimitivePlacement(origin: .origin),
            radius: .constant(.length(1.0, unit: .meter))
        )
        let secondSphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 1.5, y: 1.5, z: 0.0)
            ),
            radius: .constant(.length(1.0, unit: .meter))
        )
        _ = try builder.joinBodies([firstSphereID, secondSphereID])
        let document = try builder.build(name: "Curved join bounds overlap")
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 8.0 * .pi / 3.0) <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinPreservesVoidShellWithItsOwningOuterShell() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let outerID = try builder.box(
            width: length(0.040),
            depth: length(0.030),
            height: length(0.020)
        )
        let cavityID = try builder.box(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.010, y: 0.010, z: 0.004)
            ),
            width: length(0.020),
            depth: length(0.010),
            height: length(0.010)
        )
        let cavitySolidID = try builder.boolean(
            targets: [outerID],
            tool: cavityID,
            operation: .difference
        )
        let separateID = try builder.box(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.100, y: 0.0, z: 0.0)
            ),
            width: length(0.010),
            depth: length(0.010),
            height: length(0.010)
        )
        let joinedID = try builder.joinBodies([cavitySolidID, separateID])
        _ = try builder.unjoinBody(joinedID)
        let document = try builder.build(name: "Unjoin cavity ownership")
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(document)

        let shellCounts = evaluated.brep.bodies.values.map(\.shellIDs.count).sorted()
        #expect(shellCounts == [1, 2])
        let cavityBody = try #require(evaluated.brep.bodies.values.first { $0.shellIDs.count == 2 })
        let cavityComponents = try #require(cavityBody.solidComponents)
        #expect(cavityComponents.count == 1)
        let cavityComponent = try #require(cavityComponents.first)
        #expect(cavityComponent.outerShellID == cavityBody.shellIDs[0])
        #expect(cavityComponent.voidShellIDs == [cavityBody.shellIDs[1]])
        let orientations = cavityBody.shellIDs.compactMap { evaluated.brep.shells[$0]?.orientation }
        #expect(orientations == [.forward, .reversed])
        let expectedVolume = 0.040 * 0.030 * 0.020
            - 0.020 * 0.010 * 0.010
            + 0.010 * 0.010 * 0.010
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripPreservesJoinAndUnjoinOperations() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let firstBoxID = try appendBox(to: &builder, centerX: 0.0)
        let secondBoxID = try appendBox(to: &builder, centerX: 100.0)
        let joinID = try builder.joinBodies([firstBoxID, secondBoxID])
        let unjoinID = try builder.unjoinBody(joinID)
        let document = try builder.build(name: "Join unjoin persistence")
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        guard case let .joinBodies(join) = loaded.designGraph.nodes[joinID]?.operation else {
            Issue.record("Native package persistence must preserve the joinBodies operation.")
            return
        }
        #expect(join.targets.map(\.featureID) == [firstBoxID, secondBoxID])
        guard case let .unjoinBody(unjoin) = loaded.designGraph.nodes[unjoinID]?.operation else {
            Issue.record("Native package persistence must preserve the unjoinBody operation.")
            return
        }
        #expect(unjoin.target.featureID == joinID)
    }

    private func appendBox(
        to builder: inout DocumentBuilder,
        centerX: Double
    ) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            if centerX == 0.0 {
                sketch.rectangle(
                    width: .constant(.length(40.0, unit: .millimeter)),
                    height: .constant(.length(20.0, unit: .millimeter))
                )
            } else {
                appendTranslatedRectangle(
                    to: &sketch,
                    centerX: centerX,
                    width: 40.0,
                    height: 20.0
                )
            }
        }
        return try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
    }

    private func length(_ meters: Double) -> CADExpression {
        .constant(.length(meters, unit: .meter))
    }

    /// Draws the same axis-aligned rectangle SketchBuilder.rectangle produces,
    /// translated along the sketch X axis so join sources do not overlap.
    private func appendTranslatedRectangle(
        to sketch: inout SketchBuilder,
        centerX: Double,
        width: Double,
        height: Double
    ) {
        func millimeters(_ value: Double) -> CADExpression {
            .constant(.length(value, unit: .millimeter))
        }
        let left = millimeters(centerX - width / 2.0)
        let right = millimeters(centerX + width / 2.0)
        let bottom = millimeters(-height / 2.0)
        let top = millimeters(height / 2.0)
        let bottomLeft = SketchPoint(x: left, y: bottom)
        let bottomRight = SketchPoint(x: right, y: bottom)
        let topRight = SketchPoint(x: right, y: top)
        let topLeft = SketchPoint(x: left, y: top)
        _ = sketch.line(from: bottomLeft, to: bottomRight)
        _ = sketch.line(from: bottomRight, to: topRight)
        _ = sketch.line(from: topRight, to: topLeft)
        _ = sketch.line(from: topLeft, to: bottomLeft)
    }
}
