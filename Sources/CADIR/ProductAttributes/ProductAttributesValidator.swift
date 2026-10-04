import CADCore

public struct ProductAttributesValidator: ProductAttributesValidating {
    private struct CharacterizationKey: Hashable {
        let kind: ProductAttributeTarget.Kind
        let subshapeID: SubshapeID
    }
    private struct ShapeElementKey: Hashable {
        let definitionID: AssemblyDefinitionID
        let kind: ProductAttributeTarget.Kind
        let subshapeID: SubshapeID
    }
    public init() {}
    public func validate(_ attributes: ProductAttributes, in document: CADDocument,
                         budget: inout ProductAttributeBudget) throws {
        let limit = budget.limits.maximumRecords
        guard attributes.materials.count <= limit,
              attributes.assignments.count <= limit - attributes.materials.count,
              attributes.layers.count <= limit - attributes.materials.count - attributes.assignments.count,
              attributes.physicalCharacterizations.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count,
              attributes.shapeElementDescriptions.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count - attributes.physicalCharacterizations.count else {
            throw ProductAttributeError.resourceLimitExceeded("Product source records.")
        }
        try budget.charge(work: attributes.materials.count + attributes.assignments.count + attributes.layers.count + attributes.physicalCharacterizations.count + attributes.shapeElementDescriptions.count)
        var materials: [PhysicalMaterialID: PhysicalMaterialDescriptor] = [:]
        for material in attributes.materials {
            try budget.charge(textBytes: material.name.utf8.count)
            try budget.charge(textBytes: material.description.utf8.count)
            try material.density?.validate()
            guard materials.updateValue(material, forKey: material.id) == nil else {
                throw ProductAttributeError.invalidSource("Duplicate physical material identity.")
            }
        }
        var assignments: [ProductAttributeID: ProductAttributeAssignment] = [:]
        for assignment in attributes.assignments {
            try validateTarget(assignment.target, in: document, budget: &budget)
            try assignment.value.validate()
            switch assignment.value {
            case let .name(value):
                try budget.charge(textBytes: value.utf8.count)
                guard assignment.target.kind == .body || assignment.target.kind == .face else {
                    throw ProductAttributeError.invalidSource("Part and occurrence names retain their existing assembly owner.")
                }
            case let .material(id):
                guard materials[id] != nil else { throw ProductAttributeError.missingTarget("Physical material descriptor.") }
            case let .descriptorDensity(id):
                guard materials[id]?.density != nil else { throw ProductAttributeError.missingTarget("Descriptor density value.") }
            case .color, .opacity, .density: break
            }
            guard assignments.updateValue(assignment, forKey: assignment.id) == nil else {
                throw ProductAttributeError.invalidSource("Duplicate product assignment identity.")
            }
        }
        for assignment in attributes.assignments {
            var cursor: ProductAttributeAssignment? = assignment
            var depth = 0
            var visited = Set<ProductAttributeID>()
            while let current = cursor {
                guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Property override depth.") }
                try budget.charge(work: 1)
                guard visited.insert(current.id).inserted else { throw ProductAttributeError.invalidSource("Property override cycle.") }
                depth += 1
                if let predecessor = current.overrides {
                    guard let previous = assignments[predecessor] else { throw ProductAttributeError.missingTarget("Property override predecessor.") }
                    guard current.value.property == previous.value.property else {
                        throw ProductAttributeError.invalidSource("Override relation crosses property kinds.")
                    }
                    cursor = previous
                } else { cursor = nil }
            }
        }
        var characterized = Set<CharacterizationKey>()
        for record in attributes.physicalCharacterizations {
            guard (record.target.kind == .body || record.target.kind == .face), record.target.definitionID == nil,
                  record.target.path == nil, record.target.usageID == nil, let geometry = record.target.geometry else {
                throw ProductAttributeError.invalidSource("Physical characterization requires a global geometry target.")
            }
            try validateTarget(record.target, in: document, budget: &budget)
            try budget.charge(textBytes: record.name.utf8.count)
            try budget.charge(textBytes: record.description?.utf8.count ?? 0)
            guard !record.name.utf8.isEmpty || record.description != nil else {
                throw ProductAttributeError.invalidSource("Default physical characterization must be absent.")
            }
            guard characterized.insert(CharacterizationKey(kind: record.target.kind, subshapeID: geometry.subshapeID)).inserted else {
                throw ProductAttributeError.invalidSource("Duplicate physical characterization target.")
            }
            var attached = false
            for assignment in attributes.assignments {
                try budget.charge(work: 1)
                if assignment.target == record.target,
                   assignment.value.property == .material || assignment.value.property == .density { attached = true }
            }
            guard attached else { throw ProductAttributeError.missingTarget("Physical characterization attachment.") }
        }
        var described = Set<ShapeElementKey>()
        for record in attributes.shapeElementDescriptions {
            guard (record.target.kind == .body || record.target.kind == .face), let definition = record.target.definitionID,
                  record.target.path == nil, record.target.usageID == nil, let geometry = record.target.geometry else {
                throw ProductAttributeError.invalidSource("Shape element description requires a definition-qualified geometry target.")
            }
            try validateTarget(record.target, in: document, budget: &budget)
            try budget.charge(textBytes: record.description.utf8.count)
            guard described.insert(ShapeElementKey(definitionID: definition, kind: record.target.kind, subshapeID: geometry.subshapeID)).inserted else {
                throw ProductAttributeError.invalidSource("Duplicate shape element description target.")
            }
            var attached = false
            for assignment in attributes.assignments {
                try budget.charge(work: 1)
                guard assignment.target == record.target else { continue }
                if case let .name(label) = assignment.value, !label.utf8.isEmpty, assignment.overrides == nil { attached = true }
                if assignment.value.property == .material || assignment.value.property == .density { attached = true }
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native and public STEP cannot retain standalone shape-element metadata without an existing name or physical attachment.
            // An independent source lifetime and equivalent standard egress are required before metadata-only shape aspects can succeed.
            guard attached else { throw ProductAttributeError.unsupportedSemantics("Standalone shape element description requires a name or physical attachment.") }
        }
        // Exact same-target conflicts are structural and do not require evaluated topology.
        for assignment in attributes.assignments {
            var winnerCount = 0
            for candidate in attributes.assignments {
                try budget.charge(work: 1)
                guard candidate.target == assignment.target, candidate.value.property == assignment.value.property else { continue }
                var overridden = false
                for other in attributes.assignments {
                    try budget.charge(work: 1)
                    guard other.target == assignment.target, other.value.property == assignment.value.property else { continue }
                    var cursor = other.overrides
                    while let id = cursor {
                        try budget.charge(work: 1)
                        if id == candidate.id { overridden = true; break }
                        cursor = assignments[id]?.overrides
                    }
                    if overridden { break }
                }
                if !overridden { winnerCount += 1 }
            }
            guard winnerCount == 1 else { throw ProductAttributeError.ambiguousProperty(assignment.value.property.rawValue) }
        }
        var layerIDs = Set<ProductLayerID>(), layerNames = Set<String>()
        for layer in attributes.layers {
            try budget.charge(textBytes: layer.name.utf8.count)
            try budget.charge(textBytes: layer.description.utf8.count)
            guard !layer.name.isEmpty, layerIDs.insert(layer.id).inserted, layerNames.insert(layer.name).inserted else {
                throw ProductAttributeError.invalidSource("Layers require unique identities and nonempty unique names.")
            }
            guard layer.members.count <= budget.limits.maximumTargets - budget.consumedTargets else {
                throw ProductAttributeError.resourceLimitExceeded("Layer member storage.")
            }
            var members = Set<ProductAttributeTarget>()
            for member in layer.members {
                try validateTarget(member, in: document, budget: &budget)
                guard members.insert(member).inserted else { throw ProductAttributeError.invalidSource("Duplicate layer membership.") }
            }
        }
    }

    private func validateTarget(_ target: ProductAttributeTarget, in document: CADDocument,
                                budget: inout ProductAttributeBudget) throws {
        try budget.charge(work: 1, targets: 1)
        try target.validate()
        if let geometry = target.geometry {
            guard let feature = document.designGraph.nodes[geometry.subshapeID.featureID], !feature.isSuppressed,
                  feature.bodyOrSheetOutput != nil else { throw ProductAttributeError.missingTarget("Active geometry source feature.") }
        }
        if let id = target.definitionID {
            guard let assembly = document.assembly else { throw ProductAttributeError.missingTarget("Part definition source.") }
            try budget.charge(work: assembly.definitions.count)
            guard let definition = assembly.definitions.first(where: { $0.id == id }) else {
                throw ProductAttributeError.missingTarget("Part definition.")
            }
            if let geometry = target.geometry {
                try budget.charge(work: definition.features.count)
                guard definition.features.contains(geometry.subshapeID.featureID) else {
                    throw ProductAttributeError.missingTarget("Geometry is not owned by the selected definition.")
                }
            }
        }
        if let usage = target.usageID {
            guard let assembly = document.assembly else { throw ProductAttributeError.missingTarget("Direct usage source.") }
            try budget.charge(work: assembly.roots.count)
            var found = assembly.roots.contains(where: { $0.id == usage })
            for definition in assembly.definitions {
                try budget.charge(work: definition.children.count + 1)
                if definition.children.contains(where: { $0.id == usage }) { found = true }
            }
            guard found else { throw ProductAttributeError.missingTarget("Direct usage.") }
        }
        if let path = target.path {
            guard path.components.count <= budget.limits.maximumDepth else {
                throw ProductAttributeError.resourceLimitExceeded("Occurrence attachment depth.")
            }
            guard let assembly = document.assembly else {
                throw ProductAttributeError.missingTarget("Complete occurrence source path.")
            }
            var children = assembly.roots
            var selected: AssemblyDefinition?
            for component in path.components {
                try budget.charge(work: children.count + assembly.definitions.count + 1)
                guard let occurrence = children.first(where: { $0.id == component }),
                      let definition = assembly.definitions.first(where: { $0.id == occurrence.definitionID }) else {
                    throw ProductAttributeError.missingTarget("Occurrence path component.")
                }
                selected = definition; children = definition.children
            }
            if let geometry = target.geometry {
                guard let selected else { throw ProductAttributeError.missingTarget("Geometry occurrence definition.") }
                try budget.charge(work: selected.features.count)
                guard selected.features.contains(geometry.subshapeID.featureID) else {
                    throw ProductAttributeError.missingTarget("Geometry is not owned by the selected occurrence definition.")
                }
            }
        }
    }
}
