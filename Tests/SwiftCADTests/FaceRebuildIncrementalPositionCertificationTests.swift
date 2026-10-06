import Testing
import CADCore
import CADGeometry
import CADTopology
@testable import CADKernel
import SwiftCAD

@Suite("Face Rebuild incremental position provenance")
struct FaceRebuildIncrementalPositionCertificationTests {
    @Test(.timeLimit(.minutes(2)))
    func staleNativePositionEpochForcesDefaultEvaluatorRebuild() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sourceID = try builder.bSplineSurface(nativePlane())
        let sourceDocument = try builder.build(name: "Native plane source")
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let sourceEvaluation = try evaluator.evaluate(sourceDocument)
        let sourceFaceEntry = try #require(sourceEvaluation.subshapes.entries.first { key, value in
            guard key.featureID == sourceID else { return false }
            if case .face = value { return true }
            return false
        })
        let reference = try sourceEvaluation.stableSubshapeReference(for: sourceFaceEntry.key)
        let rebuildID = try builder.rebuildFaces(
            target: sourceID,
            faces: [reference],
            method: .tolerance(.constant(.length(1e-6, unit: .meter))),
            shrinks: true
        )
        let document = try builder.build(name: "Native plane Rebuild")

        let initial = try evaluator.evaluate(document)
        #expect(initial.evaluationMetrics.rebuiltFeatureCount == document.designGraph.order.count)
        #expect(initial.evaluationMetrics.reusedFeatureCount == 0)
        try expectExactCertificate(initial)
        #expect(initial.subshapes.entries.contains { key, value in
            guard key.featureID == rebuildID else { return false }
            if case .face = value { return true }
            return false
        })

        let currentEpochReuse = try evaluator.evaluate(document, reusing: initial)
        #expect(currentEpochReuse.evaluationMetrics.rebuiltFeatureCount == 0)
        #expect(currentEpochReuse.evaluationMetrics.reusedFeatureCount == document.designGraph.order.count)
        #expect(currentEpochReuse.brep == initial.brep)
        try expectExactCertificate(currentEpochReuse)

        let initialState = try #require(initial.incrementalEvaluationState)
        var retainedOldEpoch = initial
        retainedOldEpoch.incrementalEvaluationState = IncrementalEvaluationState(
            evaluatorIdentity: "swift-cad.document-evaluator-dev",
            documentID: initialState.documentID,
            schemaVersion: initialState.schemaVersion,
            units: initialState.units,
            parameterRevision: initialState.parameterRevision,
            tolerance: initialState.tolerance,
            graph: initialState.graph,
            featureEntries: initialState.featureEntries,
            profiles: initialState.profiles,
            curves: initialState.curves
        )

        let staleEpochEvaluation = try evaluator.evaluate(document, reusing: retainedOldEpoch)
        #expect(staleEpochEvaluation.evaluationMetrics.rebuiltFeatureCount == document.designGraph.order.count)
        #expect(staleEpochEvaluation.evaluationMetrics.reusedFeatureCount == 0)
        #expect(staleEpochEvaluation.evaluationMetrics.invalidatedFeatureCount == document.designGraph.order.count)
        #expect(staleEpochEvaluation.brep == initial.brep)
        try expectExactCertificate(staleEpochEvaluation)
    }

    private func nativePlane() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0, 0, 1, 1],
            vKnots: [0, 0, 1, 1],
            controlPoints: [
                [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]
            ],
            weights: [[1, 1], [1, 1]]
        )
    }

    private func expectExactCertificate(_ document: EvaluatedDocument) throws {
        let certificate = try #require(document.validatedBRep)
        #expect(certificate.model == document.brep)
        #expect(certificate.tolerance == document.configuration.tolerance)
        #expect(certificate.validationLevel == .exact)
    }
}
