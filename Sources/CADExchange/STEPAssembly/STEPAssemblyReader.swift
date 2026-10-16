import Foundation
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology

public struct STEPAssemblyReader: STEPAssemblyReading {
    public let tolerance: ModelingTolerance
    public let resourceLimits: ExchangeResourceLimits
    public init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits = .standard) {
        self.tolerance = tolerance; self.resourceLimits = resourceLimits
    }
    public func read(_ source: any ByteSource) throws -> ImportedExchangeModel {
        let result = try STEPExchange(tolerance: tolerance, resourceLimits: resourceLimits).import(source)
        guard result.document?.assembly != nil else { throw AssemblyError.invalidSource("STEP input has no assembly structure.") }
        return result
    }
    func read(entities: [Int: String], budget: ExchangeProcessingBudget) throws -> ImportedExchangeModel? {
        var materialIdentities: [Int: PhysicalMaterialID] = [:]
        return try read(entities: entities, budget: budget, materialIdentities: &materialIdentities)
    }
    func read(entities: [Int: String], budget: ExchangeProcessingBudget,
              materialIdentities: inout [Int: PhysicalMaterialID]) throws -> ImportedExchangeModel? {
        var documentCarrier: STEPDocumentCarrierReadReceipt?
        return try read(entities: entities, budget: budget, materialIdentities: &materialIdentities, documentCarrier: &documentCarrier)
    }
    func read(entities: [Int: String], budget: ExchangeProcessingBudget,
        materialIdentities: inout [Int: PhysicalMaterialID], documentCarrier: inout STEPDocumentCarrierReadReceipt?,
        sourceAdmission: IndependentShapeExchangeOwner? = nil) throws -> ImportedExchangeModel? {
        let owner = try sourceAdmission ?? IndependentShapeExchangeOwner(limits: resourceLimits,
            format: .step, processing: budget, consumedEntities: entities.count,
            consumedWork: 0, consumedBytes: 0)
        var execution = try owner.execution()
        return try read(entities: entities, budget: budget, materialIdentities: &materialIdentities,
            documentCarrier: &documentCarrier, sourceAdmission: owner, using: &execution)
    }

    func read(entities: [Int: String], budget: ExchangeProcessingBudget,
        materialIdentities: inout [Int: PhysicalMaterialID], documentCarrier: inout STEPDocumentCarrierReadReceipt?,
        sourceAdmission: IndependentShapeExchangeOwner,
        using execution: inout OriginalQueryExecution) throws -> ImportedExchangeModel? {
        var builder = Builder(syntax: STEPAssemblySyntax(entities: entities), budget: budget,
            tolerance: tolerance, limits: resourceLimits, owner: sourceAdmission, execution: consume execution)
        let result: ImportedExchangeModel?
        do {
            result = try builder.read(materialIdentities: &materialIdentities, documentCarrier: &documentCarrier)
        } catch {
            execution = consume builder.execution
            throw error
        }
        execution = consume builder.execution
        return result
    }
}

