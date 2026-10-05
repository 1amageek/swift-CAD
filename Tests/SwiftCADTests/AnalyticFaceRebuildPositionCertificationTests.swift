import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation
import Testing
@testable import CADKernel
import SwiftCAD

@Suite("Original analytic Rebuild publication", .timeLimit(.minutes(2)))
struct AnalyticFaceRebuildPositionCertificationTests {
    @Test
    func originalCylinderAngularUVIsPreservedAtPublicPublication() throws {
        let fixture = try document(cylinder: true)
        let retainedDocument = fixture.document, retainedSource = fixture.sourceDocument
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(fixture.document)
        try expectExact(evaluated)
        let candidate = try rebuiltSurface(featureID: fixture.rebuildID, in: evaluated)
        guard case let .cylinder(original) = fixture.sourceSurface,
              case let .closed(u0, u1) = candidate.uDomain else {
            throw FeatureEvaluationError.invalidGraph("The original cylinder and its native output chart are required.")
        }
        #expect(original.origin == .origin && original.axis == .unitZ && original.radius == 0.01)
        #expect(candidate.uDegree == 3 && candidate.vDegree == 3)
        #expect(candidate.uControlPointCount <= 131 && candidate.vControlPointCount <= 131)
        // The original ordinary cylinder law at these same native angles is
        // (.01*cos(u), .01*sin(u), v), independently of the output's radial locus.
        for fraction in [0.13, 0.37, 0.61, 0.89] {
            let u = u0 + (u1 - u0) * fraction
            for v in [0.003, 0.011, 0.017] {
                let literal = Point3D(x: 0.01 * cos(u), y: 0.01 * sin(u), z: v)
                #expect(try (candidate.point(u: u, v: v, tolerance: .standard) - literal).length <= 1e-8)
            }
        }
        #expect(fixture.document == retainedDocument && fixture.sourceDocument == retainedSource)
        #expect(evaluated.document == fixture.document)
        #expect(fixture.sourceEvaluation.brep.geometry.surfaces.values.contains(fixture.sourceSurface))
    }

