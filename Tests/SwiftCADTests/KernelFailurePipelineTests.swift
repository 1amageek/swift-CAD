import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD
import Testing

@Suite("Public kernel failure pipeline")
struct KernelFailurePipelineTests {
    @Test(.timeLimit(.minutes(1)))
    func realTessellationExhaustionRetainsItsCauseAndExactEvaluationStillSucceeds() throws {
        let document = try boxDocument()
        var limits = TessellationLimits.standard
        limits.maximumTriangleCount = 1
        let pipeline = CADPipeline(
            tolerance: .standard,
            evaluator: DocumentEvaluator(tolerance: .standard, tessellationLimits: limits)
        )
        do {
            _ = try pipeline.execute(.evaluatedDocument, on: document)
            Issue.record("The one-triangle budget must refuse the box mesh.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.category == .resourceExhaustion)
            #expect(error.tolerance == .standard)
        }
        let exact = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try exact.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try exact.brep.volume(tolerance: .standard) - 0.000024) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidGeometryIsRefusedByThePublicPipeline() throws {
        var document = try boxDocument()
        let featureID = try #require(document.designGraph.order.first)
        document.designGraph.nodes[featureID]?.operation = .primitive(PrimitiveFeature(
            definition: .box(BoxPrimitive(
                width: .constant(.length(-0.02, unit: .meter)),
                depth: .constant(.length(0.03, unit: .meter)),
                height: .constant(.length(0.04, unit: .meter))
            ))
        ))
        do {
            _ = try CADPipeline(tolerance: .standard).evaluate(document)
            Issue.record("A negative box width must not produce an evaluated document.")
        } catch let error as KernelError {
            #expect(error.category == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledEvaluationRetainsItsCauseThroughThePublicPipeline() async throws {
        let document = try boxDocument()
        let task = Task { () throws -> KernelError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try CADPipeline(tolerance: .standard).evaluate(document)
                return nil
            } catch let error as KernelError {
                return error
            }
        }
        let failure = try #require(try await task.value)
        #expect(failure.code == .cancelled)
        #expect(failure.category == .cancelled)
    }

    private func boxDocument() throws -> CADDocument {
        var document = CADDocument(units: .meters)
        let featureID = FeatureID()
        let operation = FeatureOperation.primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(0.02, unit: .meter)),
            depth: .constant(.length(0.03, unit: .meter)),
            height: .constant(.length(0.04, unit: .meter))
        ))))
        document.designGraph.nodes[featureID] = try FeatureNodeFactory.make(
            operation: operation, id: featureID, in: document, tolerance: .standard
        )
        document.designGraph.order.append(featureID)
        document.designGraph.revision = document.designGraph.revision.advanced()
        return document
    }
}
