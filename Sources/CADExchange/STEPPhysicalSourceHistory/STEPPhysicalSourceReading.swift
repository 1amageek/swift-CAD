import CADCore
import CADIR

extension STEPAttributesReader.Builder {
    mutating func physicalSourceItem(_ property: Int) throws -> Int {
        var representation: Int?
        for association in entities.keys.sorted() where names[association] == "PROPERTY_DEFINITION_REPRESENTATION" {
            try check()
            let a = try args(association,2)
            if try syntax.reference(a[0]) == property {
                guard representation == nil else { throw ProductAttributeError.ambiguousProperty("Physical source representation.") }
                representation = try syntax.reference(a[1])
            }
        }
        guard let representation, names[representation] == "REPRESENTATION" else { throw ProductAttributeError.missingTarget("Physical source value representation.") }
        let values = try syntax.list(args(representation,3)[1])
        guard values.count == 1, let item = values.first else { throw ProductAttributeError.invalidSource("Physical source property requires one actual value.") }
        return item
    }

    mutating func readPhysicalSource() throws -> (materials: [PhysicalMaterialDescriptor], assignments: [ProductAttributeAssignment]) {
        var materials: [PhysicalMaterialID:PhysicalMaterialDescriptor] = [:]
        var descriptorIDs: [Int:PhysicalMaterialID] = [:]
        for designation in entities.keys.sorted() where metadataRoles[designation] == "materialDescriptor" {
            try check()
            let d = try args(designation,2), definitions = try syntax.list(d[1])
            guard definitions.count == 1, let object = definitions.first, names[object] == "CHARACTERIZED_OBJECT" else { throw ProductAttributeError.invalidSource("Original material descriptor needs one actual characterized object.") }
            let a = try args(object,2), id = PhysicalMaterialID(try metadataID(designation).rawValue)
            guard transfer.materialIdentities[designation] == id, try string(d[0]) == string(a[0]) else { throw ProductAttributeError.invalidSource("Material descriptor designation identity/value mismatch.") }
            let name = try string(a[0]), description = a[1] == "$" ? "" : try string(a[1])
            var materialProperty: Int?, density: PhysicalDensity?
            for property in entities.keys.sorted() where metadataRoles[property] == "materialDescriptorProperty" {
                try check()
                let p = try args(property,3)
                guard try syntax.reference(p[2]) == object else { continue }
                guard try string(p[0]) == "material descriptor" else { throw ProductAttributeError.invalidSource("Invalid descriptor property owner.") }
                let label = try string(p[1]), item = try physicalSourceItem(property)
                if label == "material name" {
                    guard materialProperty == nil, names[item] == "DESCRIPTIVE_REPRESENTATION_ITEM" else { throw ProductAttributeError.ambiguousProperty("Descriptor material value.") }
                    let value = try args(item,2)
                    guard try string(value[0]) == name, try string(value[1]) == description else { throw ProductAttributeError.invalidSource("Descriptor original material fields disagree.") }
                    materialProperty = property
                } else if label == "density" {
                    guard density == nil else { throw ProductAttributeError.ambiguousProperty("Descriptor density.") }
                    var reader = STEPPhysicalDensityReader(syntax:syntax)
                    density = try reader.read(item,budget:&budget)
                } else { throw ProductAttributeError.unsupportedSemantics("Unknown descriptor property semantics.") }
                try budget.charge(targets:1); descriptorIDs[property] = id
            }
            guard materialProperty != nil else { throw ProductAttributeError.missingTarget("Descriptor material representation.") }
            guard materials.updateValue(.init(id:id,name:name,description:description,density:density),forKey:id) == nil else { throw ProductAttributeError.invalidSource("Duplicate descriptor identity.") }
            try budget.charge(targets:1)
        }
        var assignments: [ProductAttributeAssignment] = []
        for property in entities.keys.sorted() where metadataRoles[property] == "physicalAssignment" {
            try check()
            let p = try args(property,3), label = try string(p[1]), item = try physicalSourceItem(property)
            guard try string(p[0]) == "physical source property" else { throw ProductAttributeError.invalidSource("Invalid physical assignment carrier.") }
            let target = try metadataTarget(syntax.reference(p[2]))
            var descriptor: Int?, predecessor: ProductAttributeID?
            for relation in entities.keys.sorted() where names[relation] == "PROPERTY_DEFINITION_RELATIONSHIP" {
                try check()
                let r = try args(relation,4)
                guard try syntax.reference(r[3]) == property else { continue }
                let role = try string(r[0]), source = try syntax.reference(r[2])
                guard try string(r[1]).isEmpty else { throw ProductAttributeError.unsupportedSemantics("Physical source relationship has unsupported extra semantics.") }
                if role == "descriptor source" {
                    guard descriptor == nil, descriptorIDs[source] != nil else { throw ProductAttributeError.invalidSource("Missing or competing physical descriptor source.") }
                    descriptor = source
                } else if role == "overrides" {
                    guard predecessor == nil, metadataRoles[source] == "physicalAssignment" else { throw ProductAttributeError.invalidSource("Missing or competing physical predecessor.") }
                    predecessor = ProductAttributeID(try metadataID(source).rawValue)
                } else { throw ProductAttributeError.unsupportedSemantics("Unknown physical source relationship.") }
                try check()
            }
            let value: ProductAttributeValue
            if label == "material" {
                guard let descriptor, let id = descriptorIDs[descriptor], let source = materials[id],
                    names[item] == "DESCRIPTIVE_REPRESENTATION_ITEM" else { throw ProductAttributeError.missingTarget("Actual material assignment source.") }
                let original = try args(item,2)
                guard try string(original[0]) == source.name, try string(original[1]) == source.description,
                    try string(args(descriptor,3)[1]) == "material name" else { throw ProductAttributeError.invalidSource("Material assignment value differs from its original descriptor.") }
                value = .material(id)
            } else {
                var reader = STEPPhysicalDensityReader(syntax:syntax)
                let density = try reader.read(item,budget:&budget)
                if label == "density" {
                    guard descriptor == nil else { throw ProductAttributeError.invalidSource("Explicit density must not infer a descriptor dependency.") }
                    value = .density(density)
                } else if label == "descriptorDensity" {
                    guard let descriptor, let id = descriptorIDs[descriptor], materials[id]?.density == density,
                        try string(args(descriptor,3)[1]) == "density" else { throw ProductAttributeError.invalidSource("Assigned descriptor density differs from its original owner.") }
                    value = .descriptorDensity(id)
                } else { throw ProductAttributeError.unsupportedSemantics("Unknown physical assignment dimension.") }
            }
            assignments.append(.init(id:ProductAttributeID(try metadataID(property).rawValue),target:target,value:value,overrides:predecessor))
            try budget.charge(targets:1)
        }
        return (materials.values.sorted{$0.id < $1.id},assignments)
    }
}
