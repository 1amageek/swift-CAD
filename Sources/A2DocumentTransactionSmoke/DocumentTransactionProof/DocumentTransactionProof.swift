import SwiftCAD

enum DocumentTransactionProof {
    static func run() async throws {
        let fixture = try TransactionProofFixture()
        try await history(fixture)
        print("A2_COMPLETE_HISTORY_OK")
        try await orderedRollback(fixture)
        try await exactFailure(fixture)
        print("A2_ATOMIC_REFUSAL_ROLLBACK_OK")
        try await tokensAndConcurrency(fixture)
        try await capacityAndRedoBranch(fixture)
        print("A2_TOKEN_CONCURRENCY_RESOURCE_OK")
        try await cancellation(fixture)
        print("A2_CANCELLATION_PUBLICATION_OK")
    }

    private static func session(_ source: CADDocument, history: Int = 4, commands: Int = 8,
        editor: any DocumentEditing = DocumentEditor(),
        evaluator: any ExactDocumentEvaluating = DocumentEvaluator(tolerance: .standard)) throws -> any DocumentTransacting {
        try DocumentTransactionSession(document: source, editor: editor, evaluator: evaluator,
            limits: DocumentTransactionLimits(maximumHistoryEntries: history, maximumCommandsPerTransaction: commands))
    }

