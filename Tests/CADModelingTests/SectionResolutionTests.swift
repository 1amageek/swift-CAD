import CADCore
import CADIR
import CADModeling
import Testing

@Suite("Shared modeling section admission")
struct SectionResolutionTests {
    @Test(.timeLimit(.minutes(1)), arguments: [-1, 1, Int.max])
    func rejectsOutOfRangeProfileWithoutSubscriptTrap(index: Int) throws {
        let source = FeatureID()
        #expect(throws: FeatureEvaluationError.self) {
            try ResolvedModelingSection.resolveProfile(
                ProfileReference(featureID: source, profileIndex: index),
                from: [profile(source: source)]
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesSelectedProfileAndRejectsMissingOrForeignSource() throws {
        let source = FeatureID()
        let reference = ProfileReference(featureID: source, profileIndex: 1)
        let selected = profile(source: source, plane: .yz)
        #expect(try ResolvedModelingSection.resolveProfile(
            reference, from: [profile(source: source), selected]
        ) == selected)
        let missingProfiles: [[Profile]?] = [nil, [], [selected]]
        for profiles in missingProfiles {
            #expect(throws: FeatureEvaluationError.self) {
                try ResolvedModelingSection.resolveProfile(reference, from: profiles)
            }
        }
        #expect(throws: FeatureEvaluationError.self) {
            try ResolvedModelingSection.resolveProfile(
                ProfileReference(featureID: source), from: [profile(source: FeatureID())]
            )
        }
        let section = ResolvedModelingSection.profile(selected, reference)
        #expect(try section.plane() == .yz)
        #expect(try section.profileReference() == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveResolutionRejectsAmbiguityAndForeignSource() throws {
        let source = FeatureID()
        let reference = SweepCurveSectionReference(featureID: source)
        let selected = curve(source: source, plane: .xy)
        #expect(try ResolvedModelingSection.resolveCurve(
            reference, from: [selected], tolerance: .standard
        ) == selected)
        let ambiguousCurves: [[EvaluatedCurve]?] = [nil, [], [selected, selected]]
        for curves in ambiguousCurves {
            #expect(throws: KernelError.self) {
                try ResolvedModelingSection.resolveCurve(reference, from: curves, tolerance: .standard)
            }
        }
        #expect(throws: FeatureEvaluationError.self) {
            try ResolvedModelingSection.resolveCurve(
                reference, from: [curve(source: FeatureID(), plane: .xy)], tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func doesNotInventPlaneOrClosedProfileForSpatialCurve() throws {
        let source = FeatureID()
        let selected = curve(source: source, plane: nil)
        let resolved = try ResolvedModelingSection.resolveCurve(
            SweepCurveSectionReference(featureID: source), from: [selected], tolerance: .standard
        )
        let section = ResolvedModelingSection.curve(resolved)
        #expect(throws: FeatureEvaluationError.self) { try section.plane() }
        #expect(throws: FeatureEvaluationError.self) { try section.profileReference() }
        #expect(try ResolvedModelingSection.curve(curve(source: source, plane: .xy)).plane() == .xy)
    }

    private func profile(source: FeatureID, plane: SketchPlane = .xy) -> Profile {
        Profile(sourceFeatureID: source, plane: plane, vertices: [
            .origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)
        ])
    }

    private func curve(source: FeatureID, plane: SketchPlane?) -> EvaluatedCurve {
        EvaluatedCurve(sourceFeatureID: source, source: .generatedFeature, kind: .line,
            points: [.origin, Point3D(x: 1, y: 0, z: 0)], plane: plane)
    }
}
