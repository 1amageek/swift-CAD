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
        var globalPhysicalGeometry: [Int: ProductAttributeTarget] = [:]
        var physicalGeometry: [Int: ProductAttributeTarget] = [:]
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
        mutating func string(_ value: String) throws -> String {
            try duration.check(format: .step)
            let decoded = try syntax.decodedString(value, limits: STEPStringLimits(
                maximumInputBytes: budget.limits.maximumTextBytes,
                maximumOutputBytes: budget.limits.maximumTextBytes - budget.consumedTextBytes,
                maximumWork: budget.limits.maximumWork - budget.consumedWork))
            try budget.charge(work: decoded.consumedWork, textBytes: decoded.outputBytes)
            return decoded.value
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
                guard let mapped = physicalGeometry[item], mapped.definitionID == definition else {
                    throw ProductAttributeError.ambiguousProperty("Shape aspect geometry target.")
                }
                return mapped
            }
            throw ProductAttributeError.unsupportedSemantics("Unresolved STEP attribute target.")
        }
        mutating func physicalOwner(_ item: Int) throws -> ProductAttributeTarget {
            try check()
            if let target = globalPhysicalGeometry[item] { return target }
            guard transfer.definitions[item] != nil || transfer.usages[item] != nil || names[item] == "SHAPE_ASPECT" else {
                throw ProductAttributeError.unsupportedSemantics("Physical property requires a legal characterized-definition owner.")
            }
            return try target(item)
        }
        mutating func prepareGlobalPhysicalGeometry() throws {
            // Every CIWR is a real item characterization; its representation must carry no PD or instance context.
            var associated = Set<Int>()
            try check(entities.count)
            for id in entities.keys {
                switch names[id] {
                case "SHAPE_DEFINITION_REPRESENTATION":
                    try check(); let a = try args(id, 2)
                    try budget.charge(targets: 1); associated.insert(try syntax.reference(a[1]))
                case "REPRESENTATION_MAP":
                    try check(); let a = try args(id, 2)
                    try budget.charge(targets: 1); associated.insert(try syntax.reference(a[1]))
                case "SHAPE_REPRESENTATION_RELATIONSHIP", "REPRESENTATION_RELATIONSHIP":
                    try check(); let a = try args(id, 4)
                    try budget.charge(targets: 2); associated.insert(try syntax.reference(a[2])); associated.insert(try syntax.reference(a[3]))
                case "":
                    try check(entities[id]?.utf8.count ?? 1)
                    if try syntax.hasComponent(id, named: "REPRESENTATION_RELATIONSHIP") {
                        let a = try args(id, 4, component: "REPRESENTATION_RELATIONSHIP")
                        try budget.charge(targets: 2); associated.insert(try syntax.reference(a[2])); associated.insert(try syntax.reference(a[3]))
                    }
                default: break
                }
            }
            var keys = Set<[Int]>()
            try check(entities.count)
            for id in entities.keys where names[id] == "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION" {
                try check()
                let a = try args(id, 4), item = try syntax.reference(a[2]), representation = try syntax.reference(a[3])
                let wrapperName = try string(a[0])
                let wrapperDescription = a[1] == "$" ? nil : try string(a[1])
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP CIWR physical import cannot retain independent wrapper names/descriptions or contextual characterization chains yet.
                // A persistent source owner and equivalent standard egress must preserve those meanings before nonempty wrapper metadata or chained scope can be admitted.
                guard wrapperName.isEmpty, wrapperDescription == nil || wrapperDescription?.isEmpty == true else {
                    throw ProductAttributeError.unsupportedSemantics("Independent characterization metadata requires a retained source owner.")
                }
                guard let target = geometry[item], target.definitionID == nil, target.path == nil,
                      let ownedUnit = transfer.geometryUnits[item] else {
                    throw ProductAttributeError.missingTarget("Global physical item geometry correspondence.")
                }
                guard !associated.contains(representation), transfer.representations[representation] == nil,
                      names[representation] == "SHAPE_REPRESENTATION" else {
                    throw ProductAttributeError.unsupportedSemantics("Global physical characterization requires an unassociated singleton view.")
                }
                let view = try args(representation, 3), items = try syntax.list(view[1])
                try check(items.count)
                guard items == [item] else { throw ProductAttributeError.invalidSource("Global physical view must contain exactly its identified item.") }
                let context = try syntax.reference(view[2])
                guard try syntax.arguments(context, component: "GEOMETRIC_REPRESENTATION_CONTEXT") == ["3"] else {
                    throw ProductAttributeError.invalidSource("Global physical view requires a 3D geometry context.")
                }
                let unitArgs = try syntax.arguments(context, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
                guard unitArgs.count == 1 else { throw ProductAttributeError.invalidSource("Malformed global physical view unit context.") }
                var length: LengthUnit?
                for unit in try syntax.list(unitArgs[0]) {
                    try check(entities[unit]?.utf8.count ?? 1)
                    if let value = try stepLengthUnit(from: syntax.entity(unit), entities: entities) {
                        guard length == nil else { throw ProductAttributeError.invalidSource("Ambiguous global physical view length units.") }
                        length = value
                    }
                }
                guard length == ownedUnit else { throw ProductAttributeError.invalidSource("Global physical view has conflicting owned units.") }
                try budget.charge(targets: 4)
                guard keys.insert([item, representation]).inserted else {
                    throw ProductAttributeError.invalidSource("Duplicate characterized item/representation owner.")
                }
                globalPhysicalGeometry[id] = target
            }
        }
        mutating func preparePhysicalGeometry() throws {
            var associated = Set<Int>()
            try check(entities.count)
            for id in entities.keys where names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                try check()
                let representation = try syntax.reference(args(id, 2)[1])
                try budget.charge(targets: 1); associated.insert(representation)
            }
            var itemKeys = Set<[Int]>(), definitionKeys = Set<[Int]>()
            try check(entities.count)
            for id in entities.keys where names[id] == "GEOMETRIC_ITEM_SPECIFIC_USAGE" {
                try check()
                let usage = try args(id, 5), aspect = try syntax.reference(usage[2])
                let representation = try syntax.reference(usage[3]), item = try syntax.reference(usage[4])
                guard names[aspect] == "SHAPE_ASPECT" else {
                    throw ProductAttributeError.unsupportedSemantics("Unsupported GISU definition target.")
                }
                let a = try args(aspect, 4), shape = try syntax.reference(a[2])
                guard names[shape] == "PRODUCT_DEFINITION_SHAPE" else {
                    throw ProductAttributeError.invalidSource("Shape aspect requires a product definition shape.")
                }
                let owner = try syntax.reference(args(shape, 3)[2])
                guard let definition = transfer.definitions[owner], let mapped = geometry[item], let reference = mapped.geometry else {
                    throw ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")
                }
                try check(evaluated.document.assembly?.definitions.count ?? 0)
                guard let source = evaluated.document.assembly?.definitions.first(where: { $0.id == definition }) else {
                    throw ProductAttributeError.missingTarget("Shape aspect product.")
                }
                try check(source.features.count)
                guard source.features.contains(reference.subshapeID.featureID) else {
                    throw ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")
                }
                if let members = transfer.representations[representation] {
                    guard members.contains(definition) else { throw ProductAttributeError.missingTarget("Shape aspect geometry correspondence.") }
                    // The carrier's outer mapped item does not directly contain its inner body or face.
                    let ra = try args(representation, 3), items = try syntax.list(ra[1])
                    try check(items.count)
                    guard !items.contains(where: { names[$0] == "MAPPED_ITEM" }) else {
                        throw ProductAttributeError.invalidSource("GISU representation does not directly own its identified geometry.")
                    }
                } else {
                    guard !associated.contains(representation), names[representation] == "SHAPE_REPRESENTATION" else {
                        throw ProductAttributeError.invalidSource("Physical target view must be an unassociated shape representation.")
                    }
                    let view = try args(representation, 3), items = try syntax.list(view[1])
                    try check(items.count)
                    guard items.count == 1, items.first == item else {
                        throw ProductAttributeError.invalidSource("Physical target view must contain exactly its identified item.")
                    }
                    let context = try syntax.reference(view[2])
                    let dimension = try syntax.arguments(context, component: "GEOMETRIC_REPRESENTATION_CONTEXT")
                    guard dimension == ["3"] else { throw ProductAttributeError.invalidSource("Physical target view requires a 3D geometry context.") }
                    let unitArgs = try syntax.arguments(context, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
                    guard unitArgs.count == 1 else { throw ProductAttributeError.invalidSource("Malformed physical target view unit context.") }
                    var length: LengthUnit?
                    for unit in try syntax.list(unitArgs[0]) {
                        try check(entities[unit]?.utf8.count ?? 1)
                        if let value = try stepLengthUnit(from: syntax.entity(unit), entities: entities) {
                            guard length == nil else { throw ProductAttributeError.invalidSource("Ambiguous physical target view length units.") }
                            length = value
                        }
                    }
                    guard let length else { throw ProductAttributeError.invalidSource("Missing physical target view length unit.") }
                    var ownedUnit: LengthUnit?
                    for (rep, members) in transfer.representations {
                        try check()
                        if members.contains(definition), let unit = transfer.representationUnits[rep] {
                            if let existing = ownedUnit, existing != unit { throw ProductAttributeError.inconsistentArtifact("Conflicting PD representation units.") }
                            ownedUnit = unit
                        }
                    }
                    guard ownedUnit == length else { throw ProductAttributeError.invalidSource("Physical target view has conflicting owned units.") }
                }
                try budget.charge(targets: 7)
                guard itemKeys.insert([representation, item]).inserted,
                      definitionKeys.insert([representation, aspect]).inserted else {
                    throw ProductAttributeError.invalidSource("Duplicate GISU representation/item or representation/definition usage.")
                }
                guard physicalGeometry[aspect] == nil else { throw ProductAttributeError.ambiguousProperty("Shape aspect geometry target.") }
                let target = ProductAttributeTarget(kind: mapped.kind, geometry: reference, definitionID: definition)
                physicalGeometry[aspect] = target
                let label = try string(a[0]), description = a[1] == "$" ? nil : try string(a[1])
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP shape-element import cannot retain independent descriptions or chained name history yet.
                // A persistent description/predecessor owner and equivalent standard egress are required before those meanings can be admitted.
                guard description == nil || description?.isEmpty == true else {
                    throw ProductAttributeError.unsupportedSemantics("Independent shape-element descriptions require a retained source owner.")
                }
                if !label.isEmpty { try budget.charge(targets: 1); assignments.append(ProductAttributeAssignment(target: target, value: .name(label))) }
            }
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
        mutating func carrierTarget(_ carrier: Int, item: Int) throws -> ProductAttributeTarget {
            try check()
            guard let definition = transfer.partCarriers[carrier], let target = geometry[item], let reference = target.geometry else {
                throw ProductAttributeError.missingTarget("Qualified style carrier geometry correspondence.")
            }
            try check(evaluated.document.assembly?.definitions.count ?? 0)
            guard let source = evaluated.document.assembly?.definitions.first(where: { $0.id == definition }) else {
                throw ProductAttributeError.missingTarget("Qualified style carrier product.")
            }
            try check(source.features.count)
            guard source.features.contains(reference.subshapeID.featureID) else {
                throw ProductAttributeError.missingTarget("Qualified style carrier feature membership.")
            }
            return ProductAttributeTarget(kind: target.kind, geometry: reference, definitionID: definition)
        }
        mutating func usageTarget(_ context: Int, item: Int) throws -> ProductAttributeTarget {
            try check(4)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP direct-usage style import requires a producer-proved NAUO/CDSR selector.
            // Mapped-only, unproved or path-guessed contexts need an equivalent standard source owner before they can succeed.
            guard names[context] == "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION", let usage = transfer.usageContexts[context] else {
                throw ProductAttributeError.unsupportedSemantics("Direct usage style context must select one proved CDSR.")
            }
            let contextArgs = try args(context, 2), relation = try syntax.reference(contextArgs[0]), shape = try syntax.reference(contextArgs[1])
            let shapeArgs = try args(shape, 3), owner = try syntax.reference(shapeArgs[2])
            guard names[shape] == "PRODUCT_DEFINITION_SHAPE", names[owner] == "NEXT_ASSEMBLY_USAGE_OCCURRENCE",
                  transfer.usages[owner] == usage, transfer.relationships[relation] == usage else {
                throw ProductAttributeError.invalidSource("Direct usage context does not match its validated placement owner.")
            }
            let definition = try stepAppearanceLeafDefinition(for: usage, in: evaluated, budget: &budget, duration: duration)
            guard transfer.partCarriers[item] == definition.id else {
                throw ProductAttributeError.missingTarget("Direct usage style carrier does not select its child definition.")
            }
            return ProductAttributeTarget(kind: .directUsage, usageID: usage)
        }
        mutating func styleValues(_ assignmentID: Int) throws -> [ProductAttributeValue.Property: ProductAttributeValue] {
            let contextual = names[assignmentID] == "PRESENTATION_STYLE_BY_CONTEXT"
            let a = try args(assignmentID, contextual ? 2 : 1)
            guard contextual || names[assignmentID] == "PRESENTATION_STYLE_ASSIGNMENT", a[0].first == "(", a[0].last == ")" else {
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
            let item = try syntax.reference(a[2])
            let psas = try syntax.list(a[1]); try check(psas.count)
            guard psas.count == 1, let psa = psas.first else { throw ProductAttributeError.unsupportedSemantics("Multiple context-sensitive style assignments.") }
            var contextCarrier: Int?, contextUsage: Int?
            if names[psa] == "PRESENTATION_STYLE_BY_CONTEXT" {
                let context = try syntax.reference(args(psa, 2)[1])
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP scoped style import admits only proved identity PD carrier or validated CDSR usage contexts.
                // Other standard context meanings require an equivalent persistent selector and egress before they can succeed.
                guard transfer.partCarriers[context] != nil || transfer.usageContexts[context] != nil else {
                    throw ProductAttributeError.unsupportedSemantics("Style context requires a proved identity PD carrier.")
                }
                if transfer.usageContexts[context] != nil { contextUsage = context }
                else { contextCarrier = context }
            }
            var target: ProductAttributeTarget
            if !contextual, geometry[item] == nil, transfer.partCarriers[item] == nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import has no direct styled mapped-usage correspondence yet.
                // A real assembly MAPPED_ITEM must retain complete instance scope before it can be admitted; PD/representation pseudo-targets are invalid.
                throw ProductAttributeError.unsupportedSemantics("Styled item requires an actual body, face, or structural whole-part carrier target.")
            }
            if contextual {
                let contexts = try syntax.list(a[4]); try check(contexts.count)
                if contexts.count == 1, let context = contexts.first, transfer.usageContexts[context] != nil {
                    guard contextCarrier == nil, contextUsage == nil || contextUsage == context else {
                        throw ProductAttributeError.ambiguousProperty("Competing direct usage style contexts.")
                    }
                    target = try usageTarget(context, item: item)
                } else if contexts.contains(where: { names[$0] == "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION" }) {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP direct-usage appearance admits one validated CDSR context, not mixed or chained usage selectors.
                    // A persistent equivalent compound scope and standard egress must be established before these contexts can succeed.
                    throw ProductAttributeError.unsupportedSemantics("Direct usage style context must select one proved CDSR.")
                } else if contexts.count == 1, let carrier = contexts.first, transfer.partCarriers[carrier] != nil {
                    guard contextUsage == nil else { throw ProductAttributeError.ambiguousProperty("Competing direct usage style contexts.") }
                    guard contextCarrier == nil || contextCarrier == carrier else { throw ProductAttributeError.ambiguousProperty("Competing qualified style contexts.") }
                    target = try carrierTarget(carrier, item: item)
                } else {
                    guard contextUsage == nil else { throw ProductAttributeError.ambiguousProperty("Competing direct usage style contexts.") }
                    guard contextCarrier == nil else { throw ProductAttributeError.ambiguousProperty("Competing qualified style contexts.") }
                    if let definitions = transfer.representations[item] {
                        target = ProductAttributeTarget(kind: .occurrence, path: try contextPath(a[4]))
                        guard evaluated.assembly?.occurrences.contains(where: { $0.path == target.path && definitions.contains($0.definitionID) }) == true else {
                            throw ProductAttributeError.missingTarget("Contextual style component representation.")
                        }
                    } else {
                        let mapped = try self.target(item)
                        guard let geometry = mapped.geometry else { throw ProductAttributeError.unsupportedSemantics("Unsupported contextual style target.") }
                        target = ProductAttributeTarget(kind: mapped.kind, geometry: geometry, path: try contextPath(a[4]))
                    }
                }
            } else if let context = contextUsage { target = try usageTarget(context, item: item) }
            else if let carrier = contextCarrier { target = try carrierTarget(carrier, item: item) }
            else { target = try self.target(item) }
            let predecessor = a.count >= 4 ? try syntax.reference(a[3]) : nil
            var inherited: [ProductAttributeValue.Property: ProductAttributeID] = [:]
            if let predecessor { try readStyle(predecessor, depth: depth + 1); inherited = styleProperties[predecessor] ?? [:] }
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
            var hasPhysicalGeometry = false, hasGlobalPhysicalGeometry = false
            for (id, text) in entities {
                try budget.charge(textBytes: text.utf8.count)
                let name = try syntax.name(id)
                names[id] = name
                if name == "GEOMETRIC_ITEM_SPECIFIC_USAGE" { hasPhysicalGeometry = true }
                if name == "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION" { hasGlobalPhysicalGeometry = true }
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
            if hasPhysicalGeometry { try preparePhysicalGeometry() }
            if hasGlobalPhysicalGeometry { try prepareGlobalPhysicalGeometry() }
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
                let owner = try physicalOwner(syntax.reference(property[2]))
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
