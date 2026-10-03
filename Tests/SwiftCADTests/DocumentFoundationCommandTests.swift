import Foundation
import Testing
import CADCore
import CADIR
import SwiftCAD

@Suite("Document foundation commands")
struct DocumentFoundationCommandTests {
    @Test(.timeLimit(.minutes(1)))
    func typedAttributeCommandsPersistIDsAndFailurePreservesInputCopy() throws {
        let editor: any DocumentEditing = DocumentEditor()
        let initial = CADDocument(units: .meters)
        let attribute = DocumentAttribute(name: "description", owner: .init(documentID: initial.id), value: .text("Part"))
        let command = CADCommand.setDocumentAttribute(attribute)
        let restoredCommand = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(command))
        #expect(restoredCommand == command)
        let created = try editor.apply(restoredCommand, to: initial, tolerance: .standard)
        #expect(initial.documentFoundation.attributes.isEmpty)
        #expect(created.id == initial.id)
        var edited = attribute; edited.value = .text("Edited")
        let updated = try editor.apply(.setDocumentAttribute(edited), to: created, tolerance: .standard)
        #expect(updated.documentFoundation.attributes.count == 1)
        #expect(updated.documentFoundation.attribute(id: attribute.id) == edited)
        #expect(created.documentFoundation.attribute(id: attribute.id) == attribute)
        let removed = try editor.apply(.removeDocumentAttribute(attribute.id), to: updated, tolerance: .standard)
        #expect(removed.documentFoundation.attributes.isEmpty)
        var invalid = edited; invalid.value = .reference(.init(documentID: initial.id, target: .feature(FeatureID())))
        do { _ = try editor.apply(.setDocumentAttribute(invalid), to: updated, tolerance: .standard); Issue.record("Dangling command succeeded.") }
        catch let error as KernelError { #expect(error.code == .missingReference) }
        #expect(updated.documentFoundation.attribute(id: attribute.id) == edited)
        invalid = edited; invalid.value = .real(.infinity)
        do { _ = try editor.apply(.setDocumentAttribute(invalid), to: updated, tolerance: .standard); Issue.record("Nonfinite attribute succeeded.") }
        catch let error as KernelError { #expect(error.code == .invalidInput) }
    }

    @Test(.timeLimit(.minutes(1)))
    func localAttributeOwnershipAndFeatureDeletionCannotCreateOrphans() throws {
        let editor = DocumentEditor()
        var document = CADDocument(units: .meters)
        let featureID = FeatureID()
        let box = BoxPrimitive(width: .constant(.length(1, unit: .meter)),
            depth: .constant(.length(1, unit: .meter)), height: .constant(.length(1, unit: .meter)))
        let request = FeatureRequest(id: featureID, operation: .primitive(PrimitiveFeature(definition: .box(box))))
        document = try editor.apply(.appendFeature(request),
            to: document, tolerance: .standard)
        let parent = DocumentAttribute(name: "featureLabel", owner: .init(documentID: document.id, target: .feature(featureID)), value: .text("Solid"))
        document = try editor.apply(.setDocumentAttribute(parent), to: document, tolerance: .standard)
        let child = DocumentAttribute(name: "detail", owner: .init(documentID: document.id, target: .attribute(parent.id)), value: .integer(3))
        document = try editor.apply(.setDocumentAttribute(child), to: document, tolerance: .standard)
        let preserved = document
        for command in [CADCommand.removeFeature(featureID), .removeDocumentAttribute(parent.id)] {
            do { _ = try editor.apply(command, to: document, tolerance: .standard); Issue.record("Orphaning deletion succeeded.") }
            catch let error as KernelError { #expect(error.code == .missingReference) }
            #expect(document == preserved)
        }
        document = try editor.apply(.removeDocumentAttribute(child.id), to: document, tolerance: .standard)
        document = try editor.apply(.removeDocumentAttribute(parent.id), to: document, tolerance: .standard)
        document = try editor.apply(.removeFeature(featureID), to: document, tolerance: .standard)
        #expect(document.designGraph.nodes.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalReferenceResolutionUsesOnlySuppliedSnapshotAndNeverInventsSuccess() throws {
        let resolver: any DocumentReferenceResolving = DefaultDocumentReferenceResolver()
        let editor = DocumentEditor()
        var target = CADDocument(units: .meters)
        let parameter = Parameter(name: "length", expression: .constant(.length(1, unit: .meter)), kind: .length)
        target = try editor.apply(.upsertParameter(parameter), to: target, tolerance: .standard)
        let reference = DocumentObjectReference(documentID: target.id, target: .parameter(parameter.id))
        var source = CADDocument(units: .meters)
        source = try editor.apply(.setDocumentAttribute(DocumentAttribute(name: "linkedParameter", owner: .init(documentID: source.id), value: .reference(reference))), to: source, tolerance: .standard)
        try source.validate(tolerance: .standard)
        #expect(throws: DocumentFoundationError.missingDocument(target.id)) { _ = try resolver.resolve(reference, in: [:], tolerance: .standard) }
        guard case .parameter(let first) = try resolver.resolve(reference, in: [target.id: target], tolerance: .standard) else { Issue.record("Parameter did not resolve."); return }
        #expect(first == parameter)
        var changed = parameter; changed.expression = .constant(.length(2, unit: .meter))
        let newer = try editor.apply(.upsertParameter(changed), to: target, tolerance: .standard)
        guard case .parameter(let second) = try resolver.resolve(reference, in: [newer.id: newer], tolerance: .standard) else { Issue.record("New snapshot did not resolve."); return }
        #expect(second == changed)
        #expect(first == parameter)
        #expect(throws: DocumentFoundationError.self) { _ = try resolver.resolve(reference, in: [target.id: CADDocument(units: .meters)], tolerance: .standard) }
        var deleted = target; deleted.parameters.parameters.removeValue(forKey: parameter.id)
        #expect(throws: DocumentFoundationError.missingTarget(reference)) { _ = try resolver.resolve(reference, in: [deleted.id: deleted], tolerance: .standard) }
    }
}
