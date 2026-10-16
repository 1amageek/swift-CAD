import CADCore
import CADIR
import CADKernel

extension STEPAttributesWriter.Builder {
    mutating func metadataIdentity(_ entity: Int, _ identity: ProductMetadataID, role: String, description: String? = nil) throws {
        let source = try add("EXTERNAL_SOURCE(IDENTIFIER(\(try string(STEPMetadataNames.namespace))))")
        let definition = try add("IDENTIFICATION_ROLE(\(try string(role)),\(try description.map { try string($0) } ?? "$"))")
        _ = try add("APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT(\(try string(identity.description)),#\(definition),#\(source),(#\(entity)))")
    }
    mutating func metadataPoint(_ point: Point3D) throws -> Int {
        try add("CARTESIAN_POINT('',(\(stepNumber(point.x)),\(stepNumber(point.y)),\(stepNumber(point.z))))")
    }
    mutating func metadataDirection(_ direction: Vector3D) throws -> Int {
        try add("DIRECTION('',(\(stepNumber(direction.x)),\(stepNumber(direction.y)),\(stepNumber(direction.z))))")
    }
    mutating func metadataFrame(origin: Point3D, direction: Vector3D, up: Vector3D) throws -> Int {
        let p = try metadataPoint(origin), z = try metadataDirection(direction)
        let x = try metadataDirection(up.cross(direction))
        return try add("AXIS2_PLACEMENT_3D('',#\(p),#\(z),#\(x))")
    }
    mutating func metadataMeasure(_ value: Double, kind: String, unit: Int, name: String? = nil) throws -> Int {
        if let name {
            return try add("(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(\(kind)_MEASURE(\(stepNumber(value))),#\(unit)) REPRESENTATION_ITEM(\(try string(name))))")
        }
        return try add("\(kind)_MEASURE_WITH_UNIT(\(kind)_MEASURE(\(stepNumber(value))),#\(unit))")
    }
    mutating func metadataProducts(_ target: ProductAttributeTarget) throws -> [STEPAttributeProductRepresentation] {
        guard let usage = target.usageID else { return try products(target) }
        guard let source = evaluated.document.assembly else { throw ProductAttributeError.missingTarget("Metadata direct-usage source.") }
        var child: AssemblyDefinitionID?
        for occurrence in source.roots {
            try check()
            if occurrence.id == usage {
                guard child == nil else { throw ProductAttributeError.ambiguousProperty("Metadata direct-usage owner.") }
                child = occurrence.definitionID
            }
        }
        for definition in source.definitions {
            try check()
            for occurrence in definition.children {
                try check()
                if occurrence.id == usage {
                    guard child == nil else { throw ProductAttributeError.ambiguousProperty("Metadata direct-usage owner.") }
                    child = occurrence.definitionID
                }
            }
        }
        guard let child, let product = transfer.products[child], transfer.usages[usage] != nil else {
            throw ProductAttributeError.missingTarget("Metadata source usage product/NAUO correspondence.")
        }
        try budget.charge(targets:1)
        return [product]
    }

