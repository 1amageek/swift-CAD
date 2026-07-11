import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Generated name validation")
struct GeneratedNameValidatorTests {
    @Test
    func acceptsCompleteLocalCoverage() throws {
        let fixture = makeFixture()

        try GeneratedNameValidator.validate(fixture.names, in: fixture.brep)
    }

    @Test
    func rejectsMissingLocalCoverage() {
        let fixture = makeFixture()

        #expect(throws: FeatureEvaluationError.self) {
            try GeneratedNameValidator.validate([:], in: fixture.brep)
        }
    }

    @Test
    func rejectsReferenceOutsideLocalBRep() {
        let fixture = makeFixture()
        let externalName = PersistentName(components: [
            .feature(FeatureID()),
            .generated("external-body"),
        ])
        var names = fixture.names
        names[externalName] = .body(BodyID())

        #expect(throws: FeatureEvaluationError.self) {
            try GeneratedNameValidator.validate(names, in: fixture.brep)
        }
    }

    private func makeFixture() -> (
        brep: BRepModel,
        names: [PersistentName: TopologyReference]
    ) {
        let bodyID = BodyID()
        let name = PersistentName(components: [
            .feature(FeatureID()),
            .generated("body"),
        ])
        return (
            BRepModel(bodies: [
                bodyID: Body(id: bodyID, shellIDs: []),
            ]),
            [name: .body(bodyID)]
        )
    }
}
