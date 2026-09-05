import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing
@testable import CADKernel

/// The Mesh cache boundary: an artifact is reusable only for the purpose, the
/// fidelity, and the resource ceiling it was produced under, while exact B-rep
/// reuse stays independent of tessellation fidelity.
@Suite("Mesh cache scope")
struct MeshCacheScopeTests {
    // MARK: - Fixtures

    private static let preview = MeshArtifactPurpose(rawValue: "preview")
    private static let export = MeshArtifactPurpose(rawValue: "export")

    /// Coarser than `TessellationOptions.standard`, so the same body tessellates
    /// to a different artifact.
    private static let coarse = TessellationOptions(
        linearTolerance: 1.0e-3,
        angularTolerance: 5.0e-2
    )

    private static func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private static func document(
        _ definition: PrimitiveDefinition
    ) throws -> CADDocument {
        try primitiveDocument([definition])
    }

    private static func primitiveDocument(
        _ definitions: [PrimitiveDefinition]
    ) throws -> CADDocument {
        var document = CADDocument(units: .meters)
        for (index, definition) in definitions.enumerated() {
            let featureID = FeatureID()
            let node = try FeatureNodeFactory.make(
                operation: .primitive(PrimitiveFeature(definition: definition)),
                id: featureID,
                name: "cache-scope-\(index)",
                in: document,
                tolerance: .standard
            )
            document.designGraph.nodes[featureID] = node
            document.designGraph.order.append(featureID)
        }
        document.designGraph.revision = document.designGraph.revision.advanced()
        return document
    }

    private static func boxDocument() throws -> CADDocument {
        try document(.box(BoxPrimitive(
            width: length(2.0),
            depth: length(3.0),
            height: length(4.0)
        )))
    }

    /// A curved body, so its mesh actually responds to the angular tolerance.
    private static func cylinderDocument() throws -> CADDocument {
        try document(.cylinder(CylinderPrimitive(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(0.5),
            height: length(1.0)
        )))
    }

    private static func evaluate(
        _ document: CADDocument,
        purpose: MeshArtifactPurpose,
        options: TessellationOptions = .standard,
        limits: TessellationLimits = .standard
    ) throws -> EvaluatedDocument {
        try DocumentEvaluator(
            tolerance: .standard,
            tessellationOptions: options,
            tessellationLimits: limits,
            meshArtifactPurpose: purpose
        ).evaluate(document)
    }

    private static func cacheValidation(of error: any Error) -> CacheValidationError? {
        error as? CacheValidationError
    }

    // MARK: - Reuse requires the recorded configuration

    @Test(.timeLimit(.minutes(1)))
    func aCacheIsAcceptedForThePurposeAndFidelityItRecorded() throws {
        let source = try Self.boxDocument()
        let evaluated = try Self.evaluate(source, purpose: Self.preview)

        try evaluated.caches.validateFreshness(
            for: source,
            tolerance: .standard,
            tessellationOptions: .standard,
            purpose: Self.preview,
            limits: .standard
        )
        // The document's own self-check reads the purpose back from the cache,
        // so a purpose-scoped evaluation is not rejected by its own validation.
        try evaluated.validate()

        let cache = try #require(evaluated.caches.meshes.values.first)
        #expect(cache.purpose == Self.preview)
        #expect(cache.recordedUsage == (try TessellationUsage(mesh: cache.mesh)))
    }

