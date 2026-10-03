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
        var builder = Builder(syntax: STEPAssemblySyntax(entities: entities), budget: budget,
            tolerance: tolerance, limits: resourceLimits)
        return try builder.read()
    }
}

private extension STEPAssemblyReader {
    struct Builder {
        let syntax: STEPAssemblySyntax
        let budget: ExchangeProcessingBudget
        let tolerance: ModelingTolerance
        let limits: ExchangeResourceLimits
        var work = 0
        var stringBytes = 0
        mutating func string(_ value: String) throws -> String {
            try budget.check(format: .step)
            let decoded = try syntax.decodedString(value, limits: STEPStringLimits(
                maximumInputBytes: limits.maximumBytes,
                maximumOutputBytes: limits.maximumBytes - stringBytes,
                maximumWork: limits.maximumIterations - work))
            try check(decoded.consumedWork)
            stringBytes += decoded.outputBytes
            return decoded.value
        }
        mutating func check(_ count: Int = 1) throws {
            try budget.check(format: .step)
            guard count >= 0, count <= limits.maximumIterations - work else {
                throw AssemblyError.resourceLimitExceeded("STEP assembly work")
            }
            work += count
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
        func vector(_ id: Int) throws -> Vector3D {
            let a = try args(id, count: 2)
            guard try syntax.name(id) == "DIRECTION" else { throw ImportError.invalidData("Expected STEP direction.") }
            let v = try syntax.numbers(a[1])
            guard v.count == 3 else { throw ImportError.invalidData("Expected 3D direction.") }
            return try Vector3D(x: v[0], y: v[1], z: v[2]).normalized(tolerance: tolerance.distance)
        }
        func point(_ id: Int, unit: LengthUnit) throws -> Vector3D {
            let a = try args(id, count: 2)
            guard try syntax.name(id) == "CARTESIAN_POINT" else { throw ImportError.invalidData("Expected STEP point.") }
            let v = try syntax.numbers(a[1])
            guard v.count == 3 else { throw ImportError.invalidData("Expected 3D point.") }
            return Vector3D(x: unit.toInternal(v[0]), y: unit.toInternal(v[1]), z: unit.toInternal(v[2]))
        }
        func axis(_ id: Int, unit: LengthUnit) throws -> RigidTransform3D {
            guard try syntax.name(id) == "AXIS2_PLACEMENT_3D" else {
                throw ImportError.invalidData("STEP assembly requires a 3D placement frame.")
            }
            let a = try args(id, count: 4)
            let z = a[2] == "$" ? Vector3D.unitZ : try vector(syntax.reference(a[2]))
            let proposedX = a[3] == "$" ? (abs(z.x) < 0.9 ? Vector3D.unitX : .unitY) : try vector(syntax.reference(a[3]))
            let x = try (proposedX - z * proposedX.dot(z)).normalized(tolerance: tolerance.distance)
            return try RigidTransform3D(basisX: x, basisY: z.cross(x), basisZ: z,
                translation: point(syntax.reference(a[1]), unit: unit), tolerance: tolerance)
        }
        func cartesian(_ id: Int, unit: LengthUnit) throws -> RigidTransform3D {
            guard try syntax.name(id) == "CARTESIAN_TRANSFORMATION_OPERATOR_3D" else {
                throw AssemblyError.invalidSource("Unsupported STEP transformation operator.")
            }
            let a = try args(id, count: 8)
            guard a[6] == "$" || Double(a[6]) == 1 else { throw AssemblyError.invalidPlacement }
            let x = a[3] == "$" ? Vector3D.unitX : try vector(syntax.reference(a[3]))
            let y = a[4] == "$" ? Vector3D.unitY : try vector(syntax.reference(a[4]))
            let z = a[7] == "$" ? x.cross(y) : try vector(syntax.reference(a[7]))
            let frame = try RigidTransform3D(basisX: x, basisY: y, basisZ: z,
                translation: point(syntax.reference(a[5]), unit: unit), tolerance: tolerance)
            guard !frame.reversesOrientation else { throw AssemblyError.invalidPlacement }
            return frame
        }
        func compose(_ outer: RigidTransform3D, _ inner: RigidTransform3D) throws -> RigidTransform3D {
            try RigidTransform3D(basisX: outer.applying(to: inner.basisX), basisY: outer.applying(to: inner.basisY),
                basisZ: outer.applying(to: inner.basisZ), translation: outer.applying(to: inner.translation) + outer.translation,
                tolerance: tolerance)
        }
        mutating func read() throws -> ImportedExchangeModel? {
            var names: [Int: String] = [:]
            for id in syntax.entities.keys.sorted() { try check(); names[id] = try syntax.name(id) }
            let usages = names.filter { $0.value == "NEXT_ASSEMBLY_USAGE_OCCURRENCE" }.keys.sorted()
            let allMapped = names.filter { $0.value == "MAPPED_ITEM" }.keys.sorted()
            guard names.values.contains("PRODUCT_DEFINITION") else { return nil }
            var retainsProductSource = !usages.isEmpty || !allMapped.isEmpty
            if !retainsProductSource {
                for id in names.keys.sorted() where names[id] == "PRODUCT_DEFINITION" {
                    try check()
                    let pd = try args(id, count: 4), formation = try syntax.reference(pd[2])
                    let fa = try syntax.arguments(formation)
                    guard fa.count >= 3 else { throw ImportError.invalidData("Malformed STEP product formation.") }
                    let pa = try args(syntax.reference(fa[2]), count: 4)
                    let name = try string(pa[1])
                    let description = pa[2] == "$" ? nil : try string(pa[2])
                    let definitionDescription = pd[1] == "$" ? nil : try string(pd[1])
                    if !name.isEmpty || !(description ?? "").isEmpty || !(definitionDescription ?? "").isEmpty { retainsProductSource = true }
                }
                // Physical properties consume real product/shape-aspect association maps even
                // when their actual persistent target is a body or face inside that product.
                if names.values.contains("PROPERTY_DEFINITION") { retainsProductSource = true }
            }
            guard retainsProductSource else { return nil }
            var carriers = Set<Int>()
            var transfer = STEPAttributeReadTransfer()
            var definitionShapes: [Int: Int] = [:]
            for id in names.keys.sorted() where names[id] == "PRODUCT_DEFINITION_SHAPE" {
                let a = try args(id, count: 3); definitionShapes[id] = try syntax.reference(a[2])
            }
            var representations: [Int: Int] = [:]
            for id in names.keys.sorted() where names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                let a = try args(id, count: 2)
                let shape = try syntax.reference(a[0]), representation = try syntax.reference(a[1])
                guard let definition = definitionShapes[shape], names[definition] == "PRODUCT_DEFINITION",
                      representations.updateValue(representation, forKey: definition) == nil else {
                    throw AssemblyError.invalidSource("STEP product has missing or multiple shape associations.")
                }
            }
            let productIDs = names.filter { $0.value == "PRODUCT_DEFINITION" }.keys.sorted()
            guard representations.count == productIDs.count else {
                throw AssemblyError.invalidSource("STEP assembly has an external or unrepresented product definition.")
            }
            var definitionIDs: [Int: AssemblyDefinitionID] = [:]
            var productIdentifiers: [Int: String] = [:]
            var retainedProducts = Set<Int>()
            var definitions: [Int: AssemblyDefinition] = [:]
            var repItems: [Int: [Int]] = [:], repUnits: [Int: LengthUnit] = [:], repContexts: [Int: Int] = [:]
            var features: [FeatureID: FeatureNode] = [:], order: [FeatureID] = []
            var accountedGeometry = Set<Int>()
            for productID in productIDs {
                try check()
                let pd = try args(productID, count: 4)
                let formation = try syntax.reference(pd[2])
                let fa = try syntax.arguments(formation)
                guard fa.count >= 3 else { throw ImportError.invalidData("Malformed STEP product formation.") }
                let product = try syntax.reference(fa[2]), pa = try args(product, count: 4)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public STEP import cannot retain several PRODUCT_DEFINITION views sharing one PRODUCT owner.
                // Completion requires an explicit persistent product/view source model before shared product metadata can be admitted without duplicated authority.
                guard retainedProducts.insert(product).inserted else {
                    throw ProductAttributeError.unsupportedSemantics("Several definitions share one product description owner.")
                }
                let identifier = try string(pa[0]), name = try string(pa[1])
                let productDescription = pa[2] == "$" ? nil : try string(pa[2])
                let definitionDescription = pd[1] == "$" ? nil : try string(pd[1])
                productIdentifiers[productID] = identifier
                let definitionID = AssemblyDefinitionID(UUID(uuidString: identifier) ?? taggedUUID(namespace: 0x5354455050444546, id: productID))
                guard !definitionIDs.values.contains(definitionID) else { throw AssemblyError.invalidSource("Duplicate product identity.") }
                definitionIDs[productID] = definitionID
                transfer.definitions[productID] = definitionID
                guard let rep = representations[productID] else { throw AssemblyError.invalidSource("Missing product representation.") }
                let repName = try syntax.name(rep)
                guard ["SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(repName) else {
                    throw AssemblyError.invalidSource("Unsupported STEP product shape representation.")
                }
                transfer.representations[rep] = definitionID
                let ra = try args(rep, count: 3), context = try syntax.reference(ra[2])
                let lengthUnit = try unit(context)
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
                    if !representations.values.contains(inner) {
                        // A structural whole-part carrier retains local geometry without creating an assembly usage.
                        guard carriers.insert(item).inserted,
                              geometryItems.filter({ names[$0] == "MAPPED_ITEM" }).count == 1,
                              geometryItems.allSatisfy({ $0 == item || names[$0] == "AXIS2_PLACEMENT_3D" }) else {
                            throw AssemblyError.invalidSource("Whole-part carrier has competing outer geometry.")
                        }
                        guard ["SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(names[inner] ?? "") else {
                            throw AssemblyError.invalidSource("Unsupported whole-part inner representation.")
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
                        let frame = try compose(cartesian(target, unit: lengthUnit), axis(origin, unit: innerUnit).inverted())
                        guard frame == RigidTransform3D.translated(by: .zero) else {
                            throw AssemblyError.invalidSource("Whole-part carrier transform is not identity.")
                        }
                        guard transfer.representations[inner] == nil else {
                            throw AssemblyError.invalidSource("Whole-part inner geometry has competing product associations.")
                        }
                        transfer.partCarriers[item] = definitionID
                        transfer.representations[inner] = definitionID
                        geometryItems = innerItems
                    }
                }
                var geometry = Set<Int>()
                for item in geometryItems {
                    if ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(names[item] ?? "") { geometry.insert(item) }
                    else if !["AXIS2_PLACEMENT_3D", "MAPPED_ITEM", "CARTESIAN_TRANSFORMATION_OPERATOR_3D"].contains(names[item] ?? "") {
                        throw AssemblyError.invalidSource("STEP product representation contains unretained semantics.")
                    }
                }
                accountedGeometry.formUnion(geometry)
                var bodyFeatures: [FeatureID] = []
                if !geometry.isEmpty {
                    let exactTransfer = try ExactSTEPReader(entities: syntax.entities, lengthUnit: lengthUnit,
                        processingBudget: budget, tolerance: tolerance, representationItems: geometry).readWithTransfer()
                    let model = exactTransfer.model
                    for bodyID in model.bodies.keys.sorted() {
                        let local = try BRepBodySubmodelExtractor().extract(bodyIDs: [bodyID], from: model)
                        guard let body = local.bodies[bodyID] else { throw AssemblyError.invalidSource("Missing local STEP body.") }
                        let id = FeatureID()
                        features[id] = FeatureNode(id: id, name: name, operation: .importedBRep(
                            ImportedBRepFeature(model: local, sourceUnits: UnitSystem(length: lengthUnit, angle: .radian))),
                            outputs: [FeatureOutput(role: body.kind == .solid ? .body : .sheet)])
                        order.append(id); bodyFeatures.append(id)
                        for (entity, sourceBody) in exactTransfer.bodies where sourceBody == bodyID {
                            transfer.geometry[entity] = SubshapeID(featureID: id, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
                        }
                        for (ordinal, sourceFace) in local.faces.keys.sorted().enumerated() {
                            for (entity, mappedFace) in exactTransfer.faces where mappedFace == sourceFace {
                                transfer.geometry[entity] = SubshapeID(featureID: id, role: GeneratedSubshapeRole.face.rawValue, ordinal: ordinal)
                            }
                        }
                    }
                }
                definitions[productID] = AssemblyDefinition(id: definitionID, name: name, productDescription: productDescription,
                    definitionDescription: definitionDescription, features: bodyFeatures)
            }
            let allGeometry = Set(names.filter { ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains($0.value) }.keys)
            guard accountedGeometry == allGeometry else { throw AssemblyError.invalidSource("Unassociated STEP geometry would be discarded.") }
            let mapped = allMapped.filter { !carriers.contains($0) }
            guard usages.isEmpty || mapped.isEmpty else {
                throw AssemblyError.invalidSource("STEP combines competing usage and mapped-item assembly representations.")
            }
            var childProducts = Set<Int>()
            if !usages.isEmpty {
                var placementRelations: [Int: Int] = [:]
                for id in names.keys.sorted() where names[id] == "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION" {
                    let a = try args(id, count: 2), shape = try syntax.reference(a[1])
                    guard let usage = definitionShapes[shape], names[usage] == "NEXT_ASSEMBLY_USAGE_OCCURRENCE",
                          placementRelations.updateValue(try syntax.reference(a[0]), forKey: usage) == nil else {
                        throw AssemblyError.invalidSource("STEP occurrence has missing or multiple placement associations.")
                    }
                }
                guard placementRelations.count == usages.count else { throw AssemblyError.invalidSource("Missing STEP occurrence placement.") }
                for usage in usages {
                    try check()
                    let a = try args(usage, count: 6), parent = try syntax.reference(a[3]), child = try syntax.reference(a[4])
                    guard let parentRep = representations[parent], let childRep = representations[child],
                          let childID = definitionIDs[child], let relation = placementRelations[usage] else {
                        throw AssemblyError.invalidSource("STEP usage references a missing product.")
                    }
                    let rr = try args(relation, count: 4, component: "REPRESENTATION_RELATIONSHIP")
                    let r1 = try syntax.reference(rr[2]), r2 = try syntax.reference(rr[3])
                    guard (r1 == childRep && r2 == parentRep) || (r1 == parentRep && r2 == childRep),
                          repContexts[r1] != repContexts[r2], let u1 = repUnits[r1], let u2 = repUnits[r2] else {
                        throw AssemblyError.invalidSource("STEP representation relationship does not match its product usage.")
                    }
                    let tr = try args(relation, count: 1, component: "REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION")
                    let operatorID = try syntax.reference(tr[0])
                    let frame: RigidTransform3D
                    if names[operatorID] == "ITEM_DEFINED_TRANSFORMATION" {
                        let ta = try args(operatorID, count: 4), i1 = try syntax.reference(ta[2]), i2 = try syntax.reference(ta[3])
                        guard repItems[r1]?.contains(i1) == true, repItems[r2]?.contains(i2) == true else {
                            throw AssemblyError.invalidSource("STEP transformation axes do not belong to their representations.")
                        }
                        frame = try compose(axis(i2, unit: u2), axis(i1, unit: u1).inverted())
                    } else {
                        guard u1 == u2, repItems[r2]?.contains(operatorID) == true else {
                            throw AssemblyError.invalidSource("Cartesian occurrence transform has inconsistent units or ownership.")
                        }
                        frame = try cartesian(operatorID, unit: u2)
                    }
                    let identifier = try string(a[0])
                    let occurrence = AssemblyOccurrence(id: AssemblyOccurrenceID(UUID(uuidString: identifier)
                        ?? taggedUUID(namespace: 0x535445504F434355, id: usage)), name: try string(a[1]),
                        definitionID: childID, placement: r1 == childRep ? frame : frame.inverted())
                    guard var parentDefinition = definitions[parent] else { throw AssemblyError.invalidSource("Missing parent definition.") }
                    guard parentDefinition.features.isEmpty else { throw AssemblyError.invalidSource("STEP assembly geometry is an ambiguous alternative to its children.") }
                    parentDefinition.children.append(occurrence); definitions[parent] = parentDefinition
                    transfer.usages[usage] = occurrence.id; transfer.relationships[relation] = occurrence.id
                    childProducts.insert(child)
                }
            } else {
                let repProducts = Dictionary(grouping: productIDs, by: { representations[$0] ?? -1 })
                for parent in productIDs {
                    guard let parentRep = representations[parent], let parentUnit = repUnits[parentRep] else { throw AssemblyError.invalidSource("Missing mapped parent.") }
                    for item in repItems[parentRep] ?? [] where names[item] == "MAPPED_ITEM" && !carriers.contains(item) {
                        try check()
                        let ma = try args(item, count: 3), mapID = try syntax.reference(ma[1]), target = try syntax.reference(ma[2])
                        guard names[mapID] == "REPRESENTATION_MAP" else { throw AssemblyError.invalidSource("Missing STEP representation map.") }
                        let map = try args(mapID, count: 2), origin = try syntax.reference(map[0]), childRep = try syntax.reference(map[1])
                        guard let children = repProducts[childRep], children.count == 1, let child = children.first,
                              let childID = definitionIDs[child], let childUnit = repUnits[childRep], repItems[childRep]?.contains(origin) == true else {
                            throw AssemblyError.invalidSource("STEP mapped item has an ambiguous or missing product definition.")
                        }
                        let targetFrame: RigidTransform3D
                        if names[target] == "AXIS2_PLACEMENT_3D" { targetFrame = try axis(target, unit: parentUnit) }
                        else { targetFrame = try cartesian(target, unit: parentUnit) }
                        let frame = try compose(targetFrame, axis(origin, unit: childUnit).inverted())
                        guard var parentDefinition = definitions[parent], parentDefinition.features.isEmpty else {
                            throw AssemblyError.invalidSource("Mapped STEP assembly has competing geometry.")
                        }
                        parentDefinition.children.append(AssemblyOccurrence(id: AssemblyOccurrenceID(taggedUUID(namespace: 0x535445504D415050, id: item)),
                            definitionID: childID, placement: frame)); definitions[parent] = parentDefinition; childProducts.insert(child)
                    }
                }
                let retainedMappings = definitions.values.reduce(0) { $0 + $1.children.count }
                guard retainedMappings == mapped.count else { throw AssemblyError.invalidSource("Unassociated mapped occurrences.") }
            }
            var roots: [AssemblyOccurrence] = []
            for id in productIDs where !childProducts.contains(id) {
                guard let definition = definitions[id] else { throw AssemblyError.invalidSource("Missing STEP root.") }
                if productIdentifiers[id] == "swiftcad.assembly.roots", definition.name == "swiftcad.assembly.roots", definition.features.isEmpty {
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
            let assembly = DocumentAssembly(definitions: Array(definitions.values).sorted { $0.id < $1.id }, roots: roots)
            var document = CADDocument(units: UnitSystem(length: lengthUnit, angle: .radian),
                designGraph: DesignGraph(nodes: features, order: order), assembly: assembly)
            let assemblyLimits = AssemblyResourceLimits(maximumRecords: limits.maximumEntities,
                maximumOccurrences: limits.maximumEntities, maximumDepth: limits.maximumNesting,
                maximumTopologyEntities: limits.maximumEntities, maximumWork: limits.maximumIterations)
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
        func taggedUUID(namespace: UInt64, id: Int) -> UUID {
            AssemblyDefinitionID(highBits: namespace, lowBits: UInt64(id)).rawValue
        }
    }
}
