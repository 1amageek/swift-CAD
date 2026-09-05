import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Tessellation budget and admission")
struct TessellationBudgetTests {
    // MARK: - Fixtures

    private static func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private static func placement(x: Double) -> PrimitivePlacement {
        PrimitivePlacement(
            origin: Point3D(x: x, y: 0.0, z: 0.0),
            axis: .unitZ,
            referenceDirection: .unitX
        )
    }

    /// Evaluates the supplied primitives into one document without materializing
    /// tessellation artifacts, so a test controls the limits of the tessellation
    /// it performs itself.
    private static func evaluate(
        _ definitions: [PrimitiveDefinition]
    ) throws -> EvaluatedDocument {
        try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document(definitions))
    }

    private static func document(
        _ definitions: [PrimitiveDefinition]
    ) throws -> CADDocument {
        var document = CADDocument(units: .meters)
        for (index, definition) in definitions.enumerated() {
            let featureID = FeatureID()
            let node = try FeatureNodeFactory.make(
                operation: .primitive(PrimitiveFeature(definition: definition)),
                id: featureID,
                name: "budget-\(index)",
                in: document,
                tolerance: .standard
            )
            document.designGraph.nodes[featureID] = node
            document.designGraph.order.append(featureID)
            document.designGraph.revision = document.designGraph.revision.advanced()
        }
        return document
    }

    private static func boxModel() throws -> BRepModel {
        try evaluate([
            .box(BoxPrimitive(
                width: length(2.0),
                depth: length(3.0),
                height: length(4.0)
            ))
        ]).brep
    }

    /// A model large enough that a cancellation delivered after the invocation
    /// has started still arrives long before it would finish.
    private static func slowModel() throws -> BRepModel {
        try evaluate((0..<12).map { index in
            .cylinder(CylinderPrimitive(
                placement: placement(x: Double(index) * 0.2),
                radius: length(0.03 + Double(index) * 0.002),
                height: length(0.45)
            ))
        }).brep
    }

    private static func usage(of meshes: [BodyID: Mesh]) -> (vertices: Int, indices: Int) {
        var vertices = 0
        var indices = 0
        for mesh in meshes.values {
            vertices += mesh.positions.count
            indices += mesh.indices.count
        }
        return (vertices, indices)
    }

    private static func exhaustion(
        of error: any Error
    ) -> (TessellationResource, requested: Int, limit: Int)? {
        guard let tessellationError = error as? TessellationError else { return nil }
        switch tessellationError {
        case let .resourceExhausted(resource, requested, limit):
            return (resource, requested, limit)
        default:
            return nil
        }
    }

    // MARK: - Budget contracts

    @Test(.timeLimit(.minutes(1)))
    func aBudgetRejectsInvalidLimits() {
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 0

        #expect(throws: TessellationError.self) {
            _ = try TessellationBudget(limits: limits)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func chargingAccumulatesEveryDimension() throws {
        var budget = try TessellationBudget(limits: .standard)

        try budget.charge(vertices: 10, indices: 30)
        try budget.charge(vertices: 4, indices: 6)

        #expect(budget.vertexCount == 14)
        #expect(budget.indexCount == 36)
        #expect(budget.triangleCount == 12)
        #expect(budget.byteCount == 14 * TessellationBudget.bytesPerVertex
            + 36 * TessellationBudget.bytesPerIndex)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRejectedChargeLeavesTheBudgetUnchanged() throws {
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 10
        var budget = try TessellationBudget(limits: limits)
        try budget.charge(vertices: 8, indices: 12)

        do {
            try budget.charge(vertices: 5, indices: 3)
            Issue.record("Expected the vertex limit to reject the charge.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .vertexCount)
            // The reported amount is what the invocation would have reached, not
            // the increment that crossed the limit.
            #expect(reported.requested == 13)
            #expect(reported.limit == 10)
        }

        #expect(budget.vertexCount == 8)
        #expect(budget.indexCount == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRejectedReservationLeavesTheBudgetUnchanged() throws {
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 10
        var budget = try TessellationBudget(limits: limits)
        let reservation = TessellationUsage(
            vertexCount: 11,
            indexCount: 12,
            triangleCount: 4,
            byteCount: 11 * TessellationUsage.bytesPerVertex
                + 12 * TessellationUsage.bytesPerIndex
        )

        do {
            try budget.reserve(reservation)
            Issue.record("Expected the reservation to exceed the vertex limit.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .vertexCount)
            #expect(reported.requested == 11)
            #expect(reported.limit == 10)
        }

        #expect(budget.usage == .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func eachDimensionRejectsOnItsOwnLimit() throws {
        var indexLimits = TessellationLimits.standard
        indexLimits.maximumIndexCount = 6
        var indexBudget = try TessellationBudget(limits: indexLimits)
        do {
            try indexBudget.charge(vertices: 1, indices: 9)
            Issue.record("Expected the index limit to reject the charge.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .indexCount)
        }

        var triangleLimits = TessellationLimits.standard
        triangleLimits.maximumTriangleCount = 2
        var triangleBudget = try TessellationBudget(limits: triangleLimits)
        do {
            try triangleBudget.charge(vertices: 1, indices: 9)
            Issue.record("Expected the triangle limit to reject the charge.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .triangleCount)
        }

        var byteLimits = TessellationLimits.standard
        byteLimits.maximumByteCount = 32
        var byteBudget = try TessellationBudget(limits: byteLimits)
        do {
            try byteBudget.charge(vertices: 8, indices: 3)
            Issue.record("Expected the byte limit to reject the charge.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .byteCount)
        }
    }

    /// A charge that cannot be represented is refused on the same path as one
    /// that merely exceeds a limit, so no counter can wrap into an admitted value.
    @Test(.timeLimit(.minutes(1)))
    func anOutOfRangeChargeIsReportedAsExhaustion() throws {
        var budget = try TessellationBudget(limits: .hardCeiling)

        #expect(throws: TessellationError.self) {
            try budget.charge(vertices: Int.max, indices: Int.max)
        }
        #expect(budget.vertexCount == 0)
        #expect(budget.indexCount == 0)
        #expect(budget.byteCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func anUnrepresentableByteEstimateIsNotProduced() {
        #expect(TessellationBudget.estimatedByteCount(vertices: 1, indices: 1) != nil)
        #expect(TessellationBudget.estimatedByteCount(vertices: Int.max, indices: 0) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func emissionValidationRejectsGeometricGrowthBeyondWhatWasAdmitted() throws {
        var admitted = try TessellationBudget(limits: .standard)
        try admitted.charge(vertices: 100, indices: 300)

        var withinAdmission = try TessellationBudget(limits: .standard)
        try withinAdmission.charge(vertices: 90, indices: 270)
        try withinAdmission.validateEmission(against: admitted)

        // Growth that is entirely duplicated corners is admitted: the estimate
        // covers the geometric emission, not the winding repair applied to it.
        var duplicatingEmission = try TessellationBudget(limits: .standard)
        try duplicatingEmission.charge(vertices: 130, indices: 300, duplicatedVertices: 30)
        try duplicatingEmission.validateEmission(against: admitted)

        var beyondAdmission = try TessellationBudget(limits: .standard)
        try beyondAdmission.charge(vertices: 131, indices: 300, duplicatedVertices: 30)
        do {
            try beyondAdmission.validateEmission(against: admitted)
            Issue.record("Expected geometric emission beyond the admitted estimate to be rejected.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .vertexCount)
            #expect(reported.requested == 101)
            #expect(reported.limit == 100)
        }
    }

    /// Duplicated corners are storage, so they are charged against the limits
    /// even though they are excluded from the comparison against the estimate.
    @Test(.timeLimit(.minutes(1)))
    func duplicatedCornersAreStillChargedAgainstTheLimits() throws {
        let limits = TessellationLimits.standard.lowered(
            to: TessellationLimits(
                maximumVertexCount: 100,
                maximumIndexCount: 300,
                maximumTriangleCount: 100,
                maximumByteCount: 1_000_000
            )
        )
        var budget = try TessellationBudget(limits: limits)

        do {
            try budget.charge(vertices: 101, indices: 300, duplicatedVertices: 50)
            Issue.record("Expected duplicated corners to count against the vertex limit.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.0 == .vertexCount)
            #expect(reported.requested == 101)
            #expect(reported.limit == 100)
        }
        #expect(budget.vertexCount == 0)
    }

    // MARK: - Admission before allocation

    @Test(.timeLimit(.minutes(1)))
    func aModelWithinTheStandardLimitsTessellates() throws {
        let model = try Self.boxModel()

        let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model)

        #expect(meshes.count == 1)
        #expect(Self.usage(of: meshes).vertices > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func zeroReservedRequestMatchesLegacyTessellation() throws {
        let model = try Self.boxModel()
        let validatedModel = try ValidatedBRepModel(model, tolerance: .standard)
        let tessellator = MeshTessellator(tolerance: .standard)

        let legacy = try tessellator.tessellate(
            validatedModel: validatedModel,
            options: .standard
        )
        let requested = try tessellator.tessellate(
            validatedModel: validatedModel,
            options: .standard,
            limits: .standard,
            reserving: .zero
        )

        #expect(requested == legacy)
    }

    @Test(.timeLimit(.minutes(1)))
    func reservedUsageRejectsBeforeFreshEmissionCanGrow() throws {
        let model = try Self.boxModel()
        let validatedModel = try ValidatedBRepModel(model, tolerance: .standard)
        let tessellator = MeshTessellator(tolerance: .standard)
        let existingMesh = try #require(
            tessellator.tessellate(model: model).values.first
        )
        let reserved = try TessellationUsage(mesh: existingMesh)
        let limits = TessellationLimits.standard.lowered(to: TessellationLimits(
            maximumVertexCount: 30,
            maximumIndexCount: .max,
            maximumTriangleCount: .max,
            maximumByteCount: .max
        ))

        do {
            _ = try tessellator.tessellate(
                validatedModel: validatedModel,
                options: .standard,
                limits: limits,
                reserving: reserved
            )
            Issue.record("Expected reserved usage to refuse fresh tessellation before emission.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected resource exhaustion, got \(error).")
                return
            }
            #expect(resource == .vertexCount)
            #expect(requested > limit)
            #expect(limit == 30)
        }
    }

    /// Limits set to the exact emission the model produces are still refused,
    /// because admission charges a conservative estimate of the whole invocation
    /// before any output storage is reserved. If the limits were only checked
    /// while emitting, this invocation would succeed.
    @Test(.timeLimit(.minutes(1)))
    func admissionRejectsBeforeEmissionWouldHave() throws {
        let model = try Self.boxModel()
        let emitted = Self.usage(
            of: try MeshTessellator(tolerance: .standard).tessellate(model: model)
        )
        let exactLimits = TessellationLimits(
            maximumVertexCount: emitted.vertices,
            maximumIndexCount: emitted.indices,
            maximumTriangleCount: emitted.indices / 3,
            maximumByteCount: emitted.vertices * TessellationBudget.bytesPerVertex
                + emitted.indices * TessellationBudget.bytesPerIndex
        )

        do {
            _ = try MeshTessellator(tolerance: .standard, limits: exactLimits)
                .tessellate(model: model)
            Issue.record("Expected admission to reject limits equal to the actual emission.")
        } catch {
            let reported = try #require(Self.exhaustion(of: error))
            #expect(reported.requested > reported.limit)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedInvocationLeavesTheExactModelUnchanged() throws {
        let model = try Self.boxModel()
        let before = model
        let expected = try MeshTessellator(tolerance: .standard).tessellate(model: model)
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits)
                .tessellate(model: model)
        }

        #expect(model == before)
        // The exact model still tessellates to the same meshes, so the refusal
        // left no residue behind.
        let after = try MeshTessellator(tolerance: .standard).tessellate(model: model)
        #expect(after == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidLimitsAreRefusedBeforeAnyGeometryIsRead() throws {
        let model = try Self.boxModel()
        var limits = TessellationLimits.hardCeiling
        limits.maximumIndexCount += 1

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits)
                .tessellate(model: model)
        }
    }

    // MARK: - Cancellation

    @Test(.timeLimit(.minutes(1)))
    func aCancelledTaskObservesCancellationBeforeAnyWork() async throws {
        let model = try Self.boxModel()
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)

        let task = Task {
            // Hold the task at a suspension point until the cancellation has
            // been delivered, so the tessellator is entered by an already
            // cancelled task rather than racing the cancellation.
            for await _ in gate { break }
            return try MeshTessellator(tolerance: .standard).tessellate(model: model)
        }
        task.cancel()
        opened.yield()
        opened.finish()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    /// The limits supplied to the evaluator configure the tessellation the
    /// evaluator itself performs. This is the entry point a document consumer
    /// uses, so a signature that accepts limits without threading them through
    /// would leave every consumer unbounded.
    @Test(.timeLimit(.minutes(1)))
    func theEvaluatorAppliesTheSuppliedLimitsToItsOwnTessellation() throws {
        let document = try Self.document([
            .cylinder(CylinderPrimitive(
                placement: Self.placement(x: 0.0),
                radius: Self.length(0.03),
                height: Self.length(0.45)
            ))
        ])
        let limits = TessellationLimits(
            maximumVertexCount: 1,
            maximumIndexCount: 1,
            maximumTriangleCount: 1,
            maximumByteCount: 1
        )

        #expect(throws: TessellationError.self) {
            try DocumentEvaluator(
                tolerance: .standard,
                tessellationLimits: limits,
                artifactPolicy: .materialized
            ).evaluate(document)
        }

        // The same document materializes under the package default, so the
        // refusal above is the supplied limits and not the document.
        let admitted = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .materialized
        ).evaluate(document)
        #expect(admitted.meshes.isEmpty == false)
    }

    /// Cancellation delivered after the invocation has started is observed at an
    /// interior checkpoint: the fixture takes far longer to tessellate than the
    /// delay before the cancellation, so a completed result would mean no
    /// interior checkpoint ran.
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringAnInvocationAbandonsTheRemainingWork() async throws {
        let model = try Self.slowModel()

        let task = Task {
            try MeshTessellator(tolerance: .standard).tessellate(model: model)
        }
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
