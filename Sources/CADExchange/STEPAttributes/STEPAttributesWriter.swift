import CADCore
import CADIR
import CADKernel

public struct STEPAttributesWriter: STEPAttributesWriting {
    public init() {}
    public func geometryNames(for evaluated: EvaluatedDocument, resolved: ResolvedProductAttributes,
                              limits: ExchangeResourceLimits) throws -> STEPGeometryAttributeNames {
        try limits.validate()
        guard resolved.documentID == evaluated.document.id else {
            throw ProductAttributeError.invalidSource("Invalid STEP attribute transfer association.")
        }
        var builder = Builder(evaluated: evaluated, resolved: resolved, transfer: STEPAttributeWriteTransfer(), startingAt: 1,
            limits: limits, budget: try ProductAttributeBudget(limits: ProductAttributeLimits(maximumRecords: limits.maximumEntities,
                maximumTargets: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                maximumTextBytes: limits.maximumBytes, maximumWork: limits.maximumIterations)),
            duration: ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration))
        try builder.budget.charge(work: resolved.consumedWork)
        try builder.validateGeometryScope()
        return try builder.geometryNames()
    }
    public func records(for evaluated: EvaluatedDocument, resolved: ResolvedProductAttributes,
                        transfer: STEPAttributeWriteTransfer, startingAt: Int, limits: ExchangeResourceLimits) throws -> [String] {
        try limits.validate()
        guard startingAt > 0, startingAt <= limits.maximumEntities + 1, resolved.documentID == evaluated.document.id else {
            throw ProductAttributeError.invalidSource("Invalid STEP attribute transfer association.")
        }
        var builder = Builder(evaluated: evaluated, resolved: resolved, transfer: transfer, startingAt: startingAt,
            limits: limits, budget: try ProductAttributeBudget(limits: ProductAttributeLimits(maximumRecords: limits.maximumEntities,
                maximumTargets: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                maximumTextBytes: limits.maximumBytes, maximumWork: limits.maximumIterations)),
            duration: ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration))
        try builder.budget.charge(work: resolved.consumedWork)
        try builder.validateGeometryScope()
        return try builder.write()
    }
}

