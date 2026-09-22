import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADModeling
import CADExchange
import SwiftCAD

@Suite("Certified twist source and planning")
struct CertifiedTwistSweepSourceTests {
    @Test(.timeLimit(.minutes(1)))
    func sourceRoundTripDependencyReevaluationAndPlannerParity() throws {
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        var builder = DocumentBuilder(units: .meters, tolerance: tolerance)
        let angle = try builder.angleParameter(named: "rotation", 0.3, .radian)
        let error = try builder.lengthParameter(named: "rotationError", 1e-6, .meter)
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.rectangle(width: .constant(.length(0.02, unit: .meter)),
                height: .constant(.length(0.01, unit: .meter)))
            _ = sketch.circle(center: point(0, 0), radius: .constant(.length(0.002, unit: .meter)))
        }
        let path = try builder.sketch(on: .yz) { sketch in
            _ = sketch.line(from: point(0, 0), to: point(0, 0.04))
        }
        let options = SweepOptions(twistAngle: .constant(.angle(0, unit: .radian)),
            approximationTolerance: .reference(error), twistLaw: [
                SweepTwistKnot(position: 0, angle: .constant(.angle(0, unit: .radian))),
                SweepTwistKnot(position: 0.5, angle: .reference(angle)),
                SweepTwistKnot(position: 1, angle: .constant(.angle(0, unit: .radian)))
            ])
        let sweepID = try builder.sweep(profile, along: path.featureID, options: options)
        let document = try builder.build()
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: tolerance)
        try store.writePackage(for: document, to: sink)
        let packageDocument = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(try packageDocument.sourceFingerprint(tolerance: tolerance) == document.sourceFingerprint(tolerance: tolerance))
        var restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        let feature = try #require(restored.designGraph.nodes[sweepID])
        #expect(feature.operation.referencedParameterIDs == Set([angle, error]))
        #expect(try restored.sourceFingerprint(tolerance: tolerance) == document.sourceFingerprint(tolerance: tolerance))
        let planned = try SweepEvaluationPlanService().plan(document: restored,
            sections: [.profile(profile)], path: SweepPathReference(featureID: path.featureID),
            options: options, tolerance: tolerance)
        #expect(planned.evaluationKind == .certifiedStraightTwist)
        #expect(planned.status == .supported)
        let first = try DocumentEvaluator(tolerance: tolerance).evaluate(restored)
        #expect(first.brep.bodies.count == 1)
        #expect(first.brep.loops.values.filter { $0.role == .inner }.count == 2)
        try first.brep.validate(level: .exact, tolerance: tolerance)
        #expect(first.meshes.count == 1)
        restored.parameters.parameters[angle]?.expression = .constant(.angle(0.5, unit: .radian))
        let second = try DocumentEvaluator(tolerance: tolerance).evaluate(restored)
        #expect(first.brep != second.brep)
        #expect(try restored.sourceFingerprint(tolerance: tolerance) != document.sourceFingerprint(tolerance: tolerance))

        var unsupported = options
        unsupported.endScale = .constant(.scalar(0.5))
        let refusal = try SweepEvaluationPlanService().plan(document: restored,
            sections: [.profile(profile)], path: SweepPathReference(featureID: path.featureID),
            options: unsupported, tolerance: tolerance)
        #expect(refusal.status == .unsupported)
        if case .some(.sweep(var sweep)) = restored.designGraph.nodes[sweepID]?.operation {
            sweep.options = unsupported
            restored.designGraph.nodes[sweepID]?.operation = .sweep(sweep)
        }
        #expect(throws: KernelError.self) { _ = try DocumentEvaluator(tolerance: tolerance).evaluate(restored) }
    }

    @Test(.timeLimit(.minutes(1)))
    func omittedFieldsRemainUnannotatedAndInvalidLawIsRejected() throws {
        let old = SweepOptions(twistAngle: .constant(.angle(0.5, unit: .radian)))
        let decoded = try JSONDecoder().decode(SweepOptions.self, from: JSONEncoder().encode(old))
        #expect(decoded.approximationTolerance == nil)
        #expect(decoded.twistLaw == nil)
        let decision = try SweepEvaluationCapabilities().decision(for: decoded,
            geometry: .init(pathShape: .straight(profileNormalComponent: 1), sectionState: .twisted, tolerance: .standard))
        #expect(decision.unsupportedCase?.code == .sweepTwistUnavailable)
        var invalid = old
        invalid.twistLaw = [SweepTwistKnot(position: 0, angle: old.twistAngle),
            SweepTwistKnot(position: 0, angle: old.twistAngle)]
        #expect(throws: (any Error).self) { try invalid.validate() }
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
    }
}
