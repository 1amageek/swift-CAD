import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

@Suite("Polynomial continuation Rebuild publication")
struct FaceRebuildPolynomialContinuationCertificationTests {
    private let requestedDistance = 1e-7

    @Test(.timeLimit(.minutes(2)))
    func callerCertificationBudgetRefusesBeforePublishingContinuation() throws {
        let fixture = try continuationFixture(surface: archSurface())
        let limits = NativeSurfacePositionCertificationLimits(
            maximumCertificationBoxes: 1,
            maximumScalarCount: 1,
            maximumWorkUnits: 1
        )
        let evaluator = DocumentEvaluator(
            featureEvaluator: DefaultFeatureEvaluator(
                nativeSurfacePositionCertificationLimits: limits
            ),
            tolerance: .standard,
            artifactPolicy: .deferred
        )
        let pipeline = CADPipeline(tolerance: .standard, evaluator: evaluator)

        do {
            _ = try pipeline.evaluate(fixture.document)
            Issue.record("A continuation certification budget below admission cost published a Rebuild.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
        #expect(fixture.document == fixture.documentSnapshot)
        #expect(fixture.surface == fixture.surfaceSnapshot)
    }

    @Test(.timeLimit(.minutes(2)))
    func cancellationRefusesBeforePublishingContinuation() async throws {
        let fixture = try continuationFixture(surface: archSurface())
        let pipeline = CADPipeline(
            tolerance: .standard,
            evaluator: DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        )
        let task = Task { () throws -> KernelError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try pipeline.evaluate(fixture.document)
                return nil
            } catch let error as KernelError {
                return error
            }
        }
        let result = try await task.value
        let failure = try #require(result)
        #expect(failure.code == .cancelled)
        #expect(fixture.document == fixture.documentSnapshot)
        #expect(fixture.surface == fixture.surfaceSnapshot)
    }

    @Test(.timeLimit(.minutes(2)))
    func varyingPositiveWeightsAreTypedUnsupported() throws {
        try expectUnsupported(surface: varyingWeightSurface())
    }

    @Test(.timeLimit(.minutes(2)))
    func multiSpanSourceIsTypedUnsupported() throws {
        try expectUnsupported(surface: multiSpanSurface())
    }

    @Test(.timeLimit(.minutes(2)))
    func zeroExtensionMultiSpanUsesTheOriginalWholeDomainCertificate() throws {
        let fixture = try continuationFixture(surface: multiSpanSurface(), extensionFraction: 0, shrinks: true)
        let pipeline = CADPipeline(
            tolerance: .standard,
            evaluator: DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        )
        do {
            _ = try pipeline.evaluate(fixture.document)
        } catch let error as KernelError {
            Issue.record("Zero-extension whole-original certification unexpectedly failed: \(error.code).")
        }
        #expect(fixture.document == fixture.documentSnapshot)
        #expect(fixture.surface == fixture.surfaceSnapshot)
    }

    private func expectUnsupported(surface: BSplineSurface3D) throws {
        let fixture = try continuationFixture(surface: surface)
        let pipeline = CADPipeline(
            tolerance: .standard,
            evaluator: DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        )
        do {
            _ = try pipeline.evaluate(fixture.document)
            Issue.record("An unsupported polynomial continuation source published a Rebuild.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
        #expect(fixture.document == fixture.documentSnapshot)
        #expect(fixture.surface == fixture.surfaceSnapshot)
    }

    private func continuationFixture(
        surface: BSplineSurface3D,
        extensionFraction: Double = 0.25,
        shrinks: Bool = false
    ) throws -> (document: CADDocument, documentSnapshot: CADDocument, surface: BSplineSurface3D, surfaceSnapshot: BSplineSurface3D) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sourceID = try builder.bSplineSurface(surface)
        let sourceDocument = try builder.build(name: "Polynomial continuation source")
        let sourceEvaluation = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(sourceDocument)
        let sourceFaceEntry = try #require(sourceEvaluation.subshapes.entries.first { key, value in
            guard key.featureID == sourceID else { return false }
            if case .face = value { return true }
            return false
        })
        let reference = try sourceEvaluation.stableSubshapeReference(for: sourceFaceEntry.key)
        _ = try builder.rebuildFaces(
            target: sourceID,
            faces: [reference],
            method: .tolerance(.constant(.length(requestedDistance, unit: .meter))),
            extendU: extensionFraction,
            extendV: 0,
            shrinks: shrinks
        )
        let document = try builder.build(name: "Polynomial continuation Rebuild")
        return (document, document, surface, surface)
    }

    private func archSurface() -> BSplineSurface3D {
        let scale = 0.02
        let row = { (v: Double) in
            [
                Point3D(x: 0, y: v * scale, z: 0),
                Point3D(x: scale / 2, y: v * scale, z: scale / 2),
                Point3D(x: scale, y: v * scale, z: 0)
            ]
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1],
            vKnots: [0, 0, 1, 1],
            controlPoints: [row(0), row(1)]
        )
    }

    private func varyingWeightSurface() -> BSplineSurface3D {
        let surface = archSurface()
        return BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            controlPoints: surface.controlPoints,
            weights: [[1, 2, 1], [1, 2, 1]]
        )
    }

    private func multiSpanSurface() -> BSplineSurface3D {
        let scale = 0.02
        let row = { (v: Double) in
            [
                Point3D(x: 0, y: v * scale, z: 0),
                Point3D(x: scale / 3, y: v * scale, z: scale / 3),
                Point3D(x: scale * 2 / 3, y: v * scale, z: scale / 3),
                Point3D(x: scale, y: v * scale, z: 0)
            ]
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0, 0, 0, 0.5, 1, 1, 1],
            vKnots: [0, 0, 1, 1],
            controlPoints: [row(0), row(1)]
        )
    }
}
