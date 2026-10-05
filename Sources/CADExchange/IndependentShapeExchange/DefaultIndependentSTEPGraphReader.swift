import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultIndependentSTEPGraphReader: IndependentSTEPGraphReading {
    public init() {}
    public func read(entityIDs: [Int], standaloneItemEntityIDs: [Int],
        fields: any STEPFieldReading, ambientOriginalAngularSource: IndependentShapeAngularSource? = nil, ambientOriginalLengthSource: OriginalSTEPLengthSource? = nil, ambientContexts: [IndependentShapeContext] = [], productDefinitions: [Int: AssemblyDefinitionID] = [:], bodySources: [Int: SubshapeID] = [:], bodySourceGraph: DesignGraph? = nil, standaloneUnits: UnitSystem, tolerance: ModelingTolerance,
        producer: inout any IndependentSTEPGeometryReading, usage: inout IndependentShapeExchangeUsage) throws -> IndependentShapeSource? {
        try tolerance.validate(); try standaloneUnits.validate()
        var builder = Builder(fields: fields, productDefinitions: productDefinitions, bodySources: bodySources, bodySourceGraph: bodySourceGraph, producer: producer, usage: usage, tolerance: tolerance, standaloneUnits: standaloneUnits, ambientOriginalAngularSource: ambientOriginalAngularSource, ambientOriginalLengthSource: ambientOriginalLengthSource, ambientContexts: ambientContexts)
        defer { producer = builder.producer; usage = builder.usage }
        return try builder.read(entityIDs: entityIDs, standaloneItems: standaloneItemEntityIDs)
    }

    private struct Builder {
        let fields: any STEPFieldReading
        let productDefinitions: [Int: AssemblyDefinitionID]
        let bodySources: [Int: SubshapeID]
        let bodySourceGraph: DesignGraph?
        var productAssociations: [IndependentShapeProductAssociation] = []
        var producer: any IndependentSTEPGeometryReading
        var usage: IndependentShapeExchangeUsage
        let tolerance: ModelingTolerance
        let standaloneUnits: UnitSystem
        let ambientOriginalAngularSource: IndependentShapeAngularSource?
        let ambientOriginalLengthSource: OriginalSTEPLengthSource?
        let ambientContexts: [IndependentShapeContext]
        var itemLengthGains: [Int: ExactRationalCoefficient] = [:]
        var curveBasisLengthGains: [CurveID: ExactRationalCoefficient] = [:]
        var surfaceBasisLengthGains: [SurfaceID: ExactRationalCoefficient] = [:]
        var itemAngularGains: [Int: IndependentShapeAngularSource.CoordinateLaw] = [:]
        var curveBasisAngularGains: [CurveID: IndependentShapeAngularSource.CoordinateLaw] = [:]
        var surfaceBasisAngularGains: [SurfaceID: IndependentShapeAngularSource.CoordinateLaw] = [:]
        var geometry = GeometryStore()
        var items: [Int: IndependentShapeItem] = [:]
        var sets: [Int: IndependentShapeGeometricSet] = [:]
        var contexts: [Int: IndependentShapeContext] = [:]
        var representations: [Int: IndependentShapeRepresentation] = [:]
        var frames: [Int: IndependentShapeFrame] = [:]
        var frameUnits: [Int: UnitSystem] = [:]
        var definitions: [Int: IndependentShapeDefinition] = [:]
        var instances: [Int: IndependentShapeInstance] = [:]
        var groups: [Int: IndependentShapeGroup] = [:]
        var assignmentGroups: [Int: Int] = [:]
        var originalSTEPGroups: [Int: IndependentShapeSTEPGroup] = [:]
        var itemUnits: [Int: UnitSystem] = [:]
        var curveBasisUnits: [CurveID: LengthUnit] = [:]
        var surfaceAngularMeasures: [SurfaceID: IndependentShapeSurfaceAngularMeasure] = [:]
        var surfaceBasisUnits: [SurfaceID: LengthUnit] = [:]
        var instanceUnits: [Int: UnitSystem] = [:]
        var curveLinearSources: [CurveID: OriginalSTEPLineSource] = [:]
        var curveSplineSources: [CurveID: OriginalSTEPSplineCurveSource] = [:]
        var surfaceSplineSources: [SurfaceID: OriginalSTEPSplineSurfaceSource] = [:]
        var curveNames: [CurveID: String] = [:]
        var surfaceNames: [SurfaceID: String] = [:]
        var curvePositionFrames: [CurveID: IndependentShapePositionFrame] = [:]
        var surfacePositionFrames: [SurfaceID: IndependentShapePositionFrame] = [:]
        var representationIDs: [Int: IndependentShapeRepresentationID] = [:]
        var contextByRepresentation: [Int: Int] = [:]
        var activeRepresentations = Set<Int>()
        var names: [Int: String] = [:]

        mutating func read(entityIDs: [Int], standaloneItems: [Int]) throws -> IndependentShapeSource? {
            try usage.charge(entities: entityIDs.count, work: entityIDs.count)
            let levels = entityIDs.isEmpty ? 0 : Int.bitWidth - entityIDs.count.leadingZeroBitCount
            try chargeProduct(entityIDs.count, levels + 1)
            let ids = entityIDs.sorted()
            var previous: Int?
            for id in ids {
                guard id > 0, previous != id else { throw invalid("STEP entity identity is malformed/duplicated.") }
                previous = id
                names[id] = try name(id)
                if isRepresentation(names[id]!) { representationIDs[id] = .init() }
            }
            for id in ids where names[id] == "GROUP" {
                let values = try args(id, count: 2)
                try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<IndependentShapeSTEPGroup>.stride)
                originalSTEPGroups[id] = .init(name: try string(values[0]),
                    description: values[1] == "$" ? nil : try string(values[1]))
            }
            for id in ids where names[id] == "APPLIED_GROUP_ASSIGNMENT" {
                let a = try args(id, count: 2)
                let group = try fields.reference(a[0])
                guard try cachedName(group) == "GROUP" else { throw invalid("Applied assignment does not select its real GROUP owner.") }
                try usage.charge(entities: 1, work: 1)
                guard originalSTEPGroups[group] != nil else { throw invalid("Missing original GROUP declaration.") }
                assignmentGroups[id] = group
            }
            guard !representationIDs.isEmpty || !standaloneItems.isEmpty || !assignmentGroups.isEmpty || !originalSTEPGroups.isEmpty else { return nil }
            for id in ids where representationIDs[id] != nil { _ = try representation(id, depth: 1) }
            for assignment in assignmentGroups.keys.sorted() { _ = try group(assignment, depth: 1) }
            for id in standaloneItems {
                try usage.charge(work: 1)
                // The parent's primitive-root scan also lists real representation members.
                // Their established context authority must not be replaced by ambient units.
                if items[id] != nil || sets[id] != nil || frames[id] != nil || instances[id] != nil { continue }
                _ = try member(id, units: standaloneUnits, originalAngularSource: ambientOriginalAngularSource, originalLengthSource: ambientOriginalLengthSource, depth: 1)
            }
            try validateRepresentationProfiles(ids)
            var incoming = Set<IndependentShapeReference>()
            for set in sets.values { for child in set.members { try usage.charge(work: 1); incoming.insert(.item(child)) } }
            for representation in representations.values { for child in representation.members { try usage.charge(work: 1); incoming.insert(child) } }
            for definition in definitions.values { try usage.charge(work: 1); incoming.insert(.representation(definition.representationID)) }
            for group in groups.values { for child in group.members { try usage.charge(work: 1); incoming.insert(child) } }
            for association in curvePositionFrames.values { try usage.charge(work: 1); incoming.insert(.frame(association.frameID)) }
            for association in surfacePositionFrames.values { try usage.charge(work: 1); incoming.insert(.frame(association.frameID)) }
            var roots: [IndependentShapeReference] = []
            for frame in frames.values { try appendRoot(.frame(frame.id), incoming: incoming, roots: &roots) }
            for item in items.values { try appendRoot(.item(item.id), incoming: incoming, roots: &roots) }
            for set in sets.values { try appendRoot(.geometricSet(set.id), incoming: incoming, roots: &roots) }
            for representation in representations.values { try appendRoot(.representation(representation.id), incoming: incoming, roots: &roots) }
            for instance in instances.values { try appendRoot(.instance(instance.id), incoming: incoming, roots: &roots) }
            for group in groups.values { try appendRoot(.group(group.id), incoming: incoming, roots: &roots) }
            try chargeProduct(items.count + sets.count + contexts.count + representations.count + frames.count + definitions.count + instances.count + groups.count + originalSTEPGroups.count + roots.count, levels + 1)
            let source = IndependentShapeSource(geometry: geometry, items: items.values.sorted { $0.id < $1.id },
                geometricSets: sets.values.sorted { $0.id < $1.id }, contexts: contexts.values.sorted { $0.id < $1.id }, ambientContexts: ambientContexts,
                representations: representations.values.sorted { $0.id < $1.id }, frames: frames.values.sorted { $0.id < $1.id }, definitions: definitions.values.sorted { $0.id < $1.id },
                curveNames: curveNames, surfaceNames: surfaceNames, curvePositionFrames: curvePositionFrames, surfacePositionFrames: surfacePositionFrames, surfaceAngularMeasures: surfaceAngularMeasures, curveLinearSources: curveLinearSources, curveSplineSources: curveSplineSources, surfaceSplineSources: surfaceSplineSources, groups: groups.values.sorted { $0.id < $1.id }, originalSTEPGroups: originalSTEPGroups.values.sorted { $0.id < $1.id },
                instances: instances.values.sorted { $0.id < $1.id }, productAssociations: productAssociations.sorted(), ambientOriginalAngularSource: ambientOriginalAngularSource, ambientOriginalLengthSource: ambientOriginalLengthSource, roots: roots.sorted())
            try validate(source)
            return source
        }
        mutating func validateRepresentationProfiles(_ ids: [Int]) throws {
            for id in ids {
                try usage.charge(work: 1)
                if names[id] == "SHAPE_DEFINITION_REPRESENTATION" {
                    let a = try args(id, count: 2), selected = try fields.reference(a[1])
                    if let representationID = representationIDs[selected] {
                        let owner = try fields.reference(a[0])
                        guard try cachedName(owner) == "PRODUCT_DEFINITION_SHAPE" else { throw invalid("Independent SDR requires its actual product-definition shape owner.") }
                        let shape = try args(owner, count: 3), definitionEntity = try fields.reference(shape[2])
                        guard try cachedName(definitionEntity) == "PRODUCT_DEFINITION", let definitionID = productDefinitions[definitionEntity] else {
                            throw invalid("Independent SDR product definition lacks actual parent correspondence.")
                        }
                        try usage.charge(entities: 1, work: 1)
                        productAssociations.append(.init(representationID: representationID, definitionID: definitionID))
                    }
                }
            }
            for (id, representation) in representations {
                try usage.charge(work: 1)
                let wire = try args(id, count: 3), members = try refs(wire[1])
                let family = names[id] ?? ""
                if family == "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION" || family == "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION" {
                    var directSurface = false
                    var hasGeometry = false
                    for member in members {
                        try usage.charge(work: 1)
                        let kind = try cachedName(member)
                        if kind == "MAPPED_ITEM" {
                            hasGeometry = true
                            let mapped = try args(member, count: 3), map = try fields.reference(mapped[1])
                            let definition = try args(map, count: 2), source = try fields.reference(definition[1])
                            guard names[source] == family else { throw invalid("Bounded representation maps a different family.") }
                            if family == "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION" {
                                let child = try args(source, count: 3)
                                var directSet = false
                                for item in try refs(child[1]) { try usage.charge(work: 1); if names[item] == "GEOMETRIC_SET" { directSet = true } }
                                guard directSet else { throw invalid("Bounded surface mapped representation lacks its direct geometric set.") }
                            }
                        } else if kind == "GEOMETRIC_SET" || kind == "GEOMETRIC_CURVE_SET" {
                            hasGeometry = true
                            guard family != "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION" || kind == "GEOMETRIC_CURVE_SET" else {
                                throw invalid("Bounded wireframe representation requires a geometric curve set.")
                            }
                            guard let set = sets[member] else { throw invalid("Missing bounded set.") }
                            for selection in set.members {
                                try usage.charge(work: items.count)
                                guard let item = items.values.first(where: { $0.id == selection }) else { throw invalid("Missing bounded selection.") }
                                if case .surface = item.geometry { directSurface = true }
                            }
                        } else if kind == "AXIS2_PLACEMENT_3D" {
                            guard frames[member] != nil else { throw invalid("Bounded representation lost its original frame member.") }
                        } else {
                            throw unsupported("Bounded representation has an independent non-geometry member.")
                        }
                    }
                    guard hasGeometry else { throw invalid("Bounded representation has no geometric set or mapped item.") }
                    if family == "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION", !directSurface {
                        throw invalid("Bounded surface representation lacks a direct set containing a surface.")
                    }
                }
                // Confirm the original context association, rather than selecting any equal-valued context.
                guard let contextID = contextByRepresentation[id], contexts[contextID]?.id == representation.contextID else {
                    throw invalid("Representation lost its original context association.")
                }
            }
        }
        mutating func appendRoot(_ reference: IndependentShapeReference, incoming: Set<IndependentShapeReference>, roots: inout [IndependentShapeReference]) throws {
            try usage.charge(work: 1)
            if !incoming.contains(reference) { try usage.charge(entities: 1); roots.append(reference) }
        }
        mutating func representation(_ id: Int, depth: Int) throws -> IndependentShapeReference {
            try checkDepth(depth)
            if let retained = representations[id] { return .representation(retained.id) }
            guard let sourceID = representationIDs[id] else { throw invalid("Missing real representation #\(id).") }
            try usage.charge(entities: 1, work: 1)
            guard activeRepresentations.insert(id).inserted else { throw invalid("Cyclic representation map.") }
            defer { activeRepresentations.remove(id) }
            let a = try args(id, count: 3)
            let contextEntity = try fields.reference(a[2])
            let context = try context(contextEntity)
            try usage.charge(entities: 1); contextByRepresentation[id] = contextEntity
            let entities = try refs(a[1])
            guard !entities.isEmpty else { throw invalid("Empty representation.") }
            var members: [IndependentShapeReference] = []
            for entity in entities { try usage.charge(entities: 1, work: 1); members.append(try member(entity, units: context.units, originalAngularSource: context.originalAngularSource, originalLengthSource: context.originalLengthSource, depth: depth + 1)) }
            try chargeProduct(members.count, Int.bitWidth - members.count.leadingZeroBitCount + 1)
            let sorted = members.sorted()
            try unique(sorted)
            guard let family = IndependentShapeRepresentationFamily(rawValue: try cachedName(id)) else { throw invalid("Unknown original representation family.") }
            let value = IndependentShapeRepresentation(id: sourceID, name: try string(a[0]), contextID: context.id, family: family, members: sorted)
            try usage.charge(entities: 1, work: 1); representations[id] = value
            return .representation(value.id)
        }
        mutating func context(_ id: Int) throws -> IndependentShapeContext {
            if let value = contexts[id] { return value }
            let a = try args(id, component: "REPRESENTATION_CONTEXT", count: 2)
            let dimension = try args(id, component: "GEOMETRIC_REPRESENTATION_CONTEXT", count: 1)
            guard dimension[0] == "3" else { throw unsupported("Independent geometry requires an original 3D context.") }
            let units = try producer.contextUnits(entityID: id, usage: &usage)
            let originalLengthSource = try producer.contextLengthSource(entityID: id, usage: &usage)
            let originalAngularSource = try producer.contextAngularSource(entityID: id, usage: &usage)
            let value = IndependentShapeContext(identifier: try string(a[0]), type: try string(a[1]), units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource)
            try usage.charge(entities: 1, work: 1); contexts[id] = value
            return value
        }
        mutating func member(_ id: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil, depth: Int) throws -> IndependentShapeReference {
            if let selector = bodySources[id] {
                try usage.charge(work: 1)
                guard selector.role == GeneratedSubshapeRole.body.rawValue else { throw invalid("Original heterogeneous member is not a Body selector.") }
                return .body(selector)
            }
            let name = try cachedName(id)
            switch name {
            case "GEOMETRIC_SET", "GEOMETRIC_CURVE_SET": return try geometricSet(id, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource)
            case "AXIS2_PLACEMENT_3D": return .frame(try frame(id, units: units, originalLengthSource: originalLengthSource).id)
            case "MAPPED_ITEM": return try instance(id, units: units, originalLengthSource: originalLengthSource, depth: depth)
            default: return try item(id, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource)
            }
        }
        mutating func geometricSet(_ id: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil) throws -> IndependentShapeReference {
            if let retained = sets[id] {
                for itemID in retained.members {
                    try usage.charge(work: items.count)
                    guard let wireID = items.first(where: { $0.value.id == itemID })?.key else {
                        throw invalid("Shared geometric set has missing original members.")
                    }
                    _ = try self.item(wireID, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource)
                }
                return .geometricSet(retained.id)
            }
            let a = try args(id, count: 2), list = try refs(a[1])
            guard !list.isEmpty else { throw invalid("Empty geometric set.") }
            var members: [IndependentShapeItemID] = []
            for wireID in list {
                let reference = try item(wireID, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource)
                guard case .item(let itemID) = reference else { throw invalid("Geometric set contains non-geometry.") }
                if names[id] == "GEOMETRIC_CURVE_SET", case .surface = items[wireID]!.geometry { throw invalid("Geometric curve set contains a surface.") }
                try usage.charge(entities: 1); members.append(itemID)
            }
            try chargeProduct(members.count, Int.bitWidth - members.count.leadingZeroBitCount + 1)
            let sorted = members.sorted(); try unique(sorted)
            guard let family = IndependentShapeGeometricSetFamily(rawValue: try cachedName(id)) else { throw invalid("Unknown original geometric set family.") }
            let set = IndependentShapeGeometricSet(name: try string(a[0]), family: family, members: sorted)
            try usage.charge(entities: 1); sets[id] = set
            return .geometricSet(set.id)
        }
        mutating func item(_ id: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil) throws -> IndependentShapeReference {
            let lengthGain = try originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &usage)
            let dependsOnAngle = try angularDependent(id, depth: 1)
            let angularGain: IndependentShapeAngularSource.CoordinateLaw? = dependsOnAngle
                ? try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &usage) : nil
            if let retained = items[id] {
                guard itemUnits[id]?.length == units.length, let previous = itemLengthGains[id],
                      try previous.subtracting(lengthGain, usage: &usage).isZero else {
                    throw invalid("Shared primitive has conflicting exact original length laws.")
                }
                if let angularGain, let retainedGain = itemAngularGains[id] {
                    guard try IndependentSTEPAngularLaw.equivalent(retainedGain, angularGain, usage: &usage) else {
                        throw invalid("Shared primitive has conflicting original angular coordinate laws.")
                    }
                }
                return .item(retained.id)
            }
            let n = try cachedName(id)
            let surfaceNames = ["PLANE", "CYLINDRICAL_SURFACE", "CONICAL_SURFACE", "SPHERICAL_SURFACE", "TOROIDAL_SURFACE", "B_SPLINE_SURFACE_WITH_KNOTS"]
            let complexSurface: Bool
            if n.isEmpty { complexSurface = try has(id, "B_SPLINE_SURFACE") } else { complexSurface = false }
            let isSurface = surfaceNames.contains(n) || complexSurface
            let value: IndependentShapeItem
            let label = try itemName(id)
            if isSurface {
                let original = try producer.surface(entityID: id, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource, tolerance: tolerance, usage: &usage)
                try usage.charge(work: 1)
                if let previous = surfaceBasisLengthGains[original.id] {
                    guard try previous.subtracting(lengthGain, usage: &usage).isZero else {
                        throw invalid("Shared original surface basis has conflicting exact length laws.")
                    }
                } else { try usage.charge(entities: 1); surfaceBasisLengthGains[original.id] = lengthGain }
                if let retainedUnit = surfaceBasisUnits[original.id] {
                    guard retainedUnit == units.length else {
                        throw invalid("One original surface basis is interpreted in conflicting length units.")
                    }
                } else {
                    try usage.charge(entities: 1, work: 1)
                    surfaceBasisUnits[original.id] = units.length
                }
                if let angularGain {
                    if let previous = surfaceBasisAngularGains[original.id] {
                        guard try IndependentSTEPAngularLaw.equivalent(previous, angularGain, usage: &usage) else {
                            throw invalid("Shared surface basis has conflicting original angular coordinate laws.")
                        }
                    } else { try usage.charge(entities: 1); surfaceBasisAngularGains[original.id] = angularGain }
                }
                try usage.charge(entities: 1, work: original.basisName.utf8.count)
                if let raw = original.splineSource {
                    try usage.charge(entities: 1, work: 1)
                    guard surfaceSplineSources[original.id] == nil || surfaceSplineSources[original.id] == raw else {
                        throw invalid("Shared original spline surface records conflict.")
                    }
                    surfaceSplineSources[original.id] = raw
                }
                if let measure = original.angularMeasure {
                    try usage.charge(entities: 1, work: 1)
                    guard surfaceAngularMeasures[original.id] == nil || surfaceAngularMeasures[original.id] == measure else {
                        throw invalid("Shared original angular surface measure conflicts.")
                    }
                    surfaceAngularMeasures[original.id] = measure
                }
                geometry.surfaces[original.id] = original.surface
                self.surfaceNames[original.id] = original.basisName
                if let positionID = original.positionEntityID {
                    let position = try frame(positionID, units: units, originalLengthSource: originalLengthSource)
                    let association = IndependentShapePositionFrame(frameID: position.id)
                    try usage.charge(entities: 1, work: 1)
                    guard surfacePositionFrames[original.id] == nil || surfacePositionFrames[original.id] == association else {
                        throw invalid("Shared original surface has conflicting position identity.")
                    }
                    surfacePositionFrames[original.id] = association
                }
                value = .init(name: label, geometry: .surface(original.id))
            } else {
                let original = try producer.curve(entityID: id, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource, tolerance: tolerance, usage: &usage)
                try usage.charge(work: 1)
                if let previous = curveBasisLengthGains[original.id] {
                    guard try previous.subtracting(lengthGain, usage: &usage).isZero else {
                        throw invalid("Shared original curve basis has conflicting exact length laws.")
                    }
                } else { try usage.charge(entities: 1); curveBasisLengthGains[original.id] = lengthGain }
                if let retainedUnit = curveBasisUnits[original.id] {
                    guard retainedUnit == units.length else {
                        throw invalid("One original curve basis is interpreted in conflicting length units.")
                    }
                } else {
                    try usage.charge(entities: 1, work: 1)
                    curveBasisUnits[original.id] = units.length
                }
                if let angularGain {
                    if let previous = curveBasisAngularGains[original.id] {
                        guard try IndependentSTEPAngularLaw.equivalent(previous, angularGain, usage: &usage) else {
                            throw invalid("Shared curve basis has conflicting original angular coordinate laws.")
                        }
                    } else { try usage.charge(entities: 1); curveBasisAngularGains[original.id] = angularGain }
                }
                try usage.charge(entities: 1, work: original.basisName.utf8.count)
                if let raw = original.linearSource {
                    try usage.charge(entities: 1, work: 1)
                    guard curveLinearSources[original.id] == nil || curveLinearSources[original.id] == raw else {
                        throw invalid("Shared original LINE records conflict.")
                    }
                    curveLinearSources[original.id] = raw
                }
                if let raw = original.splineSource {
                    try usage.charge(entities: 1, work: 1)
                    guard curveSplineSources[original.id] == nil || curveSplineSources[original.id] == raw else {
                        throw invalid("Shared original spline curve records conflict.")
                    }
                    curveSplineSources[original.id] = raw
                }
                geometry.curves[original.id] = original.curve; curveNames[original.id] = original.basisName
                if let positionID = original.positionEntityID {
                    let position = try frame(positionID, units: units, originalLengthSource: originalLengthSource)
                    let association = IndependentShapePositionFrame(frameID: position.id, parameterLengthUnit: original.parameterLengthUnit)
                    try usage.charge(entities: 1, work: 1)
                    guard curvePositionFrames[original.id] == nil || curvePositionFrames[original.id] == association else {
                        throw invalid("Shared original curve has conflicting position identity.")
                    }
                    curvePositionFrames[original.id] = association
                }
                value = .init(name: label, geometry: .curve(original.id, trim: original.trim), trimmingSource: original.trimmingSource, traversalSource: original.traversalSource)
            }
            try usage.charge(entities: 2); items[id] = value; itemUnits[id] = units; itemLengthGains[id] = lengthGain
            if let angularGain { try usage.charge(entities: 1); itemAngularGains[id] = angularGain }
            return .item(value.id)
        }
        mutating func angularDependent(_ id: Int, depth: Int) throws -> Bool {
            try checkDepth(depth)
            let name = try cachedName(id)
            if name == "TRIMMED_CURVE" {
                let fields = try args(id, count: 6)
                return try angularDependent(self.fields.reference(fields[1]), depth: depth + 1)
            }
            return ["CIRCLE", "ELLIPSE", "CYLINDRICAL_SURFACE", "CONICAL_SURFACE", "SPHERICAL_SURFACE", "TOROIDAL_SURFACE"].contains(name)
        }
        mutating func instance(_ id: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource?, depth: Int) throws -> IndependentShapeReference {
            try checkDepth(depth)
            if let value = instances[id] {
                guard instanceUnits[id]?.length == units.length, let retained = value.originalSTEPPlacement else {
                    throw invalid("Shared original instance has conflicting unit contexts.")
                }
                let previous = try retained.originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                    ?? ExactRationalCoefficient.originalDouble(retained.lengthUnit.toInternal(1), usage: &usage)
                let current = try originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                    ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &usage)
                guard try previous.subtracting(current, usage: &usage).isZero else {
                    throw invalid("Shared original instance has conflicting exact length laws.")
                }
                return .instance(value.id)
            }
            let a = try args(id, count: 3), map = try fields.reference(a[1])
            let definition: IndependentShapeDefinition
            if let value = definitions[map] { definition = value }
            else {
                guard try cachedName(map) == "REPRESENTATION_MAP" else { throw invalid("Mapped source is not a representation map.") }
                let m = try args(map, count: 2), source = try fields.reference(m[1])
                let reference = try representation(source, depth: depth + 2)
                try usage.charge(work: 1)
                guard case .representation(let representationID) = reference,
                      let contextEntity = contextByRepresentation[source], let originalContext = contexts[contextEntity] else {
                    throw invalid("Missing mapped representation context.")
                }
                let originID = try fields.reference(m[0])
                let origin = try frame(originID, units: originalContext.units, originalLengthSource: originalContext.originalLengthSource)
                definition = .init(representationID: representationID, originFrameID: origin.id)
                try usage.charge(entities: 1); definitions[map] = definition
            }
            let targetID = try fields.reference(a[2])
            let originalSource = try producer.mappingSource(entityID: targetID, units: units, originalLengthSource: originalLengthSource, usage: &usage)
            let placement = try originalSource.derivedAffineTransform(tolerance: tolerance, maximumDepth: usage.limits.maximumAlgebraicDepth, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)
            let value = IndependentShapeInstance(name: try string(a[0]), placementName: try itemName(targetID), target: definition.id, placement: placement, originalSTEPPlacement: originalSource)
            try usage.charge(entities: 1); instances[id] = value; instanceUnits[id] = units
            return .instance(value.id)
        }
        mutating func frame(_ id: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource?) throws -> IndependentShapeFrame {
            if let value = frames[id] {
                guard frameUnits[id]?.length == units.length, let retained = value.originalSTEPPlacement else {
                    throw invalid("Shared original frame has conflicting unit contexts.")
                }
                let previous = try retained.originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                    ?? ExactRationalCoefficient.originalDouble(retained.lengthUnit.toInternal(1), usage: &usage)
                let current = try originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                    ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &usage)
                guard try previous.subtracting(current, usage: &usage).isZero else {
                    throw invalid("Shared original frame has conflicting exact length laws.")
                }
                return value
            }
            guard try cachedName(id) == "AXIS2_PLACEMENT_3D" else { throw unsupported("Original mapping frame is not AXIS2_PLACEMENT_3D.") }
            let originalSource = try producer.mappingSource(entityID: id, units: units, originalLengthSource: originalLengthSource, usage: &usage)
            let placement = try originalSource.derivedAffineTransform(tolerance: tolerance, maximumDepth: usage.limits.maximumAlgebraicDepth, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)
            let value = IndependentShapeFrame(name: try itemName(id), placement: placement, originalSTEPPlacement: originalSource)
            try usage.charge(entities: 2, work: 1); frames[id] = value; frameUnits[id] = units
            return value
        }
        mutating func group(_ assignment: Int, depth: Int) throws -> IndependentShapeReference {
            try checkDepth(depth)
            if let value = groups[assignment] { return .group(value.id) }
            guard let groupID = assignmentGroups[assignment], try cachedName(groupID) == "GROUP" else { throw invalid("Missing real assigned GROUP.") }
            let g = try args(groupID, count: 2), a = try args(assignment, count: 2)
            let groupSourceID = IndependentShapeGroupID()
            // Reserve identity before descending; the source validator rejects an actual cyclic assignment graph.
            let identity = IndependentShapeGroup(id: groupSourceID, name: try string(g[0]),
                description: g[1] == "$" ? nil : try string(g[1]), members: [], originalSTEPGroupID: originalSTEPGroups[groupID]?.id)
            try usage.charge(entities: 1); groups[assignment] = identity
            var members: [IndependentShapeReference] = []
            for wireID in try refs(a[1]) {
                let reference: IndependentShapeReference
                if representationIDs[wireID] != nil { reference = try representation(wireID, depth: depth + 1) }
                else if assignmentGroups[wireID] != nil { reference = try group(wireID, depth: depth + 1) }
                else if let value = instances[wireID] { reference = .instance(value.id) }
                else if let value = sets[wireID] { reference = .geometricSet(value.id) }
                else if let value = frames[wireID] { reference = .frame(value.id) }
                else if let value = items[wireID] { reference = .item(value.id) }
                else { reference = try member(wireID, units: standaloneUnits, originalAngularSource: ambientOriginalAngularSource, originalLengthSource: ambientOriginalLengthSource, depth: depth + 1) }
                try usage.charge(entities: 1); members.append(reference)
            }
            guard !members.isEmpty else { throw invalid("Empty applied group assignment.") }
            try chargeProduct(members.count, Int.bitWidth - members.count.leadingZeroBitCount + 1)
            let sorted = members.sorted(); try unique(sorted)
            groups[assignment] = .init(id: groupSourceID, name: identity.name, description: identity.description, members: sorted, originalSTEPGroupID: identity.originalSTEPGroupID)
            return .group(groupSourceID)
        }
        mutating func validate(_ source: IndependentShapeSource) throws {
            let records = usage.limits.maximumEntities - usage.consumedEntities
            let work = usage.limits.maximumIterations - usage.consumedWork
            guard records > 0, work > 0 else { throw IndependentShapeExchangeError.resourceLimitExceeded("No remaining source validation allowance.") }
            let deadline = usage
            let result = try DefaultIndependentShapeSourceValidator().validate(source, tolerance: tolerance,
                limits: .init(maximumRecords: records, maximumTextBytes: usage.limits.maximumBytes - usage.consumedBytes,
                              maximumDepth: usage.limits.maximumNesting, maximumWork: work, maximumCurveSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth), bodySourceGraph: bodySourceGraph, check: { try deadline.check() })
            try usage.charge(entities: result.consumedRecords, work: result.consumedWork, bytes: result.consumedTextBytes)
        }
        mutating func name(_ id: Int) throws -> String { try scan(id); return try fields.name(id) }
        mutating func cachedName(_ id: Int) throws -> String {
            if let n = names[id] { return n }
            let n = try name(id); try usage.charge(entities: 1); names[id] = n; return n
        }
        mutating func scan(_ id: Int) throws { let e = try fields.entity(id); try usage.charge(work: e.utf8.count) }
        mutating func has(_ id: Int, _ component: String) throws -> Bool { try scan(id); return try fields.hasComponent(id, named: component) }
        mutating func args(_ id: Int, component: String? = nil, count: Int) throws -> [String] {
            try scan(id); let a = try fields.arguments(id, component: component)
            guard a.count == count else { throw invalid("Malformed independent entity #\(id).") }; return a
        }
        mutating func refs(_ value: String) throws -> [Int] { try usage.charge(work: value.utf8.count); return try fields.list(value) }
        mutating func itemName(_ id: Int) throws -> String {
            try scan(id)
            let component: String? = (try fields.name(id)).isEmpty ? "REPRESENTATION_ITEM" : nil
            let a = try fields.arguments(id, component: component)
            guard let name = a.first else { throw invalid("Missing original item name.") }; return try string(name)
        }
        mutating func string(_ value: String) throws -> String {
            let result = try fields.decodedString(value, limits: .init(maximumInputBytes: usage.limits.maximumBytes,
                maximumOutputBytes: usage.limits.maximumBytes, maximumWork: usage.limits.maximumIterations - usage.consumedWork))
            try usage.charge(work: result.consumedWork, bytes: result.consumedTextBytes); return result.value
        }
        mutating func unique<T: Equatable>(_ values: [T]) throws {
            guard values.count > 1 else { return }
            for index in 1..<values.count { try usage.charge(work: 1); guard values[index - 1] != values[index] else { throw invalid("Duplicate SET membership.") } }
        }
        mutating func checkDepth(_ depth: Int) throws {
            try usage.charge(work: 1)
            guard depth <= usage.limits.maximumNesting else { throw IndependentShapeExchangeError.resourceLimitExceeded("Independent STEP nesting ceiling.") }
        }
        mutating func chargeProduct(_ a: Int, _ b: Int) throws {
            let p = a.multipliedReportingOverflow(by: b)
            guard !p.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Independent STEP work overflow.") }
            try usage.charge(work: p.partialValue)
        }
        func isRepresentation(_ name: String) -> Bool {
            ["REPRESENTATION", "SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"].contains(name)
        }
        func invalid(_ message: String) -> IndependentShapeExchangeError { .invalidAssociation(message) }
        func unsupported(_ message: String) -> IndependentShapeExchangeError { .unsupportedSemantics(message) }
    }
}
