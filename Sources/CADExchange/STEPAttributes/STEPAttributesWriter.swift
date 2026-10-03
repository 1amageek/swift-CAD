import CADCore
import CADIR
import CADKernel

public struct STEPAttributesWriter: STEPAttributesWriting {
    public init() {}
    public func geometryNames(for evaluated: EvaluatedDocument, resolved: ResolvedProductAttributes) throws -> STEPGeometryAttributeNames {
        var bodies: [BodyID: String] = [:], faces: [FaceID: String] = [:]
        var overridden = Set<ProductAttributeID>()
        for assignment in evaluated.document.productAttributes.assignments where assignment.value.property == .name {
            if let predecessor = assignment.overrides { overridden.insert(predecessor) }
        }
        for assignment in evaluated.document.productAttributes.assignments where !overridden.contains(assignment.id) {
            guard case let .name(name) = assignment.value else { continue }
            guard assignment.target.path == nil, let topology = resolved.localGeometry[assignment.target] else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Context-specific geometry names are not yet emitted by the public STEP writer.
                // STEPExchange and OfficialFormatExchange must refuse until a standard contextual name target preserves the complete path.
                throw ProductAttributeError.unsupportedSemantics("Context-specific geometry names require a standard equivalent target.")
            }
            switch topology {
            case let .body(id): bodies[id] = name
            case let .face(id): faces[id] = name
            default: throw ProductAttributeError.invalidSource("Unsupported named geometry kind.")
            }
        }
        return STEPGeometryAttributeNames(bodies: bodies, faces: faces)
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
        return try builder.write()
    }
}

