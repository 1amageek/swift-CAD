import CADCore
import CADIR
import CADKernel
import CADTopology

public struct STEPAssemblyWriter: STEPAssemblyWriting {
    public let tolerance: ModelingTolerance
    public let resourceLimits: ExchangeResourceLimits
    private let attributes: any STEPAttributesWriting
    public init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits = .standard, attributes: any STEPAttributesWriting = STEPAttributesWriter()) {
        self.tolerance = tolerance; self.resourceLimits = resourceLimits; self.attributes = attributes
    }
    public func write(_ evaluated: EvaluatedDocument, units: UnitSystem, to sink: any ByteSink) throws {
        try units.validate(); try resourceLimits.validate()
        guard let labels = evaluated.document.assembly else { throw AssemblyError.invalidSource("Missing assembly source.") }
        let assemblyLimits = AssemblyResourceLimits(maximumRecords: resourceLimits.maximumEntities,
            maximumOccurrences: resourceLimits.maximumEntities, maximumDepth: resourceLimits.maximumNesting,
            maximumTopologyEntities: resourceLimits.maximumEntities, maximumWork: resourceLimits.maximumIterations)
        _ = try DocumentAssemblyValidator().expandedOccurrences(of: labels, in: evaluated.document.designGraph,
            tolerance: tolerance, limits: assemblyLimits)
        try evaluated.document.validate(tolerance: tolerance)
        try evaluated.validateAssemblyArtifacts(tolerance: tolerance, limits: assemblyLimits)
        guard let source = evaluated.document.assembly, let artifact = evaluated.assembly else {
            throw AssemblyError.inconsistentArtifact("STEP assembly export requires assembly source and local evaluation.")
        }
        let attributeSource = evaluated.document.productAttributes
        let attributeLimits = ProductAttributeLimits(maximumRecords: resourceLimits.maximumEntities,
            maximumTargets: resourceLimits.maximumEntities, maximumDepth: resourceLimits.maximumNesting,
            maximumTextBytes: resourceLimits.maximumBytes, maximumWork: resourceLimits.maximumIterations)
        let resolved = attributeSource.isEmpty ? nil : try ProductAttributeResolver().resolve(evaluated, limits: attributeLimits)
        let names = try resolved.map { try attributes.geometryNames(for: evaluated, resolved: $0) }
        var transfer = STEPAttributeWriteTransfer()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        let writer = ExactSTEPWriter(resourceLimits: resourceLimits, tolerance: tolerance)
        var table = ExactSTEPWriter.EntityTable(maximumEntities: resourceLimits.maximumEntities, tolerance: tolerance, maximumBytes: resourceLimits.maximumBytes, maximumStringWork: resourceLimits.maximumIterations)
        var written: [AssemblyDefinitionID: ExactSTEPWriter.WrittenDefinition] = [:]
        var axes: [AssemblyOccurrenceID: Int] = [:]
        for definition in source.definitions.sorted(by: { $0.id < $1.id }) {
            try budget.check(format: .step)
            guard definition.features.isEmpty || definition.children.isEmpty else {
                throw AssemblyError.invalidSource("STEP assembly geometry and child representations would be ambiguous.")
            }
            var bodyIDs = Set<BodyID>()
            for featureID in definition.features {
                for (output, reference) in artifact.local.subshapes.entries where output.featureID == featureID {
                    if case let .body(id) = reference { bodyIDs.insert(id) }
                }
            }
            let model = try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: artifact.local.model)
            var items: [Int] = []
            for child in definition.children.sorted(by: { $0.id < $1.id }) {
                let axis = try writer.assemblyAxis(child.placement, units: units.length, table: &table)
                axes[child.id] = axis; items.append(axis)
            }
            let carrier = attributeSource.assignments.contains { $0.target.definitionID == definition.id && ($0.value.property == .color || $0.value.property == .opacity) }
                || attributeSource.layers.contains { $0.members.contains { $0.kind == .part && $0.definitionID == definition.id } }
            let product = try writer.appendDefinition(brep: model, units: units,
                identifier: definition.id.description, name: definition.name,
                productDescription: definition.productDescription, definitionDescription: definition.definitionDescription, additionalItems: items, wholePartCarrier: carrier,
                bodyNames: names?.bodies ?? [:], faceNames: names?.faces ?? [:], table: &table)
            written[definition.id] = product
            transfer.products[definition.id] = STEPAttributeProductRepresentation(definition: product.definition,
                definitionShape: product.definitionShape, representation: product.representation, context: product.context,
                geometryRepresentation: product.geometryRepresentation, carrier: product.carrier, bodies: product.bodies, faces: product.faces)
        }
        // A synthetic STEP product is a transport container for placed source roots, not a CAD feature.
        // Its exact marker is retained so our reader removes only this authored envelope container.
        var rootAxes: [Int] = []
        for occurrence in source.roots.sorted(by: { $0.id < $1.id }) {
            let axis = try writer.assemblyAxis(occurrence.placement, units: units.length, table: &table)
            axes[occurrence.id] = axis; rootAxes.append(axis)
        }
        let envelope = try writer.appendDefinition(brep: BRepModel(), units: units,
            identifier: "swiftcad.assembly.roots", name: "swiftcad.assembly.roots",
            additionalItems: rootAxes, table: &table)
        func appendUsage(_ occurrence: AssemblyOccurrence, parent: ExactSTEPWriter.WrittenDefinition) throws {
            try budget.check(format: .step)
            guard let child = written[occurrence.definitionID], let axis = axes[occurrence.id] else {
                throw AssemblyError.missingDefinition(occurrence.definitionID)
            }
            let usage = try table.add("NEXT_ASSEMBLY_USAGE_OCCURRENCE(\(try table.quotedString(occurrence.id.description)),\(try table.quotedString(occurrence.name)),'',#\(parent.definition),#\(child.definition),$)")
            let shape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(usage))")
            let transform = try table.add("ITEM_DEFINED_TRANSFORMATION('','',#\(child.origin),#\(axis))")
            let relationship = try table.add("(REPRESENTATION_RELATIONSHIP('','',#\(child.representation),#\(parent.representation)) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#\(transform)) SHAPE_REPRESENTATION_RELATIONSHIP())")
            _ = try table.add("CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#\(relationship),#\(shape))")
            transfer.usages[occurrence.id] = usage; transfer.relationships[occurrence.id] = relationship
        }
        for definition in source.definitions {
            guard let parent = written[definition.id] else { throw AssemblyError.missingDefinition(definition.id) }
            for child in definition.children { try appendUsage(child, parent: parent) }
        }
        for occurrence in source.roots { try appendUsage(occurrence, parent: envelope) }
        try budget.check(format: .step)
        if let resolved {
            let records = try attributes.records(for: evaluated, resolved: resolved, transfer: transfer,
                startingAt: table.entities.count + 1, limits: resourceLimits)
            for record in records { _ = try table.add(record) }
        }
        try writer.publish(table: table, to: sink)
    }
}