extension STEPAttributesWriter {
    struct Builder {
        let evaluated: EvaluatedDocument
        let resolved: ResolvedProductAttributes
        let transfer: STEPAttributeWriteTransfer
        let startingAt: Int
        let limits: ExchangeResourceLimits
        var budget: ProductAttributeBudget
        let duration: ExchangeProcessingBudget
        var records: [String] = []
        var styled: [ProductAttributeID: [Int]] = [:]
        var building = Set<ProductAttributeID>()
        var targetStyles: [ProductAttributeTarget: [Int]] = [:]
        var supportingStyles = Set<Int>()
        var shapeAspects: [ProductAttributeTarget: [Int]] = [:]
        var materialDesignationEntities: [PhysicalMaterialID: Int] = [:]
        var physicalDescriptorProperties: [PhysicalMaterialID: (material: Int, density: Int?)] = [:]
        var physicalAssignmentProperties: [ProductAttributeID: Int] = [:]
        var activePhysicalAssignments = Set<ProductAttributeID>()
        mutating func check(_ work: Int = 1) throws {
            try duration.check(format: .step); try budget.charge(work: work)
        }
        mutating func validateGeometryScope() throws {
            for assignment in evaluated.document.productAttributes.assignments {
                try check()
                if assignment.target.definitionID != nil, assignment.target.kind == .body || assignment.target.kind == .face,
                   case let .name(value) = assignment.value {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP qualified shape-element names cannot encode empty labels or authored name histories yet.
                    // Completion requires equivalent standard presence and predecessor ownership before these source values can succeed.
                    guard !value.isEmpty, assignment.overrides == nil else {
                        throw ProductAttributeError.unsupportedSemantics("Qualified shape-element names require a nonempty standalone label.")
                    }
                }
            }
            for layer in evaluated.document.productAttributes.layers {
                try check()
                for member in layer.members {
                    try check()
                    try member.validate()
                }
            }
        }
        mutating func geometryNames() throws -> STEPGeometryAttributeNames {
            var bodies: [BodyID: String] = [:], faces: [FaceID: String] = [:]
            var overridden = Set<ProductAttributeID>()
            for assignment in evaluated.document.productAttributes.assignments {
                try check()
                if assignment.value.property == .name, let predecessor = assignment.overrides, !overridden.contains(predecessor) {
                    try budget.charge(targets: 1); overridden.insert(predecessor)
                }
            }
            for assignment in evaluated.document.productAttributes.assignments {
                try check()
                guard !overridden.contains(assignment.id), case let .name(name) = assignment.value else { continue }
                if assignment.target.definitionID != nil, assignment.target.kind == .body || assignment.target.kind == .face { continue }
                guard assignment.target.path == nil, let topology = resolved.localGeometry[assignment.target] else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Context-specific geometry names are not yet emitted by the public STEP writer.
                    // STEPExchange and OfficialFormatExchange must refuse until a standard contextual name target preserves the complete path.
                    throw ProductAttributeError.unsupportedSemantics("Context-specific geometry names require a standard equivalent target.")
                }
                switch topology {
                case let .body(id):
                    if bodies[id] == nil { try budget.charge(targets: 1) }
                    bodies[id] = name
                case let .face(id):
                    if faces[id] == nil { try budget.charge(targets: 1) }
                    faces[id] = name
                default: throw ProductAttributeError.invalidSource("Unsupported named geometry kind.")
                }
            }
            return STEPGeometryAttributeNames(bodies: bodies, faces: faces)
        }
        mutating func string(_ value: String) throws -> String {
            try duration.check(format: .step)
            let encoded = try STEPStringCodec().encode(value, limits: STEPStringLimits(
                maximumInputBytes: budget.limits.maximumTextBytes,
                maximumOutputBytes: budget.limits.maximumTextBytes - budget.consumedTextBytes,
                maximumWork: budget.limits.maximumWork - budget.consumedWork))
            try budget.charge(work: encoded.consumedWork, textBytes: encoded.outputBytes)
            return encoded.value
        }
        mutating func add(_ text: String) throws -> Int {
            try duration.check(format: .step); try budget.charge(work: 1)
            guard records.count < limits.maximumEntities - startingAt + 1 else { throw ProductAttributeError.resourceLimitExceeded("STEP attribute records.") }
            try budget.charge(textBytes: text.utf8.count + 32)
            let id = startingAt + records.count; records.append(text); return id
        }
        mutating func products(_ target: ProductAttributeTarget) throws -> [STEPAttributeProductRepresentation] {
            if let usage = target.usageID {
                let definition = try stepAppearanceLeafDefinition(for: usage, in: evaluated, budget: &budget, duration: duration)
                guard let product = transfer.products[definition.id] else {
                    throw ProductAttributeError.missingTarget("Written direct-usage product.")
                }
                return [product]
            }
            if let definition = target.definitionID {
                guard let product = transfer.products[definition] else { throw ProductAttributeError.missingTarget("Written product.") }
                return [product]
            }
            if let path = target.path {
                guard let occurrence = evaluated.assembly?.occurrences.first(where: { $0.path == path }),
                      let product = transfer.products[occurrence.definitionID] else { throw ProductAttributeError.missingTarget("Written occurrence product.") }
                return [product]
            }
            guard let topology = resolved.localGeometry[target] else { throw ProductAttributeError.missingTarget("Written local geometry.") }
            return transfer.products.values.filter { product in
                switch topology {
                case let .body(id): return product.bodies[id] != nil
                case let .face(id): return product.faces[id] != nil
                default: return false
                }
            }
        }
        mutating func styleItems(_ target: ProductAttributeTarget) throws -> [Int] {
            try budget.charge(work: transfer.products.count + (evaluated.assembly?.occurrences.count ?? 0))
            switch target.kind {
            case .part:
                return try products(target).map { product in
                    guard let carrier = product.carrier else { throw ProductAttributeError.unsupportedSemantics("Part appearance requires a whole-part carrier.") }
                    return carrier
                }
            case .occurrence:
                let products = try products(target)
                guard products.count == 1, let carrier = products.first?.carrier else {
                    throw ProductAttributeError.unsupportedSemantics(
                        "Occurrence appearance requires a proved whole-part MAPPED_ITEM carrier.")
                }
                return [carrier]
            case .directUsage:
                return [try usageStyle(target).item]
            case .body, .face:
                guard let topology = resolved.localGeometry[target] else { throw ProductAttributeError.missingTarget("Style geometry target.") }
                let products = try products(target)
                guard !products.isEmpty else { throw ProductAttributeError.missingTarget("Style product membership.") }
                var items: [Int] = []
                var seen = Set<Int>()
                for product in products {
                    try check()
                    let item: Int
                    switch topology {
                    case let .body(id):
                        guard let entities = product.bodies[id], entities.count == 1, let entity = entities.first else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): STEPExchange cannot yet retain one attributed multi-component Body across several solid items.
                            // A standard unique Body grouping with exact attribute scope and independent round-trip evidence is required.
                            throw ProductAttributeError.unsupportedSemantics("Attributed body spans several STEP representation items.")
                        }
                        item = entity
                    case let .face(id):
                        guard let entity = product.faces[id] else { throw ProductAttributeError.missingTarget("Style face.") }
                        item = entity
                    default: throw ProductAttributeError.invalidSource("Unsupported style topology kind.")
                    }
                    if !seen.contains(item) { try budget.charge(targets: 2); seen.insert(item); items.append(item) }
                }
                return items
            }
        }
        mutating func occurrenceLayerItems(_ target: ProductAttributeTarget) throws -> [Int] {
            try check(transfer.products.count + (evaluated.assembly?.occurrences.count ?? 0)
                + (evaluated.document.assembly?.definitions.count ?? 0))
            guard target.kind == .occurrence, let path = target.path,
                  let occurrence = evaluated.assembly?.occurrences.first(where: { $0.path == path }),
                  let definition = evaluated.document.assembly?.definitions.first(where: { $0.id == occurrence.definitionID }),
                  let product = transfer.products[definition.id] else {
                throw ProductAttributeError.missingTarget("Layer occurrence source representation.")
            }
            if let carrier = product.carrier {
                try budget.charge(targets: 1)
                return [carrier]
            }
            try check(definition.features.count + product.bodies.count + product.faces.count)
            guard definition.features.isEmpty, product.bodies.isEmpty, product.faces.isEmpty else {
                throw ProductAttributeError.unsupportedSemantics("Occurrence layer requires its actual source representation or identity carrier.")
            }
            try budget.charge(targets: 1)
            return [product.representation]
        }
        mutating func geometryCarrier(_ target: ProductAttributeTarget) throws -> Int {
            try check()
            guard target.kind == .body || target.kind == .face, let definition = target.definitionID,
                  target.path == nil, let product = transfer.products[definition], let carrier = product.carrier,
                  let topology = resolved.localGeometry[target] else {
                throw ProductAttributeError.missingTarget("Qualified geometry identity carrier.")
            }
            switch topology {
            case let .body(id): guard product.bodies[id] != nil else { throw ProductAttributeError.missingTarget("Qualified carrier body membership.") }
            case let .face(id): guard product.faces[id] != nil else { throw ProductAttributeError.missingTarget("Qualified carrier face membership.") }
            default: throw ProductAttributeError.invalidSource("Qualified carrier geometry kind.")
            }
            return carrier
        }
        mutating func usageStyle(_ target: ProductAttributeTarget) throws -> (item: Int, context: Int) {
            guard target.kind == .directUsage, let usage = target.usageID else {
                throw ProductAttributeError.invalidSource("Direct usage style selector.")
            }
            let definition = try stepAppearanceLeafDefinition(for: usage, in: evaluated, budget: &budget, duration: duration)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP direct-usage appearance requires a validated NAUO/CDSR and identity child carrier.
            // Mapped-only or unproved usages need a standard owner-preserving transfer before they can succeed; path inference is not equivalent.
            guard transfer.usages[usage] != nil, let context = transfer.usageContexts[usage],
                  let carrier = transfer.products[definition.id]?.carrier else {
                throw ProductAttributeError.unsupportedSemantics("Direct usage appearance requires a proved CDSR and child carrier.")
            }
            return (carrier, context)
        }
        mutating func layerStyle(_ target: ProductAttributeTarget) throws -> [Int] {
            if let existing = targetStyles[target], !existing.isEmpty { return existing }
            if let path = target.path {
                try check(path.components.count)
                let items = try occurrenceLayerItems(target)
                guard let first = path.components.first,
                      let parentContext = transfer.usageContexts[first] else {
                    throw ProductAttributeError.unsupportedSemantics(
                        "Occurrence layer requires a validated parent CDSR context.")
                }
                var relationships: [String] = []
                for component in path.components {
                    guard let relationship = transfer.relationships[component] else {
                        throw ProductAttributeError.missingTarget("Occurrence layer relationship.")
                    }
                    try check(); try budget.charge(targets: 1)
                    relationships.append("#\(relationship)")
                }
                let parentPSA = try add("PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#\(parentContext))")
                var result: [Int] = []
                for item in items {
                    let predecessor = try add("STYLED_ITEM('',(#\(parentPSA)),#\(item))")
                    try budget.charge(targets: 2)
                    supportingStyles.insert(predecessor)
                    let nestedPSA = try add("PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)))")
                    result.append(try add(
                        "CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#\(nestedPSA)),#\(item),#\(predecessor),(\(relationships.joined(separator: ","))))"))
                }
                try budget.charge(targets: 1); targetStyles[target] = result
                return result
            }
            let items = try styleItems(target)
            let context: Int
            if target.kind == .directUsage {
                context = try usageStyle(target).context
            } else {
                context = try geometryCarrier(target)
            }
            let psa = try add("PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#\(context))")
            var result: [Int] = []
            for item in items {
                try check(); try budget.charge(targets: 1)
                result.append(try add("STYLED_ITEM('',(#\(psa)),#\(item))"))
            }
            try budget.charge(targets: 1); targetStyles[target] = result
            return result
        }
        mutating func appendStyle(_ assignment: ProductAttributeAssignment, depth: Int) throws -> [Int] {
            if let ids = styled[assignment.id] { return ids }
            guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("STEP style depth.") }
            guard building.insert(assignment.id).inserted else { throw ProductAttributeError.invalidSource("Style override cycle.") }
            defer { building.remove(assignment.id) }
            guard case let .color(color) = assignment.value else {
                throw ProductAttributeError.unsupportedSemantics("STEP style export requires an admitted explicit color property.")
            }
            let opacityCandidates = evaluated.document.productAttributes.assignments.filter {
                $0.target == assignment.target && $0.value.property == .opacity
            }
            try budget.charge(work: evaluated.document.productAttributes.assignments.count)
            guard opacityCandidates.count <= 1 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export only admits coincident color/opacity style histories.
                // Complete independent property histories require standard records preserving both override graphs before this branch can succeed.
                throw ProductAttributeError.unsupportedSemantics("Opacity and color histories need coincident standard style records.")
            }
            let opacity = opacityCandidates.first
            if let opacity {
                let previousColor = assignment.overrides.flatMap { id in evaluated.document.productAttributes.assignments.first { $0.id == id } }
                let previousOpacity = opacity.overrides.flatMap { id in evaluated.document.productAttributes.assignments.first { $0.id == id } }
                guard (previousColor == nil && previousOpacity == nil)
                    || (previousColor != nil && previousOpacity != nil && previousColor?.target == previousOpacity?.target) else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export cannot yet express differing color/opacity predecessors.
                    // Completion requires a standard equivalent property-specific provenance graph, without synthesizing color precedence.
                    throw ProductAttributeError.unsupportedSemantics("Independent opacity precedence cannot be inferred from a color override.")
                }
            }
            let rgb = try add("COLOUR_RGB('',\(color.r),\(color.g),\(color.b))")
            let side: Int
            if let opacity, case let .opacity(value) = opacity.value {
                let transparency = try add("SURFACE_STYLE_TRANSPARENT(\(1 - value))")
                let rendering = try add("SURFACE_STYLE_RENDERING_WITH_PROPERTIES(.NORMAL_SHADING.,#\(rgb),(#\(transparency)))")
                side = try add("SURFACE_SIDE_STYLE('',(#\(rendering)))")
            } else {
                let fillColor = try add("FILL_AREA_STYLE_COLOUR('',#\(rgb))")
                let fill = try add("FILL_AREA_STYLE('',(#\(fillColor)))")
                let area = try add("SURFACE_STYLE_FILL_AREA(#\(fill))")
                side = try add("SURFACE_SIDE_STYLE('',(#\(area)))")
            }
            let usage = try add("SURFACE_STYLE_USAGE(.BOTH.,#\(side))")
            let context: Int?
            if assignment.target.kind == .directUsage { context = try usageStyle(assignment.target).context }
            else if assignment.target.definitionID != nil, assignment.target.kind == .body || assignment.target.kind == .face {
                context = try geometryCarrier(assignment.target)
            } else { context = nil }
            let psa: Int
            if let context { psa = try add("PRESENTATION_STYLE_BY_CONTEXT((#\(usage)),#\(context))") }
            else { psa = try add("PRESENTATION_STYLE_ASSIGNMENT((#\(usage)))") }
            let items = try styleItems(assignment.target)
            var predecessors: [Int] = []
            if let predecessor = assignment.overrides {
                guard let previous = evaluated.document.productAttributes.assignments.first(where: { $0.id == predecessor }) else {
                    throw ProductAttributeError.missingTarget("Style predecessor assignment.")
                }
                try budget.charge(work: evaluated.document.productAttributes.assignments.count)
                predecessors = try appendStyle(previous, depth: depth + 1)
                guard predecessors.count == 1 || predecessors.count == items.count else {
                    throw ProductAttributeError.unsupportedSemantics("Style predecessor has ambiguous product correspondence.")
                }
            }
            var result: [Int] = []
            for (index, item) in items.enumerated() {
                let id: Int
                if let path = assignment.target.path {
                    guard predecessors.count == 1 else { throw ProductAttributeError.unsupportedSemantics("Contextual override requires an explicit base style.") }
                    var contexts: [String] = []
                    for component in path.components {
                        guard let relationship = transfer.relationships[component] else { throw ProductAttributeError.missingTarget("Contextual style relationship.") }
                        contexts.append("#\(relationship)")
                    }
                    id = try add("CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#\(psa)),#\(item),#\(predecessors[0]),(\(contexts.joined(separator: ","))))")
                } else if let context, !predecessors.isEmpty {
                    id = try add("CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#\(psa)),#\(item),#\(predecessors[predecessors.count == 1 ? 0 : index]),(#\(context)))")
                } else if !predecessors.isEmpty {
                    id = try add("OVER_RIDING_STYLED_ITEM('',(#\(psa)),#\(item),#\(predecessors[predecessors.count == 1 ? 0 : index]))")
                } else { id = try add("STYLED_ITEM('',(#\(psa)),#\(item))") }
                result.append(id)
            }
            styled[assignment.id] = result
            if let opacity { styled[opacity.id] = result }
            targetStyles[assignment.target, default: []].append(contentsOf: result)
            return result
        }
        mutating func physicalTargets(_ target: ProductAttributeTarget) throws -> [Int] {
            if let targets = shapeAspects[target] { return targets }
            if target.kind == .occurrence {
                guard let path = target.path, !path.components.isEmpty,
                      evaluated.assembly?.occurrences.contains(where: { $0.path == path }) == true,
                      let usageID = path.components.last,
                      let usage = transfer.usages[usageID] else {
                    throw ProductAttributeError.missingTarget("Physical occurrence path.")
                }
                // A PRODUCT_DEFINITION_SHAPE owned by the validated NAUO is the
                // standard characterized-definition owner for this exact path.
                // It preserves the occurrence selector without flattening shared geometry.
                let owner = try add("PRODUCT_DEFINITION_SHAPE('', '', #\(usage))")
                try budget.charge(targets: 1)
                shapeAspects[target] = [owner]
                return [owner]
            }
            guard target.path == nil else {
                throw ProductAttributeError.unsupportedSemantics("Physical target path requires an occurrence owner.")
            }
            if target.kind == .part { return try products(target).map(\.definition) }
            if target.kind == .directUsage {
                guard let id = target.usageID, let usage = transfer.usages[id] else { throw ProductAttributeError.missingTarget("Physical direct usage.") }
                return [usage]
            }
            let items = try styleItems(target)
            try check(transfer.products.count + (evaluated.assembly?.occurrences.count ?? 0))
            let products = try products(target)
            if target.definitionID == nil {
                guard items.count == 1, let item = items.first, let context = products.first?.context else {
                    throw ProductAttributeError.inconsistentArtifact("Global physical geometry requires one common exact item.")
                }
                for product in products {
                    try check()
                    guard product.context == context else { throw ProductAttributeError.inconsistentArtifact("Common global geometry has conflicting representation contexts.") }
                }
                let view = try add("SHAPE_REPRESENTATION('',(#\(item)),#\(context))")
                var metadata: ProductItemCharacterization?
                for candidate in evaluated.document.productAttributes.itemCharacterizations {
                    try check()
                    if candidate.target == target { metadata = candidate }
                }
                let name = try string(metadata?.name ?? "")
                let description: String
                if let value = metadata?.description { description = try string(value) } else { description = "$" }
                let owner = try add("CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(\(name),\(description),#\(item),#\(view))")
                try budget.charge(targets: 2); shapeAspects[target] = [owner]
                return [owner]
            }
            guard items.count == products.count else { throw ProductAttributeError.inconsistentArtifact("Physical geometry/product correspondence.") }
            var result: [Int] = []
            for (item, product) in zip(items, products) {
                // A direct singleton view gives each explicit PD target its own standard usage key without copying topology.
                let view = try add("SHAPE_REPRESENTATION('',(#\(item)),#\(product.context))")
                try check(evaluated.document.productAttributes.assignments.count)
                var label = ""
                for assignment in evaluated.document.productAttributes.assignments {
                    try duration.check(format: .step)
                    if assignment.target == target, case let .name(value) = assignment.value { label = value }
                }
                var description = "$"
                for record in evaluated.document.productAttributes.shapeElementDescriptions {
                    try check()
                    if record.target == target { description = try string(record.description) }
                }
                let aspect = try add("SHAPE_ASPECT(\(try string(label)),\(description),#\(product.definitionShape),.T.)")
                _ = try add("GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#\(aspect),#\(view),#\(item))")
                try budget.charge(targets: 1)
                result.append(aspect)
            }
            try budget.charge(targets: 1)
            shapeAspects[target] = result; return result
        }
        mutating func physicalProperty(_ assignment: ProductAttributeAssignment) throws {
            _ = try writePhysicalSourceAssignment(assignment,depth:0)
        }
        mutating func write() throws -> [String] {
            let source = evaluated.document.productAttributes
            try check(source.itemCharacterizations.count)
            for record in source.itemCharacterizations {
                try duration.check(format: .step)
                _ = try physicalTargets(record.target)
            }
            for record in source.shapeElementDescriptions { _ = try physicalTargets(record.target) }
            try writePhysicalSourceDescriptors()
            for assignment in source.assignments {
                switch assignment.value {
                case .name:
                    if assignment.target.definitionID != nil, assignment.target.kind == .body || assignment.target.kind == .face { _ = try physicalTargets(assignment.target) }
                case .color: _ = try appendStyle(assignment, depth: 0)
                case .opacity:
                    try budget.charge(work: source.assignments.count)
                    guard let color = source.assignments.first(where: { $0.target == assignment.target && $0.value.property == .color }) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export cannot emit an independent opacity-only history.
                        // Completion requires a standard style representation that preserves opacity without introducing an authored color.
                        throw ProductAttributeError.unsupportedSemantics("Opacity without a coincident explicit color style cannot be represented independently.")
                    }
                    _ = try appendStyle(color, depth: 0)
                case .material: try physicalProperty(assignment)
                case .density, .descriptorDensity: try physicalProperty(assignment)
                }
            }
            for layer in source.layers {
                try check()
                for member in layer.members {
                    try check()
                    if member.kind == .occurrence || member.kind == .directUsage || (member.definitionID != nil && (member.kind == .body || member.kind == .face)) {
                        _ = try layerStyle(member)
                    }
                }
            }
            try check(styled.count + targetStyles.count)
            var styleSet = Set<Int>()
            for ids in styled.values { for id in ids { try check(); try budget.charge(targets: 1); styleSet.insert(id) } }
            for ids in targetStyles.values { for id in ids { try check(); try budget.charge(targets: 1); styleSet.insert(id) } }
            for id in supportingStyles { try check(); try budget.charge(targets: 1); styleSet.insert(id) }
            try budget.charge(targets: styleSet.count)
            var allStyles = Array(styleSet)
            if !allStyles.isEmpty {
                // Preserve default-visible parts that have no explicit style without fabricating colors.
                let null = try add("PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)))")
                for (definitionID, product) in transfer.products {
                    try check()
                    let part = ProductAttributeTarget(kind: .part, definitionID: definitionID)
                    if targetStyles[part] != nil { continue }
                    for items in product.bodies.values {
                        try check()
                        for item in items {
                            try check(source.assignments.count + 1)
                            let covered = source.assignments.contains { assignment in
                                guard assignment.value.property == .color, assignment.target.path == nil,
                                      assignment.target.definitionID == nil,
                                      let topology = resolved.localGeometry[assignment.target] else { return false }
                                if case let .body(id) = topology { return product.bodies[id]?.contains(item) == true }
                                return false
                            }
                            if !covered {
                                try budget.charge(targets: 1)
                                allStyles.append(try add("STYLED_ITEM('',(#\(null)),#\(item))"))
                            }
                        }
                    }
                }
                guard let context = transfer.products.values.first?.context else { throw ProductAttributeError.missingTarget("Global styling context.") }
                _ = try add("DRAUGHTING_MODEL('',(\(allStyles.sorted().map { "#\($0)" }.joined(separator: ","))),#\(context))")
            }
            for layer in source.layers {
                var members = Set<Int>()
                for member in layer.members {
                    if let path = member.path {
                        // A nested occurrence uses the carrier-backed contextual chain emitted
                        // by layerStyle; a missing chain is rejected before this publication step.
                        guard !path.components.isEmpty, let styles = targetStyles[member], !styles.isEmpty else {
                            throw ProductAttributeError.unsupportedSemantics("Instance layer membership requires an admitted contextual styled item.")
                        }
                        members.formUnion(styles)
                    } else if member.kind == .directUsage || (member.definitionID != nil && (member.kind == .body || member.kind == .face)) {
                        let scoped = try layerStyle(member); try check(scoped.count); try budget.charge(targets: scoped.count)
                        members.formUnion(scoped)
                    } else { members.formUnion(try styleItems(member)) }
                }
                guard !members.isEmpty else { throw ProductAttributeError.unsupportedSemantics("Empty layer cannot be represented by a standard assigned-item set.") }
                _ = try add("PRESENTATION_LAYER_ASSIGNMENT(\(try string(layer.name)),\(try string(layer.description)),(\(members.sorted().map { "#\($0)" }.joined(separator: ","))))")
            }
            try writeMetadata()
            return records
        }
    }
}

