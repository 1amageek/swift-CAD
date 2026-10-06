import CADCore
import CADIR

extension STEPAttributesWriter.Builder {
    mutating func physicalDensitySourceItem(_ density: PhysicalDensity) throws -> Int {
        try density.validate()
        let mass = try add("(MASS_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.GRAM.))")
        let length = try add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
        let m = try add("DERIVED_UNIT_ELEMENT(#\(mass),1.)"), l = try add("DERIVED_UNIT_ELEMENT(#\(length),-3.)")
        let unit = try add("DERIVED_UNIT((#\(m),#\(l)))")
        return try add("(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(\(density.kilogramsPerCubicMeter)),#\(unit)) REPRESENTATION_ITEM('density'))")
    }

    mutating func physicalSourceRepresentation(property: Int, item: Int) throws {
        guard let context = transfer.products.values.first?.context else { throw ProductAttributeError.missingTarget("Physical source representation context.") }
        let representation = try add("REPRESENTATION('',(#\(item)),#\(context))")
        _ = try add("PROPERTY_DEFINITION_REPRESENTATION(#\(property),#\(representation))")
    }

    mutating func writePhysicalSourceDescriptors() throws {
        for descriptor in evaluated.document.productAttributes.materials {
            try check()
            let object = try add("CHARACTERIZED_OBJECT(\(try string(descriptor.name)),\(try string(descriptor.description)))")
            let designation = try add("MATERIAL_DESIGNATION(\(try string(descriptor.name)),(#\(object)))")
            try metadataIdentity(designation,ProductMetadataID(descriptor.id.rawValue),role:"materialDescriptor")
            let source = try add("EXTERNAL_SOURCE(IDENTIFIER(\(try string(STEPSourceIdentityRole.namespace))))")
            let role = try add("IDENTIFICATION_ROLE('material',$)")
            _ = try add("APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT(\(try string(descriptor.id.description)),#\(role),#\(source),(#\(designation)))")
            let material = try add("PROPERTY_DEFINITION('material descriptor','material name',#\(object))")
            try metadataIdentity(material,ProductMetadataID(),role:"materialDescriptorProperty")
            let description = try add("DESCRIPTIVE_REPRESENTATION_ITEM(\(try string(descriptor.name)),\(try string(descriptor.description)))")
            try physicalSourceRepresentation(property:material,item:description)
            let density: Int?
            if let value = descriptor.density {
                let property = try add("PROPERTY_DEFINITION('material descriptor','density',#\(object))")
                try metadataIdentity(property,ProductMetadataID(),role:"materialDescriptorProperty")
                let item = try physicalDensitySourceItem(value)
                try physicalSourceRepresentation(property:property,item:item)
                density = property
            } else { density = nil }
            try budget.charge(targets:2)
            materialDesignationEntities[descriptor.id] = designation
            physicalDescriptorProperties[descriptor.id] = (material,density)
        }
    }

    mutating func writePhysicalSourceAssignment(_ assignment: ProductAttributeAssignment, depth: Int) throws -> Int {
        try check()
        guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Physical source override depth.") }
        if let existing = physicalAssignmentProperties[assignment.id] { return existing }
        guard activePhysicalAssignments.insert(assignment.id).inserted else { throw ProductAttributeError.invalidSource("Physical source override cycle.") }
        defer { activePhysicalAssignments.remove(assignment.id) }
        let target = try metadataTarget(assignment.target)
        let item: Int, descriptorProperty: Int?, kind: String
        switch assignment.value {
        case .material(let id):
            guard let descriptor = evaluated.document.productAttributes.materials.first(where:{$0.id == id}),
                let properties = physicalDescriptorProperties[id] else { throw ProductAttributeError.missingTarget("Original material descriptor.") }
            try check(evaluated.document.productAttributes.materials.count)
            item = try add("DESCRIPTIVE_REPRESENTATION_ITEM(\(try string(descriptor.name)),\(try string(descriptor.description)))")
            descriptorProperty = properties.material; kind = "material"
        case .density(let density):
            item = try physicalDensitySourceItem(density); descriptorProperty = nil; kind = "density"
        case .descriptorDensity(let id):
            guard let descriptor = evaluated.document.productAttributes.materials.first(where:{$0.id == id}),
                let value = descriptor.density, let property = physicalDescriptorProperties[id]?.density else {
                throw ProductAttributeError.missingTarget("Original descriptor-owned density.")
            }
            try check(evaluated.document.productAttributes.materials.count)
            item = try physicalDensitySourceItem(value); descriptorProperty = property; kind = "descriptorDensity"
        default: throw ProductAttributeError.invalidSource("Not a physical source property.")
        }
        let property = try add("PROPERTY_DEFINITION('physical source property',\(try string(kind)),#\(target))")
        try metadataIdentity(property,ProductMetadataID(assignment.id.rawValue),role:"physicalAssignment")
        try physicalSourceRepresentation(property:property,item:item)
        if let descriptorProperty {
            _ = try add("PROPERTY_DEFINITION_RELATIONSHIP('descriptor source','',#\(descriptorProperty),#\(property))")
        }
        if let id = assignment.overrides {
            try check(evaluated.document.productAttributes.assignments.count)
            guard let previous = evaluated.document.productAttributes.assignments.first(where:{$0.id == id}),
                previous.value.property == assignment.value.property else { throw ProductAttributeError.invalidSource("Physical predecessor property mismatch.") }
            let predecessor = try writePhysicalSourceAssignment(previous,depth:depth+1)
            _ = try add("PROPERTY_DEFINITION_RELATIONSHIP('overrides','',#\(predecessor),#\(property))")
        }
        try budget.charge(targets:1)
        physicalAssignmentProperties[assignment.id] = property
        return property
    }
}
