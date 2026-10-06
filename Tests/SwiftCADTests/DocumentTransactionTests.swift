import Foundation
import Testing
import SwiftCAD

@Suite("Document transactions")
struct DocumentTransactionTests {
    private func limits(history: Int = 4, commands: Int = 8) throws -> DocumentTransactionLimits {
        try DocumentTransactionLimits(maximumHistoryEntries: history, maximumCommandsPerTransaction: commands)
    }

    private func boxDocument() throws -> CADDocument {
        try CADDocument.make(units: .meters, tolerance: .standard, named: "Original") { builder in
            try builder.box(width: .length(1, .meter), depth: .length(2, .meter), height: .length(3, .meter))
        }
    }

    private func session(
        _ document: CADDocument,
        history: Int = 4,
        commands: Int = 8,
        editor: any DocumentEditing = DocumentEditor(),
        evaluator: any ExactDocumentEvaluating = DocumentEvaluator(tolerance: .standard)
    ) throws -> any DocumentTransacting {
        try DocumentTransactionSession(document: document, editor: editor, evaluator: evaluator,
            limits: limits(history: history, commands: commands))
    }

    private func attribute(_ document: CADDocument, _ value: String) -> DocumentAttribute {
        DocumentAttribute(name: "label", owner: .init(documentID: document.id), value: .text(value))
    }

