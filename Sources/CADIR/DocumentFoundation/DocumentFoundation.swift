import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

public struct DocumentFoundation: Hashable, Sendable {
    public private(set) var attributes: [DocumentAttribute]

    public init(attributes: [DocumentAttribute] = []) {
        self.attributes = attributes.sorted { $0.id < $1.id }
    }
    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case attributes }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.attributes], in: decoder)
        self.init(attributes: try c.decode([DocumentAttribute].self, forKey: .attributes))
        _ = try attributeIndex()
    }

    #endif

    public func attribute(id: DocumentAttributeID) -> DocumentAttribute? {
        attributes.first { $0.id == id }
    }

    /// Produces an attribute-table value. Its containing document must validate
    /// all local owners and reference values before publishing the value.
    public func setting(_ attribute: DocumentAttribute) throws -> DocumentFoundation {
        try attribute.validate()
        var updated = attributes
        if let index = updated.firstIndex(where: { $0.id == attribute.id }) { updated[index] = attribute }
        else { updated.append(attribute) }
        return DocumentFoundation(attributes: updated)
    }

    public func removing(_ id: DocumentAttributeID) throws -> DocumentFoundation {
        guard attributes.contains(where: { $0.id == id }) else { throw DocumentFoundationError.missingAttribute(id) }
        return DocumentFoundation(attributes: attributes.filter { $0.id != id })
    }

    public func validate(in document: CADDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(in: document, using: &execution)
    }

    public func validate(in document: CADDocument, using execution: inout OriginalQueryExecution) throws {
        let index = try attributeIndex(using: &execution)
        var names: [DocumentObjectReference: Set<String>] = [:]
        for attribute in attributes {
            try execution.consumeWork(1)
            guard attribute.owner.documentID == document.id else { throw DocumentFoundationError.foreignOwner(attribute.owner) }
            for _ in attribute.name.utf8 { try execution.consumeWork(1) }
            var ownerNames = names[attribute.owner, default: []]
            if !ownerNames.isEmpty {
                try execution.retainStorage(count: ownerNames.count, stride: MemoryLayout<String>.stride)
            }
            let insertedName = try OriginalParameterQueryStorage.insert(attribute.name, in: &ownerNames, using: &execution)
            try OriginalParameterQueryStorage.set(ownerNames, for: attribute.owner, in: &names, using: &execution)
            if !insertedName {
                throw DocumentFoundationError.duplicateName(attribute.name, owner: attribute.owner)
            }
            try validateLocal(attribute.owner, in: document, attributes: index)
            switch attribute.value {
            case .reference(let reference):
                try execution.consumeWork(1)
                try validateLocal(reference, in: document, attributes: index)
            case .references(let references):
                for reference in references {
                    try execution.consumeWork(1)
                    try validateLocal(reference, in: document, attributes: index)
                }
            default: break
            }
        }
        var complete = Set<DocumentAttributeID>()
        for attribute in attributes {
            try execution.consumeWork(1)
            if complete.contains(attribute.id) { continue }
            var path = Set<DocumentAttributeID>()
            var current: DocumentAttributeID? = attribute.id
            while let id = current, !complete.contains(id) {
                try execution.consumeWork(1)
                try execution.admitSourceDepth(path.count + 1)
                guard try OriginalParameterQueryStorage.insert(id, in: &path, using: &execution) else { throw DocumentFoundationError.ownershipCycle(id) }
                guard let owner = index[id]?.owner else { throw DocumentFoundationError.missingAttribute(id) }
                if case .attribute(let parent) = owner.target { current = parent } else { current = nil }
            }
            for id in path {
                try execution.consumeWork(1)
                if !complete.contains(id) {
                    try OriginalParameterQueryStorage.insert(id, in: &complete, using: &execution)
                }
            }
        }
    }

    private func attributeIndex() throws -> [DocumentAttributeID: DocumentAttribute] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try attributeIndex(using: &execution)
    }

    private func attributeIndex(using execution: inout OriginalQueryExecution) throws -> [DocumentAttributeID: DocumentAttribute] {
        var index: [DocumentAttributeID: DocumentAttribute] = [:]
        for attribute in attributes {
            try execution.consumeWork(1)
            try attribute.validate(using: &execution)
            let previousAttribute = index[attribute.id]
            try OriginalParameterQueryStorage.set(attribute, for: attribute.id, in: &index, using: &execution)
            guard previousAttribute == nil else { throw DocumentFoundationError.duplicateAttribute(attribute.id) }
        }
        return index
    }

    private func validateLocal(_ reference: DocumentObjectReference, in document: CADDocument,
                               attributes: [DocumentAttributeID: DocumentAttribute]) throws {
        guard reference.documentID == document.id else { return }
        let exists: Bool
        switch reference.target {
        case .document: exists = true
        case .feature(let id): exists = document.designGraph.nodes[id] != nil
        case .parameter(let id): exists = document.parameters.parameters[id] != nil
        case .attribute(let id): exists = attributes[id] != nil
        }
        guard exists else { throw DocumentFoundationError.missingTarget(reference) }
    }
}

#if !hasFeature(Embedded)
extension DocumentFoundation: Codable {}
#endif
