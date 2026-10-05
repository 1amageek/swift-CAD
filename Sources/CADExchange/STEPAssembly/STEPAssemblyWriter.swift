import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology

public struct STEPAssemblyWriter: STEPAssemblyWriting {
    public let tolerance: ModelingTolerance
    public let resourceLimits: ExchangeResourceLimits
    private let attributes: any STEPAttributesWriting
    private let allowsGroupSemanticLoss: Bool
    private let surfaceOverrides: [Surface3D: BSplineSurface3D]
    private let curveConversions: ExchangeCurveConversionPlan
    private let processingBudgetOverride: ExchangeProcessingBudget?
    public init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits = .standard, attributes: any STEPAttributesWriting = STEPAttributesWriter()) {
        self.tolerance = tolerance; self.resourceLimits = resourceLimits; self.attributes = attributes; surfaceOverrides = [:]; curveConversions = .init(); processingBudgetOverride = nil; allowsGroupSemanticLoss = false
    }
    init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits, surfaceOverrides: [Surface3D: BSplineSurface3D], curveConversions: ExchangeCurveConversionPlan = .init(), processingBudget: ExchangeProcessingBudget? = nil, allowsGroupSemanticLoss: Bool = false) {
        self.tolerance = tolerance; self.resourceLimits = resourceLimits; attributes = STEPAttributesWriter(); self.surfaceOverrides = surfaceOverrides; self.curveConversions = curveConversions; processingBudgetOverride = processingBudget; self.allowsGroupSemanticLoss = allowsGroupSemanticLoss
    }
    public func write(_ evaluated: EvaluatedDocument, units: UnitSystem, to sink: any ByteSink) throws {
        try units.validate(); try resourceLimits.validate()
        guard let labels = evaluated.document.assembly else { throw AssemblyError.invalidSource("Missing assembly source.") }
        let assemblyLimits = AssemblyResourceLimits(maximumRecords: resourceLimits.maximumEntities,
            maximumOccurrences: resourceLimits.maximumEntities, maximumDepth: resourceLimits.maximumNesting,
            maximumTopologyEntities: resourceLimits.maximumEntities, maximumWork: resourceLimits.maximumIterations, maximumTextBytes: resourceLimits.maximumBytes,
            maximumAlgebraicDepth: resourceLimits.maximumAlgebraicDepth)
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
        let names = try resolved.map { try attributes.geometryNames(for: evaluated, resolved: $0, limits: resourceLimits) }
        var transfer = STEPAttributeWriteTransfer()
        let budget = processingBudgetOverride ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        let writer = ExactSTEPWriter(resourceLimits: resourceLimits, tolerance: tolerance, surfaceOverrides: surfaceOverrides, curveConversions: curveConversions, processingBudget: budget, allowsGroupSemanticLoss: allowsGroupSemanticLoss)
        var table = ExactSTEPWriter.EntityTable(maximumEntities: resourceLimits.maximumEntities, tolerance: tolerance, maximumBytes: resourceLimits.maximumBytes, maximumStringWork: resourceLimits.maximumIterations, maximumSourceDepth: resourceLimits.maximumNesting, maximumAlgebraicDepth: resourceLimits.maximumAlgebraicDepth, processingBudget: budget)
        let identityWriter: any STEPSourceIdentityWriting = STEPSourceIdentityWriter()
        var sharingBudget = try ProductAttributeBudget(limits: attributeLimits)
        try sharingBudget.charge(work: resolved?.consumedWork ?? 0)
        var geometryKeys: [AssemblyDefinitionID: [FeatureID]] = [:]
        var carrierKeys = Set<[FeatureID]>()
        var appearanceUsages = Set<AssemblyOccurrenceID>(), usageCarrierDefinitions = Set<AssemblyDefinitionID>()
        var occurrenceCarrierDefinitions = Set<AssemblyDefinitionID>()
        for assignment in attributeSource.assignments {
            try budget.check(format: .step); try sharingBudget.charge(work: 1)
            if assignment.target.kind == .directUsage, let usage = assignment.target.usageID,
               assignment.value.property == .color || assignment.value.property == .opacity {
                try sharingBudget.charge(targets: 1); appearanceUsages.insert(usage)
            }
            if assignment.target.kind == .occurrence,
               assignment.value.property == .color || assignment.value.property == .opacity,
               let path = assignment.target.path,
               let occurrence = evaluated.assembly?.occurrences.first(where: { $0.path == path }) {
                try sharingBudget.charge(targets: 1); occurrenceCarrierDefinitions.insert(occurrence.definitionID)
            }
        }
        for layer in attributeSource.layers {
            try budget.check(format: .step); try sharingBudget.charge(work: 1)
            for member in layer.members {
                try budget.check(format: .step); try sharingBudget.charge(work: 1)
                if member.kind == .directUsage, let usage = member.usageID {
                    try sharingBudget.charge(targets: 1); appearanceUsages.insert(usage)
                }
                if member.kind == .occurrence, let path = member.path,
                   let occurrence = evaluated.assembly?.occurrences.first(where: { $0.path == path }) {
                    try sharingBudget.charge(targets: 1); occurrenceCarrierDefinitions.insert(occurrence.definitionID)
                }
            }
        }
        for occurrence in source.roots {
            try budget.check(format: .step); try sharingBudget.charge(work: 1)
            if appearanceUsages.contains(occurrence.id) { try sharingBudget.charge(targets: 1); usageCarrierDefinitions.insert(occurrence.definitionID) }
        }
        for definition in source.definitions {
            try budget.check(format: .step); try sharingBudget.charge(work: 1)
            for occurrence in definition.children {
                try budget.check(format: .step); try sharingBudget.charge(work: 1)
                if appearanceUsages.contains(occurrence.id) { try sharingBudget.charge(targets: 1); usageCarrierDefinitions.insert(occurrence.definitionID) }
            }
        }
        for definition in source.definitions where !definition.features.isEmpty {
            try budget.check(format: .step)
            let count = definition.features.count
            let levels = Int.bitWidth - count.leadingZeroBitCount
            guard count <= (attributeLimits.maximumWork - sharingBudget.consumedWork) / (levels + 1) else {
                throw ProductAttributeError.resourceLimitExceeded("Canonical shared geometry key work.")
            }
            try sharingBudget.charge(work: count * (levels + 1), targets: count + 1)
            let key = definition.features.sorted(); geometryKeys[definition.id] = key
            try sharingBudget.charge(work: attributeSource.assignments.count)
            var carrier = usageCarrierDefinitions.contains(definition.id)
                || occurrenceCarrierDefinitions.contains(definition.id)
                || attributeSource.assignments.contains {
                $0.target.definitionID == definition.id && ($0.value.property == .color || $0.value.property == .opacity)
            }
            for layer in attributeSource.layers {
                try budget.check(format: .step)
                try sharingBudget.charge(work: layer.members.count + 1)
                if layer.members.contains(where: { $0.definitionID == definition.id }) { carrier = true }
            }
            if carrier, !carrierKeys.contains(key) { try sharingBudget.charge(targets: 1); carrierKeys.insert(key) }
        }
        var sharedGeometry: [[FeatureID]: ExactSTEPWriter.WrittenDefinition] = [:]
        var featureGeometry: [FeatureID: ExactSTEPWriter.WrittenGeometry] = [:]
        var geometryContext: ExactSTEPWriter.WrittenGeometryContext?
        if evaluated.document.independentShapes != nil {
            table.independentUsage = try IndependentShapeExchangeUsage(limits: resourceLimits, format: .step, processing: budget,
                consumedEntities: 0, consumedWork: sharingBudget.consumedWork, consumedBytes: 0)
        }
        let paidSharingWork = sharingBudget.consumedWork
        var products: [AssemblyProductID: Int] = [:]
        for product in source.products.sorted(by: { $0.id < $1.id }) {
            try budget.check(format: .step)
            let entity = try writer.appendProduct(product, table: &table)
            products[product.id] = entity
            try identityWriter.append(uuid: product.id.description, role: .product, target: entity, table: &table)
        }
        var formations: [AssemblyProductFormationID: Int] = [:]
        for formation in source.formations.sorted(by: { $0.id < $1.id }) {
            try budget.check(format: .step)
            guard let product = products[formation.productID] else { throw AssemblyError.invalidSource("Missing exported product.") }
            let entity = try writer.appendFormation(formation, product: product, table: &table)
            formations[formation.id] = entity
            try identityWriter.append(uuid: formation.id.description, role: .formation, target: entity, table: &table)
        }
        var written: [AssemblyDefinitionID: ExactSTEPWriter.WrittenDefinition] = [:]
        var axes: [AssemblyOccurrenceID: Int] = [:]
        var referenceAxes: [AssemblyOccurrenceID: Int] = [:]
        var referenceItems: [AssemblyDefinitionID: [Int]] = [:]
        func retainPlacement(_ occurrence: AssemblyOccurrence) throws {
            try sharingBudget.charge(work: 1, targets: 1)
            switch occurrence.placement {
            case .rigid, .affine, .step:
                axes[occurrence.id] = try writer.assemblyPlacementItem(occurrence.placement,
                    units: units.length, table: &table)
            case .word(let word):
                // FIXME(INCOMPLETE_IMPLEMENTATION): This standard IDT transport retains
                // exactly the original target/reference word. Other original operation
                // sequences need a legal chain carrier before public STEP export succeeds.
                guard word.factors.count == 2,
                      case .forward(let target) = word.factors[0],
                      case .inverse(let origin) = word.factors[1] else {
                    throw IndependentShapeExchangeError.metadataLoss("STEP has no admitted carrier for this original placement word.")
                }
                try sharingBudget.charge(work: 2, targets: 2)
                let targetID = try writer.assemblyPlacementItem(target, units: units.length, table: &table)
                let originID = try writer.assemblyPlacementItem(origin, units: units.length, table: &table)
                axes[occurrence.id] = targetID; referenceAxes[occurrence.id] = originID
                referenceItems[occurrence.definitionID, default: []].append(originID)
            }
        }
        for definition in source.definitions {
            try budget.check(format: .step)
            for child in definition.children { try retainPlacement(child) }
        }
        for root in source.roots { try retainPlacement(root) }
        for definition in source.definitions.sorted(by: { $0.id < $1.id }) {
            try budget.check(format: .step)
            var items = referenceItems[definition.id] ?? []
            for child in definition.children.sorted(by: { $0.id < $1.id }) {
                try sharingBudget.charge(work: 1, targets: 1)
                guard let axis = axes[child.id] else { throw AssemblyError.invalidSource("Missing original placement target.") }
                items.append(axis)
            }
            let key = geometryKeys[definition.id] ?? []
            let carrier = !key.isEmpty && carrierKeys.contains(key)
            guard let formation = formations[definition.formationID] else { throw AssemblyError.invalidSource("Missing exported formation.") }
            let product: ExactSTEPWriter.WrittenDefinition
            if !key.isEmpty, let geometry = sharedGeometry[key] {
                if !carrier {
                    let retainedBodyCount = geometry.bodies.count
                    let retainedSortLevels = max(1, Int.bitWidth - max(1, retainedBodyCount).leadingZeroBitCount)
                    let retainedSortWork = retainedBodyCount * (retainedSortLevels + 1)
                    try sharingBudget.charge(work: retainedSortWork, targets: retainedBodyCount)
                    var retainedItemCount = 0
                    for bodyItems in geometry.bodies.values {
                        try sharingBudget.charge(work: 1)
                        retainedItemCount += bodyItems.count
                    }
                    try sharingBudget.charge(work: retainedItemCount + items.count,
                        targets: retainedItemCount + items.count)
                } else {
                    try sharingBudget.charge(work: items.count, targets: items.count)
                }
                product = try writer.appendSharedDefinition(geometry: geometry, retainedFormation: formation,
                    identifier: definition.identifier, description: definition.definitionDescription,
                    placementItems: items, wholePartCarrier: carrier, units: units, table: &table)
            } else if key.isEmpty {
                product = try writer.appendDefinition(brep: BRepModel(), units: units,
                    identifier: "", name: "", definitionDescription: definition.definitionDescription, additionalItems: items,
                    retainedFormation: formation, definitionIdentifier: definition.identifier, table: &table)
            } else {
                var geometries: [ExactSTEPWriter.WrittenGeometry] = []
                try sharingBudget.charge(work: key.count, targets: key.count)
                for feature in key {
                    try budget.check(format: .step)
                    if featureGeometry[feature] == nil {
                        try sharingBudget.charge(work: artifact.local.subshapes.entries.count)
                        var bodyIDs = Set<BodyID>()
                        for (output, reference) in artifact.local.subshapes.entries where output.featureID == feature {
                            try budget.check(format: .step)
                            if case let .body(id) = reference {
                                try sharingBudget.charge(targets: 1)
                                bodyIDs.insert(id)
                            }
                        }
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP modular geometry export cannot preserve a multi-body feature's sole source owner yet.
                        // A standard grouped feature identity transport must reconstruct that owner before multi-body outputs can succeed.
                        guard bodyIDs.count == 1 else {
                            throw ProductAttributeError.unsupportedSemantics("Modular STEP geometry requires one body per feature.")
                        }
                        let local = artifact.local.model
                        for count in [local.vertices.count, local.edges.count, local.loops.count,
                                      local.faces.count, local.shells.count, local.bodies.count] {
                            try sharingBudget.charge(work: count)
                        }
                        let model = try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: local)
                        let context: ExactSTEPWriter.WrittenGeometryContext
                        if let retained = geometryContext { context = retained }
                        else {
                            try sharingBudget.charge(work: 1, targets: 1)
                            context = try writer.appendGeometryContext(units: units, table: &table)
                            geometryContext = context
                        }
                        let geometry = try writer.appendGeometry(brep: model, units: units, geometryContext: context,
                            bodyNames: names?.bodies ?? [:], faceNames: names?.faces ?? [:], table: &table)
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP modular export cannot yet reconstruct one Body owning several emitted solid components.
                        // Preserve component-to-source body grouping through a standard transport before publishing multiple items as one feature.
                        guard geometry.bodies.count == 1, geometry.items.count == 1 else {
                            throw ProductAttributeError.unsupportedSemantics("Modular STEP geometry requires one exact item per feature.")
                        }
                        try sharingBudget.charge(targets: 1)
                        featureGeometry[feature] = geometry
                    }
                    guard let geometry = featureGeometry[feature] else { throw AssemblyError.invalidSource("Missing emitted feature geometry.") }
                    let compositionCount = geometry.items.count + geometry.bodies.count + geometry.faces.count
                    try sharingBudget.charge(work: compositionCount, targets: compositionCount)
                    geometries.append(geometry)
                }
                try sharingBudget.charge(work: items.count, targets: items.count)
                product = try writer.appendModularDefinition(geometries: geometries, retainedFormation: formation,
                    identifier: definition.identifier, description: definition.definitionDescription,
                    placementItems: items, wholePartCarrier: carrier, units: units, processing: budget, table: &table)
                try sharingBudget.charge(work: key.count, targets: 1)
                sharedGeometry[key] = product
            }
            try identityWriter.append(uuid: definition.id.description, role: .definition, target: product.definition, table: &table)
            if key.isEmpty {
                try identityWriter.append(uuid: definition.id.description, role: .representationCarrier, target: product.representation, table: &table)
            }
            written[definition.id] = product
            transfer.products[definition.id] = STEPAttributeProductRepresentation(definition: product.definition,
                definitionShape: product.definitionShape, representation: product.representation, context: product.context,
                geometryRepresentation: product.geometryRepresentation, carrier: product.carrier, bodies: product.bodies, faces: product.faces)
        }
        // A synthetic STEP product is a transport container for placed source roots, not a CAD feature.
        // Its exact marker is retained so our reader removes only this authored envelope container.
        var rootAxes: [Int] = []
        for occurrence in source.roots.sorted(by: { $0.id < $1.id }) {
            try sharingBudget.charge(work: 1, targets: 1)
            guard let axis = axes[occurrence.id] else { throw AssemblyError.invalidSource("Missing original root placement target.") }
            rootAxes.append(axis)
        }
        let envelope = try writer.appendDefinition(brep: BRepModel(), units: units,
            identifier: "swiftcad.assembly.roots", name: "swiftcad.assembly.roots",
            additionalItems: rootAxes, table: &table)
        try identityWriter.append(uuid: AssemblyDefinitionID().description, role: .representationCarrier, target: envelope.representation, table: &table)
        func appendUsage(_ occurrence: AssemblyOccurrence, parent: ExactSTEPWriter.WrittenDefinition) throws {
            try budget.check(format: .step)
            guard let child = written[occurrence.definitionID], let axis = axes[occurrence.id] else {
                throw AssemblyError.missingDefinition(occurrence.definitionID)
            }
            let usage = try table.add("NEXT_ASSEMBLY_USAGE_OCCURRENCE(\(try table.quotedString(occurrence.id.description)),\(try table.quotedString(occurrence.name)),'',#\(parent.definition),#\(child.definition),$)")
            let shape = try table.add("PRODUCT_DEFINITION_SHAPE('','',#\(usage))")
            let reference = referenceAxes[occurrence.id] ?? child.origin
            let transform = try table.add("ITEM_DEFINED_TRANSFORMATION('','',#\(reference),#\(axis))")
            let relationship = try table.add("(REPRESENTATION_RELATIONSHIP('','',#\(child.representation),#\(parent.representation)) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#\(transform)) SHAPE_REPRESENTATION_RELATIONSHIP())")
            let context = try table.add("CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#\(relationship),#\(shape))")
            try budget.check(format: .step); try sharingBudget.charge(work: 1, targets: 1)
            transfer.usages[occurrence.id] = usage; transfer.relationships[occurrence.id] = relationship
            transfer.usageContexts[occurrence.id] = context
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
        if let independent = evaluated.document.independentShapes {
            guard var usage = table.independentUsage else { throw IndependentShapeExchangeError.invalidAssociation("Missing assembly/independent caller ledger.") }
            try usage.charge(work: sharingBudget.consumedWork - paidSharingWork)
            try usage.validateDocument(evaluated.document, tolerance: tolerance)
            try usage.charge(entities: written.count, work: written.count)
            var definitionEntities: [AssemblyDefinitionID: Int] = [:]
            for (id, definition) in written { definitionEntities[id] = definition.definition }
            var bodyBindings: [SubshapeID: IndependentSTEPBodyBinding] = [:]
            for (selector, reference) in artifact.local.subshapes.entries {
                try usage.charge(entities: 1, work: 1)
                guard case .body(let id) = reference, let geometry = featureGeometry[selector.featureID] else { continue }
                guard let entities = geometry.bodies[id], entities.count == 1, let entity = entities.first else {
                    throw IndependentShapeExchangeError.invalidAssociation("Original mixed Body selector has no sole emitted source entity.")
                }
                bodyBindings[selector] = try IndependentSTEPBodyBinding(entityID: entity, lengthUnit: units.length)
            }
            try writer.appendIndependent(independent, units: units, table: &table, productDefinitions: definitionEntities,
                bodyBindings: bodyBindings, bodySourceGraph: evaluated.document.designGraph, usage: &usage)
        }
        try writer.publish(table: table, to: sink)
    }
}