    private func expectError(
        _ expected: DocumentTransactionError,
        _ operation: () async throws -> Void
    ) async {
        do { try await operation(); Issue.record("Expected a transaction failure.") }
        catch let error as DocumentTransactionError { #expect(error == expected) }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    private func expectSameEvaluation(_ actual: EvaluatedDocument, _ expected: EvaluatedDocument) {
        #expect(actual.document == expected.document)
        #expect(actual.brep == expected.brep)
        #expect(actual.subshapes == expected.subshapes)
        #expect(actual.lineage == expected.lineage)
        #expect(actual.parameters.values == expected.parameters.values)
        #expect(actual.parameters.names == expected.parameters.names)
        #expect(actual.curves == expected.curves)
        #expect(actual.configuration == expected.configuration)
        #expect(actual.evaluationMetrics == expected.evaluationMetrics)
        #expect(actual.assembly == expected.assembly)
        // Native exact evaluations deliberately own no materialized mesh/cache artifacts.
        #expect(actual.meshes.isEmpty && expected.meshes.isEmpty)
        #expect(actual.caches.brep == nil && expected.caches.brep == nil)
        #expect(actual.caches.meshes.isEmpty && expected.caches.meshes.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func orderedBatchFailurePreservesPriorDraftAndCommittedState() async throws {
        let source = try boxDocument()
        let session = try session(source)
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        let retained = attribute(source, "Retained")
        let prior = try await session.stage([.setDocumentAttribute(retained)], in: token)
        var changed = retained; changed.value = .text("Must not survive")
        let dangling = DocumentAttribute(name: "dangling", owner: .init(documentID: source.id),
            value: .reference(.init(documentID: source.id, target: .feature(FeatureID()))))
        do {
            _ = try await session.stage([.setDocumentAttribute(changed), .setDocumentAttribute(dangling)], in: token)
            Issue.record("A partially failing batch was accepted.")
        } catch let error as KernelError { #expect(error.code == .missingReference) }
        let preview = try await session.preview(token)
        #expect(preview.sourceDocument == prior.sourceDocument)
        #expect(preview.commandCount == 1)
        expectSameEvaluation((await session.snapshot()).evaluatedDocument, before.evaluatedDocument)
        try await session.rollback(token)
        #expect((await session.status()).activeTransaction == nil)
        await expectError(.staleTransaction) { _ = try await session.preview(token) }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPrimitiveFailureDoesNotPublishAndDraftCanBeCorrected() async throws {
        let source = try boxDocument()
        let session = try session(source)
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        let featureID = FeatureID()
        func box(_ width: Double) -> FeatureRequest {
            FeatureRequest(id: featureID, operation: .primitive(PrimitiveFeature(definition: .box(
                BoxPrimitive(width: .length(width, .meter), depth: .length(1, .meter), height: .length(1, .meter))))))
        }
        let belowTolerance = ModelingTolerance.standard.distance / 2
        let preview = try await session.stage([.appendFeature(box(belowTolerance))], in: token)
        try preview.sourceDocument.validate(tolerance: .standard)
        do { _ = try await session.commit(token); Issue.record("Geometry below modeling tolerance was published.") }
        catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.residual == belowTolerance)
        }
        let failed = await session.snapshot()
        expectSameEvaluation(failed.evaluatedDocument, before.evaluatedDocument)
        #expect(failed.status.epoch == 0 && failed.status.undoCount == 0 && failed.status.redoCount == 0)
        #expect(failed.status.activeTransaction == token)
        _ = try await session.stage([.replaceFeature(box(2))], in: token)
        let committed = try await session.commit(token)
        #expect(committed.status.epoch == 1 && committed.status.undoCount == 1)
        #expect(committed.evaluatedDocument.brep.bodies.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoRedoRestoresCompleteDependenciesReferencesMetadataAndIdentities() async throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let widthID = try builder.lengthParameter(named: "width", 1)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: .parameter(widthID), height: .length(2, .meter))
        }
        let firstExtrude = try builder.extrude(profile, distance: .length(3, .meter))
        var source = try builder.build(name: "Before")
        source.metadata.createdAt = Date(timeIntervalSince1970: 10)
        source.metadata.updatedAt = Date(timeIntervalSince1970: 20)
        let oldReference = DocumentAttribute(name: "selected", owner: .init(documentID: source.id),
            value: .reference(.init(documentID: source.id, target: .feature(firstExtrude))))
        source = try DocumentEditor().apply(.setDocumentAttribute(oldReference), to: source, tolerance: .standard)
        let curveID = CurveID()
        let item = IndependentShapeItem(name: "Original independent line",
            geometry: .curve(curveID, trim: CurveTrim(startParameter: 0, endParameter: 1)))
        let independent = IndependentShapeSource(geometry: GeometryStore(curves: [curveID:
            .line(Line3D(origin: .origin, direction: Vector3D(x: 1, y: 0, z: 0)))]),
            items: [item], roots: [.item(item.id)])
        _ = try DefaultIndependentShapeSourceValidator().validate(independent, tolerance: .standard)
        source.independentShapes = independent
        try source.validate(tolerance: .standard)
        let session = try session(source, editor: MetadataUpdatingEditor())
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        var width = try #require(source.parameters.parameters[widthID])
        width.expression = .length(4, .meter)
        let secondID = FeatureID()
        let second = FeatureRequest(id: secondID, operation: .extrude(
            ExtrudeFeature(profile: profile, distance: .length(5, .meter), operation: .newBody)))
        var reference = oldReference
        reference.value = .reference(.init(documentID: source.id, target: .feature(secondID)))
        _ = try await session.stage([.upsertParameter(width), .appendFeature(second), .setDocumentAttribute(reference)], in: token)
        let after = try await session.commit(token)
        #expect(before.sourceDocument.independentShapes == independent)
        #expect(after.sourceDocument.independentShapes == independent)
        #expect(after.sourceDocument.designGraph.dependencies.count == source.designGraph.dependencies.count + 1)
        #expect(after.sourceDocument.documentFoundation.attribute(id: reference.id) == reference)
        #expect(after.sourceDocument.metadata.updatedAt == Date(timeIntervalSince1970: 23))
        #expect(after.sourceDocument.parameters.revision != source.parameters.revision)
        #expect(after.evaluatedDocument.brep.bodies.count == 2)
        let undone = try await session.undo(expectedEpoch: 1)
        expectSameEvaluation(undone.evaluatedDocument, before.evaluatedDocument)
        #expect(undone.status.epoch == 2 && undone.status.undoCount == 0 && undone.status.redoCount == 1)
        let redone = try await session.redo(expectedEpoch: 2)
        expectSameEvaluation(redone.evaluatedDocument, after.evaluatedDocument)
        #expect(redone.status.epoch == 3 && redone.status.undoCount == 1 && redone.status.redoCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func staleEpochAndForeignOrConsumedTokensCannotCauseABA() async throws {
        let source = try boxDocument()
        let session = try session(source)
        let other = try self.session(source)
        let foreign = try await other.begin(expectedEpoch: 0)
        await expectError(.foreignToken) { _ = try await session.preview(foreign) }
        let token = try await session.begin(expectedEpoch: 0)
        await expectError(.activeTransaction) { _ = try await session.undo(expectedEpoch: 0) }
        _ = try await session.stage([.setDocumentAttribute(attribute(source, "Changed"))], in: token)
        _ = try await session.commit(token)
        await expectError(.staleTransaction) { try await session.rollback(token) }
        _ = try await session.undo(expectedEpoch: 1)
        #expect((await session.snapshot()).sourceDocument == source)
        await expectError(.staleEpoch(expected: 0, actual: 2)) { _ = try await session.begin(expectedEpoch: 0) }
        await expectError(.staleEpoch(expected: 1, actual: 2)) { _ = try await session.redo(expectedEpoch: 1) }
        await expectError(.staleTransaction) { _ = try await session.commit(token) }
        let replacement = try await session.begin(expectedEpoch: 2)
        #expect(replacement != token)
        try await session.rollback(replacement)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentBeginAdmitsExactlyOneDraft() async throws {
        let session = try session(boxDocument())
        let outcomes = await withTaskGroup(of: BeginOutcome.self, returning: [BeginOutcome].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return .accepted(try await session.begin(expectedEpoch: 0)) }
                    catch let error as DocumentTransactionError { return .rejected(error) }
                    catch { return .unexpected }
                }
            }
            var outcomes: [BeginOutcome] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
        var accepted: [DocumentTransactionToken] = []
        var rejected = 0
        for outcome in outcomes {
            switch outcome {
            case .accepted(let token): accepted.append(token)
            case .rejected(let error): #expect(error == .transactionAlreadyActive); rejected += 1
            case .unexpected: Issue.record("Unexpected begin error.")
            }
        }
        #expect(accepted.count == 1 && rejected == 1)
        #expect((await session.status()).activeTransaction == accepted.first)
        try await session.rollback(try #require(accepted.first))
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitCapacityRejectsWithoutPruningAndNewBranchClearsRedoOnlyOnSuccess() async throws {
        #expect(throws: DocumentTransactionError.invalidLimits) { _ = try limits(history: 0) }
        #expect(throws: DocumentTransactionError.invalidLimits) { _ = try limits(commands: 0) }
        let source = try boxDocument()
        let session = try session(source, history: 1, commands: 1)
        let first = try await session.begin(expectedEpoch: 0)
        await expectError(.emptyTransaction) { _ = try await session.commit(first) }
        await expectError(.emptyCommandBatch) { _ = try await session.stage([], in: first) }
        let firstAttribute = attribute(source, "First")
        let command = CADCommand.setDocumentAttribute(firstAttribute)
        await expectError(.resourceLimitExceeded("Commands per transaction")) {
            _ = try await session.stage([command, command], in: first)
        }
        #expect((try await session.preview(first)).commandCount == 0)
        _ = try await session.stage([command], in: first)
        let full = try await session.commit(first)
        let second = try await session.begin(expectedEpoch: 1)
        var secondAttribute = firstAttribute; secondAttribute.value = .text("Second")
        _ = try await session.stage([.setDocumentAttribute(secondAttribute)], in: second)
        await expectError(.resourceLimitExceeded("History entries")) { _ = try await session.commit(second) }
        expectSameEvaluation((await session.snapshot()).evaluatedDocument, full.evaluatedDocument)
        #expect((await session.status()).undoCount == 1)
        try await session.rollback(second)
        _ = try await session.undo(expectedEpoch: 1)
        let failedBranch = try await session.begin(expectedEpoch: 2)
        let belowTolerance = ModelingTolerance.standard.distance / 2
        let invalidGeometry = FeatureRequest(operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .length(belowTolerance, .meter), depth: .length(1, .meter), height: .length(1, .meter))))))
        let invalidPreview = try await session.stage([.appendFeature(invalidGeometry)], in: failedBranch)
        try invalidPreview.sourceDocument.validate(tolerance: .standard)
        do { _ = try await session.commit(failedBranch); Issue.record("Invalid redo replacement succeeded.") }
        catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.residual == belowTolerance)
        }
        #expect((await session.status()).redoCount == 1)
        #expect((await session.status()).epoch == 2)
        try await session.rollback(failedBranch)
        let third = try await session.begin(expectedEpoch: 2)
        _ = try await session.stage([.setDocumentAttribute(attribute(source, "Branch"))], in: third)
        #expect((await session.status()).redoCount == 1)
        let branched = try await session.commit(third)
        #expect(branched.status.undoCount == 1 && branched.status.redoCount == 0)
        await expectError(.noRedo) { _ = try await session.redo(expectedEpoch: 3) }
        _ = try await session.undo(expectedEpoch: 3)
        await expectError(.noUndo) { _ = try await session.undo(expectedEpoch: 4) }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAfterActualEvaluationPreventsPublicationAndRetainsDraft() async throws {
        let source = try boxDocument()
        let session = try session(source, evaluator: CancellingEvaluator())
        let before = await session.snapshot()
        let token = try await session.begin(expectedEpoch: 0)
        let cancel = DocumentAttribute(name: "cancelAfterEvaluation", owner: .init(documentID: source.id), value: .boolean(true))
        _ = try await session.stage([.setDocumentAttribute(cancel)], in: token)
        let task = Task { try await session.commit(token) }
        do { _ = try await task.value; Issue.record("Cancelled evaluation was published.") }
        catch is CancellationError { }
        let after = await session.snapshot()
        expectSameEvaluation(after.evaluatedDocument, before.evaluatedDocument)
        #expect(after.status.epoch == 0 && after.status.undoCount == 0 && after.status.activeTransaction == token)
        try await session.rollback(token)
    }

    @Test(.timeLimit(.minutes(1)))
    func initialExactGeometryFailurePreventsSessionCreation() throws {
        #expect(throws: FeatureEvaluationError.emptyResult("Evaluation produced no bodies or curves.")) {
            _ = try session(CADDocument(units: .meters))
        }
        var source = CADDocument(units: .meters)
        let belowTolerance = ModelingTolerance.standard.distance / 2
        let request = FeatureRequest(operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .length(belowTolerance, .meter), depth: .length(1, .meter), height: .length(1, .meter))))))
        source = try DocumentEditor().apply(.appendFeature(request), to: source, tolerance: .standard)
        try source.validate(tolerance: .standard)
        do { _ = try session(source); Issue.record("Initial geometry below modeling tolerance was accepted.") }
        catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.residual == belowTolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func incompatibleInjectedOutputsNeverReplaceOwnedSourceAuthority() async throws {
        let source = try boxDocument()
        let editorSession = try session(source, editor: ForeignDocumentEditor())
        let editorToken = try await editorSession.begin(expectedEpoch: 0)
        await expectError(.incompatibleEditorOutput) {
            _ = try await editorSession.stage([.setDocumentAttribute(attribute(source, "Changed"))], in: editorToken)
        }
        #expect((try await editorSession.preview(editorToken)).sourceDocument == source)
        #expect((try await editorSession.preview(editorToken)).commandCount == 0)
        for changeTolerance in [false, true] {
            let evaluatorSession = try session(source, evaluator: IncompatibleEvaluator(changeTolerance: changeTolerance))
            let before = await evaluatorSession.snapshot()
            let token = try await evaluatorSession.begin(expectedEpoch: 0)
            let mismatch = DocumentAttribute(name: "mismatch", owner: .init(documentID: source.id), value: .boolean(true))
            _ = try await evaluatorSession.stage([.setDocumentAttribute(mismatch)], in: token)
            await expectError(.incompatibleEvaluationOutput) { _ = try await evaluatorSession.commit(token) }
            expectSameEvaluation((await evaluatorSession.snapshot()).evaluatedDocument, before.evaluatedDocument)
            #expect((await evaluatorSession.status()).activeTransaction == token)
            #expect((await evaluatorSession.status()).undoCount == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationInsideEditorPreservesTheEntireDraftBatch() async throws {
        let source = try boxDocument()
        let session = try session(source, editor: CancellingEditor())
        let token = try await session.begin(expectedEpoch: 0)
        let command = CADCommand.setDocumentAttribute(attribute(source, "Cancelled"))
        let task = Task { try await session.stage([command], in: token) }
        do { _ = try await task.value; Issue.record("Cancelled source edit was staged.") }
        catch is CancellationError { }
        let preview = try await session.preview(token)
        #expect(preview.sourceDocument == source && preview.commandCount == 0)
        let status = await session.status()
        #expect(status.epoch == 0 && status.undoCount == 0)
        try await session.rollback(token)
    }

    @Test(.timeLimit(.minutes(1)))
    func preCancelledPublicOperationsPreserveCompleteStateAndTokenLifetime() async throws {
        let source = try boxDocument()
        let session = try session(source)
        let before = await session.snapshot()
        try await expectCancelled { _ = try await session.begin(expectedEpoch: 0) }
        let token = try await session.begin(expectedEpoch: 0)
        let command = CADCommand.setDocumentAttribute(attribute(source, "Retained"))
        try await expectCancelled { _ = try await session.stage([command], in: token) }
        #expect((try await session.preview(token)).commandCount == 0)
        _ = try await session.stage([command], in: token)
        try await expectCancelled { _ = try await session.preview(token) }
        try await expectCancelled { _ = try await session.commit(token) }
        try await expectCancelled { try await session.rollback(token) }
        let unchanged = await session.snapshot()
        expectSameEvaluation(unchanged.evaluatedDocument, before.evaluatedDocument)
        #expect(unchanged.status.epoch == 0 && unchanged.status.activeTransaction == token)
        let committed = try await session.commit(token)
        try await expectCancelled { _ = try await session.undo(expectedEpoch: 1) }
        expectSameEvaluation((await session.snapshot()).evaluatedDocument, committed.evaluatedDocument)
        let undone = try await session.undo(expectedEpoch: 1)
        try await expectCancelled { _ = try await session.redo(expectedEpoch: 2) }
        expectSameEvaluation((await session.snapshot()).evaluatedDocument, undone.evaluatedDocument)
    }

    private func expectCancelled(_ operation: @Sendable @escaping () async throws -> Void) async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await operation()
        }
        do { try await task.value; Issue.record("A pre-cancelled operation succeeded.") }
        catch is CancellationError {}
    }
}