// Shared semantic admission for reader/writer contexts; this consumes the immutable source, not expanded occurrence paths.
func stepAppearanceLeafDefinition(for usage: AssemblyOccurrenceID, in evaluated: EvaluatedDocument,
                                 budget: inout ProductAttributeBudget, duration: ExchangeProcessingBudget) throws -> AssemblyDefinition {
    guard let source = evaluated.document.assembly else { throw ProductAttributeError.missingTarget("Direct usage appearance source.") }
    var child: AssemblyDefinitionID?
    for occurrence in source.roots {
        try duration.check(format: .step); try budget.charge(work: 1)
        if occurrence.id == usage {
            guard child == nil else { throw ProductAttributeError.ambiguousProperty("Direct usage source owner.") }
            child = occurrence.definitionID
        }
    }
    for definition in source.definitions {
        try duration.check(format: .step); try budget.charge(work: 1)
        for occurrence in definition.children {
            try duration.check(format: .step); try budget.charge(work: 1)
            if occurrence.id == usage {
                guard child == nil else { throw ProductAttributeError.ambiguousProperty("Direct usage source owner.") }
                child = occurrence.definitionID
            }
        }
    }
    try duration.check(format: .step); try budget.charge(work: source.definitions.count)
    guard let child, let definition = source.definitions.first(where: { $0.id == child }) else {
        throw ProductAttributeError.missingTarget("Direct usage appearance child.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP direct-usage appearance currently retains only nonempty geometry-bearing leaf children.
    // Nonleaf or empty usage appearance needs standard descendant/default semantics matching native resolution before it can succeed.
    guard !definition.features.isEmpty, definition.children.isEmpty else {
        throw ProductAttributeError.unsupportedSemantics("Direct usage appearance requires a nonempty leaf child.")
    }
    return definition
}
