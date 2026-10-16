import HashTreeCollections
import CADCore
import CADGeometry

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
        var execution = try budget.execution()
        try validate(attributes, in: document, budget: &budget, using: &execution)
    }

    public func validate(_ attributes: ProductAttributes, in document: CADDocument,
                         budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        let invocation = budget
        try invocation.withExecution(using: &execution) { execution in
            let limit = budget.limits.maximumRecords
            guard attributes.materials.count <= limit,
                  attributes.assignments.count <= limit - attributes.materials.count,
                  attributes.layers.count <= limit - attributes.materials.count - attributes.assignments.count,
                  attributes.itemCharacterizations.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count,
                  attributes.shapeElementDescriptions.count <= limit - attributes.materials.count - attributes.assignments.count - attributes.layers.count - attributes.itemCharacterizations.count else {
                throw ProductAttributeError.resourceLimitExceeded("Product source records.")
            }
            try budget.charge(work: attributes.materials.count + attributes.assignments.count + attributes.layers.count + attributes.itemCharacterizations.count + attributes.shapeElementDescriptions.count, using: &execution)
            try validateMetadata(attributes, in: document, budget: &budget, using: &execution)
            try execution.retainStorage(count: attributes.materials.count, stride: MemoryLayout<(PhysicalMaterialID, PhysicalMaterialDescriptor)>.stride)
            var materials: [PhysicalMaterialID: PhysicalMaterialDescriptor] = [:]
            materials.reserveCapacity(attributes.materials.count)
            for material in attributes.materials {
                try budget.charge(textBytes: material.name.utf8.count, using: &execution)
                try budget.charge(textBytes: material.description.utf8.count, using: &execution)
                try material.density?.validate()
                guard materials.updateValue(material, forKey: material.id) == nil else {
                    throw ProductAttributeError.invalidSource("Duplicate physical material identity.")
                }
            }
            try execution.retainStorage(count: attributes.assignments.count, stride: MemoryLayout<(ProductAttributeID, ProductAttributeAssignment)>.stride)
            var assignments: [ProductAttributeID: ProductAttributeAssignment] = [:]
            assignments.reserveCapacity(attributes.assignments.count)
            for assignment in attributes.assignments {
                try validateTarget(assignment.target, in: document, budget: &budget, using: &execution)
                try assignment.value.validate()
                switch assignment.value {
                case let .name(value):
                    try budget.charge(textBytes: value.utf8.count, using: &execution)
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
                    try budget.charge(work: 1, using: &execution)
                    try execution.retainStorage(count: 1, stride: MemoryLayout<ProductAttributeID>.stride)
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
            try execution.retainStorage(count: attributes.itemCharacterizations.count, stride: MemoryLayout<CharacterizationKey>.stride)
            var characterized = Set<CharacterizationKey>()
            characterized.reserveCapacity(attributes.itemCharacterizations.count)
            for record in attributes.itemCharacterizations {
                guard (record.target.kind == .body || record.target.kind == .face), record.target.definitionID == nil,
                      record.target.path == nil, record.target.usageID == nil, let geometry = record.target.geometry else {
                    throw ProductAttributeError.invalidSource("Physical characterization requires a global geometry target.")
                }
                try validateTarget(record.target, in: document, budget: &budget, using: &execution)
                try budget.charge(textBytes: record.name.utf8.count, using: &execution)
                try budget.charge(textBytes: record.description?.utf8.count ?? 0, using: &execution)
                guard !record.name.utf8.isEmpty || record.description != nil else {
                    throw ProductAttributeError.invalidSource("Default physical characterization must be absent.")
                }
                guard characterized.insert(CharacterizationKey(kind: record.target.kind, subshapeID: geometry.subshapeID)).inserted else {
                    throw ProductAttributeError.invalidSource("Duplicate physical characterization target.")
                }
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone shape-element descriptions now have a source and standard egress owner.
            // Native and public STEP success/failure behavior must be verified before this source-first change is reported complete.
            try execution.retainStorage(count: attributes.shapeElementDescriptions.count, stride: MemoryLayout<ShapeElementKey>.stride)
            var described = Set<ShapeElementKey>()
            described.reserveCapacity(attributes.shapeElementDescriptions.count)
            for record in attributes.shapeElementDescriptions {
                guard (record.target.kind == .body || record.target.kind == .face), let definition = record.target.definitionID,
                      record.target.path == nil, record.target.usageID == nil, let geometry = record.target.geometry else {
                    throw ProductAttributeError.invalidSource("Shape element description requires a definition-qualified geometry target.")
                }
                try validateTarget(record.target, in: document, budget: &budget, using: &execution)
                try budget.charge(textBytes: record.description.utf8.count, using: &execution)
                guard described.insert(ShapeElementKey(definitionID: definition, kind: record.target.kind, subshapeID: geometry.subshapeID)).inserted else {
                    throw ProductAttributeError.invalidSource("Duplicate shape element description target.")
                }

            }
            // Exact same-target conflicts are structural and do not require evaluated topology.
            for assignment in attributes.assignments {
                var winnerCount = 0
                for candidate in attributes.assignments {
                    try budget.charge(work: 1, using: &execution)
                    guard candidate.target == assignment.target, candidate.value.property == assignment.value.property else { continue }
                    var overridden = false
                    for other in attributes.assignments {
                        try budget.charge(work: 1, using: &execution)
                        guard other.target == assignment.target, other.value.property == assignment.value.property else { continue }
                        var cursor = other.overrides
                        while let id = cursor {
                            try budget.charge(work: 1, using: &execution)
                            if id == candidate.id { overridden = true; break }
                            cursor = assignments[id]?.overrides
                        }
                        if overridden { break }
                    }
                    if !overridden { winnerCount += 1 }
                }
                guard winnerCount == 1 else { throw ProductAttributeError.ambiguousProperty(assignment.value.property.rawValue) }
            }
            try execution.retainStorage(count: attributes.layers.count, stride: MemoryLayout<ProductLayerID>.stride)
            try execution.retainStorage(count: attributes.layers.count, stride: MemoryLayout<String>.stride)
            var layerIDs = Set<ProductLayerID>(), layerNames = Set<String>()
            layerIDs.reserveCapacity(attributes.layers.count); layerNames.reserveCapacity(attributes.layers.count)
            for layer in attributes.layers {
                try budget.charge(textBytes: layer.name.utf8.count, using: &execution)
                try budget.charge(textBytes: layer.description.utf8.count, using: &execution)
                guard !layer.name.isEmpty, layerIDs.insert(layer.id).inserted, layerNames.insert(layer.name).inserted else {
                    throw ProductAttributeError.invalidSource("Layers require unique identities and nonempty unique names.")
                }
                guard layer.members.count <= budget.limits.maximumTargets - budget.consumedTargets else {
                    throw ProductAttributeError.resourceLimitExceeded("Layer member storage.")
                }
                try execution.retainStorage(count: layer.members.count, stride: MemoryLayout<ProductAttributeTarget>.stride)
                var members = Set<ProductAttributeTarget>()
                members.reserveCapacity(layer.members.count)
                for member in layer.members {
                    try validateTarget(member, in: document, budget: &budget, using: &execution)
                    guard members.insert(member).inserted else { throw ProductAttributeError.invalidSource("Duplicate layer membership.") }
                }
            }

        }
    }

    private func validateMetadata(_ attributes: ProductAttributes, in document: CADDocument,
                                  budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
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
        func text(_ value: String, _ budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
            try budget.charge(work: 1, textBytes: value.utf8.count, using: &execution)
        }
        func identity(_ id: ProductMetadataID, using execution: inout OriginalQueryExecution) throws {
            try execution.retainStorage(count: 1, stride: MemoryLayout<ProductMetadataID>.stride)
            guard identities.insert(id).inserted else { throw ProductAttributeError.invalidSource("Duplicate product metadata identity.") }
        }
        try budget.charge(work: counts.reduce(0, +), targets: counts.reduce(0, +), using: &execution)
        try execution.retainStorage(count: pmi.datums.count, stride: MemoryLayout<ProductMetadataID>.stride)
        try execution.retainStorage(count: pmi.dimensions.count, stride: MemoryLayout<ProductMetadataID>.stride)
        try execution.retainStorage(count: pmi.tolerances.count, stride: MemoryLayout<ProductMetadataID>.stride)
        try execution.retainStorage(count: pmi.annotations.count, stride: MemoryLayout<ProductMetadataID>.stride)
        var datums = Set<ProductMetadataID>(), dimensions = Set<ProductMetadataID>()
        var tolerances = Set<ProductMetadataID>(), annotations = Set<ProductMetadataID>()
        datums.reserveCapacity(pmi.datums.count); dimensions.reserveCapacity(pmi.dimensions.count)
        tolerances.reserveCapacity(pmi.tolerances.count); annotations.reserveCapacity(pmi.annotations.count)
        for datum in pmi.datums { try execution.consumeWork(1); datums.insert(datum.id) }
        for dimension in pmi.dimensions { try execution.consumeWork(1); dimensions.insert(dimension.id) }
        for tolerance in pmi.tolerances { try execution.consumeWork(1); tolerances.insert(tolerance.id) }
        for annotation in pmi.annotations { try execution.consumeWork(1); annotations.insert(annotation.id) }
        for datum in pmi.datums {
            try identity(datum.id, using: &execution); try validateTarget(datum.target, in: document, budget: &budget, using: &execution)
            try text(datum.name, &budget, using: &execution); try text(datum.description, &budget, using: &execution); try text(datum.identification, &budget, using: &execution)
            guard !datum.identification.isEmpty else { throw ProductAttributeError.invalidSource("Empty datum identification.") }
        }
        for dimension in pmi.dimensions {
            try identity(dimension.id, using: &execution); try dimension.validate(using: &execution)
            try text(dimension.name, &budget, using: &execution); try text(dimension.description, &budget, using: &execution)
            try validateTarget(dimension.target, in: document, budget: &budget, using: &execution)
            if let reference = dimension.referenceTarget { try validateTarget(reference, in: document, budget: &budget, using: &execution) }
        }
        for tolerance in pmi.tolerances {
            try identity(tolerance.id, using: &execution); try tolerance.validate(using: &execution)
            try text(tolerance.name, &budget, using: &execution); try text(tolerance.description, &budget, using: &execution)
            try validateTarget(tolerance.target, in: document, budget: &budget, using: &execution)
            try budget.charge(work: tolerance.datumIDs.count + tolerance.modifiers.count, using: &execution)
            guard tolerance.datumIDs.allSatisfy({ datums.contains($0) }) else {
                throw ProductAttributeError.missingTarget("Geometric tolerance datum.")
            }
        }
        for annotation in pmi.annotations {
            try identity(annotation.id, using: &execution); try text(annotation.name, &budget, using: &execution); try text(annotation.text, &budget, using: &execution)
            guard annotation.textLiterals.count <= budget.limits.maximumRecords - records else { throw ProductAttributeError.resourceLimitExceeded("Annotation literal records.") }
            records += annotation.textLiterals.count
            var combined = ""
            for literal in annotation.textLiterals {
                try identity(literal.id, using: &execution)
                for value in [literal.literalName,literal.occurrenceName,literal.text,literal.alignment,literal.fontName] { try text(value,&budget, using: &execution) }
                try budget.charge(work:32,targets:1, using: &execution)
                guard literal.origin.isFinite, literal.direction.isFinite, literal.up.isFinite,
                    abs(literal.direction.length-1) <= 1e-12, abs(literal.up.length-1) <= 1e-12,
                    abs(literal.direction.dot(literal.up)) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid annotation literal frame.") }
                if literal.placement == .twoDimensional {
                    guard literal.origin.z == 0, literal.direction == .unitZ, literal.up.z == 0 else { throw ProductAttributeError.invalidSource("Annotation 2D literal has nonplanar placement values.") }
                }
                try execution.retainStorage(bytes: combined.utf8.count)
                try execution.retainStorage(bytes: literal.text.utf8.count)
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
            for target in annotation.targets { try validateTarget(target, in: document, budget: &budget, using: &execution) }
            for line in annotation.polylines {
                try budget.charge(work: line.count, targets: line.count, using: &execution)
                guard line.count >= 2, line.allSatisfy({ $0.isFinite }) else { throw ProductAttributeError.invalidSource("Invalid annotation polyline.") }
            }
        }
        func frame(_ origin: Point3D, _ direction: Vector3D, _ up: Vector3D) throws {
            guard origin.isFinite, direction.isFinite, up.isFinite,
                  abs(direction.length - 1) <= 1e-12, abs(up.length - 1) <= 1e-12,
                  abs(direction.dot(up)) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid orthonormal metadata frame.") }
        }
        func clipping(_ expression: ProductClippingExpression, depth: Int, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
            guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Saved-view clipping depth.") }
            try budget.charge(work: 1, targets: 1, using: &execution)
            switch expression {
            case .plane(let plane):
                guard plane.origin.isFinite, plane.normal.isFinite, abs(plane.normal.length - 1) <= 1e-12 else { throw ProductAttributeError.invalidSource("Invalid clipping halfspace.") }
            case .union(let operands), .intersection(let operands):
                guard operands.count >= 2 else { throw ProductAttributeError.invalidSource("A clipping Boolean operation requires two operands.") }
                for operand in operands {
                    if case .union = expression, case .union = operand { throw ProductAttributeError.invalidSource("Clipping unions alternate with intersections.") }
                    if case .intersection = expression, case .intersection = operand { throw ProductAttributeError.invalidSource("Clipping intersections alternate with unions.") }
                    try clipping(operand, depth: depth + 1, budget: &budget, using: &execution)
                }
            }
        }
        for view in metadata.views {
            try identity(view.id, using: &execution); try text(view.name, &budget, using: &execution); try frame(view.origin, view.direction, view.up)
            guard view.horizontalSize.isFinite, view.verticalSize.isFinite, view.focalDistance.isFinite,
                  view.nearDistance.isFinite, view.farDistance.isFinite,
                  view.horizontalSize > 0, view.verticalSize > 0 else {
                throw ProductAttributeError.invalidSource("Invalid saved-view volume.")
            }
            try frame(view.windowOrigin, view.windowDirection, view.windowUp)
            guard view.projectionPoint.isFinite, view.windowPlacement != .twoDimensional || (view.windowOrigin.z == 0 && view.windowDirection == .unitZ) else { throw ProductAttributeError.invalidSource("Saved-view window and projection point conflict with the view plane.") }
            if let expression = view.clippingExpression { try clipping(expression, depth: 0, budget: &budget, using: &execution) }
            for plane in view.clippingPlanes {
                try budget.charge(work: 1, targets: 1, using: &execution)
                guard plane.origin.isFinite, plane.normal.isFinite, abs(plane.normal.length - 1) <= 1e-12 else {
                    throw ProductAttributeError.invalidSource("Invalid saved-view clipping plane.")
                }
            }
            for placement in view.annotationPlacements {
                try budget.charge(work: 1, targets: 1, using: &execution); try frame(placement.origin, placement.direction, placement.up)
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
            try identity(property.id, using: &execution); try text(property.name, &budget, using: &execution); try text(property.description, &budget, using: &execution)
            try validateTarget(property.target, in: document, budget: &budget, using: &execution)
            switch property.value {
            case let .area(value), let .volume(value), let .length(value):
                guard value.isFinite, value >= 0 else { throw ProductAttributeError.invalidSource("Invalid physical validation measure.") }
            case let .centroid(point):
                guard point.isFinite else { throw ProductAttributeError.invalidSource("Invalid validation centroid.") }
            }
        }
    }

    private func validateTarget(_ target: ProductAttributeTarget, in document: CADDocument,
                                budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        try budget.charge(work: 1, targets: 1, using: &execution)
        try target.validate(using: &execution)
        if let geometry = target.geometry {
            guard let feature = document.designGraph.nodes[geometry.subshapeID.featureID], !feature.isSuppressed,
                  feature.bodyOrSheetOutput != nil else { throw ProductAttributeError.missingTarget("Active geometry source feature.") }
        }
        if let id = target.definitionID {
            guard let assembly = document.assembly else { throw ProductAttributeError.missingTarget("Part definition source.") }
            try budget.charge(work: assembly.definitions.count, using: &execution)
            guard let definition = assembly.definitions.first(where: { $0.id == id }) else {
                throw ProductAttributeError.missingTarget("Part definition.")
            }
            if let geometry = target.geometry {
                try budget.charge(work: definition.features.count, using: &execution)
                guard definition.features.contains(geometry.subshapeID.featureID) else {
                    throw ProductAttributeError.missingTarget("Geometry is not owned by the selected definition.")
                }
            }
        }
        if let usage = target.usageID {
            guard let assembly = document.assembly else { throw ProductAttributeError.missingTarget("Direct usage source.") }
            try budget.charge(work: assembly.roots.count, using: &execution)
            var found = assembly.roots.contains(where: { $0.id == usage })
            for definition in assembly.definitions {
                try budget.charge(work: definition.children.count + 1, using: &execution)
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
                try budget.charge(work: children.count + assembly.definitions.count + 1, using: &execution)
                guard let occurrence = children.first(where: { $0.id == component }),
                      let definition = assembly.definitions.first(where: { $0.id == occurrence.definitionID }) else {
                    throw ProductAttributeError.missingTarget("Occurrence path component.")
                }
                selected = definition; children = definition.children
            }
            if let geometry = target.geometry {
                guard let selected else { throw ProductAttributeError.missingTarget("Geometry occurrence definition.") }
                try budget.charge(work: selected.features.count, using: &execution)
                guard selected.features.contains(geometry.subshapeID.featureID) else {
                    throw ProductAttributeError.missingTarget("Geometry is not owned by the selected occurrence definition.")
                }
            }
        }
    }
}