private enum BeginOutcome: Sendable {
    case accepted(DocumentTransactionToken)
    case rejected(DocumentTransactionError)
    case unexpected
}

private struct MetadataUpdatingEditor: DocumentEditing {
    func apply(_ command: CADCommand, to document: CADDocument, tolerance: ModelingTolerance) throws -> CADDocument {
        var result = try DocumentEditor().apply(command, to: document, tolerance: tolerance)
        result.metadata.updatedAt = result.metadata.updatedAt.addingTimeInterval(1)
        return result
    }
}

private struct CancellingEvaluator: ExactDocumentEvaluating {
    var evaluationTolerance: ModelingTolerance { .standard }

    func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument {
        let result = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        if document.documentFoundation.attributes.contains(where: { $0.name == "cancelAfterEvaluation" }) {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return result
    }
}

private struct ForeignDocumentEditor: DocumentEditing {
    func apply(_ command: CADCommand, to document: CADDocument, tolerance: ModelingTolerance) throws -> CADDocument {
        var result = try DocumentEditor().apply(command, to: document, tolerance: tolerance)
        result.id = DocumentID()
        return result
    }
}

private struct CancellingEditor: DocumentEditing {
    func apply(_ command: CADCommand, to document: CADDocument, tolerance: ModelingTolerance) throws -> CADDocument {
        let result = try DocumentEditor().apply(command, to: document, tolerance: tolerance)
        withUnsafeCurrentTask { $0?.cancel() }
        return result
    }
}

private struct IncompatibleEvaluator: ExactDocumentEvaluating {
    let changeTolerance: Bool
    var evaluationTolerance: ModelingTolerance { .standard }

    func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument {
        let actual = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        guard document.documentFoundation.attributes.contains(where: { $0.name == "mismatch" }) else { return actual }
        var changed = document
        var configuration = actual.configuration
        if changeTolerance { configuration.tolerance.distance *= 2 }
        else { changed.metadata.name = "Different evaluated source" }
        return EvaluatedDocument(document: changed, parameters: actual.parameters, brep: actual.brep, meshes: actual.meshes,
            curves: actual.curves, caches: actual.caches, subshapes: actual.subshapes, lineage: actual.lineage,
            configuration: configuration, evaluationMetrics: actual.evaluationMetrics)
    }
}
