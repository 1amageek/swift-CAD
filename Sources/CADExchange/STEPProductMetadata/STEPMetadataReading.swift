import Foundation
import CADCore
import CADIR
import CADKernel

extension STEPAttributesReader.Builder {
    mutating func metadataNumber(_ token: String) throws -> Double {
        try check()
        guard let number = Double(token.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else {
            throw ProductAttributeError.invalidSource("Invalid STEP metadata numerical value.")
        }
        return number
    }
    mutating func prepareMetadataIdentities() throws {
        for id in entities.keys.sorted() where names[id] == "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT" {
            try check()
            let a = try args(id, 4), source = try args(syntax.reference(a[2]), 1)
            guard source[0].hasPrefix("IDENTIFIER("), source[0].hasSuffix(")") else { continue }
            let namespace = try string(String(source[0].dropFirst(11).dropLast()))
            guard namespace == STEPMetadataNames.namespace else { continue }
            let role = try args(syntax.reference(a[1]), 2), roleName = try string(role[0])
            let targets = try syntax.list(a[3])
            guard targets.count == 1, let target = targets.first else { throw ProductAttributeError.invalidSource("Metadata source identity needs one standard target.") }
            let identifier = try string(a[0])
            let identity = ProductMetadataID(try PortableIdentity128(canonicalString: identifier))
            guard metadataIdentities.updateValue(identity, forKey: target) == nil,
                  metadataRoles.updateValue(roleName, forKey: target) == nil else {
                throw ProductAttributeError.invalidSource("Competing STEP metadata identities.")
            }
            if role[1] != "$" { metadataRoleDescriptions[target] = try string(role[1]) }
            let accepted: Bool
            switch roleName {
            case "datum": accepted = names[target] == "DATUM"
            case "dimension": accepted = ["DIMENSIONAL_SIZE", "DIMENSIONAL_LOCATION", "ANGULAR_SIZE", "ANGULAR_LOCATION"].contains(names[target] ?? "")
            case "tolerance": accepted = try metadataToleranceKind(target) != nil
            case "annotation": accepted = names[target] == "DRAUGHTING_CALLOUT"
            case "annotationText": accepted = names[target] == "ANNOTATION_TEXT_OCCURRENCE"
            case "materialDescriptor": accepted = names[target] == "MATERIAL_DESIGNATION"
            case "materialDescriptorProperty", "physicalAssignment": accepted = names[target] == "PROPERTY_DEFINITION"
            case "view": accepted = ["CAMERA_MODEL_D3", "CAMERA_MODEL_D3_MULTI_CLIPPING"].contains(names[target] ?? "")
            case "validation": accepted = names[target] == "PROPERTY_DEFINITION"
            case "clip:positive", "clip:negative": accepted = names[target] == "PLANE"
            case "clip:union": accepted = names[target] == "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION"
            case "clip:intersection": accepted = names[target] == "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION"
            case "target:global", "target:qualified", "target:contextual", "target:part", "target:occurrence", "target:directUsage":
                accepted = ["SHAPE_ASPECT", "DATUM_FEATURE"].contains(names[target] ?? "")
            default: accepted = false
            }
            guard accepted else { throw ProductAttributeError.invalidSource("STEP metadata role and real entity do not match.") }
            try budget.charge(targets: 3)
        }
        for id in entities.keys.sorted() {
            try check()
            if metadataRoles[id]?.hasPrefix("target:") == true || names[id] == "DATUM_FEATURE" {
                metadataAspectIDs.insert(id)
            }
            switch names[id] {
            case "DIMENSIONAL_SIZE", "ANGULAR_SIZE":
                let a = try syntax.arguments(id, component: nil)
                guard a.count >= 2 else { throw ProductAttributeError.invalidSource("Malformed dimensional characteristic.") }
                metadataAspectIDs.insert(try syntax.reference(a[0]))
            case "DIMENSIONAL_LOCATION", "ANGULAR_LOCATION":
                let a = try syntax.arguments(id, component: nil)
                guard a.count >= 4 else { throw ProductAttributeError.invalidSource("Malformed dimensional location.") }
                metadataAspectIDs.insert(try syntax.reference(a[2])); metadataAspectIDs.insert(try syntax.reference(a[3]))
            default:
                if try metadataToleranceKind(id) != nil {
                    let a = try metadataToleranceArguments(id)
                    metadataAspectIDs.insert(try syntax.reference(a[3]))
                }
            }
        }
        for id in metadataAspectIDs.sorted() { _ = try metadataTarget(id) }
    }
    mutating func metadataToleranceKind(_ id: Int) throws -> ProductGeometricTolerance.Kind? {
        try check()
        for (kind, name) in STEPMetadataNames.tolerances {
            try check()
            if names[id] == name { return kind }
            if names[id] == "", try syntax.hasComponent(id, named: name) { return kind }
        }
        return nil
    }
    mutating func metadataToleranceArguments(_ id: Int) throws -> [String] {
        if names[id] == "" { return try args(id, 4, component: "GEOMETRIC_TOLERANCE") }
        return try args(id, 4)
    }
    mutating func metadataID(_ entity: Int) throws -> ProductMetadataID {
        try check()
        if let id = metadataIdentities[entity] { return id }
        let id = ProductMetadataID(); try budget.charge(targets: 1); metadataIdentities[entity] = id; return id
    }
    mutating func metadataTarget(_ aspect: Int) throws -> ProductAttributeTarget {
        try check()
        if let target = metadataTargets[aspect] { return target }
        guard ["SHAPE_ASPECT", "DATUM_FEATURE"].contains(names[aspect] ?? "") else {
            if let mapped = geometry[aspect] { return mapped }
            throw ProductAttributeError.invalidSource("PMI requires a real shape aspect.")
        }
        let a = try args(aspect, 4), shape = try syntax.reference(a[2])
        guard names[shape] == "PRODUCT_DEFINITION_SHAPE" else { throw ProductAttributeError.invalidSource("PMI aspect lacks a product shape.") }
        let owner = try syntax.reference(args(shape, 3)[2])
        let role = metadataRoles[aspect]
        var target: ProductAttributeTarget?
        if role == "target:part", let definition = transfer.definitions[owner] {
            target = ProductAttributeTarget(kind: .part, definitionID: definition)
        } else if role == "target:directUsage", let usage = transfer.usages[owner] {
            target = ProductAttributeTarget(kind: .directUsage, usageID: usage)
        } else if role == "target:occurrence", let usage = transfer.usages[owner] {
            let path = try metadataPath(aspect, leaf: usage)
            target = ProductAttributeTarget(kind: .occurrence, path: path)
        } else {
            var mapped: ProductAttributeTarget?
            for id in entities.keys.sorted() where names[id] == "GEOMETRIC_ITEM_SPECIFIC_USAGE" {
                let usage = try args(id, 5)
                guard try syntax.reference(usage[2]) == aspect else { continue }
                let item = try syntax.reference(usage[4]), rep = try syntax.reference(usage[3])
                guard let geometry = geometry[item], let reference = geometry.geometry else {
                    throw ProductAttributeError.missingTarget("PMI geometry source correspondence.")
                }
                let fields = try args(rep, 3), items = try syntax.list(fields[1])
                guard items.contains(item) else { throw ProductAttributeError.invalidSource("PMI GISU item is outside its representation.") }
                let candidate: ProductAttributeTarget
                if role == "target:global" || evaluated.document.assembly == nil {
                    candidate = geometry
                } else if role == "target:contextual", let usage = transfer.usages[owner] {
                    candidate = ProductAttributeTarget(kind: geometry.kind, geometry: reference, path: try metadataPath(aspect, leaf: usage))
                } else if let definition = transfer.definitions[owner] {
                    guard let source = evaluated.document.assembly?.definitions.first(where: { $0.id == definition }),
                          source.features.contains(reference.subshapeID.featureID) else {
                        throw ProductAttributeError.missingTarget("PMI product does not own its geometry source.")
                    }
                    candidate = ProductAttributeTarget(kind: geometry.kind, geometry: reference, definitionID: definition)
                } else { throw ProductAttributeError.missingTarget("PMI product source owner.") }
                guard mapped == nil || mapped == candidate else { throw ProductAttributeError.ambiguousProperty("PMI GISU identifies multiple source targets.") }
                mapped = candidate
                try budget.charge(work: items.count, targets: 1)
            }
            target = mapped
        }
        guard let target else { throw ProductAttributeError.missingTarget("PMI shape aspect has no geometry correspondence.") }
        try target.validate(); try budget.charge(targets: 1); metadataTargets[aspect] = target; return target
    }
    mutating func metadataPath(_ aspect: Int, leaf: AssemblyOccurrenceID) throws -> AssemblyOccurrencePath {
        if let value = metadataRoleDescriptions[aspect] {
            var components: [AssemblyOccurrenceID] = []
            for part in value.split(separator: ",", omittingEmptySubsequences: false) {
                guard let entity = Int(part), let usage = transfer.relationships[entity] else {
                    throw ProductAttributeError.missingTarget("PMI full contextual relationship path.")
                }
                try budget.charge(work: 1, targets: 1); components.append(usage)
            }
            let path = AssemblyOccurrencePath(components)
            guard components.last == leaf, evaluated.assembly?.occurrences.contains(where: { $0.path == path }) == true else {
                throw ProductAttributeError.missingTarget("PMI contextual path does not exist.")
            }
            return path
        }
        let matches = evaluated.assembly?.occurrences.filter { $0.path.components.last == leaf } ?? []
        try check(evaluated.assembly?.occurrences.count ?? 0)
        guard matches.count == 1, let path = matches.first?.path else { throw ProductAttributeError.ambiguousProperty("PMI occurrence path.") }
        return path
    }
    mutating func metadataLengthScale(_ unit: Int) throws -> Double {
        try check()
        guard let length = try stepLengthUnit(from: syntax.entity(unit), entities: entities) else {
            throw ProductAttributeError.invalidSource("Metadata length measure lacks a length unit.")
        }
        return length.metersPerUnit
    }
    mutating func metadataMeasure(_ item: Int, depth: Int = 0) throws -> (value: Double, kind: String, label: String) {
        guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Metadata unit conversion depth.") }
        let a: [String], label: String
        if names[item] == "" {
            a = try args(item, 2, component: "MEASURE_WITH_UNIT")
            label = try string(args(item, 1, component: "REPRESENTATION_ITEM")[0])
        } else { a = try args(item, 2); label = "" }
        guard let open = a[0].firstIndex(of: "("), a[0].last == ")" else { throw ProductAttributeError.invalidSource("Metadata measure lacks a typed numerical value.") }
        let kind = String(a[0][..<open]), value = try metadataNumber(String(a[0][a[0].index(after: open)..<a[0].index(before: a[0].endIndex)]))
        let unit = try syntax.reference(a[1]), scale: Double
        switch kind {
        case "LENGTH_MEASURE": scale = try metadataLengthScale(unit)
        case "AREA_MEASURE", "VOLUME_MEASURE":
            let degree = kind == "AREA_MEASURE" ? 2 : 3
            if names[unit] == "DERIVED_UNIT" {
                let elements = try syntax.list(args(unit, 1)[0]); guard elements.count == 1, let element = elements.first else { throw ProductAttributeError.invalidSource("Validation measure needs one length power unit.") }
                let e = try args(element, 2), exponent = try metadataNumber(e[1]); guard exponent == Double(degree) else { throw ProductAttributeError.invalidSource("Validation measure unit exponent mismatch.") }
                let length = try metadataLengthScale(syntax.reference(e[0])); scale = degree == 2 ? length * length : length * length * length
            } else {
                let component = kind == "AREA_MEASURE" ? "AREA_UNIT" : "VOLUME_UNIT"
                guard try syntax.hasComponent(unit, named: component), try syntax.hasComponent(unit, named: "SI_UNIT") else { throw ProductAttributeError.unsupportedSemantics("Unsupported physical validation unit.") }
                let si = try args(unit, 2, component: "SI_UNIT")
                let length = try stepLengthUnit(from: "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(\(si[0]),.METRE.))", entities: entities)
                guard let length else { throw ProductAttributeError.invalidSource("Invalid SI validation unit prefix.") }
                scale = degree == 2 ? length.metersPerUnit * length.metersPerUnit : length.metersPerUnit * length.metersPerUnit * length.metersPerUnit
            }
        case "PLANE_ANGLE_MEASURE":
            guard try syntax.hasComponent(unit, named: "PLANE_ANGLE_UNIT") else { throw ProductAttributeError.invalidSource("Metadata angle lacks an angle unit.") }
            if try syntax.hasComponent(unit, named: "SI_UNIT") {
                guard try args(unit, 2, component: "SI_UNIT") == ["$", ".RADIAN."] else { throw ProductAttributeError.invalidSource("Unsupported angle SI unit.") }
                scale = 1
            } else {
                let conversion = try args(unit, 2, component: "CONVERSION_BASED_UNIT")
                let factor = try metadataMeasure(syntax.reference(conversion[1]), depth: depth + 1)
                guard factor.kind == "PLANE_ANGLE_MEASURE", factor.value > 0 else { throw ProductAttributeError.invalidSource("Invalid plane-angle conversion gain.") }
                scale = factor.value
            }
        default: throw ProductAttributeError.unsupportedSemantics("Unsupported metadata measure kind.")
        }
        let result = value * scale
        guard result.isFinite else { throw ProductAttributeError.invalidSource("Metadata measure conversion overflow.") }
        return (result, kind, label)
    }
    mutating func metadataRepresentation(_ property: Int, association: String = "PROPERTY_DEFINITION_REPRESENTATION") throws -> Int {
        var representations: [Int] = []
        for id in entities.keys.sorted() where names[id] == association {
            try check(); let a = try args(id, 2)
            if try syntax.reference(a[0]) == property { representations.append(try syntax.reference(a[1])); try budget.charge(targets: 1) }
        }
        guard representations.count == 1, let result = representations.first else { throw ProductAttributeError.ambiguousProperty("Metadata representation association.") }
        return result
    }
    mutating func metadataPoint(_ entity: Int, scale: Double) throws -> Point3D {
        guard names[entity] == "CARTESIAN_POINT" else { throw ProductAttributeError.invalidSource("Expected metadata Cartesian point.") }
        let a = try args(entity, 2), values = try syntax.numbers(a[1])
        guard values.count == 3 else { throw ProductAttributeError.invalidSource("Metadata point needs three coordinates.") }
        try check(3)
        let point = Point3D(x: values[0] * scale, y: values[1] * scale, z: values[2] * scale)
        guard point.isFinite else { throw ProductAttributeError.invalidSource("Metadata point conversion overflow.") }; return point
    }
    mutating func metadataDirection(_ entity: Int) throws -> Vector3D {
        guard names[entity] == "DIRECTION" else { throw ProductAttributeError.invalidSource("Expected metadata direction.") }
        let a = try args(entity, 2), values = try syntax.numbers(a[1])
        guard values.count == 3 else { throw ProductAttributeError.invalidSource("Metadata direction needs three components.") }
        return try Vector3D(x: values[0],y: values[1],z: values[2]).normalized(tolerance: Double.leastNonzeroMagnitude)
    }
    mutating func metadataFirstAxis(_ z: Vector3D, reference: Vector3D?) throws -> Vector3D {
        try check(32)
        let candidate = reference ?? ((z == .unitX || z == Vector3D.unitX * -1) ? .unitY : .unitX)
        return try (candidate - z * candidate.dot(z)).normalized(tolerance: Double.leastNonzeroMagnitude)
    }
    mutating func metadataFrame(_ entity: Int, scale: Double) throws -> (Point3D, Vector3D, Vector3D) {
        guard names[entity] == "AXIS2_PLACEMENT_3D" else { throw ProductAttributeError.invalidSource("Expected metadata 3D frame.") }
        let a = try args(entity, 4), origin = try metadataPoint(syntax.reference(a[1]), scale: scale)
        let z = a[2] == "$" ? Vector3D.unitZ : try metadataDirection(syntax.reference(a[2]))
        let x = try metadataFirstAxis(z, reference: a[3] == "$" ? nil : metadataDirection(syntax.reference(a[3])))
        let up = try z.cross(x).normalized(tolerance: Double.leastNonzeroMagnitude)
        return (origin, z, up)
    }
    mutating func metadataContextScale(_ representation: Int) throws -> Double {
        let rep = try args(representation, 3), context = try syntax.reference(rep[2])
        let units = try syntax.list(args(context, 1, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")[0])
        var length: Double?
        for id in units {
            if let unit = try stepLengthUnit(from: syntax.entity(id), entities: entities) {
                guard length == nil else { throw ProductAttributeError.invalidSource("Ambiguous metadata context length unit.") }
                length = unit.metersPerUnit
            }
            try check()
        }
        guard let length else { throw ProductAttributeError.invalidSource("Metadata representation lacks length units.") }; return length
    }
    mutating func metadataContainingRepresentation(_ item: Int) throws -> Int {
        var found: Int?, scale: Double?
        for id in entities.keys.sorted() where ["DRAUGHTING_MODEL", "REPRESENTATION", "MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION"].contains(names[id] ?? "") {
            try check(); let a = try args(id, 3), items = try syntax.list(a[1]); try check(items.count)
            if items.contains(item) {
                let current = try metadataContextScale(id)
                guard scale == nil || scale == current else { throw ProductAttributeError.invalidSource("Shared metadata item has inconsistent units.") }
                found = id; scale = current
            }
        }
        guard let found else { throw ProductAttributeError.missingTarget("Metadata item representation context.") }; return found
    }
    mutating func metadataBoolean(_ token: String) throws -> Bool {
        switch token { case ".T.": return true; case ".F.": return false; default: throw ProductAttributeError.invalidSource("Invalid camera clipping Boolean.") }
    }
    mutating func metadataClipping(_ entity: Int, scale: Double, depth: Int = 0, ancestors: Set<Int> = []) throws -> ProductClippingExpression {
        guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Clipping expression ingress depth.") }
        guard !ancestors.contains(entity) else { throw ProductAttributeError.invalidSource("Cyclic STEP clipping expression.") }
        try check(); try budget.charge(targets: 1)
        if names[entity] == "PLANE" {
            let a = try args(entity, 2), frame = try metadataFrame(syntax.reference(a[1]), scale: scale)
            let positive = metadataRoles[entity] != "clip:negative"
            return .plane(ProductClippingPlane(origin: frame.0, normal: positive ? frame.1 : frame.1 * -1, keepPositive: positive))
        }
        guard ["CAMERA_MODEL_D3_MULTI_CLIPPING_UNION", "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION"].contains(names[entity] ?? "") else { throw ProductAttributeError.invalidSource("Unknown clipping-expression operator.") }
        let union = names[entity] == "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION"
        let a = try args(entity, 2), ids = try syntax.list(a[1])
        try budget.charge(work: ids.count, targets: ids.count)
        guard ids.count >= 2, Set(ids).count == ids.count else { throw ProductAttributeError.invalidSource("Clipping expression requires two distinct operands.") }
        for id in ids {
            try check()
            guard names[id] == "PLANE" || names[id] == (union ? "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION" : "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION") else { throw ProductAttributeError.invalidSource("Clipping expression violates the standard alternating SELECT.") }
        }
        var originalIDs = ids
        if metadataRoles[entity] == (union ? "clip:union" : "clip:intersection") {
            guard let description = metadataRoleDescriptions[entity] else { throw ProductAttributeError.invalidSource("Original clipping node lacks its child association.") }
            originalIDs = []
            for token in description.split(separator: ",", omittingEmptySubsequences: false) {
                guard let child = Int(token), entities[child] != nil else { throw ProductAttributeError.missingTarget("Original clipping child operator.") }
                try budget.charge(work:1,targets:1); originalIDs.append(child)
            }
            guard originalIDs.count >= 2, Set(originalIDs).count == originalIDs.count else { throw ProductAttributeError.invalidSource("Original clipping grouping needs distinct child identities.") }
            var physicalIDs: [Int] = []
            for child in originalIDs {
                try check()
                if names[child] == names[entity] {
                    let values = try syntax.list(args(child,2)[1])
                    try budget.charge(work:values.count,targets:values.count)
                    physicalIDs.append(contentsOf:values)
                } else { try budget.charge(targets:1); physicalIDs.append(child) }
            }
            try check(physicalIDs.count)
            guard physicalIDs == ids else { throw ProductAttributeError.invalidSource("Original clipping grouping conflicts with actual physical operands.") }
        }
        var descendants = ancestors; descendants.insert(entity)
        var operands: [ProductClippingExpression] = []
        for child in originalIDs {
            operands.append(try metadataClipping(child, scale: scale, depth: depth + 1, ancestors: descendants))
        }
        return union ? .union(operands) : .intersection(operands)
    }
    mutating func readMetadata() throws -> (ProductManufacturingInformation, ProductViewMetadata) {
        var pmi = ProductManufacturingInformation(), metadata = ProductViewMetadata()
        for id in entities.keys.sorted() where names[id] == "DATUM" {
            let a = try args(id, 5)
            var features: [Int] = []
            for relationship in entities.keys.sorted() where names[relationship] == "SHAPE_ASPECT_RELATIONSHIP" {
                let r = try args(relationship, 4)
                if try syntax.reference(r[3]) == id { features.append(try syntax.reference(r[2])) }
                try check()
            }
            guard features.count == 1, let feature = features.first, names[feature] == "DATUM_FEATURE" else { throw ProductAttributeError.invalidSource("A datum needs one established feature.") }
            let f = try args(feature, 4)
            pmi.datums.append(ProductDatum(id: try metadataID(id), name: try string(f[0]), description: a[1] == "$" ? "" : try string(a[1]),
                identification: try string(a[4]), target: try metadataTarget(feature)))
            try budget.charge(targets: 1)
        }
        for id in entities.keys.sorted() where ["DIMENSIONAL_SIZE", "ANGULAR_SIZE", "DIMENSIONAL_LOCATION", "ANGULAR_LOCATION"].contains(names[id] ?? "") {
            let a = try syntax.arguments(id, component: nil), location = names[id]?.contains("LOCATION") == true
            let rep = try metadataRepresentation(id, association: "DIMENSIONAL_CHARACTERISTIC_REPRESENTATION"), r = try args(rep, 3)
            let items = try syntax.list(r[1]); var nominal: (value: Double, kind: String, label: String)?, description = ""
            for item in items {
                if names[item] == "DESCRIPTIVE_REPRESENTATION_ITEM" {
                    let value = try args(item, 2)
                    guard try string(value[0]) == "description" else { throw ProductAttributeError.unsupportedSemantics("Unknown dimension descriptive semantics.") }
                    description = try string(value[1])
                } else {
                    guard nominal == nil else { throw ProductAttributeError.ambiguousProperty("Dimension nominal measures.") }
                    nominal = try metadataMeasure(item)
                }
            }
            guard let nominal else { throw ProductAttributeError.missingTarget("Dimension nominal measure.") }
            let kind = ProductDimension.Kind(rawValue: nominal.label) ?? (nominal.kind == "PLANE_ANGLE_MEASURE" ? .angle : (location ? .location : .size))
            let name = try string(a[location ? 0 : 1]), target = try metadataTarget(syntax.reference(a[location ? 2 : 0]))
            let reference = location ? try metadataTarget(syntax.reference(a[3])) : nil
            var lower: Double?, upper: Double?
            for tolerance in entities.keys.sorted() where names[tolerance] == "PLUS_MINUS_TOLERANCE" {
                let t = try args(tolerance, 2)
                if try syntax.reference(t[1]) == id {
                    guard lower == nil else { throw ProductAttributeError.ambiguousProperty("Dimension tolerance range.") }
                    let bounds = try args(syntax.reference(t[0]), 2)
                    let lo = try metadataMeasure(syntax.reference(bounds[0])), hi = try metadataMeasure(syntax.reference(bounds[1]))
                    guard lo.kind == nominal.kind, hi.kind == nominal.kind else { throw ProductAttributeError.invalidSource("Dimension tolerance measure dimension mismatch.") }
                    lower = lo.value; upper = hi.value
                }
                try check()
            }
            pmi.dimensions.append(ProductDimension(id: try metadataID(id), name: name, description: description, kind: kind,
                target: target, referenceTarget: reference, nominal: nominal.value, lowerDeviation: lower, upperDeviation: upper))
            try budget.charge(targets: 1)
        }
        for id in entities.keys.sorted() {
            guard let kind = try metadataToleranceKind(id) else { continue }
            let a = try metadataToleranceArguments(id), measure = try metadataMeasure(syntax.reference(a[2]))
            guard measure.kind == "LENGTH_MEASURE" else { throw ProductAttributeError.invalidSource("Tolerance magnitude must be length.") }
            var datumIDs: [ProductMetadataID] = [], modifiers: [ProductGeometricTolerance.Modifier] = []
            if names[id] == "", try syntax.hasComponent(id, named: "GEOMETRIC_TOLERANCE_WITH_DATUM_REFERENCE") {
                let r = try args(id, 1, component: "GEOMETRIC_TOLERANCE_WITH_DATUM_REFERENCE")
                var ordered: [(Int, ProductMetadataID)] = []
                for reference in try syntax.list(r[0]) {
                    let d = try args(reference, 2), precedence = try metadataNumber(d[0]), datum = try syntax.reference(d[1])
                    guard precedence.rounded() == precedence, precedence > 0, precedence <= Double(Int.max), names[datum] == "DATUM" else { throw ProductAttributeError.invalidSource("Invalid ordered datum reference.") }
                    ordered.append((Int(precedence), try metadataID(datum))); try budget.charge(targets: 1)
                }
                ordered.sort { $0.0 < $1.0 }
                guard Set(ordered.map { $0.0 }).count == ordered.count else { throw ProductAttributeError.invalidSource("Competing datum precedence.") }
                datumIDs = ordered.map { $0.1 }
            }
            if names[id] == "", try syntax.hasComponent(id, named: "GEOMETRIC_TOLERANCE_WITH_MODIFIERS") {
                let tokens = try syntax.split(String(args(id, 1, component: "GEOMETRIC_TOLERANCE_WITH_MODIFIERS")[0].dropFirst().dropLast()))
                for token in tokens {
                    guard let modifier = STEPMetadataNames.modifiers.first(where: { "." + $0.value + "." == token })?.key else { throw ProductAttributeError.unsupportedSemantics("Unknown standard tolerance modifier.") }
                    modifiers.append(modifier); try budget.charge(targets: 1)
                }
            }
            for property in entities.keys.sorted() where names[property] == "PROPERTY_DEFINITION" {
                let p = try args(property, 3)
                if try syntax.reference(p[2]) == id, try string(p[0]) == "geometric tolerance modifier" {
                    guard let modifier = ProductGeometricTolerance.Modifier(rawValue: try string(p[1])) else { throw ProductAttributeError.invalidSource("Unknown authored tolerance modifier.") }
                    modifiers.append(modifier)
                }
                try check()
            }
            pmi.tolerances.append(ProductGeometricTolerance(id: try metadataID(id), name: try string(a[0]), description: a[1] == "$" ? "" : try string(a[1]), kind: kind,
                magnitude: measure.value, target: try metadataTarget(syntax.reference(a[3])), datumIDs: datumIDs, modifiers: modifiers))
            try budget.charge(targets: 1)
        }
        for id in entities.keys.sorted() where names[id] == "DRAUGHTING_CALLOUT" {
            let a = try args(id, 2), parts = try syntax.list(a[1]), rep = try metadataContainingRepresentation(id), scale = try metadataContextScale(rep)
            var text = "", literals: [ProductAnnotationTextLiteral] = [], lines: [[Point3D]] = []
            for part in parts {
                let occurrence = try args(part, 3), item = try syntax.reference(occurrence[2])
                for style in try syntax.list(occurrence[1]) {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Context-bound and non-null annotation styles need a persistent original style owner before public ingress can accept them.
                    // STEP metadata import currently accepts only actual null-style assignments.
                    guard names[style] == "PRESENTATION_STYLE_ASSIGNMENT" else {
                        throw ProductAttributeError.unsupportedSemantics("Original drawing annotation style binding is not yet represented.")
                    }
                    let elements = try args(style,1)
                    let values = try syntax.split(String(elements[0].dropFirst().dropLast()))
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Drawing annotation ingress currently has no persistent source owner for non-null presentation-style selections.
                    // Public STEP metadata import must retain their actual colour/font-size/curve-style values and scoped precedence before accepting these occurrences.
                    guard names[style] == "PRESENTATION_STYLE_ASSIGNMENT", !values.isEmpty,
                        values.allSatisfy({ $0.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() == "NULL_STYLE(.NULL.)" }) else {
                        throw ProductAttributeError.unsupportedSemantics("Original drawing annotation style is not yet represented.")
                    }
                    try check(values.count)
                }
                if names[part] == "ANNOTATION_TEXT_OCCURRENCE", names[item] == "TEXT_LITERAL" {
                    let literal = try args(item, 6), frameID = try syntax.reference(literal[2])
                    let frame: (Point3D,Vector3D,Vector3D)
                    let placement: ProductAnnotationTextLiteral.Placement
                    if names[frameID] == "AXIS2_PLACEMENT_2D" {
                        let position = try args(frameID,3), pointID = try syntax.reference(position[1])
                        guard names[pointID] == "CARTESIAN_POINT" else { throw ProductAttributeError.invalidSource("Annotation 2D literal position is not a point.") }
                        let coordinates = try syntax.numbers(args(pointID,2)[1])
                        guard coordinates.count == 2 else { throw ProductAttributeError.invalidSource("Annotation 2D literal needs two coordinates.") }
                        var x = Vector3D.unitX
                        if position[2] != "$" {
                            let directionID = try syntax.reference(position[2])
                            guard names[directionID] == "DIRECTION" else { throw ProductAttributeError.invalidSource("Annotation literal reference is not a direction.") }
                            let axis = try syntax.numbers(args(directionID,2)[1])
                            guard axis.count == 2 else { throw ProductAttributeError.invalidSource("Annotation 2D literal needs a two-component reference.") }
                            x = try Vector3D(x:axis[0],y:axis[1],z:0).normalized(tolerance:Double.leastNonzeroMagnitude)
                        }
                        frame = (Point3D(x:coordinates[0]*scale,y:coordinates[1]*scale,z:0),.unitZ,Vector3D(x:-x.y,y:x.x,z:0))
                        placement = .twoDimensional
                    } else { frame = try metadataFrame(frameID,scale:scale); placement = .threeDimensional }
                    let font = try syntax.reference(literal[5])
                    guard names[font] == "DRAUGHTING_PRE_DEFINED_TEXT_FONT" else { throw ProductAttributeError.unsupportedSemantics("Unsupported original drawing-text font family.") }
                    let fontName = try string(args(font,1)[0])
                    guard let path = ProductAnnotationTextLiteral.Path(rawValue:literal[4].trimmingCharacters(in:CharacterSet(charactersIn:".")).lowercased()) else { throw ProductAttributeError.invalidSource("Invalid original text path.") }
                    let content = try string(literal[1])
                    literals.append(.init(id:try metadataID(part),literalName:try string(literal[0]),occurrenceName:try string(occurrence[0]),text:content,
                        origin:frame.0,direction:frame.1,up:frame.2,placement:placement,alignment:try string(literal[3]),path:path,fontName:fontName))
                    text += content
                    try budget.charge(targets:1)
                } else if names[part] == "ANNOTATION_CURVE_OCCURRENCE", names[item] == "POLYLINE" {
                    let line = try args(item, 2); var points: [Point3D] = []
                    for point in try syntax.list(line[1]) { points.append(try metadataPoint(point, scale: scale)); try budget.charge(targets: 1) }
                    lines.append(points)
                } else { throw ProductAttributeError.unsupportedSemantics("Unsupported drawing annotation primitive.") }
            }
            var targets: [ProductAttributeTarget] = [], semanticID: ProductMetadataID?, meaning = ProductAnnotation.Meaning.note
            for association in entities.keys.sorted() where names[association] == "DRAUGHTING_MODEL_ITEM_ASSOCIATION" {
                let d = try args(association, 5)
                guard try syntax.reference(d[4]) == id else { continue }
                let owner = try syntax.reference(d[2]), role = try string(d[0])
                if metadataAspectIDs.contains(owner) { targets.append(try metadataTarget(owner)) }
                else {
                    guard semanticID == nil else { throw ProductAttributeError.ambiguousProperty("Annotation semantic association.") }
                    if names[owner] == "DATUM" { meaning = .datum }
                    else if try metadataToleranceKind(owner) != nil { meaning = .tolerance }
                    else if ["DIMENSIONAL_SIZE", "DIMENSIONAL_LOCATION", "ANGULAR_SIZE", "ANGULAR_LOCATION"].contains(names[owner] ?? "") { meaning = .dimension }
                    else { throw ProductAttributeError.unsupportedSemantics("Unsupported annotation semantic owner.") }
                    guard role.isEmpty || role == meaning.rawValue else { throw ProductAttributeError.invalidSource("Annotation semantic association role conflicts with owner.") }
                    semanticID = try metadataID(owner)
                }
                try check()
            }
            pmi.annotations.append(ProductAnnotation(id: try metadataID(id), name: try string(a[0]), text: text, meaning: meaning,
                semanticID: semanticID, targets: targets, polylines: lines, textLiterals: literals)); try budget.charge(targets: 1)
        }
        for id in entities.keys.sorted() where ["CAMERA_MODEL_D3", "CAMERA_MODEL_D3_MULTI_CLIPPING"].contains(names[id] ?? "") {
            let a = try syntax.arguments(id, component: nil), rep = try metadataContainingRepresentation(id), scale = try metadataContextScale(rep)
            guard a.count == (names[id] == "CAMERA_MODEL_D3" ? 3 : 4) else { throw ProductAttributeError.invalidSource("Malformed camera arguments.") }
            let frame = try metadataFrame(syntax.reference(a[1]), scale: scale), volume = try args(syntax.reference(a[2]), 9)
            let box = try args(syntax.reference(volume[8]), 4)
            let projection: ProductSavedView.Projection
            switch volume[0] { case ".PARALLEL.": projection = .parallel; case ".CENTRAL.": projection = .perspective; default: throw ProductAttributeError.invalidSource("Unknown view projection.") }
            let front = try metadataBoolean(volume[4]), back = try metadataBoolean(volume[6]), sides = try metadataBoolean(volume[7])
            let projectionPoint = try metadataPoint(syntax.reference(volume[1]), scale: scale)
            let windowID = try syntax.reference(box[3])
            let window: (Point3D, Vector3D, Vector3D)
            let windowPlacement: ProductSavedView.WindowPlacement
            if names[windowID] == "AXIS2_PLACEMENT_2D" {
                let placement = try args(windowID, 3)
                let pointID = try syntax.reference(placement[1])
                guard names[pointID] == "CARTESIAN_POINT" else { throw ProductAttributeError.invalidSource("Window location is not a Cartesian point.") }
                let point = try syntax.numbers(args(pointID, 2)[1])
                guard point.count == 2 else { throw ProductAttributeError.invalidSource("2D window requires two original coordinates.") }
                var x = Vector3D.unitX
                if placement[2] != "$" {
                    let directionID = try syntax.reference(placement[2])
                    guard names[directionID] == "DIRECTION" else { throw ProductAttributeError.invalidSource("Window reference is not a direction.") }
                    let coordinates = try syntax.numbers(args(directionID, 2)[1])
                    guard coordinates.count == 2 else { throw ProductAttributeError.invalidSource("2D window reference needs two components.") }
                    x = try Vector3D(x: coordinates[0], y: coordinates[1], z: 0).normalized(tolerance: Double.leastNonzeroMagnitude)
                }
                window = (Point3D(x: point[0] * scale, y: point[1] * scale, z: 0), .unitZ, Vector3D(x: -x.y, y: x.x, z: 0))
                windowPlacement = .twoDimensional
            } else {
                window = try metadataFrame(windowID, scale: scale)
                windowPlacement = .threeDimensional
            }
            var clips: [ProductClippingPlane] = [], placements: [ProductAnnotationPlacement] = []
            var expression: ProductClippingExpression?
            if a.count == 4 {
                let ids = try syntax.list(a[3])
                guard !ids.isEmpty, Set(ids).count == ids.count else { throw ProductAttributeError.invalidSource("Camera clipping SET must be nonempty and unique.") }
                var decoded: [ProductClippingExpression] = []
                for id in ids {
                    guard names[id] == "PLANE" || names[id] == "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION" else { throw ProductAttributeError.invalidSource("Camera clipping violates its standard SELECT.") }
                    decoded.append(try metadataClipping(id, scale: scale))
                }
                if let description = metadataRoleDescriptions[id] {
                    let fields = description.split(separator: ";", omittingEmptySubsequences: false)
                    guard fields.count == 2, fields[0].hasPrefix("planes:"), fields[1].hasPrefix("expression:"),
                          let count = Int(fields[0].dropFirst(7)), count >= 0, count <= decoded.count else { throw ProductAttributeError.invalidSource("Invalid saved clipping source partition.") }
                    for value in decoded.prefix(count) { guard case .plane(let plane) = value else { throw ProductAttributeError.invalidSource("Saved clipping plane partition identifies a Boolean operation.") }; clips.append(plane) }
                    let token = String(fields[1].dropFirst(11))
                    if token != "none" {
                        guard let sourceID = Int(token) else { throw ProductAttributeError.invalidSource("Invalid clipping expression source identity.") }
                        let root = try metadataClipping(sourceID, scale: scale)
                        let sourceOperands: [Int]
                        if names[sourceID] == "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION" { sourceOperands = try syntax.list(args(sourceID, 2)[1]) }
                        else { sourceOperands = [sourceID] }
                        guard Array(ids.dropFirst(count)) == sourceOperands else { throw ProductAttributeError.invalidSource("Camera actual clipping law conflicts with retained source expression.") }
                        expression = root
                    } else { guard count == decoded.count else { throw ProductAttributeError.invalidSource("Unowned actual clipping operands.") } }
                } else if decoded.allSatisfy({ if case .plane = $0 { return true }; return false }) {
                    for value in decoded { if case .plane(let plane) = value { clips.append(plane) } }
                } else { expression = decoded.count == 1 ? decoded[0] : .intersection(decoded) }
            }
            let repArgs = try args(rep, 3)
            for item in try syntax.list(repArgs[1]) where names[item] == "MAPPED_ITEM" {
                let mapped = try args(item, 3), map = try args(syntax.reference(mapped[1]), 2)
                let annotationRep = try args(syntax.reference(map[1]), 3), contents = try syntax.list(annotationRep[1])
                guard !contents.isEmpty, contents.allSatisfy({ names[$0] == "DRAUGHTING_CALLOUT" }) else { throw ProductAttributeError.invalidSource("View mapped representation must contain source annotations.") }
                let mappingOrigin = try metadataFrame(syntax.reference(map[0]), scale: scale)
                let transform = try args(syntax.reference(mapped[2]), 8)
                let z = transform[7] == "$" ? Vector3D.unitZ : try metadataDirection(syntax.reference(transform[7]))
                let x = try metadataFirstAxis(z, reference: transform[3] == "$" ? nil : metadataDirection(syntax.reference(transform[3])))
                let candidateY = transform[4] == "$" ? Vector3D.unitY : try metadataDirection(syntax.reference(transform[4]))
                let y = try (candidateY - z * candidateY.dot(z) - x * candidateY.dot(x)).normalized(tolerance: Double.leastNonzeroMagnitude)
                let origin = try metadataPoint(syntax.reference(transform[5]), scale: scale), gain = transform[6] == "$" ? 1 : try metadataNumber(transform[6])
                for annotation in contents {
                placements.append(ProductAnnotationPlacement(annotationID: try metadataID(annotation), origin: origin, direction: z, up: y, scale: gain, basisX: x, mappingOrigin: mappingOrigin.0, mappingDirection: mappingOrigin.1, mappingUp: mappingOrigin.2)); try budget.charge(targets: 1)
                }
            }
            metadata.views.append(ProductSavedView(id: try metadataID(id), name: try string(a[0]), origin: frame.0, direction: frame.1, up: frame.2,
                projection: projection, horizontalSize: try metadataNumber(box[1]) * scale, verticalSize: try metadataNumber(box[2]) * scale,
                focalDistance: try metadataNumber(volume[2]) * scale, nearDistance: try metadataNumber(volume[3]) * scale,
                farDistance: try metadataNumber(volume[5]) * scale, clippingPlanes: clips, annotationPlacements: placements,
                projectionPoint: projectionPoint, windowOrigin: window.0, windowUp: window.2, windowDirection: window.1, windowPlacement: windowPlacement,
                frontClipping: front, backClipping: back, sideClipping: sides, clippingExpression: expression)); try budget.charge(targets: 1)
        }
        for id in entities.keys.sorted() where names[id] == "PROPERTY_DEFINITION" {
            let a = try args(id, 3)
            guard try string(a[0]) == "geometric validation property" else { continue }
            let rep = try metadataRepresentation(id), r = try args(rep, 3), items = try syntax.list(r[1])
            guard items.count == 1, let item = items.first else { throw ProductAttributeError.invalidSource("Validation property needs one numerical value.") }
            let value: ProductValidationProperty.Value
            if names[item] == "CARTESIAN_POINT" { value = .centroid(try metadataPoint(item, scale: metadataContextScale(rep))) }
            else {
                let measure = try metadataMeasure(item)
                switch measure.kind { case "AREA_MEASURE": value = .area(measure.value); case "VOLUME_MEASURE": value = .volume(measure.value)
                case "LENGTH_MEASURE": value = .length(measure.value); default: throw ProductAttributeError.invalidSource("Invalid validation measure dimension.") }
            }
            metadata.validationProperties.append(ProductValidationProperty(id: try metadataID(id), name: try string(r[0]), description: a[1] == "$" ? "" : try string(a[1]),
                target: try metadataTarget(syntax.reference(a[2])), value: value)); try budget.charge(targets: 1)
        }
        return (pmi, metadata)
    }
}
