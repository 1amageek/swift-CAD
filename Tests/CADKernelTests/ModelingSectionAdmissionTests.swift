import CADCore
import CADIR
import CADKernel
import CADModeling
import CADTopology
import Testing

@Suite("Modeling section admission through evaluation")
struct ModelingSectionAdmissionTests {
    @Test(.timeLimit(.minutes(1)), arguments: [1, Int.max])
    func sweepRejectsMissingProfileBeforeConstruction(index: Int) throws {
        let source = FeatureID()
        let path = FeatureID()
        let reference = ProfileReference(featureID: source, profileIndex: index)
        let feature = node(sections: [.profile(reference)], path: path)
        let context = context(source: source, path: path)
        #expect(throws: FeatureEvaluationError.missingProfile(source, index)) {
            try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: feature, context: context
            )
        }
        #expect(context.brep.bodies.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepDoesNotSilentlyDiscardAdditionalSections() throws {
        let source = FeatureID()
        let path = FeatureID()
        let feature = node(sections: [
            .profile(ProfileReference(featureID: source)),
            .profile(ProfileReference(featureID: FeatureID()))
        ], path: path)
        #expect(throws: FeatureEvaluationError.self) {
            try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: feature, context: context(source: source, path: path)
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resolvedProfileStillBuildsExactSolid() throws {
        let source = FeatureID()
        let path = FeatureID()
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: node(sections: [.profile(ProfileReference(featureID: source))], path: path),
            context: context(source: source, path: path)
        )
        #expect(result.brep.bodies.values.first?.kind == .solid)
        #expect(result.brep.faces.count == 5)
        try result.brep.validate(level: .exact, tolerance: .standard)
    }

    private func node(sections: [SweepSectionReference], path: FeatureID) -> FeatureNode {
        FeatureNode(operation: .sweep(SweepFeature(
            sections: sections, path: SweepPathReference(featureID: path)
        )), inputs: sections.map { FeatureInput(featureID: $0.featureID, role: $0.inputRole) }
            + [FeatureInput(featureID: path, role: .curve)], outputs: [FeatureOutput(role: .body)])
    }

    private func context(source: FeatureID, path: FeatureID) -> EvaluationContext {
        let profile = Profile(sourceFeatureID: source, plane: .xy, vertices: [
            .origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)
        ])
        let curve = EvaluatedCurve(sourceFeatureID: path, source: .generatedFeature,
            kind: .line, points: [.origin, Point3D(x: 0, y: 0, z: 1)], plane: .yz)
        return EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [source: [profile]], curves: [path: [curve]], tolerance: .standard)
    }
}
