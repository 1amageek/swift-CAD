import Foundation
import CADCore
import CADIR
import CADKernel

public struct STEPAttributesReader: STEPAttributesReading {
    private let resolver: any ProductAttributeResolving
    public init(resolver: any ProductAttributeResolving = ProductAttributeResolver()) { self.resolver = resolver }
    public func read(entities: [Int: String], transfer: STEPAttributeReadTransfer,
                     evaluated: EvaluatedDocument, limits: ExchangeResourceLimits) throws -> ProductAttributes {
        try limits.validate()
        guard entities.count <= limits.maximumEntities else { throw ProductAttributeError.resourceLimitExceeded("STEP attribute entity table.") }
        var builder = Builder(syntax: STEPAssemblySyntax(entities: entities), entities: entities, transfer: transfer,
            evaluated: evaluated, resolver: resolver,
            budget: try ProductAttributeBudget(limits: ProductAttributeLimits(maximumRecords: limits.maximumEntities,
                maximumTargets: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                maximumTextBytes: limits.maximumBytes, maximumWork: limits.maximumIterations)),
            duration: ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration))
        return try builder.read()
    }
}

private extension STEPAttributesReader {
    struct Builder {
        let syntax: any STEPFieldReading
        let entities: [Int: String]
        let transfer: STEPAttributeReadTransfer
        let evaluated: EvaluatedDocument
        let resolver: any ProductAttributeResolving
        var budget: ProductAttributeBudget
        let duration: ExchangeProcessingBudget
        var names: [Int: String] = [:]
        var geometry: [Int: ProductAttributeTarget] = [:]
        var assignments: [ProductAttributeAssignment] = []
        var styleProperties: [Int: [ProductAttributeValue.Property: ProductAttributeID]] = [:]
        var styleTargets: [Int: ProductAttributeTarget] = [:]
        var buildingStyles = Set<Int>()
        mutating func check(_ work: Int = 1) throws {
            try duration.check(format: .step); try budget.charge(work: work)
        }
        func args(_ id: Int, _ count: Int, component: String? = nil) throws -> [String] {
            let a = try syntax.arguments(id, component: component)
            guard a.count == count else { throw ProductAttributeError.invalidSource("Malformed STEP attribute argument count.") }
            return a
        }
        func string(_ value: String) throws -> String {
            let value = try syntax.string(value)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEPExchange and OfficialFormatExchange name, material, and layer imports do not yet decode STEP encoded strings.
            // Completion requires standards-correct extended and shifted-character decoding with lossless value and round-trip evidence before these strings can be admitted.
            guard !value.contains("\\X"), !value.contains("\\S\\") else {
                throw ProductAttributeError.unsupportedSemantics("Unsupported encoded STEP attribute string.")
            }
            return value
        }
        mutating func target(_ item: Int) throws -> ProductAttributeTarget {
            try check()
            if let target = geometry[item] { return target }
            if let definition = transfer.partCarriers[item] { return ProductAttributeTarget(kind: .part, definitionID: definition) }
            if let definition = transfer.definitions[item] { return ProductAttributeTarget(kind: .part, definitionID: definition) }
            if let usage = transfer.usages[item] { return ProductAttributeTarget(kind: .directUsage, usageID: usage) }
            if names[item] == "SHAPE_ASPECT" {
                let a = try args(item, 4), shape = try syntax.reference(a[2])
                let pds = try args(shape, 3), owner = try syntax.reference(pds[2])
                guard let definition = transfer.definitions[owner] else { throw ProductAttributeError.missingTarget("Shape aspect product.") }
                var matches: [ProductAttributeTarget] = []
                for id in entities.keys where names[id] == "GEOMETRIC_ITEM_SPECIFIC_USAGE" {
                    try check()
                    let usage = try args(id, 5)
                    if try syntax.reference(usage[2]) == item {
                        let representation = try syntax.reference(usage[3]), geometryID = try syntax.reference(usage[4])
                        guard transfer.representations[representation] == definition, let mapped = geometry[geometryID] else {
                            throw ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")
                        }
                        try budget.charge(targets: 1); matches.append(mapped)
                    }
                }
                guard matches.count == 1, let mapped = matches.first else { throw ProductAttributeError.ambiguousProperty("Shape aspect geometry target.") }
                return mapped
            }
            throw ProductAttributeError.unsupportedSemantics("Unresolved STEP attribute target.")
        }
        mutating func contextPath(_ token: String) throws -> AssemblyOccurrencePath {
            let contexts = try syntax.list(token)
            try check(contexts.count)
            guard !contexts.isEmpty else { throw ProductAttributeError.invalidSource("Empty contextual style path.") }
            var components: [AssemblyOccurrenceID] = []
            for id in contexts {
                guard let occurrence = transfer.relationships[id] else {
                    throw ProductAttributeError.unsupportedSemantics("Unsupported contextual style relationship.")
                }
                components.append(occurrence)
            }
            var candidates: [AssemblyOccurrencePath] = []
            for occurrence in evaluated.assembly?.occurrences ?? [] {
                try check(occurrence.path.components.count)
                if occurrence.path.components == components || Array(occurrence.path.components.dropFirst()) == components {
                    try budget.charge(targets: 1); candidates.append(occurrence.path)
                }
            }
            guard candidates.count == 1, let result = candidates.first else { throw ProductAttributeError.ambiguousProperty("Contextual occurrence path.") }
            return result
        }
        mutating func styleValues(_ assignmentID: Int) throws -> [ProductAttributeValue.Property: ProductAttributeValue] {
            let a = try args(assignmentID, 1)
            guard names[assignmentID] == "PRESENTATION_STYLE_ASSIGNMENT", a[0].first == "(", a[0].last == ")" else {
                throw ProductAttributeError.unsupportedSemantics("Unsupported style assignment.")
            }
            let tokens = try syntax.split(String(a[0].dropFirst().dropLast()))
            var result: [ProductAttributeValue.Property: ProductAttributeValue] = [:]
            for token in tokens {
                try check()
                if token == "NULL_STYLE(.NULL.)" { continue }
                let id = try syntax.reference(token)
                let usage = try args(id, 2)
                guard names[id] == "SURFACE_STYLE_USAGE", usage[0] == ".BOTH." else {
                    throw ProductAttributeError.unsupportedSemantics("Unsupported front/back or nonsurface style.")
                }
                let sideID = try syntax.reference(usage[1]), side = try args(sideID, 2)
                guard names[sideID] == "SURFACE_SIDE_STYLE" else { throw ProductAttributeError.invalidSource("Missing surface side style.") }
                for element in try syntax.list(side[1]) {
                    try check()
                    var values: [ProductAttributeValue] = []
                    switch names[element] {
                    case "SURFACE_STYLE_FILL_AREA":
                        let fill = try args(element, 1), fillID = try syntax.reference(fill[0]), area = try args(fillID, 2)
                        guard names[fillID] == "FILL_AREA_STYLE" else { throw ProductAttributeError.invalidSource("Missing fill area style.") }
                        let colors = try syntax.list(area[1])
                        guard colors.count == 1, let colorID = colors.first else { throw ProductAttributeError.ambiguousProperty("Surface fill color.") }
                        let color = try args(colorID, 2)
                        guard names[colorID] == "FILL_AREA_STYLE_COLOUR" else { throw ProductAttributeError.unsupportedSemantics("Unsupported fill pattern.") }
                        values = [.color(try colorValue(syntax.reference(color[1])))]
                    case "SURFACE_STYLE_RENDERING", "SURFACE_STYLE_RENDERING_WITH_PROPERTIES":
                        let rendering = try syntax.arguments(element, component: nil)
                        guard rendering.count == (names[element] == "SURFACE_STYLE_RENDERING" ? 2 : 3), rendering[0] == ".NORMAL_SHADING." else {
                            throw ProductAttributeError.unsupportedSemantics("Unsupported rendering method.")
                        }
                        values = [.color(try colorValue(syntax.reference(rendering[1])))]
                        if rendering.count == 3 {
                            for property in try syntax.list(rendering[2]) {
                                try check()
                                guard names[property] == "SURFACE_STYLE_TRANSPARENT" else { throw ProductAttributeError.unsupportedSemantics("Unsupported surface rendering property.") }
                                let p = try args(property, 1)
                                guard let transparency = Double(p[0]), transparency.isFinite, (0...1).contains(transparency) else {
                                    throw ProductAttributeError.invalidSource("Invalid surface transparency.")
                                }
                                values.append(.opacity(1 - transparency))
                            }
                        }
                    default: throw ProductAttributeError.unsupportedSemantics("Unknown surface style property.")
                    }
                    for value in values {
                        if let existing = result[value.property], existing != value { throw ProductAttributeError.ambiguousProperty(value.property.rawValue) }
                        result[value.property] = value
                    }
                }
            }
            return result
        }
        mutating func colorValue(_ id: Int) throws -> ColorRGBA {
            try check()
            if names[id] == "COLOUR_RGB" {
                let a = try args(id, 4)
                guard let r = Double(a[1]), let g = Double(a[2]), let b = Double(a[3]) else { throw ProductAttributeError.invalidSource("Malformed RGB color.") }
                let result = ColorRGBA(r: r, g: g, b: b, a: 1); try result.validate(); return result
            }
            if names[id] == "DRAUGHTING_PRE_DEFINED_COLOUR" {
                let a = try args(id, 1)
                let colors: [String: ColorRGBA] = ["black": ColorRGBA(r: 0,g: 0,b: 0,a: 1), "white": ColorRGBA(r: 1,g: 1,b: 1,a: 1),
                    "red": ColorRGBA(r: 1,g: 0,b: 0,a: 1), "green": ColorRGBA(r: 0,g: 1,b: 0,a: 1), "blue": ColorRGBA(r: 0,g: 0,b: 1,a: 1),
                    "yellow": ColorRGBA(r: 1,g: 1,b: 0,a: 1), "magenta": ColorRGBA(r: 1,g: 0,b: 1,a: 1), "cyan": ColorRGBA(r: 0,g: 1,b: 1,a: 1)]
                guard let color = colors[try string(a[0])] else { throw ProductAttributeError.unsupportedSemantics("Unknown predefined color.") }
                return color
            }
            throw ProductAttributeError.unsupportedSemantics("Unsupported color representation.")
        }
        mutating func readStyle(_ id: Int, depth: Int = 0) throws {
            if styleProperties[id] != nil { return }
            guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("STEP style override depth.") }
            try check()
            guard buildingStyles.insert(id).inserted else { throw ProductAttributeError.invalidSource("STEP style override cycle.") }
            defer { buildingStyles.remove(id) }
            let kind = names[id], a = try syntax.arguments(id, component: nil)
            let contextual = kind == "CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM"
            guard a.count == (contextual ? 5 : kind == "OVER_RIDING_STYLED_ITEM" ? 4 : 3) else {
                throw ProductAttributeError.invalidSource("Malformed styled item.")
            }
            var target: ProductAttributeTarget
            let item = try syntax.reference(a[2])
            if !contextual, geometry[item] == nil, transfer.partCarriers[item] == nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import has no direct styled mapped-usage correspondence yet.
                // A real assembly MAPPED_ITEM must retain complete instance scope before it can be admitted; PD/representation pseudo-targets are invalid.
                throw ProductAttributeError.unsupportedSemantics("Styled item requires an actual body, face, or structural whole-part carrier target.")
            }
            if contextual, let definition = transfer.representations[item] {
                target = ProductAttributeTarget(kind: .occurrence, path: try contextPath(a[4]))
                guard evaluated.assembly?.occurrences.contains(where: { $0.path == target.path && $0.definitionID == definition }) == true else {
                    throw ProductAttributeError.missingTarget("Contextual style component representation.")
                }
            } else {
                target = try self.target(item)
                if contextual {
                    guard let geometry = target.geometry else { throw ProductAttributeError.unsupportedSemantics("Unsupported contextual style target.") }
                    target = ProductAttributeTarget(kind: target.kind, geometry: geometry, path: try contextPath(a[4]))
                }
            }
            let predecessor = a.count >= 4 ? try syntax.reference(a[3]) : nil
            var inherited: [ProductAttributeValue.Property: ProductAttributeID] = [:]
            if let predecessor { try readStyle(predecessor, depth: depth + 1); inherited = styleProperties[predecessor] ?? [:] }
            let psas = try syntax.list(a[1])
            guard psas.count == 1, let psa = psas.first else { throw ProductAttributeError.unsupportedSemantics("Multiple context-sensitive style assignments.") }
            let values = try styleValues(psa)
            if predecessor != nil, values.isEmpty { throw ProductAttributeError.unsupportedSemantics("Null overriding style visibility semantics.") }
            for property in values.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let value = values[property] else { throw ProductAttributeError.invalidSource("Missing style property.") }
                try budget.charge(targets: 1)
                let assignment = ProductAttributeAssignment(target: target, value: value, overrides: inherited[property])
                assignments.append(assignment); inherited[property] = assignment.id
            }
            styleProperties[id] = inherited; styleTargets[id] = target
        }
        mutating func read() throws -> ProductAttributes {
            try budget.charge(work: entities.count)
            for (id, text) in entities {
                try budget.charge(textBytes: text.utf8.count)
                names[id] = try syntax.name(id)
            }
            for (entityID, subshape) in transfer.geometry {
                try check()
                let reference = try resolver.sourceReference(for: subshape, in: evaluated)
                let kind: ProductAttributeTarget.Kind
                switch reference.geometrySignature {
                case .body: kind = .body
                case .face: kind = .face
                default: throw ProductAttributeError.invalidSource("STEP attribute geometry transfer has wrong kind.")
                }
                let target = ProductAttributeTarget(kind: kind, geometry: reference)
                try budget.charge(targets: 1); geometry[entityID] = target
                let a = try syntax.arguments(entityID, component: nil)
                guard let name = a.first else { throw ProductAttributeError.invalidSource("Missing shape item name.") }
                let value = try string(name)
                if !value.isEmpty { try budget.charge(targets: 1); assignments.append(ProductAttributeAssignment(target: target, value: .name(value))) }
            }
            let styles = entities.keys.filter { ["STYLED_ITEM", "OVER_RIDING_STYLED_ITEM", "CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM"].contains(names[$0] ?? "") }.sorted()
            let containers = entities.keys.filter { ["DRAUGHTING_MODEL", "MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION"].contains(names[$0] ?? "") }
            if !styles.isEmpty {
                guard containers.count == 1, let container = containers.first else { throw ProductAttributeError.ambiguousProperty("Global styling container.") }
                let a = try args(container, 3)
                guard try string(a[0]).isEmpty else { throw ProductAttributeError.unsupportedSemantics("Non-global styling container.") }
                let items = try syntax.list(a[1])
                try check(items.count)
                let itemSet = Set(items)
                guard Set(styles).isSubset(of: itemSet) else { throw ProductAttributeError.unsupportedSemantics("Unreferenced styled item.") }
                for id in styles { try readStyle(id) }
                // A body must be initially visible as a whole; partial invisible geometry is not a silent mesh loss.
                for (entityID, target) in geometry where target.kind == .body {
                    try check(styles.count + items.count)
                    let part = transfer.partCarriers.first { carrier in
                        guard let feature = target.geometry?.subshapeID.featureID else { return false }
                        return evaluated.document.assembly?.definitions.first(where: { $0.id == carrier.value })?.features.contains(feature) == true
                    }?.key
                    let visible = itemSet.contains(entityID) || styles.contains { style in
                        guard let styled = styleTargets[style], styled.path == nil else { return false }
                        if styled == target { return true }
                        if let part, styled.kind == .part { return styled.definitionID == transfer.partCarriers[part] }
                        return false
                    }
                    guard visible else { throw ProductAttributeError.unsupportedSemantics("Global styling hides unrepresented body geometry.") }
                }
            } else if !containers.isEmpty { throw ProductAttributeError.unsupportedSemantics("Styling container without retained styles.") }
            var layers: [ProductLayer] = []
            var layerIndex: [String: Int] = [:]
            for id in entities.keys.sorted() where names[id] == "PRESENTATION_LAYER_ASSIGNMENT" {
                try check()
                let a = try args(id, 3), name = try string(a[0]), description = try string(a[1])
                guard !name.isEmpty else { throw ProductAttributeError.invalidSource("Empty layer name.") }
                var members: [ProductAttributeTarget] = []
                for item in try syntax.list(a[2]) {
                    guard styleTargets[item] != nil || geometry[item] != nil || transfer.partCarriers[item] != nil else {
                        throw ProductAttributeError.unsupportedSemantics("Layer member must be a retained representation item or contextual styled item.")
                    }
                    let member = try styleTargets[item] ?? target(item)
                    if !members.contains(member) { try budget.charge(targets: 1); members.append(member) }
                }
                if let index = layerIndex[name] {
                    guard layers[index].description == description else { throw ProductAttributeError.ambiguousProperty("Same-name layer description.") }
                    var merged = layers[index].members
                    for member in members where !merged.contains(member) { try budget.charge(targets: 1); merged.append(member) }
                    layers[index] = ProductLayer(id: layers[index].id, name: name, description: description, members: merged)
                } else { layerIndex[name] = layers.count; layers.append(ProductLayer(name: name, description: description, members: members)) }
            }
            var materialValues: [ProductAttributeTarget: (String, String)] = [:]
            var densities: [ProductAttributeTarget: PhysicalDensity] = [:]
            for id in entities.keys.sorted() where names[id] == "PROPERTY_DEFINITION" {
                try check()
                let property = try args(id, 3), propertyName = try string(property[0]), label = property[1] == "$" ? "" : try string(property[1])
                guard propertyName == "material property", label == "material name" || label == "density" else {
                    throw ProductAttributeError.unsupportedSemantics("Unknown physical property semantics.")
                }
                let owner = try target(syntax.reference(property[2]))
                var representations: [Int] = []
                for association in entities.keys where names[association] == "PROPERTY_DEFINITION_REPRESENTATION" {
                    try check()
                    let a = try args(association, 2)
                    if try syntax.reference(a[0]) == id { try budget.charge(targets: 1); representations.append(try syntax.reference(a[1])) }
                }
                guard representations.count == 1, let representation = representations.first else { throw ProductAttributeError.ambiguousProperty("Physical property representation.") }
                let rep = try args(representation, 3), items = try syntax.list(rep[1])
                guard names[representation] == "REPRESENTATION", items.count == 1, let item = items.first else {
                    throw ProductAttributeError.unsupportedSemantics("Unsupported physical property representation.")
                }
                if label == "material name" {
                    let value = try args(item, 2)
                    guard names[item] == "DESCRIPTIVE_REPRESENTATION_ITEM" else { throw ProductAttributeError.unsupportedSemantics("Unsupported physical material representation.") }
                    guard materialValues.updateValue((try string(value[0]), try string(value[1])), forKey: owner) == nil else {
                        throw ProductAttributeError.ambiguousProperty("Competing material properties.")
                    }
                } else {
                    var densityReader = STEPPhysicalDensityReader(syntax: syntax)
                    let value = try densityReader.read(item, budget: &budget)
                    guard densities.updateValue(value, forKey: owner) == nil else { throw ProductAttributeError.ambiguousProperty("Competing density properties.") }
                }
            }
            var materials: [PhysicalMaterialDescriptor] = []
            for (target, value) in materialValues {
                try budget.charge(targets: 1)
                let material = PhysicalMaterialDescriptor(name: value.0, description: value.1, density: densities[target])
                materials.append(material); assignments.append(ProductAttributeAssignment(target: target, value: .material(material.id)))
                if densities[target] != nil { assignments.append(ProductAttributeAssignment(target: target, value: .descriptorDensity(material.id))) }
            }
            for (target, density) in densities where materialValues[target] == nil {
                try budget.charge(targets: 1); assignments.append(ProductAttributeAssignment(target: target, value: .density(density)))
            }
            let result = ProductAttributes(materials: materials, assignments: assignments, layers: layers)
            var document = evaluated.document; document.productAttributes = result
            try ProductAttributesValidator().validate(result, in: document, budget: &budget)
            return result
        }
    }
}
