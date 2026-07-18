import Testing
import CADCore
@testable import CADIR

@Suite("Validated CAD document mutations")
struct ValidatedCADDocumentMutationTests {
    @Test(.timeLimit(.minutes(1)))
    func graphStableReplacementPreservesValidationCertificate() throws {
        let fixture = try makeExtrudeDocument()
        let validated = try ValidatedCADDocument(fixture.document, tolerance: .standard)
        var replacement = try #require(
            fixture.document.designGraph.nodes[fixture.extrudeID]
        )
        replacement.operation = .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: fixture.sketchID),
            distance: .constant(.length(2.0, unit: .meter))
        ))

        let updated = try validated.replacingGraphStableFeature(replacement)

        #expect(updated.document.designGraph.order == fixture.document.designGraph.order)
        #expect(updated.document.designGraph.dependencies == fixture.document.designGraph.dependencies)
        #expect(
            updated.document.designGraph.revision.value
                == fixture.document.designGraph.revision.value + 1
        )
        try updated.document.validate(tolerance: updated.tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func graphStableReplacementRejectsDependencyChanges() throws {
        let fixture = try makeExtrudeDocument()
        let validated = try ValidatedCADDocument(fixture.document, tolerance: .standard)
        var replacement = try #require(
            fixture.document.designGraph.nodes[fixture.extrudeID]
        )
        replacement.inputs = []

        #expect(throws: FeatureEvaluationError.self) {
            try validated.replacingGraphStableFeature(replacement)
        }
        #expect(validated.document.designGraph.revision == fixture.document.designGraph.revision)
    }

    @Test(.timeLimit(.minutes(1)))
    func graphStableReplacementRejectsInvalidExpressions() throws {
        let fixture = try makeExtrudeDocument()
        let validated = try ValidatedCADDocument(fixture.document, tolerance: .standard)
        var replacement = try #require(
            fixture.document.designGraph.nodes[fixture.extrudeID]
        )
        replacement.operation = .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: fixture.sketchID),
            distance: .constant(.length(-1.0, unit: .meter))
        ))

        #expect(throws: FeatureEvaluationError.self) {
            try validated.replacingGraphStableFeature(replacement)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func graphStableBatchRecordsOneValidatedTransition() throws {
        let fixture = try makeExtrudeDocument()
        let validated = try ValidatedCADDocument(fixture.document, tolerance: .standard)
        var sketchReplacement = try #require(
            fixture.document.designGraph.nodes[fixture.sketchID]
        )
        sketchReplacement.name = "UpdatedSketch"
        var extrudeReplacement = try #require(
            fixture.document.designGraph.nodes[fixture.extrudeID]
        )
        extrudeReplacement.operation = .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: fixture.sketchID),
            distance: .constant(.length(2.0, unit: .meter))
        ))

        let updated = try validated.replacingGraphStableFeatures([
            sketchReplacement,
            extrudeReplacement,
        ])

        #expect(updated.transition?.sourceIdentity == validated.identity)
        #expect(updated.transition?.changedFeatureIDs == [fixture.sketchID, fixture.extrudeID])
        #expect(
            updated.document.designGraph.revision.value
                == fixture.document.designGraph.revision.value + 1
        )
        try updated.document.validate(tolerance: updated.tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func graphStableBatchRejectsDuplicateFeatureIDs() throws {
        let fixture = try makeExtrudeDocument()
        let validated = try ValidatedCADDocument(fixture.document, tolerance: .standard)
        let replacement = try #require(
            fixture.document.designGraph.nodes[fixture.extrudeID]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try validated.replacingGraphStableFeatures([replacement, replacement])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func appendValidatesOnlyTheGraphExtensionAndProducesACompleteCertificate() throws {
        let source = try ValidatedCADDocument(CADDocument(units: .meters), tolerance: .standard)
        let features = makeExtrudeFeatures()

        let updated = try source.appendingFeatures(features)

        #expect(source.document.designGraph.order.isEmpty)
        #expect(updated.document.designGraph.order == features.map(\.id))
        #expect(updated.document.designGraph.revision == DocumentRevision(1))
        #expect(updated.transition == nil)
        try updated.document.validate(tolerance: updated.tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func appendRejectsForwardDependenciesWithoutPublishingAPartialDocument() throws {
        let source = try ValidatedCADDocument(CADDocument(units: .meters), tolerance: .standard)
        let features = makeExtrudeFeatures()

        #expect(throws: FeatureEvaluationError.self) {
            try source.appendingFeatures(Array(features.reversed()))
        }
        #expect(source.document.designGraph.order.isEmpty)
        #expect(source.document.designGraph.revision == DocumentRevision())
    }

    @Test(.timeLimit(.minutes(1)))
    func appendRejectsActiveDependenciesOnSuppressedSources() throws {
        let source = try ValidatedCADDocument(CADDocument(units: .meters), tolerance: .standard)
        var features = makeExtrudeFeatures()
        features[0].isSuppressed = true

        #expect(throws: FeatureEvaluationError.self) {
            try source.appendingFeatures(features)
        }
    }

    private func makeExtrudeFeatures() -> [FeatureNode] {
        let sketchID = FeatureID()
        return [
            FeatureNode(
                id: sketchID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            FeatureNode(
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: sketchID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            ),
        ]
    }

    private func makeExtrudeDocument() throws -> (
        document: CADDocument,
        sketchID: FeatureID,
        extrudeID: FeatureID
    ) {
        var document = CADDocument(units: .meters)
        let sketchID = try document.appendFeature(
            FeatureNode(
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            tolerance: .standard
        )
        let extrudeID = try document.appendFeature(
            FeatureNode(
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: sketchID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            ),
            tolerance: .standard
        )
        return (document, sketchID, extrudeID)
    }
}