    @Test(.timeLimit(.minutes(1)))
    func aCacheBuiltForOnePurposeIsNotReturnedForAnother() throws {
        let source = try Self.boxDocument()
        let evaluated = try Self.evaluate(source, purpose: Self.preview)

        do {
            try evaluated.caches.validateFreshness(
                for: source,
                tolerance: .standard,
                tessellationOptions: .standard,
                purpose: Self.export,
                limits: .standard
            )
            Issue.record("Expected the cache to refuse a different purpose.")
        } catch {
            let validation = try #require(Self.cacheValidation(of: error))
            guard case let .meshCachePurposeMismatch(_, cached, requested) = validation else {
                Issue.record("Expected a purpose mismatch, got \(validation).")
                return
            }
            #expect(cached == Self.preview)
            #expect(requested == Self.export)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aCacheBuiltAtOneFidelityIsNotReturnedAtAnother() throws {
        let source = try Self.cylinderDocument()
        let evaluated = try Self.evaluate(source, purpose: Self.preview)

        do {
            try evaluated.caches.validateFreshness(
                for: source,
                tolerance: .standard,
                tessellationOptions: Self.coarse,
                purpose: Self.preview,
                limits: .standard
            )
            Issue.record("Expected the cache to refuse a different fidelity.")
        } catch {
            let validation = try #require(Self.cacheValidation(of: error))
            guard case let .staleMeshCache(_, reason) = validation else {
                Issue.record("Expected a stale mesh cache, got \(validation).")
                return
            }
            #expect(reason.contains("Tessellation options"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func recordedUsageAboveTheRequestedLimitsIsRefused() throws {
        let source = try Self.boxDocument()
        let evaluated = try Self.evaluate(source, purpose: Self.preview)
        let cache = try #require(evaluated.caches.meshes.values.first)
        let recordedVertexCount = cache.recordedUsage.amount(for: .vertexCount)
        let narrowed = TessellationLimits.standard.lowered(
            to: TessellationLimits(
                maximumVertexCount: recordedVertexCount - 1,
                maximumIndexCount: .max,
                maximumTriangleCount: .max,
                maximumByteCount: .max
            )
        )

        do {
            try evaluated.caches.validateFreshness(
                for: source,
                tolerance: .standard,
                tessellationOptions: .standard,
                purpose: Self.preview,
                limits: narrowed
            )
            Issue.record("Expected the cache to refuse limits narrower than its recorded usage.")
        } catch {
            let validation = try #require(Self.cacheValidation(of: error))
            guard case let .meshCacheExceedsLimits(_, resource, recorded, limit) = validation else {
                Issue.record("Expected an over-limit refusal, got \(validation).")
                return
            }
            #expect(resource == .vertexCount)
            #expect(recorded == recordedVertexCount)
            #expect(limit == recordedVertexCount - 1)
        }
    }

    /// A usage that understates the artifact it is stored with would let a narrow
    /// request inherit a wider ceiling, so it is refused before the limits are
    /// consulted at all.
    @Test(.timeLimit(.minutes(1)))
    func aRecordedUsageThatDoesNotDescribeTheArtifactIsRefused() throws {
        let source = try Self.boxDocument()
        let evaluated = try Self.evaluate(source, purpose: Self.preview)
        var caches = evaluated.caches
        let bodyID = try #require(caches.meshes.keys.first)
        var cache = try #require(caches.meshes[bodyID])
        cache.recordedUsage = .zero
        caches.meshes[bodyID] = cache

        do {
            try caches.validateFreshness(
                for: source,
                tolerance: .standard,
                tessellationOptions: .standard,
                purpose: Self.preview,
                limits: .standard
            )
            Issue.record("Expected an understated usage to be refused.")
        } catch {
            let validation = try #require(Self.cacheValidation(of: error))
            guard case let .staleMeshCache(_, reason) = validation else {
                Issue.record("Expected a stale mesh cache, got \(validation).")
                return
            }
            #expect(reason.contains("Recorded usage"))
        }
    }

    // MARK: - B-rep reuse is independent of tessellation fidelity

    @Test(.timeLimit(.minutes(1)))
    func exactBRepReuseIsIndependentOfTessellationFidelity() throws {
        let source = try Self.cylinderDocument()
        let standardFidelity = try Self.evaluate(source, purpose: Self.preview)
        let coarseFidelity = try Self.evaluate(
            source,
            purpose: Self.export,
            options: Self.coarse
        )

        let standardBRep = try #require(standardFidelity.caches.brep)
        let coarseBRep = try #require(coarseFidelity.caches.brep)
        #expect(standardBRep.model == coarseBRep.model)
        #expect(standardBRep.sourceFingerprint == coarseBRep.sourceFingerprint)
        #expect(standardBRep.designRevision == coarseBRep.designRevision)
        #expect(standardBRep.parameterRevision == coarseBRep.parameterRevision)

        // The meshes, unlike the B-rep, do depend on the fidelity, so the
        // agreement above is evidence and not an artifact of an unchanged input.
        let standardMesh = try #require(standardFidelity.caches.meshes.values.first)
        let coarseMesh = try #require(coarseFidelity.caches.meshes.values.first)
        #expect(standardMesh.mesh.positions.count != coarseMesh.mesh.positions.count)
    }

    // MARK: - Incremental evaluator admission

    @Test(.timeLimit(.minutes(1)))
    func incrementalReuseRegeneratesAPurposeMismatchWithoutRelabelingTheArtifact() throws {
        let source = try Self.boxDocument()
        let preview = try Self.evaluate(source, purpose: Self.preview)
        let exportEvaluator = DocumentEvaluator(
            tolerance: .standard,
            meshArtifactPurpose: Self.export
        )

        let exported = try exportEvaluator.evaluate(source, reusing: preview)
        #expect(exported.brep == preview.brep)
        #expect(exported.evaluationMetrics.rebuiltFeatureCount == 0)
        #expect(exported.evaluationMetrics.tessellatedBodyCount == 1)
        #expect(exported.evaluationMetrics.reusedMeshCount == 0)
        let cache = try #require(exported.caches.meshes.values.first)
        #expect(cache.purpose == Self.export)
        #expect(cache.purpose != preview.caches.meshes.values.first?.purpose)
        try exported.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func incrementalReuseUsesTheSameTypedLimitRefusalAsFreshEvaluation() throws {
        let source = try Self.boxDocument()
        let preview = try Self.evaluate(source, purpose: Self.preview)
        let cache = try #require(preview.caches.meshes.values.first)
        let recordedVertexCount = cache.recordedUsage.vertexCount
        let narrowed = TessellationLimits.standard.lowered(to: TessellationLimits(
            maximumVertexCount: recordedVertexCount - 1,
            maximumIndexCount: .max,
            maximumTriangleCount: .max,
            maximumByteCount: .max
        ))
        let evaluator = DocumentEvaluator(
            tolerance: .standard,
            tessellationLimits: narrowed,
            meshArtifactPurpose: Self.preview
        )

        func resourceExhaustion(_ operation: () throws -> Void) throws -> TessellationError {
            do {
                try operation()
                Issue.record("Expected the tessellation limit to be refused.")
                return .resourceExhausted(.vertexCount, requested: 0, limit: 0)
            } catch let error as TessellationError {
                return error
            }
        }

        let freshFailure = try resourceExhaustion {
            _ = try evaluator.evaluate(source)
        }
        let reusedFailure = try resourceExhaustion {
            _ = try evaluator.evaluate(source, reusing: preview)
        }
        guard case let .resourceExhausted(freshResource, freshRequested, freshLimit) = freshFailure,
              case let .resourceExhausted(reusedResource, reusedRequested, reusedLimit) = reusedFailure else {
            Issue.record("Expected both paths to report resource exhaustion.")
            return
        }
        #expect(freshResource == reusedResource)
        #expect(freshLimit == reusedLimit)
        // Fresh admission reports its conservative estimate (25 vertices),
        // while cache admission reports the recorded artifact usage (24). Both
        // refuse the same resource against the same requested ceiling.
        #expect(freshRequested > freshLimit)
        #expect(reusedRequested > reusedLimit)
    }

    @Test(.timeLimit(.minutes(1)))
    func reusedMeshesShareOneAggregateLimit() throws {
        let source = try Self.primitiveDocument([
            .box(BoxPrimitive(
                width: Self.length(2.0),
                depth: Self.length(3.0),
                height: Self.length(4.0)
            )),
            .box(BoxPrimitive(
                width: Self.length(2.0),
                depth: Self.length(3.0),
                height: Self.length(4.0)
            )),
        ])
        let initial = try Self.evaluate(source, purpose: Self.preview)
        let limits = TessellationLimits.standard.lowered(to: TessellationLimits(
            maximumVertexCount: 30,
            maximumIndexCount: .max,
            maximumTriangleCount: .max,
            maximumByteCount: .max
        ))
        let evaluator = DocumentEvaluator(
            tolerance: .standard,
            tessellationLimits: limits,
            meshArtifactPurpose: Self.preview
        )

        do {
            _ = try evaluator.evaluate(source, reusing: initial)
            Issue.record("Expected reused meshes to be admitted cumulatively.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected aggregate resource exhaustion, got \(error).")
                return
            }
            #expect(resource == .vertexCount)
            #expect(requested > limit)
            #expect(limit == 30)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func reusedAndChangedMeshesShareOneAggregateLimit() throws {
        let source = try Self.primitiveDocument([
            .box(BoxPrimitive(
                width: Self.length(2.0),
                depth: Self.length(3.0),
                height: Self.length(4.0)
            )),
            .box(BoxPrimitive(
                width: Self.length(2.0),
                depth: Self.length(3.0),
                height: Self.length(4.0)
            )),
        ])
        let initial = try Self.evaluate(source, purpose: Self.preview)
        var edited = source
        let changedFeatureID = try #require(edited.designGraph.order.first)
        edited.designGraph.nodes[changedFeatureID]?.operation = .primitive(
            PrimitiveFeature(definition: .box(BoxPrimitive(
                width: Self.length(5.0),
                depth: Self.length(3.0),
                height: Self.length(4.0)
            ))))
        edited.designGraph.revision = edited.designGraph.revision.advanced()
        let limits = TessellationLimits.standard.lowered(to: TessellationLimits(
            maximumVertexCount: 30,
            maximumIndexCount: .max,
            maximumTriangleCount: .max,
            maximumByteCount: .max
        ))
        let evaluator = DocumentEvaluator(
            tolerance: .standard,
            tessellationLimits: limits,
            meshArtifactPurpose: Self.preview
        )

        do {
            _ = try evaluator.evaluate(edited, reusing: initial)
            Issue.record("Expected reused and changed meshes to be admitted cumulatively.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected aggregate resource exhaustion, got \(error).")
                return
            }
            #expect(resource == .vertexCount)
            #expect(requested > limit)
            #expect(limit == 30)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func injectedTessellatorOutputUsesTheAggregateLimit() throws {
        let source = try Self.boxDocument()
        let limits = TessellationLimits.standard.lowered(to: TessellationLimits(
            maximumVertexCount: 30,
            maximumIndexCount: .max,
            maximumTriangleCount: .max,
            maximumByteCount: .max
        ))
        let evaluator = DocumentEvaluator(
            tessellator: OversizedTessellator(),
            tolerance: .standard,
            tessellationLimits: limits
        )

        do {
            _ = try evaluator.evaluate(source)
            Issue.record("Expected injected tessellator output to be aggregate-limited.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected aggregate resource exhaustion, got \(error).")
                return
            }
            #expect(resource == .vertexCount)
            #expect(requested > limit)
            #expect(limit == 30)
        }
    }
}

private struct OversizedTessellator: Tessellating {
    private let base = MeshTessellator(tolerance: .standard)

    func tessellate(
        model: BRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh] {
        try base.tessellate(model: model, options: options).mapValues { mesh in
            var oversized = mesh
            oversized.positions.append(contentsOf: mesh.positions)
            oversized.normals.append(contentsOf: mesh.normals)
            return oversized
        }
    }
}
