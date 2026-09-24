import CADCore
import CADGeometry
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
        let reference = CurveSectionReference(featureID: source)
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
            CurveSectionReference(featureID: source), from: [selected], tolerance: .standard
        )
        let section = ResolvedModelingSection.curve(resolved)
        #expect(throws: FeatureEvaluationError.self) { try section.plane() }
        #expect(throws: FeatureEvaluationError.self) { try section.profileReference() }
        #expect(try ResolvedModelingSection.curve(curve(source: source, plane: .xy)).plane() == .xy)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func reversedConicPreservesLocusClosureAndSource(trimmed: Bool) throws {
        let id = FeatureID()
        let exact = Curve3D.circle(Circle3D(center: .origin, normal: .unitZ, radius: 1))
        let parameters = [0.0, Double.pi, Double.pi * 2]
        let source = EvaluatedCurve(sourceFeatureID: id, source: .sketchEntity(SketchEntityID()), kind: .circle,
            points: try parameters.map { try exact.point(at: $0, tolerance: .standard) },
            isClosed: true, plane: .xy, exactCurve: exact,
            exactParameterDomain: .closed(0, 2 * .pi), exactPointParameters: parameters)
        let reference = CurveSectionReference(featureID: id,
            parameterDomain: trimmed ? .closed(0, .pi) : nil, isReversed: true)
        let result = try ResolvedModelingSection.resolveCurve(reference, from: [source], tolerance: .standard)
        #expect(result.sourceFeatureID == id)
        #expect(result.source == source.source)
        #expect(result.plane == .xy)
        #expect(result.isClosed == !trimmed)
        #expect(result.points[0].isApproximatelyEqual(
            to: try exact.point(at: trimmed ? .pi : 2 * .pi, tolerance: .standard), tolerance: 1e-9))
        #expect(result.points[1].y * (trimmed ? 1 : -1) > 0)
        for point in result.points {
            #expect(abs(point.x * point.x + point.y * point.y - 1) < 1e-9)
            #expect(abs(point.z) < 1e-9)
        }
        try result.validate(tolerance: .standard)
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
