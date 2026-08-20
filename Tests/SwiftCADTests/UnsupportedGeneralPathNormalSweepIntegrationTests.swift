import Testing
@testable import SwiftCAD

@Suite("Unsupported general path-normal sweep integration")
struct UnsupportedGeneralPathNormalSweepIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func curvedPathNormalSweepReturnsTypedUnsupportedResult() throws {
        var profileSketchID: FeatureID?
        var editedPathID: FeatureID?
        let document = try CADDocument.millimeters(
            tolerance: .standard,
            named: "Section Sweep"
        ) { cad in
            let width = try cad.lengthParameter(named: "width", 8.0)
            let height = try cad.lengthParameter(named: "height", 6.0)

            let profile = try cad.sketch(on: .xy, named: "Profile") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            profileSketchID = profile.featureID
            let startSource = try cad.sketch(on: .zx, named: "Bridge start source") { sketch in
                _ = sketch.line(
                    from: sectionSweepBridgePoint(-20.0, 0.0),
                    to: sectionSweepBridgePoint(0.0, 0.0)
                )
            }
            let endSource = try cad.sketch(on: .zx, named: "Bridge end source") { sketch in
                _ = sketch.line(
                    from: sectionSweepBridgePoint(20.0, 0.0),
                    to: sectionSweepBridgePoint(40.0, 0.0)
                )
            }
            let path = try cad.bridgeCurve(
                from: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: startSource.featureID),
                    end: .end,
                    requiredLevel: .tangent
                ),
                to: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: endSource.featureID),
                    end: .start,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: .standard),
                named: "Bridge path"
            )
            let source = CurveOutputReference(featureID: path)
            let editedPath = try cad.editCurve(
                source,
                edits: [
                    .setControlPoint(CurveControlPointEdit(
                        target: CurveControlPointReference(curve: source, controlPointIndex: 1),
                        point: Point3D(x: 0.002, y: 0.0, z: 0.006)
                    ))
                ],
                named: "Edited path"
            )
            editedPathID = editedPath

            try cad.sweep(profile, along: editedPath, named: "Sweep")
        }

        let profileID = try #require(profileSketchID)
        let pathID = try #require(editedPathID)
        let plan = try SweepEvaluationPlanService().plan(
            document: document,
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            tolerance: .standard
        )
        #expect(plan.status == .unsupported)
        #expect(plan.pathShape == .curved)
        #expect(plan.unsupportedCode == .sweepPathNormalUnavailable)
        #expect(plan.evaluationKind == nil)
        #expect(plan.outputTopologyKind == nil)

        let pipeline = CADPipeline(tolerance: .standard)
        do {
            _ = try pipeline.evaluate(document)
            Issue.record("General path-normal sweep must not return sampled section topology.")
        } catch let error as KernelError {
            #expect(error.code == .sweepPathNormalUnavailable)
        }
    }
}

private func sectionSweepBridgePoint(_ z: Double, _ x: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(z, unit: .millimeter)),
        y: .constant(.length(x, unit: .millimeter))
    )
}