    private static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw DocumentTransactionProofError(reason: reason) }
    }

    private static func sameEvaluation(_ actual: EvaluatedDocument, _ expected: EvaluatedDocument) throws {
        try require(actual.document == expected.document, "Complete source snapshot was not restored.")
        try require(actual.brep == expected.brep && actual.subshapes == expected.subshapes,
            "Geometry or generated subshape identities were not restored.")
        try require(actual.lineage == expected.lineage && actual.curves == expected.curves,
            "Lineage or curve state was not restored.")
        try require(actual.parameters.values == expected.parameters.values && actual.parameters.names == expected.parameters.names,
            "Resolved parameter state was not restored.")
        try require(actual.configuration == expected.configuration && actual.evaluationMetrics == expected.evaluationMetrics
            && actual.assembly == expected.assembly, "Evaluation configuration, metrics or assembly was not restored.")
        try require(actual.meshes.isEmpty && expected.meshes.isEmpty && actual.caches.brep == nil && expected.caches.brep == nil
            && actual.caches.meshes.isEmpty && expected.caches.meshes.isEmpty, "Exact snapshots unexpectedly materialized artifacts.")
    }

    private static func transactionError(_ expected: DocumentTransactionError,
        _ operation: @Sendable () async throws -> Void) async throws {
        do { try await operation() }
        catch let actual as DocumentTransactionError {
            try require(actual == expected, "Unexpected transaction refusal reason.")
            return
        }
        throw DocumentTransactionProofError(reason: "An invalid transaction operation succeeded.")
    }

    private static func cancelled(_ operation: @Sendable @escaping () async throws -> Void) async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await operation()
        }
        do { try await task.value }
        catch is CancellationError { return }
        throw DocumentTransactionProofError(reason: "A cancelled operation succeeded.")
    }

    private static func box(_ width: Double, id: FeatureID = FeatureID()) -> FeatureRequest {
        FeatureRequest(id: id, operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .length(width, .meter), depth: .length(1, .meter), height: .length(1, .meter))))))
    }

    private static func geometryFailure(_ session: any DocumentTransacting, _ token: DocumentTransactionToken,
        residual: Double) async throws {
        do { _ = try await session.commit(token) }
        catch let error as KernelError {
            try require(error.code == .invalidInput && error.residual == residual,
                "Actual exact geometry refusal had the wrong reason.")
            return
        }
        throw DocumentTransactionProofError(reason: "Geometry below tolerance was published.")
    }

    private static func history(_ fixture: TransactionProofFixture) async throws {
        let source = fixture.document
        guard let originalIndependent = source.independentShapes else {
            throw DocumentTransactionProofError(reason: "The independent source fixture is absent.")
        }
        try require(originalIndependent.items.count == 1 && originalIndependent.geometry.curves.count == 1,
            "The independent source fixture does not retain its original law.")
        let session = try session(source, editor: TransactionProofMetadataEditor())
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        guard var width = source.parameters.parameters[fixture.widthID] else {
            throw DocumentTransactionProofError(reason: "Original parameter is absent.")
        }
        width.expression = .length(4, .meter)
        let secondID = FeatureID()
        let second = FeatureRequest(id: secondID, operation: .extrude(
            ExtrudeFeature(profile: fixture.profile, distance: .length(5, .meter), operation: .newBody)))
        var reference = fixture.reference
        reference.value = .reference(.init(documentID: source.id, target: .feature(secondID)))
        let preview = try await session.stage([.upsertParameter(width), .appendFeature(second), .setDocumentAttribute(reference)], in: token)
        try require(preview.commandCount == 3, "Ordered commands were not staged together.")
        try sameEvaluation((await session.snapshot()).evaluatedDocument, before.evaluatedDocument)
        let after = try await session.commit(token)
        try require(preview.sourceDocument.independentShapes == originalIndependent
            && before.sourceDocument.independentShapes == originalIndependent
            && after.sourceDocument.independentShapes == originalIndependent,
            "Staging or exact publication changed the independent original source.")
        try require(after.sourceDocument.designGraph.dependencies.count == source.designGraph.dependencies.count + 1,
            "The new feature dependency was not published.")
        try require(after.sourceDocument.documentFoundation.attribute(id: reference.id) == reference,
            "The changed persistent reference was not published.")
        try require(after.sourceDocument.parameters.revision != source.parameters.revision
            && after.evaluatedDocument.parameters.values[fixture.widthID]?.value == 4,
            "The changed parameter was not resolved.")
        try require(after.sourceDocument.metadata != source.metadata, "The metadata transition was not exercised.")
        try require(before.evaluatedDocument.brep.bodies.count == 1 && after.evaluatedDocument.brep.bodies.count == 2,
            "The actual new-body operation did not generate geometry.")
        try require(after.status.epoch == 1 && after.status.undoCount == 1 && after.status.activeTransaction == nil,
            "Commit did not publish one complete record.")
        let undone = try await session.undo(expectedEpoch: 1)
        try sameEvaluation(undone.evaluatedDocument, before.evaluatedDocument)
        try require(undone.status.epoch == 2 && undone.status.redoCount == 1, "Undo lost monotonic history.")
        let redone = try await session.redo(expectedEpoch: 2)
        try sameEvaluation(redone.evaluatedDocument, after.evaluatedDocument)
        try require(redone.status.epoch == 3 && redone.status.redoCount == 0, "Redo lost monotonic history.")
    }

    private static func orderedRollback(_ fixture: TransactionProofFixture) async throws {
        let source = fixture.document
        let session = try session(source)
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        var retained = fixture.reference
        retained.value = .text("Retained draft")
        let prior = try await session.stage([.setDocumentAttribute(retained)], in: token)
        var changed = retained
        changed.value = .text("Must not survive")
        let dangling = DocumentAttribute(name: "dangling", owner: .init(documentID: source.id),
            value: .reference(.init(documentID: source.id, target: .feature(FeatureID()))))
        do {
            _ = try await session.stage([.setDocumentAttribute(changed), .setDocumentAttribute(dangling)], in: token)
            throw DocumentTransactionProofError(reason: "A partially invalid batch succeeded.")
        } catch let error as KernelError {
            try require(error.code == .missingReference, "The source refusal had the wrong reason.")
        }
        let preview = try await session.preview(token)
        try require(preview.sourceDocument == prior.sourceDocument && preview.commandCount == prior.commandCount,
            "A failing ordered batch partially changed the draft.")
        try sameEvaluation((await session.snapshot()).evaluatedDocument, before.evaluatedDocument)
        try await session.rollback(token)
        let rolledBack = await session.snapshot()
        try sameEvaluation(rolledBack.evaluatedDocument, before.evaluatedDocument)
        try require(rolledBack.status.epoch == 0 && rolledBack.status.undoCount == 0
            && rolledBack.status.activeTransaction == nil, "Rollback altered committed history.")
        try await transactionError(.staleTransaction) { _ = try await session.preview(token) }
    }

    private static func exactFailure(_ fixture: TransactionProofFixture) async throws {
        do {
            _ = try session(CADDocument(units: .meters))
            throw DocumentTransactionProofError(reason: "An empty initial exact result created a session.")
        } catch let error as FeatureEvaluationError {
            try require(error == .emptyResult("Evaluation produced no bodies or curves."),
                "Initial exact evaluation had the wrong refusal reason.")
        }
        let session = try session(fixture.document)
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        let id = FeatureID()
        let residual = ModelingTolerance.standard.distance / 2
        let preview = try await session.stage([.appendFeature(box(residual, id: id))], in: token)
        try preview.sourceDocument.validate(tolerance: .standard)
        try await geometryFailure(session, token, residual: residual)
        let failed = await session.snapshot()
        try sameEvaluation(failed.evaluatedDocument, before.evaluatedDocument)
        try require(failed.status.epoch == 0 && failed.status.undoCount == 0 && failed.status.activeTransaction == token,
            "Failed exact commit changed publication state.")
        _ = try await session.stage([.replaceFeature(box(2, id: id))], in: token)
        let corrected = try await session.commit(token)
        try require(corrected.status.epoch == 1 && corrected.evaluatedDocument.brep.bodies.count == 2,
            "A failed draft could not be corrected and committed.")
    }

    private static func tokensAndConcurrency(_ fixture: TransactionProofFixture) async throws {
        let session = try session(fixture.document)
        let other = try self.session(fixture.document)
        let foreign = try await other.begin(expectedEpoch: 0)
        try await transactionError(.foreignToken) { _ = try await session.preview(foreign) }
        try await other.rollback(foreign)
        let token = try await session.begin(expectedEpoch: 0)
        try await transactionError(.activeTransaction) { _ = try await session.undo(expectedEpoch: 0) }
        _ = try await session.stage([.setDocumentAttribute(fixture.reference)], in: token)
        _ = try await session.commit(token)
        _ = try await session.undo(expectedEpoch: 1)
        try await transactionError(.staleEpoch(expected: 0, actual: 2)) { _ = try await session.begin(expectedEpoch: 0) }
        try await transactionError(.staleEpoch(expected: 1, actual: 2)) { _ = try await session.redo(expectedEpoch: 1) }
        try await transactionError(.staleTransaction) { _ = try await session.commit(token) }
        let replacement = try await session.begin(expectedEpoch: 2)
        try require(replacement != token, "Undo recreated a consumed token.")
        try await session.rollback(replacement)

        let concurrent = try self.session(fixture.document)
        let outcomes = await withTaskGroup(of: TransactionProofBeginOutcome.self, returning: [TransactionProofBeginOutcome].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return .accepted(try await concurrent.begin(expectedEpoch: 0)) }
                    catch let error as DocumentTransactionError { return .rejected(error) }
                    catch { return .unexpected }
                }
            }
            var results: [TransactionProofBeginOutcome] = []
            for await result in group { results.append(result) }
            return results
        }
        var accepted: DocumentTransactionToken?
        var rejected = 0
        for result in outcomes {
            switch result {
            case .accepted(let token):
                try require(accepted == nil, "Concurrent begin admitted two drafts.")
                accepted = token
            case .rejected(let error):
                try require(error == .transactionAlreadyActive, "Concurrent begin had the wrong refusal.")
                rejected += 1
            case .unexpected: throw DocumentTransactionProofError(reason: "Concurrent begin had an unexpected error.")
            }
        }
        guard let accepted else { throw DocumentTransactionProofError(reason: "Concurrent begin admitted no draft.") }
        let status = await concurrent.status()
        try require(rejected == 1 && status.activeTransaction == accepted,
            "Concurrent admission did not retain its accepted draft.")
        try await concurrent.rollback(accepted)
    }

    private static func capacityAndRedoBranch(_ fixture: TransactionProofFixture) async throws {
        let session = try session(fixture.document, history: 1, commands: 1)
        let token = try await session.begin(expectedEpoch: 0)
        let command = CADCommand.setDocumentAttribute(fixture.reference)
        try await transactionError(.resourceLimitExceeded("Commands per transaction")) {
            _ = try await session.stage([command, command], in: token)
        }
        try require((try await session.preview(token)).commandCount == 0, "Resource refusal changed the draft.")
        _ = try await session.stage([command], in: token)
        let full = try await session.commit(token)
        let second = try await session.begin(expectedEpoch: 1)
        _ = try await session.stage([command], in: second)
        try await transactionError(.resourceLimitExceeded("History entries")) { _ = try await session.commit(second) }
        try sameEvaluation((await session.snapshot()).evaluatedDocument, full.evaluatedDocument)
        try await session.rollback(second)
        _ = try await session.undo(expectedEpoch: 1)
        let failed = try await session.begin(expectedEpoch: 2)
        let residual = ModelingTolerance.standard.distance / 2
        _ = try await session.stage([.appendFeature(box(residual))], in: failed)
        try await geometryFailure(session, failed, residual: residual)
        let status = await session.status()
        try require(status.epoch == 2 && status.redoCount == 1, "Failed branch discarded redo.")
        try await session.rollback(failed)
        let branch = try await session.begin(expectedEpoch: 2)
        _ = try await session.stage([command], in: branch)
        let committed = try await session.commit(branch)
        try require(committed.status.undoCount == 1 && committed.status.redoCount == 0, "New branch retained stale redo.")
        try await transactionError(.noRedo) { _ = try await session.redo(expectedEpoch: 3) }
    }

    private static func cancellation(_ fixture: TransactionProofFixture) async throws {
        let session = try session(fixture.document)
        let before = await session.snapshot()
        try await cancelled { _ = try await session.begin(expectedEpoch: 0) }
        let token = try await session.begin(expectedEpoch: 0)
        try await cancelled { _ = try await session.stage([.setDocumentAttribute(fixture.reference)], in: token) }
        try require((try await session.preview(token)).commandCount == 0, "Cancelled stage changed the draft.")
        _ = try await session.stage([.setDocumentAttribute(fixture.reference)], in: token)
        try await cancelled { _ = try await session.preview(token) }
        try await cancelled { _ = try await session.commit(token) }
        try await cancelled { try await session.rollback(token) }
        let retained = await session.snapshot()
        try sameEvaluation(retained.evaluatedDocument, before.evaluatedDocument)
        try require(retained.status.activeTransaction == token && retained.status.epoch == 0,
            "Cancelled publication or rollback changed state.")
        _ = try await session.commit(token)
        let committed = await session.snapshot()
        try await cancelled { _ = try await session.undo(expectedEpoch: 1) }
        try sameEvaluation((await session.snapshot()).evaluatedDocument, committed.evaluatedDocument)
        _ = try await session.undo(expectedEpoch: 1)
        let undone = await session.snapshot()
        try await cancelled { _ = try await session.redo(expectedEpoch: 2) }
        try sameEvaluation((await session.snapshot()).evaluatedDocument, undone.evaluatedDocument)
        try await cancelled { _ = try self.session(fixture.document) }

        let evaluating = try self.session(fixture.document, evaluator: TransactionProofCancellingEvaluator())
        let evaluationBefore = await evaluating.snapshot()
        let evaluationToken = try await evaluating.begin(expectedEpoch: 0)
        let attribute = DocumentAttribute(name: "cancelAfterEvaluation", owner: .init(documentID: fixture.document.id), value: .boolean(true))
        _ = try await evaluating.stage([.setDocumentAttribute(attribute)], in: evaluationToken)
        let task = Task { try await evaluating.commit(evaluationToken) }
        do { _ = try await task.value; throw DocumentTransactionProofError(reason: "Cancelled actual evaluation was published.") }
        catch is CancellationError {}
        let after = await evaluating.snapshot()
        try sameEvaluation(after.evaluatedDocument, evaluationBefore.evaluatedDocument)
        try require(after.status.epoch == 0 && after.status.undoCount == 0 && after.status.activeTransaction == evaluationToken,
            "Post-evaluation cancellation discarded the active draft.")
        try await evaluating.rollback(evaluationToken)
    }
}