    @Test
    func faithfulOldV1AnalyticSnapshotRebuildsWhileCurrentV2StateReuses() throws {
        let fixture = try document(cylinder: false)
        let retainedDocument = fixture.document
        // Use the actual default evaluator: custom feature-evaluator injection
        // disables incremental reuse and cannot prove this provenance boundary.
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let initial = try evaluator.evaluate(fixture.document)
        let total = fixture.document.designGraph.order.count
        #expect(initial.evaluationMetrics.rebuiltFeatureCount == total)
        #expect(initial.evaluationMetrics.reusedFeatureCount == 0)
        let state = try #require(initial.incrementalEvaluationState)
        #expect(state.evaluatorIdentity == "swift-cad.document-evaluator-native-position-certification-v2")
        let reused = try evaluator.evaluate(fixture.document, reusing: initial)
        #expect(reused.evaluationMetrics.rebuiltFeatureCount == 0)
        #expect(reused.evaluationMetrics.reusedFeatureCount == total)
        #expect(reused.brep == initial.brep)
        try expectExact(reused)

        var oldV1 = initial
        // Preserve every source graph, cached feature, model and provenance field
        // except the faithful historical epoch under which analytic fitting bypassed proof.
        oldV1.incrementalEvaluationState = IncrementalEvaluationState(
            evaluatorIdentity: "swift-cad.document-evaluator-native-position-certification-v1",
            documentID: state.documentID, schemaVersion: state.schemaVersion,
            units: state.units, parameterRevision: state.parameterRevision,
            tolerance: state.tolerance, graph: state.graph, featureEntries: state.featureEntries,
            profiles: state.profiles, curves: state.curves)
        let rebuilt = try evaluator.evaluate(fixture.document, reusing: oldV1)
        #expect(rebuilt.evaluationMetrics.rebuiltFeatureCount == total)
        #expect(rebuilt.evaluationMetrics.reusedFeatureCount == 0)
        #expect(rebuilt.evaluationMetrics.invalidatedFeatureCount == total)
        #expect(rebuilt.brep == initial.brep && fixture.document == retainedDocument)
        try expectExact(rebuilt)
        let candidate = try rebuiltSurface(featureID: fixture.rebuildID, in: rebuilt)
        // The selected box top's original nil-frame plane is z=.02, U=X, V=Y.
        for (u, v) in [(0.003, 0.004), (0.009, 0.013), (0.017, 0.006)] {
            #expect(try (candidate.point(u: u, v: v, tolerance: .standard)
                - Point3D(x: u, y: v, z: 0.02)).length <= 1e-7)
        }
    }

    @Test(arguments: [false, true])
    func originalCallerProofBudgetRefusesBeforePublicInstallation(cylinder: Bool) throws {
        let fixture = try document(cylinder: cylinder)
        let retainedDocument = fixture.document, retainedBRep = fixture.sourceEvaluation.brep
        let evaluator = DocumentEvaluator(featureEvaluator: DefaultFeatureEvaluator(
            nativeSurfacePositionCertificationLimits: .init(maximumCertificationBoxes: 1,
                maximumScalarCount: 1, maximumWorkUnits: 1)),
            tolerance: .standard, artifactPolicy: .deferred)
        do {
            _ = try evaluator.evaluate(fixture.document)
            Issue.record("An analytic Rebuild bypassed its original caller position-proof allowance.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.featureID == fixture.rebuildID && error.tolerance == .standard)
        }
        #expect(fixture.document == retainedDocument && fixture.sourceEvaluation.brep == retainedBRep)
    }

    @Test
    func cancelledPublicEvaluationCannotPublishAnAnalyticRebuild() async throws {
        let fixture = try document(cylinder: false)
        let retainedDocument = fixture.document, retainedBRep = fixture.sourceEvaluation.brep
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(fixture.document)
        }
        do { _ = try await task.value; Issue.record("Cancelled analytic Rebuild evaluation published a document.") }
        catch is CancellationError {}
        #expect(fixture.document == retainedDocument && fixture.sourceEvaluation.brep == retainedBRep)
    }

    private func document(cylinder: Bool) throws -> (
        document: CADDocument, sourceDocument: CADDocument, sourceEvaluation: EvaluatedDocument,
        sourceSurface: Surface3D, rebuildID: FeatureID
    ) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sourceID: FeatureID
        if cylinder {
            sourceID = try builder.cylinder(radius: .constant(.length(0.01, unit: .meter)),
                height: .constant(.length(0.02, unit: .meter)))
        } else {
            let side = CADExpression.constant(.length(0.02, unit: .meter))
            sourceID = try builder.box(width: side, depth: side, height: side)
        }
        let sourceDocument = try builder.build(name: "Original analytic Rebuild source")
        let sourceEvaluation = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        try expectExact(sourceEvaluation)
        let keys = sourceEvaluation.subshapes.entries.compactMap { key, reference -> SubshapeID? in
            guard key.featureID == sourceID, case let .face(faceID) = reference,
                  let face = sourceEvaluation.brep.faces[faceID],
                  let surface = sourceEvaluation.brep.geometry.surfaces[face.surfaceID] else { return nil }
            if cylinder, case .cylinder = surface { return key }
            if !cylinder, case let .plane(plane) = surface, plane.normal.z > 0.99 { return key }
            return nil
        }
        let key = try #require(keys.min())
        guard case let .face(faceID)? = sourceEvaluation.subshapes.entries[key],
              let face = sourceEvaluation.brep.faces[faceID],
              let sourceSurface = sourceEvaluation.brep.geometry.surfaces[face.surfaceID] else {
            throw FeatureEvaluationError.invalidGraph("The original analytic Rebuild face must resolve.")
        }
        let reference = try sourceEvaluation.stableSubshapeReference(for: key)
        let rebuildID = try builder.rebuildFaces(target: sourceID, faces: [reference],
            method: .tolerance(.constant(.length(cylinder ? 1e-8 : 1e-7, unit: .meter))))
        return (try builder.build(name: "Original analytic Rebuild publication"), sourceDocument,
            sourceEvaluation, sourceSurface, rebuildID)
    }

    private func rebuiltSurface(featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> BSplineSurface3D {
        let candidates = evaluated.subshapes.entries.compactMap { key, reference -> BSplineSurface3D? in
            guard key.featureID == featureID, case let .face(faceID) = reference,
                  let face = evaluated.brep.faces[faceID],
                  case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return surface
        }
        #expect(candidates.count == 1)
        return try #require(candidates.first)
    }

    private func expectExact(_ evaluated: EvaluatedDocument) throws {
        let receipt = try #require(evaluated.validatedBRep)
        #expect(receipt.model == evaluated.brep && receipt.validationLevel == .exact)
        #expect(receipt.tolerance == .standard)
    }
}