    mutating func metadataTarget(_ target: ProductAttributeTarget, subtype: String = "SHAPE_ASPECT", name: String = "", description: String = "") throws -> Int {
        try check(); try target.validate()
        let products = try metadataProducts(target)
        guard let product = products.first else { throw ProductAttributeError.missingTarget("PMI target product.") }
        let shape: Int
        if let usage = target.usageID ?? target.path?.components.last {
            guard let entity = transfer.usages[usage] else { throw ProductAttributeError.missingTarget("PMI target occurrence.") }
            shape = try add("PRODUCT_DEFINITION_SHAPE('','',#\(entity))")
        } else { shape = product.definitionShape }
        let aspect = try add("\(subtype)(\(try string(name)),\(try string(description)),#\(shape),.T.)")
        // Whole source selectors are owned by their PDS/NAUO, independently of presentation carriers.
        let items = target.geometry == nil ? [] : try styleItems(target)
        for item in items {
            let view = try add("SHAPE_REPRESENTATION('',(#\(item)),#\(product.context))")
            _ = try add("GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#\(aspect),#\(view),#\(item))")
        }
        let scope = target.geometry == nil ? target.kind.rawValue : (target.path == nil ? (target.definitionID == nil ? "global" : "qualified") : "contextual")
        var pathDescription: String?
        if let path = target.path {
            // Written relationship IDs represent the full occurrence chain, not a leaf UUID.
            var chain: [String] = []
            for usage in path.components {
                guard let relationship = transfer.relationships[usage] else { throw ProductAttributeError.missingTarget("PMI path relationship.") }
                chain.append(String(relationship))
            }
            pathDescription = chain.joined(separator: ",")
        }
        try metadataIdentity(aspect, ProductMetadataID(), role: "target:" + scope, description: pathDescription)
        return aspect
    }
    mutating func metadataClipPlane(_ plane: ProductClippingPlane) throws -> Int {
        let normal = plane.keepPositive ? plane.normal : plane.normal * -1
        let candidate = abs(normal.dot(.unitX)) < 0.9 ? Vector3D.unitX : .unitY
        let up = try (candidate - normal * candidate.dot(normal)).normalized(tolerance: Double.leastNonzeroMagnitude)
        let position = try metadataFrame(origin: plane.origin, direction: normal, up: up)
        let entity = try add("PLANE('',#\(position))")
        try metadataIdentity(entity, ProductMetadataID(), role: plane.keepPositive ? "clip:positive" : "clip:negative")
        return entity
    }
    mutating func metadataClipExpression(_ expression: ProductClippingExpression, depth: Int = 0) throws -> (entity: Int, cameraOperands: [Int], physicalOperands: [Int]) {
        guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Clipping expression egress depth.") }
        try check()
        switch expression {
        case .plane(let plane): let id = try metadataClipPlane(plane); return (id, [id], [id])
        case .union(let children), .intersection(let children):
            let isUnion: Bool
            if case .union = expression { isUnion = true } else { isUnion = false }
            var ids: [Int] = [], sourceChildren: [Int] = []
            for child in children {
                let encoded = try metadataClipExpression(child, depth: depth + 1)
                try budget.charge(targets: encoded.physicalOperands.count + 1)
                sourceChildren.append(encoded.entity)
                let sameOperation: Bool
                switch child {
                case .union: sameOperation = isUnion
                case .intersection: sameOperation = !isUnion
                case .plane: sameOperation = false
                }
                if sameOperation { ids.append(contentsOf: encoded.physicalOperands) }
                else { ids.append(encoded.entity) }
            }
            let name = isUnion ? "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION" : "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION"
            let id = try add("\(name)('',(\(ids.map { "#\($0)" }.joined(separator: ","))))")
            try metadataIdentity(id, ProductMetadataID(), role: isUnion ? "clip:union" : "clip:intersection",
                description: sourceChildren.map(String.init).joined(separator: ","))
            return (id, isUnion ? [id] : ids, ids)
        }
    }
    mutating func writeMetadata() throws {
        let source = evaluated.document.productAttributes
        guard !source.manufacturingInformation.isEmpty || !source.viewMetadata.isEmpty else { return }
        let meter = try add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))")
        let radian = try add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
        let steradian = try add("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())")
        let context = try add("(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(meter),#\(radian),#\(steradian))) REPRESENTATION_CONTEXT('',''))")
        var semantic: [ProductMetadataID: Int] = [:], datumEntities: [ProductMetadataID: Int] = [:]
        for datum in source.manufacturingInformation.datums {
            let feature = try metadataTarget(datum.target, subtype: "DATUM_FEATURE", name: datum.name, description: datum.description)
            let featureText = records[feature - startingAt]
            let syntax = STEPAssemblySyntax(entities: [feature: featureText])
            let shape = try syntax.reference(syntax.arguments(feature)[2])
            let entity = try add("DATUM('',\(try string(datum.description)),#\(shape),.F.,\(try string(datum.identification)))")
            _ = try add("SHAPE_ASPECT_RELATIONSHIP('','',#\(feature),#\(entity))")
            try metadataIdentity(entity, datum.id, role: "datum")
            datumEntities[datum.id] = entity; semantic[datum.id] = entity
        }
        for dimension in source.manufacturingInformation.dimensions {
            let target = try metadataTarget(dimension.target)
            let entity: Int
            if let reference = dimension.referenceTarget {
                let second = try metadataTarget(reference)
                if dimension.kind == .angle {
                    entity = try add("ANGULAR_LOCATION(\(try string(dimension.name)),\(try string(dimension.description)),#\(target),#\(second),.EQUAL.)")
                } else {
                    entity = try add("DIMENSIONAL_LOCATION(\(try string(dimension.name)),\(try string(dimension.description)),#\(target),#\(second))")
                }
            } else if dimension.kind == .angle {
                entity = try add("ANGULAR_SIZE(#\(target),\(try string(dimension.name)),.EQUAL.)")
            } else { entity = try add("DIMENSIONAL_SIZE(#\(target),\(try string(dimension.name)))") }
            let kind = dimension.kind == .angle ? "PLANE_ANGLE" : "LENGTH", unit = dimension.kind == .angle ? radian : meter
            let nominal = try metadataMeasure(dimension.nominal, kind: kind, unit: unit, name: dimension.kind.rawValue)
            let description = try add("DESCRIPTIVE_REPRESENTATION_ITEM('description',\(try string(dimension.description)))")
            let rep = try add("SHAPE_DIMENSION_REPRESENTATION('',(#\(nominal),#\(description)),#\(context))")
            _ = try add("DIMENSIONAL_CHARACTERISTIC_REPRESENTATION(#\(entity),#\(rep))")
            if let lower = dimension.lowerDeviation, let upper = dimension.upperDeviation {
                let lo = try metadataMeasure(lower, kind: kind, unit: unit), hi = try metadataMeasure(upper, kind: kind, unit: unit)
                let range = try add("TOLERANCE_VALUE(#\(lo),#\(hi))")
                _ = try add("PLUS_MINUS_TOLERANCE(#\(range),#\(entity))")
            }
            try metadataIdentity(entity, dimension.id, role: "dimension"); semantic[dimension.id] = entity
        }
        for tolerance in source.manufacturingInformation.tolerances {
            let target = try metadataTarget(tolerance.target), magnitude = try metadataMeasure(tolerance.magnitude, kind: "LENGTH", unit: meter)
            guard let kind = STEPMetadataNames.tolerances[tolerance.kind] else { throw ProductAttributeError.invalidSource("Unknown geometric tolerance kind.") }
            var components = ["\(kind)()", "GEOMETRIC_TOLERANCE(\(try string(tolerance.name)),\(try string(tolerance.description)),#\(magnitude),#\(target))"]
            if !tolerance.datumIDs.isEmpty {
                var references: [Int] = []
                for (index, id) in tolerance.datumIDs.enumerated() {
                    guard let datum = datumEntities[id] else { throw ProductAttributeError.missingTarget("Written tolerance datum.") }
                    references.append(try add("DATUM_REFERENCE(\(index + 1),#\(datum))"))
                }
                components.append("GEOMETRIC_TOLERANCE_WITH_DATUM_REFERENCE((\(references.map { "#\($0)" }.joined(separator: ","))))")
            }
            var modifiers: [String] = []
            for modifier in tolerance.modifiers {
                if let token = STEPMetadataNames.modifiers[modifier] { modifiers.append(".\(token).") }
            }
            if !modifiers.isEmpty { components.append("GEOMETRIC_TOLERANCE_WITH_MODIFIERS((\(modifiers.joined(separator: ","))))") }
            let entity = try add("(\(components.sorted().joined(separator: " ")))")
            try metadataIdentity(entity, tolerance.id, role: "tolerance")
            semantic[tolerance.id] = entity
            // Modifiers with explicit default/zone meaning remain independently authored properties.
            for modifier in tolerance.modifiers where STEPMetadataNames.modifiers[modifier] == nil {
                let property = try add("PROPERTY_DEFINITION('geometric tolerance modifier',\(try string(modifier.rawValue)),#\(entity))")
                let descriptor = try add("DESCRIPTIVE_REPRESENTATION_ITEM('modifier',\(try string(modifier.rawValue)))")
                let rep = try add("REPRESENTATION('',(#\(descriptor)),#\(context))")
                _ = try add("PROPERTY_DEFINITION_REPRESENTATION(#\(property),#\(rep))")
            }
        }
        let nullStyle = try add("PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)))")
        var annotationEntities: [ProductMetadataID: Int] = [:]
        for annotation in source.manufacturingInformation.annotations {
            var parts: [Int] = []
            for literal in annotation.textLiterals {
                let frame: Int
                if literal.placement == .twoDimensional {
                    let point = try add("CARTESIAN_POINT('',(\(stepNumber(literal.origin.x)),\(stepNumber(literal.origin.y))))")
                    let x = literal.up.cross(literal.direction)
                    let direction = try add("DIRECTION('',(\(stepNumber(x.x)),\(stepNumber(x.y))))")
                    frame = try add("AXIS2_PLACEMENT_2D('',#\(point),#\(direction))")
                } else { frame = try metadataFrame(origin:literal.origin,direction:literal.direction,up:literal.up) }
                let font = try add("DRAUGHTING_PRE_DEFINED_TEXT_FONT(\(try string(literal.fontName)))")
                let text = try add("TEXT_LITERAL(\(try string(literal.literalName)),\(try string(literal.text)),#\(frame),\(try string(literal.alignment)),.\(literal.path.rawValue.uppercased()).,#\(font))")
                let occurrence = try add("ANNOTATION_TEXT_OCCURRENCE(\(try string(literal.occurrenceName)),(#\(nullStyle)),#\(text))")
                try metadataIdentity(occurrence,literal.id,role:"annotationText")
                parts.append(occurrence)
            }
            for line in annotation.polylines {
                var points: [Int] = []
                for point in line { points.append(try metadataPoint(point)) }
                let polyline = try add("POLYLINE('',(\(points.map { "#\($0)" }.joined(separator: ","))))")
                parts.append(try add("ANNOTATION_CURVE_OCCURRENCE('',(#\(nullStyle)),#\(polyline))"))
            }
            let entity = try add("DRAUGHTING_CALLOUT(\(try string(annotation.name)),(\(parts.map { "#\($0)" }.joined(separator: ","))))")
            try metadataIdentity(entity, annotation.id, role: "annotation")
            let rep = try add("DRAUGHTING_MODEL('',(#\(entity)),#\(context))")
            if let id = annotation.semanticID {
                guard let owner = semantic[id] else { throw ProductAttributeError.missingTarget("Written annotation semantic owner.") }
                _ = try add("DRAUGHTING_MODEL_ITEM_ASSOCIATION(\(try string(annotation.meaning.rawValue)),'',#\(owner),#\(rep),#\(entity))")
            }
            for target in annotation.targets {
                let owner = try metadataTarget(target)
                _ = try add("DRAUGHTING_MODEL_ITEM_ASSOCIATION('target','',#\(owner),#\(rep),#\(entity))")
            }
            annotationEntities[annotation.id] = entity
        }
        for view in source.viewMetadata.views {
            let frame = try metadataFrame(origin: view.origin, direction: view.direction, up: view.up)
            let boxFrame: Int
            if view.windowPlacement == .twoDimensional {
                let point = try add("CARTESIAN_POINT('',(\(stepNumber(view.windowOrigin.x)),\(stepNumber(view.windowOrigin.y))))")
                let axis = try add("DIRECTION('',(\(stepNumber(view.windowUp.y)),\(stepNumber(-view.windowUp.x))))")
                boxFrame = try add("AXIS2_PLACEMENT_2D('',#\(point),#\(axis))")
            } else {
                boxFrame = try metadataFrame(origin: view.windowOrigin, direction: view.windowDirection, up: view.windowUp)
            }
            let box = try add("PLANAR_BOX('',\(stepNumber(view.horizontalSize)),\(stepNumber(view.verticalSize)),#\(boxFrame))")
            let projectionPoint = try metadataPoint(view.projectionPoint)
            let volume = try add("VIEW_VOLUME(.\(view.projection == .parallel ? "PARALLEL" : "CENTRAL").,#\(projectionPoint),\(stepNumber(view.focalDistance)),\(stepNumber(view.nearDistance)),\(view.frontClipping ? ".T." : ".F."),\(stepNumber(view.farDistance)),\(view.backClipping ? ".T." : ".F."),\(view.sideClipping ? ".T." : ".F."),#\(box))")
            var planes: [Int] = []
            for plane in view.clippingPlanes { planes.append(try metadataClipPlane(plane)) }
            var expressionEntity: Int?
            if let expression = view.clippingExpression {
                let encoded = try metadataClipExpression(expression)
                expressionEntity = encoded.entity; planes.append(contentsOf: encoded.cameraOperands)
            }
            let camera: Int
            if planes.isEmpty { camera = try add("CAMERA_MODEL_D3(\(try string(view.name)),#\(frame),#\(volume))") }
            else { camera = try add("CAMERA_MODEL_D3_MULTI_CLIPPING(\(try string(view.name)),#\(frame),#\(volume),(\(planes.map { "#\($0)" }.joined(separator: ","))))") }
            try metadataIdentity(camera, view.id, role: "view", description: "planes:\(view.clippingPlanes.count);expression:\(expressionEntity.map(String.init) ?? "none")")
            var items = [camera]
            for placement in view.annotationPlacements {
                guard let annotation = annotationEntities[placement.annotationID] else { throw ProductAttributeError.missingTarget("Written view annotation.") }
                let origin = try metadataFrame(origin: placement.mappingOrigin, direction: placement.mappingDirection, up: placement.mappingUp)
                let representation = try add("DRAUGHTING_MODEL('',(#\(annotation)),#\(context))")
                let map = try add("REPRESENTATION_MAP(#\(origin),#\(representation))")
                let p = try metadataPoint(placement.origin), z = try metadataDirection(placement.direction)
                let y = try metadataDirection(placement.up), x = try metadataDirection(placement.basisX)
                let transform = try add("CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#\(x),#\(y),#\(p),\(stepNumber(placement.scale)),#\(z))")
                items.append(try add("MAPPED_ITEM('',#\(map),#\(transform))"))
            }
            _ = try add("DRAUGHTING_MODEL(\(try string(view.name)),(\(items.map { "#\($0)" }.joined(separator:","))),#\(context))")
        }
        for property in source.viewMetadata.validationProperties {
            let owner = try metadataTarget(property.target)
            let item: Int
            switch property.value {
            case let .centroid(point): item = try metadataPoint(point)
            case let .length(value): item = try metadataMeasure(value, kind: "LENGTH", unit: meter, name: "length")
            case let .area(value):
                let exponent = try add("DERIVED_UNIT_ELEMENT(#\(meter),2.)"), unit = try add("DERIVED_UNIT((#\(exponent)))")
                item = try metadataMeasure(value, kind: "AREA", unit: unit, name: "surface area")
            case let .volume(value):
                let exponent = try add("DERIVED_UNIT_ELEMENT(#\(meter),3.)"), unit = try add("DERIVED_UNIT((#\(exponent)))")
                item = try metadataMeasure(value, kind: "VOLUME", unit: unit, name: "volume")
            }
            let p = try add("PROPERTY_DEFINITION('geometric validation property',\(try string(property.description)),#\(owner))")
            let rep = try add("REPRESENTATION(\(try string(property.name)),(#\(item)),#\(context))")
            _ = try add("PROPERTY_DEFINITION_REPRESENTATION(#\(p),#\(rep))")
            try metadataIdentity(p, property.id, role: "validation")
        }
    }
}
