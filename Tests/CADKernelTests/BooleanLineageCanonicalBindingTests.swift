import CADCore
import CADGeometry
import CADTopology
import Testing
@testable import CADKernel

@Suite("Boolean lineage canonical binding", .timeLimit(.minutes(1)))
struct BooleanLineageCanonicalBindingTests {
    private func execution(entry: OriginalQueryFailureContext.Entry = .admitted,
        work: Int = 1_000, checkpoint: (@Sendable () throws -> Void)? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: work,
            storageByteLimit: 1_000_000, checkpoint: checkpoint),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32),
            context: .init(operation: .unspecified, entry: entry, stage: .publication))
    }

    private func build(retain: Bool, using execution: inout OriginalQueryExecution)
        throws -> [SubshapeID: TopologyLineage] {
        let feature = FeatureID(PortableIdentity128(high: 1, low: 1))
        let vertex = Vertex(id: VertexID(PortableIdentity128(high: 2, low: 1)), point: .origin)
        let output = SubshapeID(featureID: feature, role: "result", ordinal: 0)
        var model = BRepModel()
        model.vertices[vertex.id] = vertex
        let issued = TopologyLineage(output: output, relation: .generated)
        return try BooleanTopologyLineageBuilder().build(featureID: feature,
            operandBodyIDs: [], inputModel: BRepModel(), resultModel: model,
            inputSubshapes: [:], outputSubshapes: [output: .vertex(vertex.id)],
            inputLineage: [:], tolerance: .standard,
            retainedLineage: retain ? [output: issued] : [:], using: &execution)
    }

    @Test func completeRetainedProvenanceIsPreserved() throws {
        var execution = try execution()
        let result = try build(retain: true, using: &execution)
        #expect(result.count == 1)
        #expect(result.values.first?.relation == .generated)
        #expect(execution.localWork > 0)
        #expect(execution.localStorageBytes > 0)
    }

    @Test func missingProvenanceHasIdenticalRefusalAcrossEntryContexts() throws {
        let entries: [OriginalQueryFailureContext.Entry] = [.ordinary, .admitted]
        for entry in entries {
            var execution = try execution(entry: entry)
            do {
                _ = try build(retain: false, using: &execution)
                Issue.record("Missing original provenance returned a lineage result.")
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
            }
        }
    }

    @Test func retainedPublicationPreservesResourceRefusal() throws {
        var execution = try execution(work: 0)
        do {
            _ = try build(retain: true, using: &execution)
            Issue.record("Zero-work publication returned a lineage result.")
        } catch {
            let published = OriginalQueryFailure.published(error,
                context: execution.context, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
    }

    @Test func retainedPublicationPreservesCancellation() throws {
        var execution = try execution(checkpoint: { throw CancellationError() })
        do {
            _ = try build(retain: true, using: &execution)
            Issue.record("Cancelled publication returned a lineage result.")
        } catch let error as ExactScalarFailure {
            guard case .cancelled = error else {
                Issue.record("Cancellation lost its original scalar cause.")
                return
            }
        }
    }
}
