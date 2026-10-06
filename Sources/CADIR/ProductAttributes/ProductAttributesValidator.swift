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
              attributes.itemCharacterizations.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count,
              attributes.shapeElementDescriptions.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count - attributes.itemCharacterizations.count else {
            throw ProductAttributeError.resourceLimitExceeded("Product source records.")
        }
        try budget.charge(work: attributes.materials.count + attributes.assignments.count + attributes.layers.count + attributes.itemCharacterizations.count + attributes.shapeElementDescriptions.count)
        try validateMetadata(attributes, in: document, budget: &budget)
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
        for record in attributes.itemCharacterizations {
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
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone shape-element descriptions now have a source and standard egress owner.
        // Native and public STEP success/failure behavior must be verified before this source-first change is reported complete.
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

    private func validateMetadata(_ attributes: ProductAttributes, in document: CADDocument,
                                  budget: inout ProductAttributeBudget) throws {
        let pmi = attributes.manufacturingInformation, metadata = attributes.viewMetadata
        let counts = [pmi.datums.count, pmi.dimensions.count, pmi.tolerances.count, pmi.annotations.count,
                      metadata.views.count, metadata.validationProperties.count]
        var records = attributes.materials.count + attributes.assignments.count + attributes.layers.count
            + attributes.itemCharacterizations.count + attributes.shapeElementDescriptions.count
        for count in counts {
            guard count <= budget.limits.maximumRecords - records else {
                throw ProductAttributeError.resourceLimitExceeded("Product metadata records.")
            }
            records += count
        }
        var identities = Set<ProductMetadataID>()
        func text(_ value: String, _ budget: inout ProductAttributeBudget) throws {
            try budget.charge(work: 1, textBytes: value.utf8.count)
        }
        func identity(_ id: ProductMetadataID) throws {
            guard identities.insert(id).inserted else { throw ProductAttributeError.invalidSource("Duplicate product metadata identity.") }
        }
        try budget.charge(work: counts.reduce(0, +), targets: counts.reduce(0, +))
        let datums = Set(pmi.datums.map(\.id)), dimensions = Set(pmi.dimensions.map(\.id))
        let tolerances = Set(pmi.tolerances.map(\.id)), annotations = Set(pmi.annotations.map(\.id))
        for datum in pmi.datums {
            try identity(datum.id); try validateTarget(datum.target, in: document, budget: &budget)
            try text(datum.name, &budget); try text(datum.description, &budget); try text(datum.identification, &budget)
            guard !datum.identification.isEmpty else { throw ProductAttributeError.invalidSource("Empty datum identification.") }
        }
        for dimension in pmi.dimensions {
            try identity(dimension.id); try dimension.validate()
            try text(dimension.name, &budget); try text(dimension.description, &budget)
            try validateTarget(dimension.target, in: document, budget: &budget)
            if let reference = dimension.referenceTarget { try validateTarget(reference, in: document, budget: &budget) }
        }
        for tolerance in pmi.tolerances {
            try identity(tolerance.id); try tolerance.validate()
            try text(tolerance.name, &budget); try text(tolerance.description, &budget)
            try validateTarget(tolerance.target, in: document, budget: &budget)
            try budget.charge(work: tolerance.datumIDs.count + tolerance.modifiers.count)
            guard tolerance.datumIDs.allSatisfy({ datums.contains($0) }) else {
                throw ProductAttributeError.missingTarget("Geometric tolerance datum.")
            }
        }
        for annotation in pmi.annotations {
            try identity(annotation.id); try text(annotation.name, &budget); try text(annotation.text, &budget)
            guard annotation.textLiterals.count <= budget.limits.maximumRecords - records else { throw ProductAttributeError.resourceLimitExceeded("Annotation literal records.") }
            records += annotation.textLiterals.count
            var combined = ""
            for literal in annotation.textLiterals {
                try identity(literal.id)
                for value in [literal.literalName,literal.occurrenceName,literal.text,literal.alignment,literal.fontName] { try text(value,&budget) }
                try budget.charge(work:32,targets:1)
                guard literal.origin.isFinite, literal.direction.isFinite, literal.up.isFinite,
                    abs(literal.direction.length-1) <= 1e-12, abs(literal.up.length-1) <= 1e-12,
                    abs(literal.direction.dot(literal.up)) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid annotation literal frame.") }
                if literal.placement == .twoDimensional {
                    guard literal.origin.z == 0, literal.direction == .unitZ, literal.up.z == 0 else { throw ProductAttributeError.invalidSource("Annotation 2D literal has nonplanar placement values.") }
                }
                combined += literal.text
            }
            guard combined == annotation.text, !annotation.textLiterals.isEmpty || !annotation.polylines.isEmpty else { throw ProductAttributeError.invalidSource("Annotation plain text differs from its original literal content or has no drawing content.") }
            switch annotation.meaning {
            case .note:
                guard annotation.semanticID == nil else { throw ProductAttributeError.invalidSource("A note has no semantic record reference.") }
            case .dimension:
                guard let id = annotation.semanticID, dimensions.contains(id) else { throw ProductAttributeError.missingTarget("Annotation dimension.") }
            case .tolerance:
                guard let id = annotation.semanticID, tolerances.contains(id) else { throw ProductAttributeError.missingTarget("Annotation tolerance.") }
            case .datum:
                guard let id = annotation.semanticID, datums.contains(id) else { throw ProductAttributeError.missingTarget("Annotation datum.") }
            }
            for target in annotation.targets { try validateTarget(target, in: document, budget: &budget) }
            for line in annotation.polylines {
                try budget.charge(work: line.count, targets: line.count)
                guard line.count >= 2, line.allSatisfy(\.isFinite) else { throw ProductAttributeError.invalidSource("Invalid annotation polyline.") }
            }
        }
        func frame(_ origin: Point3D, _ direction: Vector3D, _ up: Vector3D) throws {
            guard origin.isFinite, direction.isFinite, up.isFinite,
                  abs(direction.length - 1) <= 1e-12, abs(up.length - 1) <= 1e-12,
                  abs(direction.dot(up)) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid orthonormal metadata frame.") }
        }
        func clipping(_ expression: ProductClippingExpression, depth: Int, budget: inout ProductAttributeBudget) throws {
            guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Saved-view clipping depth.") }
            try budget.charge(work: 1, targets: 1)
            switch expression {
            case .plane(let plane):
                guard plane.origin.isFinite, plane.normal.isFinite, abs(plane.normal.length - 1) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid clipping halfspace.") }
            case .union(let operands), .intersection(let operands):
                guard operands.count >= 2 else { throw ProductAttributeError.invalidSource("A clipping Boolean operation requires two operands.") }
                for operand in operands {
                    if case .union = expression, case .union = operand { throw ProductAttributeError.invalidSource("Clipping unions alternate with intersections.") }
                    if case .intersection = expression, case .intersection = operand { throw ProductAttributeError.invalidSource("Clipping intersections alternate with unions.") }
                    try clipping(operand, depth: depth + 1, budget: &budget)
                }
            }
        }
        for view in metadata.views {
            try identity(view.id); try text(view.name, &budget); try frame(view.origin, view.direction, view.up)
            guard view.horizontalSize.isFinite, view.verticalSize.isFinite, view.focalDistance.isFinite,
                  view.nearDistance.isFinite, view.farDistance.isFinite,
                  view.horizontalSize > 0, view.verticalSize > 0 else {
                throw ProductAttributeError.invalidSource("Invalid saved-view volume.")
            }
            try frame(view.windowOrigin, view.windowDirection, view.windowUp)
            guard view.projectionPoint.isFinite, view.windowPlacement != .twoDimensional || (view.windowOrigin.z == 0 && view.windowDirection == .unitZ) else { throw ProductAttributeError.invalidSource("Saved-view window and projection point conflict with the view plane.") }
            if let expression = view.clippingExpression { try clipping(expression, depth: 0, budget: &budget) }
            for plane in view.clippingPlanes {
                try budget.charge(work: 1, targets: 1)
                guard plane.origin.isFinite, plane.normal.isFinite, abs(plane.normal.length - 1) <= 1e-12 else {
                    throw ProductAttributeError.invalidSource("Invalid saved-view clipping plane.")
                }
            }
            for placement in view.annotationPlacements {
                try budget.charge(work: 1, targets: 1); try frame(placement.origin, placement.direction, placement.up)
                try frame(placement.mappingOrigin, placement.mappingDirection, placement.mappingUp)
                guard placement.basisX.isFinite, abs(placement.basisX.length - 1) <= 1e-12,
                      abs(placement.basisX.dot(placement.up)) <= 1e-12,
                      abs(placement.basisX.dot(placement.direction)) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid independent annotation transform axis.") }
                guard annotations.contains(placement.annotationID),
                      placement.scale.isFinite, placement.scale > 0 else {
                    throw ProductAttributeError.invalidSource("Invalid saved-view annotation placement.")
                }
            }
        }
        for property in metadata.validationProperties {
            try identity(property.id); try text(property.name, &budget); try text(property.description, &budget)
            try validateTarget(property.target, in: document, budget: &budget)
            switch property.value {
            case let .area(value), let .volume(value), let .length(value):
                guard value.isFinite, value >= 0 else { throw ProductAttributeError.invalidSource("Invalid physical validation measure.") }
            case let .centroid(point):
                guard point.isFinite else { throw ProductAttributeError.invalidSource("Invalid validation centroid.") }
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