private extension STEPAttributesWriter {
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
        var shapeAspects: [ProductAttributeTarget: [Int]] = [:]
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
        func products(_ target: ProductAttributeTarget) throws -> [STEPAttributeProductRepresentation] {
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
            case .occurrence: return try products(target).map(\.representation)
            case .directUsage:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP attribute export has no direct-usage style-to-complete-path expansion.
                // Completion requires standard contextual records retaining every actual shared usage scope without flattening.
                throw ProductAttributeError.unsupportedSemantics("Direct usage styling needs a complete contextual instance path.")
            case .body, .face:
                guard let topology = resolved.localGeometry[target] else { throw ProductAttributeError.missingTarget("Style geometry target.") }
                let products = try products(target)
                guard !products.isEmpty else { throw ProductAttributeError.missingTarget("Style product membership.") }
                return try products.map { product in
                    switch topology {
                    case let .body(id):
                        guard let items = product.bodies[id], items.count == 1, let item = items.first else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): STEPExchange cannot yet retain one attributed multi-component Body across several solid items.
                            // A standard unique Body grouping with exact attribute scope and independent round-trip evidence is required.
                            throw ProductAttributeError.unsupportedSemantics("Attributed body spans several STEP representation items.")
                        }
                        return item
                    case let .face(id):
                        guard let item = product.faces[id] else { throw ProductAttributeError.missingTarget("Style face.") }
                        return item
                    default: throw ProductAttributeError.invalidSource("Unsupported style topology kind.")
                    }
                }
            }
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
            let psa = try add("PRESENTATION_STYLE_ASSIGNMENT((#\(usage)))")
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
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP physical-property export has no complete nested instance-path representation.
            // Completion requires an admitted standard contextual association and an independent shared/nested-path round trip.
            guard target.path == nil else { throw ProductAttributeError.unsupportedSemantics("A complete physical instance path cannot be reduced to a direct STEP usage.") }
            if target.kind == .part { return try products(target).map(\.definition) }
            if target.kind == .directUsage {
                guard let id = target.usageID, let usage = transfer.usages[id] else { throw ProductAttributeError.missingTarget("Physical direct usage.") }
                return [usage]
            }
            let items = try styleItems(target), products = try products(target)
            guard items.count == products.count else { throw ProductAttributeError.inconsistentArtifact("Physical geometry/product correspondence.") }
            var result: [Int] = []
            for (item, product) in zip(items, products) {
                let aspect = try add("SHAPE_ASPECT('','',#\(product.definitionShape),.T.)")
                _ = try add("GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#\(aspect),#\(product.geometryRepresentation),#\(item))")
                result.append(aspect)
            }
            shapeAspects[target] = result; return result
        }
        mutating func physicalProperty(_ assignment: ProductAttributeAssignment) throws {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP physical-property export has no explicit standard override-order representation.
            // Completion requires a standard ordering relationship preserving independent material and density provenance.
            guard assignment.overrides == nil else {
                throw ProductAttributeError.unsupportedSemantics("Physical override chains require a standard-equivalent ordering relationship.")
            }
            let item: Int, label: String
            switch assignment.value {
            case let .material(id):
                try budget.charge(work: evaluated.document.productAttributes.materials.count)
                guard let material = evaluated.document.productAttributes.materials.first(where: { $0.id == id }) else { throw ProductAttributeError.missingTarget("Physical material.") }
                label = "material name"; item = try add("DESCRIPTIVE_REPRESENTATION_ITEM(\(try string(material.name)),\(try string(material.description)))")
            case .density, .descriptorDensity:
                let density: PhysicalDensity
                if case let .density(value) = assignment.value { density = value }
                else if case let .descriptorDensity(id) = assignment.value,
                        let value = evaluated.document.productAttributes.materials.first(where: { $0.id == id })?.density { density = value }
                else { throw ProductAttributeError.missingTarget("Explicit descriptor density assignment.") }
                let mass = try add("(MASS_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.GRAM.))")
                let length = try add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
                let m = try add("DERIVED_UNIT_ELEMENT(#\(mass),1.)"), l = try add("DERIVED_UNIT_ELEMENT(#\(length),-3.)")
                let unit = try add("DERIVED_UNIT((#\(m),#\(l)))")
                label = "density"
                item = try add("(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(\(density.kilogramsPerCubicMeter)),#\(unit)) REPRESENTATION_ITEM('density'))")
            default: throw ProductAttributeError.invalidSource("Unsupported physical property value.")
            }
            let targets = try physicalTargets(assignment.target)
            guard let context = transfer.products.values.first?.context else { throw ProductAttributeError.missingTarget("Property representation context.") }
            for target in targets {
                let property = try add("PROPERTY_DEFINITION('material property',\(try string(label)),#\(target))")
                let representation = try add("REPRESENTATION(\(try string(label)),(#\(item)),#\(context))")
                _ = try add("PROPERTY_DEFINITION_REPRESENTATION(#\(property),#\(representation))")
            }
        }
        mutating func write() throws -> [String] {
            let source = evaluated.document.productAttributes
            var referenced = Set<PhysicalMaterialID>()
            for assignment in source.assignments {
                switch assignment.value {
                case .name: break
                case .color: _ = try appendStyle(assignment, depth: 0)
                case .opacity:
                    try budget.charge(work: source.assignments.count)
                    guard let color = source.assignments.first(where: { $0.target == assignment.target && $0.value.property == .color }) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export cannot emit an independent opacity-only history.
                        // Completion requires a standard style representation that preserves opacity without introducing an authored color.
                        throw ProductAttributeError.unsupportedSemantics("Opacity without a coincident explicit color style cannot be represented independently.")
                    }
                    _ = try appendStyle(color, depth: 0)
                case let .material(id): referenced.insert(id); try physicalProperty(assignment)
                case .density, .descriptorDensity: try physicalProperty(assignment)
                }
            }
            for material in source.materials {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export cannot retain an unattached physical descriptor.
                // Completion requires a standard retained descriptor owner without inventing a part/property attachment.
                guard referenced.contains(material.id) else { throw ProductAttributeError.unsupportedSemantics("Unattached physical descriptor cannot be discarded.") }
                if material.density != nil {
                    for assignment in source.assignments where assignment.value == .material(material.id) {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP export cannot retain a latent descriptor density independently of effective target density.
                        // Completion requires a standard descriptor-owned density association with no synthesized target override.
                        guard source.assignments.contains(where: { $0.target == assignment.target && $0.value == .descriptorDensity(material.id) }) else {
                            throw ProductAttributeError.unsupportedSemantics("Descriptor density requires an explicit target density assignment for standard transfer.")
                        }
                    }
                }
            }
            var allStyles = Array(Set(styled.values.flatMap { $0 }))
            if !allStyles.isEmpty {
                // Preserve default-visible parts that have no explicit style without fabricating colors.
                let null = try add("PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)))")
                for (definitionID, product) in transfer.products {
                    let part = ProductAttributeTarget(kind: .part, definitionID: definitionID)
                    if targetStyles[part] != nil { continue }
                    for items in product.bodies.values {
                        for item in items {
                            let covered = source.assignments.contains { assignment in
                                guard assignment.value.property == .color, assignment.target.path == nil,
                                      let topology = resolved.localGeometry[assignment.target] else { return false }
                                if case let .body(id) = topology { return product.bodies[id]?.contains(item) == true }
                                return false
                            }
                            if !covered { allStyles.append(try add("STYLED_ITEM('',(#\(null)),#\(item))")) }
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
                        guard !path.components.isEmpty, let styles = targetStyles[member], !styles.isEmpty else {
                            throw ProductAttributeError.unsupportedSemantics("Instance layer membership requires an admitted contextual styled item.")
                        }
                        members.formUnion(styles)
                    } else { members.formUnion(try styleItems(member)) }
                }
                guard !members.isEmpty else { throw ProductAttributeError.unsupportedSemantics("Empty layer cannot be represented by a standard assigned-item set.") }
                _ = try add("PRESENTATION_LAYER_ASSIGNMENT(\(try string(layer.name)),\(try string(layer.description)),(\(members.sorted().map { "#\($0)" }.joined(separator: ","))))")
            }
            return records
        }
    }
}
