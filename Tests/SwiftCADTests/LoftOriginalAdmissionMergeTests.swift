import CADCore
import CADIR
import CADKernel
import SwiftCAD
import Testing

@Suite("Loft original admission merge")
struct LoftOriginalAdmissionMergeTests {
    @Test(.timeLimit(.minutes(2)))
    func profileTrimmingRefusesPublicationAndRetainsAuthoredSections() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let near = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(-5, 30), to: point(20, 30))
        }.featureID
        let far = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(-5, 70), to: point(20, 70))
        }.featureID
        let left = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(0, 30), to: point(0, 70))
        }.featureID
        let right = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(10, 30), to: point(14, 70))
        }.featureID
        let loft = try builder.loft(
            sections: [near, far].map {
                LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0)))
            },
            guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: right)],
            options: LoftOptions(resultKind: .sheet, trimsProfiles: true)
        )
        try expectRefusalWithoutPublication(
            try builder.build(), loft: loft, inputs: [near, far, left, right]
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func guideEndExtensionRefusesPublicationAndRetainsAuthoredGuides() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let near = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(0, 30), to: point(10, 30))
        }.featureID
        let far = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(0, 70), to: point(10, 70))
        }.featureID
        let left = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(0, 0), to: point(0, 100))
        }.featureID
        let right = try builder.sketch(on: .xy) {
            _ = $0.line(from: point(10, 0), to: point(10, 100))
        }.featureID
        let loft = try builder.loft(
            sections: [near, far].map {
                LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0)))
            },
            guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: right)],
            options: LoftOptions(resultKind: .sheet, trimsOverlap: false)
        )
        try expectRefusalWithoutPublication(
            try builder.build(), loft: loft, inputs: [near, far, left, right]
        )
    }

    private func expectRefusalWithoutPublication(
        _ document: CADDocument,
        loft: FeatureID,
        inputs: [FeatureID]
    ) throws {
        let original = document
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let pipeline = CADPipeline(tolerance: .standard, evaluator: evaluator)
        do {
            _ = try pipeline.evaluate(document)
            Issue.record("Unsupported original Loft trimming must not publish an evaluated document.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.phase == .evaluation)
            #expect(error.featureID == loft)
            #expect(error.tolerance == .standard)
        }
        #expect(document == original)

        // The diagnostic entry must preserve the same authored source and expose
        // the failing Loft without a partial evaluated document or success state.
        let report = evaluator.evaluateReport(document)
        #expect(report.document == original)
        if case .some = report.evaluatedDocument {
            Issue.record("A failed original Loft report must not retain a published evaluated document.")
        }
        #expect(report.failure != nil)
        #expect(!report.isComplete)
        for input in inputs {
            #expect(report.featureStates[input] == .evaluated)
            #expect(report.document.designGraph.nodes[input] == original.designGraph.nodes[input])
        }
        guard case let .failed(failure)? = report.featureStates[loft] else {
            Issue.record("The original Loft must be the failed producer, not an unevaluated or successful feature.")
            return
        }
        #expect(failure.featureID == loft)
        try report.validate()
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
}