private extension STEPAssemblyReader {
    struct Builder: ~Copyable {
        let syntax: STEPAssemblySyntax
        let budget: ExchangeProcessingBudget
        let tolerance: ModelingTolerance
        let limits: ExchangeResourceLimits
        let owner: IndependentShapeExchangeOwner
        var execution: OriginalQueryExecution
        var work: Int { owner.consumedWork }
        var stringBytes: Int { owner.consumedBytes }
        mutating func string(_ value: String) throws -> String {
            try budget.check(format: .step)
            let decoded = try syntax.decodedString(value, limits: STEPStringLimits(
                maximumInputBytes: limits.maximumBytes,
                maximumOutputBytes: limits.maximumBytes - stringBytes,
                maximumWork: limits.maximumIterations - work))
            try check(decoded.consumedWork)
            try execution.retainSourceStorage(bytes: decoded.outputBytes)
            return decoded.value
        }
        mutating func check(_ count: Int = 1) throws {
            try budget.check(format: .step)
            guard count >= 0, count <= limits.maximumIterations - work else {
                throw AssemblyError.resourceLimitExceeded("STEP assembly work")
            }
            try execution.consumeWork(count)
        }
        func args(_ id: Int, count: Int, component: String? = nil) throws -> [String] {
            let a = try syntax.arguments(id, component: component)
            guard a.count == count else { throw ImportError.invalidData("STEP assembly #\(id) has invalid argument count.") }
            return a
        }
        func unit(_ context: Int) throws -> LengthUnit {
            let a = try syntax.arguments(context, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
            guard a.count == 1 else { throw ImportError.invalidData("Malformed STEP unit context.") }
            var units: [LengthUnit] = []
            for id in try syntax.list(a[0]) {
                if let unit = try stepLengthUnit(from: syntax.entity(id), entities: syntax.entities) { units.append(unit) }
            }
            guard units.count == 1, let unit = units.first else {
                throw ImportError.invalidData("Each STEP representation context requires exactly one length unit.")
            }
            return unit
        }
        mutating func placementItem(_ id: Int, unit: LengthUnit, contextEntityID: Int) throws -> AssemblyPlacement {
            let family = try syntax.name(id)
            guard family == "AXIS2_PLACEMENT_3D" || family == "CARTESIAN_TRANSFORMATION_OPERATOR_3D" else {
                throw AssemblyError.invalidSource("Unsupported STEP transformation item.")
            }
            let original = try ExactSTEPReader.originalMappingSource(entityID: id, entities: syntax.entities,
                units: UnitSystem(length: unit, angle: .radian), contextEntityID: contextEntityID, processingBudget: budget,
                tolerance: tolerance, usage: owner, using: &execution)
            return .step(original)
        }
        func originalPlacement(target: AssemblyPlacement, origin: AssemblyPlacement) throws -> AssemblyPlacement {
            .word(try AssemblyPlacementWord(factors: [.forward(target), .inverse(origin)]))
        }
        mutating func sameOriginalPlacement(_ first: AssemblyPlacement, _ second: AssemblyPlacement) throws -> Bool {
            try check()
            let firstWord: AssemblyPlacementWord
            let secondWord: AssemblyPlacementWord
            if case .word(let word) = first { firstWord = word }
            else { firstWord = try .init(factors: [.forward(first)]) }
            if case .word(let word) = second { secondWord = word }
            else { secondWord = try .init(factors: [.forward(second)]) }
            let lhs = try firstWord.originalOperationWord(tolerance: tolerance, maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumNesting, using: &execution)
            let rhs = try secondWord.originalOperationWord(tolerance: tolerance, maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumNesting, using: &execution)
            let equal = try lhs.isEquivalent(to: rhs, tolerance: tolerance, maximumDepth: limits.maximumAlgebraicDepth, usage: &execution)
            return equal
        }
        mutating func read(materialIdentities: inout [Int: PhysicalMaterialID], documentCarrier: inout STEPDocumentCarrierReadReceipt?) throws -> ImportedExchangeModel? {
            documentCarrier = nil
            var names: [Int: String] = [:]
            for id in syntax.entities.keys.sorted() { try check(); names[id] = try syntax.name(id) }
            let usages = names.filter { $0.value == "NEXT_ASSEMBLY_USAGE_OCCURRENCE" }.keys.sorted()
            let allMapped = names.filter { $0.value == "MAPPED_ITEM" }.keys.sorted()
            let identityReader: any STEPSourceIdentityReading = STEPSourceIdentityReader()
            let identities = try identityReader.read(fields: syntax, names: names, processingBudget: budget, limits: limits,
                remainingWork: limits.maximumIterations - work, remainingTextBytes: limits.maximumBytes - stringBytes)
            try check(identities.consumedWork); try execution.retainSourceStorage(bytes: identities.textBytes)
            materialIdentities.removeAll(keepingCapacity: true)
            for (entity, identity) in identities.values where names[entity] == "MATERIAL_DESIGNATION" {
                materialIdentities[entity] = PhysicalMaterialID(identity)
            }
            guard names.values.contains("PRODUCT_DEFINITION") else {
                guard identities.values.isEmpty, identities.documentCarriers.isEmpty else { throw AssemblyError.invalidSource("Native identity assignments require represented product definitions.") }
                return nil
            }
            var ownershipRecords: Int { owner.consumedEntities - syntax.entities.count }
            try check(names.count)
            let ownershipRoots = names.keys.filter { ["REPRESENTATION", "SHAPE_REPRESENTATION",
                "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION",
                "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", "MAPPED_ITEM"].contains(names[$0] ?? "") }
            let originalFields = syntax
            let ownership = try STEPRepresentationGeometryOwnership.classify(fields: originalFields,
                entityIDs: ownershipRoots, maximumDepth: limits.maximumNesting) { records, units in
                    try check(units)
                    guard records >= 0, records <= limits.maximumEntities - syntax.entities.count - ownershipRecords else {
                        throw AssemblyError.resourceLimitExceeded("Original representation classification records.")
                    }
                    try execution.consumeRecords(records)
                }
            if !identities.documentCarriers.isEmpty {
                guard identities.documentCarriers.count == 1, let carrier = identities.documentCarriers.first,
                      usages.isEmpty, names.values.filter({ $0 == "PRODUCT_DEFINITION" }).count == 1,
                      names.values.filter({ $0 == "PRODUCT" }).count == 1,
                      names.values.filter({ $0 == "PRODUCT_DEFINITION_FORMATION" }).count == 1,
                      !names.values.contains("PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE"),
                      identities.values.keys.allSatisfy({ names[$0] == "MATERIAL_DESIGNATION" }),
                      !allMapped.contains(where: { ownership[$0]?.contains(.body) == true }) else {
                    throw AssemblyError.invalidSource("Document framing carrier conflicts with real product structure or Body mappings.")
                }
                let pd = try args(carrier.key, count: 4), formationID = try syntax.reference(pd[2])
                let formation = try args(formationID, count: 3), productID = try syntax.reference(formation[2])
                let product = try args(productID, count: 4)
                guard names[formationID] == "PRODUCT_DEFINITION_FORMATION", names[productID] == "PRODUCT",
                      try string(product[0]) == "SWIFTCAD", try string(product[2]).isEmpty,
                      try string(formation[0]).isEmpty, try string(formation[1]).isEmpty,
                      try string(pd[0]) == "design", try string(pd[1]).isEmpty else {
                    throw AssemblyError.invalidSource("Document framing carrier has nonneutral authored product descriptors.")
                }
                var shapes: [Int] = []
                for id in names.keys where names[id] == "PRODUCT_DEFINITION_SHAPE" {
                    let shape = try args(id, count: 3)
                    if try syntax.reference(shape[2]) == carrier.key { try check(); shapes.append(id) }
                }
                guard shapes.count == 1, let shapeID = shapes.first else { throw AssemblyError.invalidSource("Document framing requires its sole actual shape definition.") }
                var selected: [Int] = []
                for id in names.keys where names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                    let association = try args(id, count: 2)
                    if try syntax.reference(association[0]) == shapeID { try check(); selected.append(try syntax.reference(association[1])) }
                }
                guard selected.count == 1, let representation = selected.first,
                      ["SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(names[representation] ?? ""),
                      ownership[representation]?.contains(.body) == true,
                      ownership[representation]?.contains(.independent) != true else {
                    throw AssemblyError.invalidSource("Document framing requires its sole actual Body representation.")
                }
                let documentName = try string(product[1])
                documentCarrier = .init(documentID: DocumentID(carrier.value), documentName: documentName,
                    consumedEntities: syntax.entities.count + ownershipRecords,
                    consumedWork: work, consumedTextBytes: stringBytes)
                return nil
            }
            // Every actual product PD owns product source unless the explicit framing role was admitted above.
            var carriers = Set<Int>()
            var transfer = STEPAttributeReadTransfer()
            transfer.materialIdentities = materialIdentities
            var definitionShapes: [Int: Int] = [:]
            for id in names.keys.sorted() where names[id] == "PRODUCT_DEFINITION_SHAPE" {
                let a = try args(id, count: 3); definitionShapes[id] = try syntax.reference(a[2])
            }
            var representations: [Int: Int] = [:]
            var associatedRepresentations = Set<Int>()
            for id in names.keys.sorted() where names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                let a = try args(id, count: 2)
                let shape = try syntax.reference(a[0]), representation = try syntax.reference(a[1])
                guard let definition = definitionShapes[shape], names[definition] == "PRODUCT_DEFINITION",
                      names[representation] != nil else {
                    throw AssemblyError.invalidSource("STEP product has missing shape association.")
                }
                try check(); associatedRepresentations.insert(representation)
                if let previous = representations[definition] {
                    let previousName = names[previous] ?? "", nextName = names[representation] ?? ""
                    let bodyFamilies = ["ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"]
                    if bodyFamilies.contains(nextName) {
                        guard !bodyFamilies.contains(previousName) else { throw AssemblyError.invalidSource("Product has competing Body representations.") }
                        representations[definition] = representation
                    }
                } else { representations[definition] = representation }
            }
            let productIDs = names.filter { $0.value == "PRODUCT_DEFINITION" }.keys.sorted()
            guard representations.count == productIDs.count else {
                throw AssemblyError.invalidSource("STEP assembly has an external or unrepresented product definition.")
            }
            var definitionIDs: [Int: AssemblyDefinitionID] = [:]
            var ownerEntities: [Int: (product: Int, formation: Int)] = [:]
            var products: [Int: AssemblyProduct] = [:]
            var formations: [Int: AssemblyProductFormation] = [:]
            var definitions: [Int: AssemblyDefinition] = [:]
            var repItems: [Int: [Int]] = [:], repUnits: [Int: LengthUnit] = [:], repContexts: [Int: Int] = [:]
            var features: [FeatureID: FeatureNode] = [:], order: [FeatureID] = []
            var geometryOwners: [Int: (unit: LengthUnit, feature: FeatureID)] = [:]
            var ownedFaces = Set<FaceID>(), ownedEdges = Set<EdgeID>(), ownedVertices = Set<VertexID>()
            var ownedLoops = Set<LoopID>(), ownedShells = Set<ShellID>()
            var accountedGeometry = Set<Int>()
            for productID in productIDs {
                try check()
                let pd = try args(productID, count: 4)
                let formation = try syntax.reference(pd[2])
                let formationName = try syntax.name(formation)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP product import admits only base and specified-source formations.
                // Other formation subtypes require a persistent semantic owner and matching standard writer before admission.
                guard ["PRODUCT_DEFINITION_FORMATION", "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE"].contains(formationName) else {
                    throw AssemblyError.invalidSource("Unsupported STEP product formation subtype.")
                }
                let fa = try args(formation, count: formationName == "PRODUCT_DEFINITION_FORMATION" ? 3 : 4)
                let product = try syntax.reference(fa[2]), pa = try args(product, count: 4)
                guard names[product] == "PRODUCT" else { throw ImportError.invalidData("Missing STEP product.") }
                if products[product] == nil {
                    products[product] = AssemblyProduct(id: AssemblyProductID(identities.values[product]
                        ?? taggedUUID(namespace: 0x5354455050524F44, id: product)), identifier: try string(pa[0]),
                        name: try string(pa[1]), description: pa[2] == "$" ? nil : try string(pa[2]))
                }
                guard let retainedProduct = products[product] else { throw AssemblyError.invalidSource("Missing retained product.") }
                if formations[formation] == nil {
                    var specified: AssemblyProductSource?
                    if formationName == "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE" {
                        guard fa[3].hasPrefix("."), fa[3].hasSuffix("."),
                              let source = AssemblyProductSource(rawValue: String(fa[3].dropFirst().dropLast()).lowercased()) else {
                            throw ImportError.invalidData("Invalid STEP specified-source literal.")
                        }
                        specified = source
                    }
                    formations[formation] = AssemblyProductFormation(id: AssemblyProductFormationID(identities.values[formation]
                        ?? taggedUUID(namespace: 0x53544550464F524D, id: formation)), productID: retainedProduct.id,
                        versionIdentifier: try string(fa[0]), description: fa[1] == "$" ? nil : try string(fa[1]), specifiedSource: specified)
                }
                guard let retainedFormation = formations[formation] else { throw AssemblyError.invalidSource("Missing retained formation.") }
                let name = retainedProduct.name
                let identifier = try string(pd[0]), definitionDescription = pd[1] == "$" ? nil : try string(pd[1])
                ownerEntities[productID] = (product, formation)
                let definitionID = AssemblyDefinitionID(identities.values[productID] ?? taggedUUID(namespace: 0x5354455050444546, id: productID))
                guard !definitionIDs.values.contains(definitionID) else { throw AssemblyError.invalidSource("Duplicate definition identity.") }
                definitionIDs[productID] = definitionID
                transfer.definitions[productID] = definitionID
                guard let rep = representations[productID] else { throw AssemblyError.invalidSource("Missing product representation.") }
                let repName = try syntax.name(rep)
                guard ["SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"].contains(repName) else {
                    throw AssemblyError.invalidSource("Unsupported STEP product shape representation.")
                }
                try check()
                transfer.representations[rep, default: []].insert(definitionID)
                let ra = try args(rep, count: 3), context = try syntax.reference(ra[2])
                let lengthUnit = try unit(context)
                try check()
                transfer.representationUnits[rep] = lengthUnit
                let items = try syntax.list(ra[1]); repItems[rep] = items; repUnits[rep] = lengthUnit; repContexts[rep] = context
                // A representation relationship may associate a shape representation with its local exact geometry.
                var geometryItems = items
                for relationship in names.keys.sorted() where names[relationship] == "SHAPE_REPRESENTATION_RELATIONSHIP" {
                    try check()
                    let relation = try args(relationship, count: 4)
                    let r1 = try syntax.reference(relation[2]), r2 = try syntax.reference(relation[3])
                    if r1 == rep || r2 == rep {
                        let other = r1 == rep ? r2 : r1
                        let oa = try args(other, count: 3), otherContext = try syntax.reference(oa[2])
                        guard try unit(otherContext) == lengthUnit else {
                            throw AssemblyError.invalidSource("Untransformed geometry relationship has conflicting units.")
                        }
                        geometryItems += try syntax.list(oa[1])
                    }
                }
                for item in geometryItems where names[item] == "MAPPED_ITEM" {
                    let ma = try args(item, count: 3), mapID = try syntax.reference(ma[1])
                    guard names[mapID] == "REPRESENTATION_MAP" else { throw AssemblyError.invalidSource("Missing representation map.") }
                    let mapping = try args(mapID, count: 2), inner = try syntax.reference(mapping[1])
                    guard let sourceOwnership = ownership[inner] else { throw AssemblyError.invalidSource("Missing original map source membership.") }
                    if !sourceOwnership.contains(.body) { continue }
                    if !associatedRepresentations.contains(inner) {
                        // A structural whole-part carrier retains local geometry without creating an assembly usage.
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import cannot retain a shared whole-part carrier as a multi-definition attribute set.
                        // A standard set-scope source/egress contract must retain each style/layer predecessor before this shared carrier can be admitted.
                        guard transfer.partCarriers[item] == nil else {
                            throw ProductAttributeError.unsupportedSemantics("A whole-part carrier cannot select several definitions.")
                        }
                        guard carriers.insert(item).inserted,
                              geometryItems.filter({ names[$0] == "MAPPED_ITEM" }).count == 1,
                              geometryItems.allSatisfy({ $0 == item || names[$0] == "AXIS2_PLACEMENT_3D" }) else {
                            throw AssemblyError.invalidSource("Whole-part carrier has competing outer geometry.")
                        }
                        guard ["SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(names[inner] ?? "") else {
                            throw AssemblyError.invalidSource("Unsupported whole-part inner representation.")
                        }
                        if repName != "SHAPE_REPRESENTATION", names[inner] != repName {
                            throw AssemblyError.invalidSource("Whole-part carrier has conflicting representation family.")
                        }
                        let ia = try args(inner, count: 3), innerContext = try syntax.reference(ia[2])
                        let innerUnit = try unit(innerContext), innerItems = try syntax.list(ia[1]), origin = try syntax.reference(mapping[0])
                        guard innerUnit == lengthUnit, innerItems.contains(origin),
                              innerItems.allSatisfy({ ["AXIS2_PLACEMENT_3D", "MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(names[$0] ?? "") }),
                              innerItems.contains(where: { ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(names[$0] ?? "") }) else {
                            throw AssemblyError.invalidSource("Whole-part carrier requires unassociated exact local geometry and equal units.")
                        }
                        let target = try syntax.reference(ma[2])
                        guard names[target] == "CARTESIAN_TRANSFORMATION_OPERATOR_3D" else {
                            throw AssemblyError.invalidSource("Whole-part carrier requires a standard identity mapping operator.")
                        }
                        let targetFrame = try placementItem(target, unit: lengthUnit, contextEntityID: context)
                        let originFrame = try placementItem(origin, unit: innerUnit, contextEntityID: innerContext)
                        guard try sameOriginalPlacement(targetFrame, originFrame) else {
                            throw AssemblyError.invalidSource("Whole-part carrier transform is not identity.")
                        }
                        transfer.partCarriers[item] = definitionID
                        try check()
                        transfer.representations[inner, default: []].insert(definitionID)
                        transfer.representationUnits[inner] = innerUnit
                        geometryItems = innerItems
                    }
                }
                var geometry = Set<Int>()
                for item in geometryItems {
                    try check()
                    if ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(names[item] ?? "") { geometry.insert(item) }
                    else if !["AXIS2_PLACEMENT_3D", "MAPPED_ITEM", "CARTESIAN_TRANSFORMATION_OPERATOR_3D"].contains(names[item] ?? "") {
                        // Independent membership is consumed from this same original table below.
                        let originalKind = names[item] ?? ""
                        try check(syntax.entities[item]?.utf8.count ?? 0)
                        var spline = false
                        if originalKind.isEmpty { spline = try syntax.hasComponent(item, named: "B_SPLINE_CURVE") || syntax.hasComponent(item, named: "B_SPLINE_SURFACE") }
                        guard ["GEOMETRIC_SET", "GEOMETRIC_CURVE_SET", "TRIMMED_CURVE", "LINE", "CIRCLE", "ELLIPSE", "HYPERBOLA", "PARABOLA", "B_SPLINE_CURVE_WITH_KNOTS", "RATIONAL_B_SPLINE_CURVE", "PLANE", "CYLINDRICAL_SURFACE", "CONICAL_SURFACE", "SPHERICAL_SURFACE", "TOROIDAL_SURFACE", "OFFSET_SURFACE", "B_SPLINE_SURFACE_WITH_KNOTS", "RATIONAL_B_SPLINE_SURFACE"].contains(originalKind) || spline else {
                            throw AssemblyError.invalidSource("STEP product representation contains unretained semantics.")
                        }
                    }
                }
                try check(geometry.count)
                let solids = geometry.filter { names[$0] == "MANIFOLD_SOLID_BREP" || names[$0] == "BREP_WITH_VOIDS" }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP assembly import admits homogeneous exact item groups only.
                // A proved standard mixed-family association must retain local owners and attribute scope before mixed groups can succeed.
                guard solids.isEmpty || solids.count == geometry.count else {
                    throw ProductAttributeError.unsupportedSemantics("Mixed sheet and solid STEP geometry requires a proved representation family.")
                }
                if repName == "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", !solids.isEmpty {
                    throw AssemblyError.invalidSource("Sheet representation contains solid geometry.")
                }
                if repName == "ADVANCED_BREP_SHAPE_REPRESENTATION", !geometry.isEmpty, solids.isEmpty {
                    throw AssemblyError.invalidSource("Solid representation contains sheet geometry.")
                }
                try check(geometry.count)
                accountedGeometry.formUnion(geometry)
                var bodyFeatures: [FeatureID] = []
                for item in geometry.sorted() {
                    try check()
                    if let retained = geometryOwners[item] {
                        guard retained.unit == lengthUnit else {
                            throw AssemblyError.invalidSource("Shared geometry has conflicting owned units.")
                        }
                        bodyFeatures.append(retained.feature)
                        continue
                    }
                    // Bound the exact reader's source domain before recursive extraction.
                    try check(syntax.entities.count)
                    let exactTransfer = try ExactSTEPReader(entities: syntax.entities, lengthUnit: lengthUnit,
                        processingBudget: budget, tolerance: tolerance, representationItems: [item]).readWithTransfer()
                    let local = exactTransfer.model
                    guard local.bodies.count == 1, let bodyID = exactTransfer.bodies[item], let body = local.bodies[bodyID] else {
                        throw AssemblyError.invalidSource("An exact STEP body item requires one local body owner.")
                    }
                    let counts = [local.faces.count, local.edges.count, local.vertices.count, local.loops.count, local.shells.count]
                    for count in counts { try check(count) }
                    guard !local.faces.keys.contains(where: { ownedFaces.contains($0) }),
                          !local.edges.keys.contains(where: { ownedEdges.contains($0) }),
                          !local.vertices.keys.contains(where: { ownedVertices.contains($0) }),
                          !local.loops.keys.contains(where: { ownedLoops.contains($0) }),
                          !local.shells.keys.contains(where: { ownedShells.contains($0) }) else {
                        throw AssemblyError.invalidSource("Distinct exact items have competing topology ownership.")
                    }
                    for count in counts { try check(count) }
                    ownedFaces.formUnion(local.faces.keys); ownedEdges.formUnion(local.edges.keys)
                    ownedVertices.formUnion(local.vertices.keys); ownedLoops.formUnion(local.loops.keys); ownedShells.formUnion(local.shells.keys)
                    try check(2)
                    let id = FeatureID()
                    features[id] = FeatureNode(id: id, name: name, operation: .importedBRep(
                        ImportedBRepFeature(model: local, sourceUnits: UnitSystem(length: lengthUnit, angle: .radian))),
                        outputs: [FeatureOutput(role: body.kind == .solid ? .body : .sheet)])
                    order.append(id); bodyFeatures.append(id)
                    for (entity, sourceBody) in exactTransfer.bodies where sourceBody == bodyID {
                        try check()
                        transfer.geometry[entity] = SubshapeID(featureID: id, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
                        transfer.geometryUnits[entity] = lengthUnit
                    }
                    for (ordinal, sourceFace) in local.faces.keys.sorted().enumerated() {
                        for (entity, mappedFace) in exactTransfer.faces where mappedFace == sourceFace {
                            try check()
                            transfer.geometry[entity] = SubshapeID(featureID: id, role: GeneratedSubshapeRole.face.rawValue, ordinal: ordinal)
                            transfer.geometryUnits[entity] = lengthUnit
                        }
                    }
                    try check()
                    geometryOwners[item] = (lengthUnit, id)
                }
                definitions[productID] = AssemblyDefinition(id: definitionID, formationID: retainedFormation.id, identifier: identifier,
                    definitionDescription: definitionDescription, features: bodyFeatures)
            }
            for id in names.keys where names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                try check(2)
                let a = try args(id, count: 2), shape = try syntax.reference(a[0]), rep = try syntax.reference(a[1])
                guard let owner = definitionShapes[shape], let definition = definitionIDs[owner] else { continue }
                try check(); transfer.representations[rep, default: []].insert(definition)
                let repArgs = try args(rep, count: 3)
                transfer.representationUnits[rep] = try unit(syntax.reference(repArgs[2]))
            }
            let allGeometry = Set(names.filter { ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains($0.value) }.keys)
            guard accountedGeometry == allGeometry else { throw AssemblyError.invalidSource("Unassociated STEP geometry would be discarded.") }
            try check(allMapped.count)
            let mapped = allMapped.filter { !carriers.contains($0) && ownership[$0]?.contains(.body) == true }
            var childProducts = Set<Int>()
            if !usages.isEmpty {
                var placementRelations: [Int: Int] = [:]
                var placementContexts: [Int: Int] = [:]
                for id in names.keys.sorted() where names[id] == "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION" {
                    try check(2)
                    let a = try args(id, count: 2), shape = try syntax.reference(a[1])
                    guard let usage = definitionShapes[shape], names[usage] == "NEXT_ASSEMBLY_USAGE_OCCURRENCE",
                          placementRelations.updateValue(try syntax.reference(a[0]), forKey: usage) == nil else {
                        throw AssemblyError.invalidSource("STEP occurrence has missing or multiple placement associations.")
                    }
                    placementContexts[usage] = id
                }
                guard placementRelations.count == usages.count else { throw AssemblyError.invalidSource("Missing STEP occurrence placement.") }
                for usage in usages {
                    try check()
                    let a = try args(usage, count: 6), parent = try syntax.reference(a[3]), child = try syntax.reference(a[4])
                    guard let parentRep = representations[parent], let childRep = representations[child],
                          let childID = definitionIDs[child], let relation = placementRelations[usage],
                          let context = placementContexts[usage] else {
                        throw AssemblyError.invalidSource("STEP usage references a missing product.")
                    }
                    let rr = try args(relation, count: 4, component: "REPRESENTATION_RELATIONSHIP")
                    let r1 = try syntax.reference(rr[2]), r2 = try syntax.reference(rr[3])
                    guard (r1 == childRep && r2 == parentRep) || (r1 == parentRep && r2 == childRep),
                          let context1 = repContexts[r1], let context2 = repContexts[r2], context1 != context2, let u1 = repUnits[r1], let u2 = repUnits[r2] else {
                        throw AssemblyError.invalidSource("STEP representation relationship does not match its product usage.")
                    }
                    let tr = try args(relation, count: 1, component: "REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION")
                    let operatorID = try syntax.reference(tr[0])
                    let sourcePlacement: AssemblyPlacement
                    if names[operatorID] == "ITEM_DEFINED_TRANSFORMATION" {
                        let ta = try args(operatorID, count: 4), i1 = try syntax.reference(ta[2]), i2 = try syntax.reference(ta[3])
                        guard repItems[r1]?.contains(i1) == true, repItems[r2]?.contains(i2) == true else {
                            throw AssemblyError.invalidSource("STEP transformation axes do not belong to their representations.")
                        }
                        let first = try placementItem(i1, unit: u1, contextEntityID: context1)
                        let second = try placementItem(i2, unit: u2, contextEntityID: context2)
                        sourcePlacement = r1 == childRep
                            ? try originalPlacement(target: second, origin: first)
                            : try originalPlacement(target: first, origin: second)
                    } else {
                        guard u1 == u2, repItems[r2]?.contains(operatorID) == true else {
                            throw AssemblyError.invalidSource("Cartesian occurrence transform has inconsistent units or ownership.")
                        }
                        let original = try placementItem(operatorID, unit: u2, contextEntityID: context2)
                        sourcePlacement = r1 == childRep ? original
                            : .word(try AssemblyPlacementWord(factors: [.inverse(original)]))
                    }
                    let identifier = try string(a[0])
                    let occurrenceIdentity: PortableIdentity128
                    do {
                        occurrenceIdentity = try PortableIdentity128(canonicalString: identifier)
                    } catch {
                        occurrenceIdentity = taggedUUID(namespace: 0x535445504F434355, id: usage)
                    }
                    let occurrence = AssemblyOccurrence(id: AssemblyOccurrenceID(occurrenceIdentity), name: try string(a[1]),
                        definitionID: childID, sourcePlacement: sourcePlacement)
                    guard var parentDefinition = definitions[parent] else { throw AssemblyError.invalidSource("Missing parent definition.") }
                    parentDefinition.children.append(occurrence); definitions[parent] = parentDefinition
                    transfer.usages[usage] = occurrence.id; transfer.relationships[relation] = occurrence.id
                    try check(); transfer.usageContexts[context] = occurrence.id
                    childProducts.insert(child)
                }
                var matched = Set<AssemblyOccurrenceID>()
                for item in mapped {
                    try check()
                    guard ownership[item]?.contains(.independent) == true else {
                        throw AssemblyError.invalidSource("STEP has an unretained competing Body map and usage placement.")
                    }
                    var parents = Set<AssemblyDefinitionID>()
                    var originalParentUnits = Set<LengthUnit>()
                    var originalParentContexts = Set<Int>()
                    for (rep, owners) in transfer.representations {
                        let ra = try args(rep, count: 3), items = try syntax.list(ra[1]); try check(items.count + owners.count)
                        if items.contains(item) { parents.formUnion(owners); originalParentUnits.insert(try unit(syntax.reference(ra[2]))); originalParentContexts.insert(try syntax.reference(ra[2])) }
                    }
                    let ma = try args(item, count: 3), mapID = try syntax.reference(ma[1]), target = try syntax.reference(ma[2])
                    let map = try args(mapID, count: 2), origin = try syntax.reference(map[0]), inner = try syntax.reference(map[1])
                    guard names[mapID] == "REPRESENTATION_MAP", parents.count == 1, let parentID = parents.first,
                          let parentPD = definitionIDs.first(where: { $0.value == parentID })?.key,
                          let parent = definitions[parentPD], let childOwners = transfer.representations[inner],
                          childOwners.count == 1, let childID = childOwners.first,
                          definitionIDs.values.contains(childID) else {
                        throw AssemblyError.invalidSource("Mixed map has missing or competing original product associations.")
                    }
                    let originalFields = syntax
                    let bodyMembers = try STEPRepresentationBodyMembership.collect(inner, fields: originalFields,
                        maximumDepth: limits.maximumNesting) { records, units in
                            try check(units)
                            guard records <= limits.maximumEntities - syntax.entities.count - ownershipRecords else {
                                throw AssemblyError.resourceLimitExceeded("Mapped Body correspondence records.")
                            }
                            try execution.consumeRecords(records)
                        }
                    var selectedFeatures = Set<FeatureID>()
                    for member in bodyMembers {
                        try check()
                        guard let selector = transfer.geometry[member], selector.role == GeneratedSubshapeRole.body.rawValue else {
                            throw AssemblyError.invalidSource("Mapped source Body lacks its actual imported feature correspondence.")
                        }
                        selectedFeatures.insert(selector.featureID)
                    }
                    guard definitions.count <= limits.maximumEntities - syntax.entities.count - ownershipRecords else {
                        throw AssemblyError.resourceLimitExceeded("Mapped child definition source records.")
                    }
                    try execution.consumeRecords(definitions.count)
                    let actualChildFeatures = try STEPRepresentationBodyMembership.features(in: childID,
                        definitions: Array(definitions.values), maximumDepth: limits.maximumNesting) { records, units in
                            try check(units)
                            guard records <= limits.maximumEntities - syntax.entities.count - ownershipRecords else {
                                throw AssemblyError.resourceLimitExceeded("Mapped child feature correspondence records.")
                            }
                            try execution.consumeRecords(records)
                        }
                    guard !selectedFeatures.isEmpty, selectedFeatures == actualChildFeatures else {
                        throw AssemblyError.invalidSource("Mixed map Body membership differs from the actual child product geometry.")
                    }
                    let innerArgs = try args(inner, count: 3), innerItems = try syntax.list(innerArgs[1])
                    guard innerItems.contains(origin), originalParentUnits.count == 1, let parentUnit = originalParentUnits.first,
                        let parentContext = originalParentContexts.min() else {
                        throw AssemblyError.invalidSource("Mixed map origin or parent context is absent.")
                    }
                    let innerContext = try syntax.reference(innerArgs[2])
                    let innerUnit = try unit(innerContext)
                    try check(originalParentContexts.count)
                    let targetFrame = try placementItem(target, unit: parentUnit, contextEntityID: parentContext)
                    for originalContext in originalParentContexts where originalContext != parentContext {
                        let alternate = try placementItem(target, unit: parentUnit, contextEntityID: originalContext)
                        guard try sameOriginalPlacement(targetFrame, alternate) else {
                            throw AssemblyError.invalidSource("Mapped target has competing original context coordinate laws.")
                        }
                    }
                    let originFrame = try placementItem(origin, unit: innerUnit, contextEntityID: innerContext)
                    let frame = try originalPlacement(target: targetFrame, origin: originFrame)
                    try check(parent.children.count)
                    var selectedOccurrence: AssemblyOccurrence?
                    for candidate in parent.children where candidate.definitionID == childID && !matched.contains(candidate.id) {
                        guard try sameOriginalPlacement(candidate.placement, frame) else { continue }
                        if let previous = selectedOccurrence {
                            if candidate.id < previous.id { selectedOccurrence = candidate }
                        } else { selectedOccurrence = candidate }
                    }
                    guard let occurrence = selectedOccurrence else {
                        throw AssemblyError.invalidSource("Mixed map has no matching original child usage placement.")
                    }
                    try check(); matched.insert(occurrence.id)
                }
            } else {
                let repProducts = Dictionary(grouping: productIDs, by: { representations[$0] ?? -1 })
                for parent in productIDs {
                    guard let parentRep = representations[parent], let parentUnit = repUnits[parentRep], let parentContext = repContexts[parentRep] else { throw AssemblyError.invalidSource("Missing mapped parent.") }
                    for item in repItems[parentRep] ?? [] where names[item] == "MAPPED_ITEM" && !carriers.contains(item) && ownership[item]?.contains(.body) == true {
                        try check()
                        let ma = try args(item, count: 3), mapID = try syntax.reference(ma[1]), target = try syntax.reference(ma[2])
                        guard names[mapID] == "REPRESENTATION_MAP" else { throw AssemblyError.invalidSource("Missing STEP representation map.") }
                        let map = try args(mapID, count: 2), origin = try syntax.reference(map[0]), childRep = try syntax.reference(map[1])
                        guard let children = repProducts[childRep], children.count == 1, let child = children.first,
                              let childID = definitionIDs[child], let childUnit = repUnits[childRep], let childContext = repContexts[childRep], repItems[childRep]?.contains(origin) == true else {
                            throw AssemblyError.invalidSource("STEP mapped item has an ambiguous or missing product definition.")
                        }
                        let targetFrame = try placementItem(target, unit: parentUnit, contextEntityID: parentContext)
                        let originFrame = try placementItem(origin, unit: childUnit, contextEntityID: childContext)
                        let frame = try originalPlacement(target: targetFrame, origin: originFrame)
                        guard var parentDefinition = definitions[parent] else {
                            throw AssemblyError.invalidSource("Mapped STEP assembly has a missing parent definition.")
                        }
                        parentDefinition.children.append(AssemblyOccurrence(id: AssemblyOccurrenceID(taggedUUID(namespace: 0x535445504D415050, id: item)),
                            definitionID: childID, sourcePlacement: frame)); definitions[parent] = parentDefinition; childProducts.insert(child)
                    }
                }
                let retainedMappings = definitions.values.reduce(0) { $0 + $1.children.count }
                guard retainedMappings == mapped.count else { throw AssemblyError.invalidSource("Unassociated mapped occurrences.") }
            }
            guard products.count == names.values.filter({ $0 == "PRODUCT" }).count,
                  formations.count == names.values.filter({ $0 == "PRODUCT_DEFINITION_FORMATION" || $0 == "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE" }).count else {
                throw AssemblyError.invalidSource("Unreferenced STEP product or formation would be discarded.")
            }
            var roots: [AssemblyOccurrence] = []
            for id in productIDs where !childProducts.contains(id) {
                try check()
                guard let definition = definitions[id], let owners = ownerEntities[id],
                      let formation = formations[owners.formation], let product = products[owners.product] else {
                    throw AssemblyError.invalidSource("Missing STEP root metadata owners.")
                }
                if product.identifier == "swiftcad.assembly.roots", product.name == "swiftcad.assembly.roots",
                   product.description == "", formation.versionIdentifier == "", formation.description == "",
                   formation.specifiedSource == nil, definition.identifier == "design", definition.definitionDescription == "",
                   identities.values[id] == nil, identities.values[owners.formation] == nil, identities.values[owners.product] == nil,
                   definition.features.isEmpty {
                    roots += definition.children; definitions.removeValue(forKey: id)
                } else {
                    roots.append(AssemblyOccurrence(id: AssemblyOccurrenceID(taggedUUID(namespace: 0x53544550524F4F54, id: id)), definitionID: definition.id))
                }
            }
            guard let firstRoot = roots.first,
                  let productID = definitionIDs.first(where: { $0.value == firstRoot.definitionID })?.key,
                  let representation = representations[productID], let lengthUnit = repUnits[representation] else {
                throw AssemblyError.invalidSource("STEP assembly has no acyclic represented root.")
            }
            // Prune only the transport envelope's now-unreferenced metadata owners.
            let usedFormations = Set(definitions.values.map(\.formationID))
            formations = formations.filter { usedFormations.contains($0.value.id) }
            let usedProducts = Set(formations.values.map(\.productID))
            products = products.filter { usedProducts.contains($0.value.id) }
            let assembly = DocumentAssembly(products: Array(products.values).sorted { $0.id < $1.id },
                formations: Array(formations.values).sorted { $0.id < $1.id }, definitions: Array(definitions.values).sorted { $0.id < $1.id }, roots: roots)
            var document = CADDocument(units: UnitSystem(length: lengthUnit, angle: .radian),
                designGraph: DesignGraph(nodes: features, order: order), assembly: assembly)
            let independentOwner = owner
            let independentItems = try independentSTEPItemRoots(entities: syntax.entities, names: names, budget: budget) { records, units in
                try independentOwner.charge(entities: records, work: units, using: &execution)
            }
            if let original = try ExactSTEPReader.readIndependent(entities: syntax.entities, processingBudget: budget,
                tolerance: tolerance, standaloneItems: independentItems, productDefinitions: definitionIDs, bodySources: transfer.geometry.filter { $0.value.role == GeneratedSubshapeRole.body.rawValue },
                bodySourceGraph: document.designGraph, usage: independentOwner, using: &execution) {
                document.independentShapes = original.source
            }
            try independentOwner.validateDocument(document, tolerance: tolerance, using: &execution)
            let assemblyLimits = AssemblyResourceLimits(maximumRecords: limits.maximumEntities,
                maximumOccurrences: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                maximumTopologyEntities: limits.maximumEntities, maximumWork: limits.maximumIterations, maximumTextBytes: limits.maximumBytes,
                maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
            _ = try DocumentAssemblyValidator().expandedOccurrences(of: assembly, in: document.designGraph,
                tolerance: tolerance, limits: assemblyLimits)
            try document.validate(tolerance: tolerance)
            let evaluator = DocumentEvaluator(tolerance: tolerance, assemblyResourceLimits: assemblyLimits)
            let base = try evaluator.evaluateExact(document)
            document.productAttributes = try STEPAttributesReader().read(entities: syntax.entities,
                transfer: transfer, evaluated: base, limits: limits)
            try document.validate(tolerance: tolerance)
            let evaluated = document.productAttributes.isEmpty ? base : try evaluator.evaluateExact(document)
            if !document.productAttributes.isEmpty {
                _ = try ProductAttributeResolver().resolve(evaluated, limits: ProductAttributeLimits(maximumRecords: limits.maximumEntities,
                    maximumTargets: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                    maximumTextBytes: limits.maximumBytes, maximumWork: limits.maximumIterations))
            }
            try check()
            return ImportedExchangeModel(format: .step, document: document, brep: evaluated.brep, units: document.units)
        }
        func taggedUUID(namespace: UInt64, id: Int) -> PortableIdentity128 {
            let identity = AssemblyDefinitionID(highBits: namespace, lowBits: UInt64(id))
            return identity.rawValue
        }
    }
}
