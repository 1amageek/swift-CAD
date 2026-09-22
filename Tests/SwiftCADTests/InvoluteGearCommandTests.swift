import Foundation
import Testing
import SwiftCAD

@Suite("Native gear command parity", .timeLimit(.minutes(1)))
struct InvoluteGearCommandTests {
    @Test func builderAndPublicCommandRetainEditableSource() throws {
        var gear = InvoluteGearFeature(toothCount: 32, dimensions: [
            .baseRadius: .constant(.length(0.03007, unit: .meter)),
            .pitchRadius: .constant(.length(0.032, unit: .meter)),
            .tipRadius: .constant(.length(0.034, unit: .meter)),
            .rootRadius: .constant(.length(0.0295, unit: .meter)),
            .filletRadius: .constant(.length(0.00076, unit: .meter)),
            .pitchToothAngle: .constant(.angle(.pi / 32, unit: .radian)),
            .width: .constant(.length(0.01, unit: .meter)),
            .twistAngle: .constant(.angle(0.1, unit: .radian)),
            .profileError: .constant(.length(1e-7, unit: .meter)),
            .sweepError: .constant(.length(1e-6, unit: .meter))
        ], doubleHelical: true)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let id = try builder.involuteGear(gear, named: "Gear")
        let built = try builder.build(name: "Gear parity")
        let command = CADCommand.appendFeature(FeatureRequest(id: id, name: "Gear",
            operation: .involuteGear(gear)))
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
        let editor = DocumentEditor()
        let appended = try editor.apply(decoded, to: CADDocument(units: .meters), tolerance: .standard)
        #expect(appended.designGraph == built.designGraph)
        gear.dimensions[.width] = .constant(.length(0.02, unit: .meter))
        let updated = try editor.apply(.replaceFeature(FeatureRequest(id: id, name: "Gear",
            operation: .involuteGear(gear))), to: appended, tolerance: .standard)
        #expect(updated.designGraph.order == [id])
        #expect(updated.designGraph.nodes[id]?.operation == .involuteGear(gear))
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(updated))
        #expect(restored.designGraph == updated.designGraph)
        gear.toothCount = 2
        #expect(throws: KernelError.self) {
            try editor.apply(.replaceFeature(FeatureRequest(id: id,
                operation: .involuteGear(gear))), to: updated, tolerance: .standard)
        }
        #expect(updated.designGraph.nodes[id]?.operation == restored.designGraph.nodes[id]?.operation)
    }
}
