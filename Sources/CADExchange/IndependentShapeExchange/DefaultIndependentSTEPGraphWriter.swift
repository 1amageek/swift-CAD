import Foundation
import CADCore
import CADGeometry
import CADIR

public struct DefaultIndependentSTEPGraphWriter: IndependentSTEPGraphWriting {
    private let allowsGroupSemanticLoss: Bool
    public init() { allowsGroupSemanticLoss = false }
    init(allowingGroupSemanticLoss: Bool) { allowsGroupSemanticLoss = allowingGroupSemanticLoss }
    public func write(_ source: IndependentShapeSource, standaloneUnits: UnitSystem, tolerance: ModelingTolerance,
                      producer: inout any IndependentSTEPGeometryWriting,
                      usage: inout IndependentShapeExchangeUsage) throws -> Data {
        try append(source, standaloneUnits: standaloneUnits, tolerance: tolerance,
            producer: &producer, usage: &usage)
        return try producer.finish(usage: &usage)
    }

    public func append<Producer: IndependentSTEPGeometryWriting>(_ source: IndependentShapeSource,
        standaloneUnits: UnitSystem, tolerance: ModelingTolerance, productDefinitions: [AssemblyDefinitionID: Int] = [:],
        bodyBindings: [SubshapeID: IndependentSTEPBodyBinding] = [:], bodySourceGraph: DesignGraph? = nil,
        producer: inout Producer, usage: inout IndependentShapeExchangeUsage) throws {
        try standaloneUnits.validate(); try tolerance.validate()
        let records = usage.limits.maximumEntities - usage.consumedEntities
        let work = usage.limits.maximumIterations - usage.consumedWork
        guard records > 0, work > 0 else { throw IndependentShapeExchangeError.resourceLimitExceeded("No source validation allowance.") }
        let deadline = usage
        let validation = try DefaultIndependentShapeSourceValidator().validate(source, tolerance: tolerance,
            limits: .init(maximumRecords: records, maximumTextBytes: usage.limits.maximumBytes - usage.consumedBytes,
                          maximumDepth: usage.limits.maximumNesting, maximumWork: work, maximumCurveSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth), bodySourceGraph: bodySourceGraph, check: { try deadline.check() })
        try usage.charge(entities: validation.consumedRecords, work: validation.consumedWork, bytes: validation.consumedTextBytes)
        var builder = Builder(source: source, productDefinitions: productDefinitions, bodyBindings: bodyBindings, producer: producer, usage: usage, standaloneUnits: standaloneUnits, allowsGroupSemanticLoss: allowsGroupSemanticLoss)
        defer { producer = builder.producer; usage = builder.usage }
        try builder.author()
    }

    private struct Builder<Producer: IndependentSTEPGeometryWriting> {
        let source: IndependentShapeSource
        let productDefinitions: [AssemblyDefinitionID: Int]
        let bodyBindings: [SubshapeID: IndependentSTEPBodyBinding]
        var producer: Producer
        var usage: IndependentShapeExchangeUsage
        let standaloneUnits: UnitSystem
        let allowsGroupSemanticLoss: Bool
        var unitsByFrame: [IndependentShapeFrameID: UnitSystem] = [:]
        var wireFrames: [IndependentShapeFrameID: Int] = [:]
        var unitsByItem: [IndependentShapeItemID: UnitSystem] = [:]
        var angularGainsByItem: [IndependentShapeItemID: IndependentShapeAngularSource.CoordinateLaw] = [:]
        var lengthSourcesByItem: [IndependentShapeItemID: OriginalSTEPLengthSource] = [:]
        var lengthGainsByItem: [IndependentShapeItemID: ExactRationalCoefficient] = [:]
        var angularSourcesByItem: [IndependentShapeItemID: IndependentShapeAngularSource] = [:]
        var unitsBySet: [IndependentShapeSetID: UnitSystem] = [:]
        var unitsByInstance: [IndependentShapeInstanceID: UnitSystem] = [:]
        var wireItems: [IndependentShapeItemID: Int] = [:]
        var wireSets: [IndependentShapeSetID: Int] = [:]
        var wireRepresentations: [IndependentShapeRepresentationID: Int] = [:]
        var wireDefinitions: [IndependentShapeDefinitionID: Int] = [:]
        var wireInstances: [IndependentShapeInstanceID: Int] = [:]
        var wireGroups: [IndependentShapeGroupID: Int] = [:]
        var wireGroupOwners: [IndependentShapeSTEPGroupID: Int] = [:]
        var wireContexts: [IndependentShapeContextID: Int] = [:]
        var originalItems: [IndependentShapeItemID: IndependentShapeItem] = [:]
        var representations: [IndependentShapeRepresentationID: IndependentShapeRepresentation] = [:]
        var definitions: [IndependentShapeDefinitionID: IndependentShapeDefinition] = [:]
        var instances: [IndependentShapeInstanceID: IndependentShapeInstance] = [:]
        var sets: [IndependentShapeSetID: IndependentShapeGeometricSet] = [:]
        var contexts: [IndependentShapeContextID: IndependentShapeContext] = [:]
        var groups: [IndependentShapeGroupID: IndependentShapeGroup] = [:]

        mutating func author() throws {
            for item in source.items { try usage.charge(entities: 1, work: 1); originalItems[item.id] = item }
            for context in source.contexts { try usage.charge(entities: 1, work: 1); contexts[context.id] = context }
            for representation in source.representations { try usage.charge(entities: 1, work: 1); representations[representation.id] = representation }
            for definition in source.definitions { try usage.charge(entities: 1, work: 1); definitions[definition.id] = definition }
            for instance in source.instances { try usage.charge(entities: 1, work: 1); instances[instance.id] = instance }
            for set in source.geometricSets { try usage.charge(entities: 1, work: 1); sets[set.id] = set }
            for group in source.groups { try usage.charge(entities: 1, work: 1); groups[group.id] = group }
            try validateStandardRoots()
            // Assign units from actual representation membership before any geometry emission.
            for representation in source.representations {
                guard let context = contexts[representation.contextID] else { throw invalid("Missing representation context.") }
                for member in representation.members {
                    try usage.charge(work: 1)
                    switch member {
                    case .body(let selector):
                        guard let binding = bodyBindings[selector] else { throw invalid("Missing parent's original emitted Body correspondence.") }
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public mixed STEP egress still needs the parent Body producer for distinct original context units.
                        // Never bind coordinates emitted in another unit to this original representation context.
                        guard binding.lengthUnit == context.units.length else { throw unsupported("Original mixed Body context differs from the actual emitted coordinate unit.") }
                    case .item(let id): try bindItem(id, units: context.units, originalAngularSource: context.originalAngularSource, originalLengthSource: context.originalLengthSource)
                    case .geometricSet(let id):
                        guard let set = sets[id] else { throw invalid("Missing geometric set.") }
                        try usage.charge(entities: 1)
                        if let previous = unitsBySet[id], previous.length != context.units.length { throw unsupported("A shared geometric set has distinct unit contexts.") }
                        unitsBySet[id] = context.units
                        for item in set.members { try bindItem(item, units: context.units, originalAngularSource: context.originalAngularSource, originalLengthSource: context.originalLengthSource) }
                    case .frame(let id):
                        try usage.charge(entities: 1, work: 1)
                        if let previous = unitsByFrame[id], previous.length != context.units.length { throw unsupported("A shared original frame has distinct unit contexts.") }
                        unitsByFrame[id] = context.units
                    case .instance(let id):
                        try usage.charge(entities: 1)
                        if let previous = unitsByInstance[id], previous.length != context.units.length { throw unsupported("A shared mapped item has distinct target unit contexts.") }
                        unitsByInstance[id] = context.units
                    case .group:
                        throw unsupported("A group is not a STEP representation item.")
                    case .representation: throw invalid("Invalid representation membership.")
                    }
                }
            }
            // Primitive positions are real dependencies, not new independent frame roots.
            for item in source.items {
                try usage.charge(work: 1)
                let association: IndependentShapePositionFrame?
                switch item.geometry {
                case .curve(let id, _): association = source.curvePositionFrames[id]
                case .surface(let id): association = source.surfacePositionFrames[id]
                }
                if let association {
                    let units = unitsByItem[item.id] ?? standaloneUnits
                    try usage.charge(entities: 1, work: 1)
                    if let old = unitsByFrame[association.frameID], old.length != units.length {
                        throw unsupported("Original position frame has conflicting unit contexts.")
                    }
                    unitsByFrame[association.frameID] = units
                }
            }
            var needsStandaloneUnits = false
            for item in source.items { try usage.charge(work: 1); if unitsByItem[item.id] == nil { needsStandaloneUnits = true } }
            for frame in source.frames { try usage.charge(work: 1); if unitsByFrame[frame.id] == nil { needsStandaloneUnits = true } }
            for context in source.ambientContexts { _ = try producer.context(context, usage: &usage) }
            if needsStandaloneUnits && source.ambientContexts.isEmpty { _ = try producer.standaloneUnits(standaloneUnits, originalAngularSource: source.ambientOriginalAngularSource, originalLengthSource: source.ambientOriginalLengthSource, usage: &usage) }
            for context in source.contexts {
                let entity = try producer.context(context, usage: &usage)
                try usage.charge(entities: 1); wireContexts[context.id] = entity
            }
            for frame in source.frames {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original IGES lexical matrix source has no legal STEP identity/ordered source carrier in this producer.
                // Public STEP egress must preserve the source or obtain an explicit reported loss before success.
                guard frame.originalIGES == nil else { throw IndependentShapeExchangeError.metadataLoss("Original IGES matrix source requires its legal STEP carrier.") }
                let entity = try producer.mappingOrigin(frame.placement, originalSource: frame.originalSTEPPlacement, name: frame.name, units: unitsByFrame[frame.id] ?? standaloneUnits, usage: &usage)
                try usage.charge(entities: 1); wireFrames[frame.id] = entity
            }
            for item in source.items {
                try usage.charge(work: 1)
                let entity: Int, units = unitsByItem[item.id] ?? standaloneUnits
                switch item.geometry {
                case .curve(let id, _):
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Independent public STEP export cannot encode absent original basis-label metadata losslessly yet.
                    // Prove a legal optional standard carrier or use an explicit caller loss policy before missing labels can succeed.
                    guard source.curveNames[id] != nil else { throw IndependentShapeExchangeError.metadataLoss("Original curve basis label is absent.") }
                    entity = try producer.curve(item, source: source, units: units, originalAngularSource: angularSourcesByItem[item.id] ?? (unitsByItem[item.id] == nil ? source.ambientOriginalAngularSource : nil), originalLengthSource: lengthSourcesByItem[item.id] ?? (unitsByItem[item.id] == nil ? source.ambientOriginalLengthSource : nil), positionEntityID: source.curvePositionFrames[id].flatMap { wireFrames[$0.frameID] }, usage: &usage)
                case .surface(let id):
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Independent public STEP export cannot encode absent original surface basis-label metadata losslessly yet.
                    // A legal optional standard carrier or explicit caller loss policy must retain absence versus an empty label.
                    guard source.surfaceNames[id] != nil else { throw IndependentShapeExchangeError.metadataLoss("Original surface basis label is absent.") }
                    entity = try producer.surface(item, source: source, units: units, originalAngularSource: angularSourcesByItem[item.id] ?? (unitsByItem[item.id] == nil ? source.ambientOriginalAngularSource : nil), originalLengthSource: lengthSourcesByItem[item.id] ?? (unitsByItem[item.id] == nil ? source.ambientOriginalLengthSource : nil), positionEntityID: source.surfacePositionFrames[id].flatMap { wireFrames[$0.frameID] }, usage: &usage)
                }
                try usage.charge(entities: 1); wireItems[item.id] = entity
            }
            for set in source.geometricSets {
                var elements: [Int] = []
                for member in set.members {
                    try usage.charge(entities: 1, work: 1)
                    guard let entity = wireItems[member] else { throw invalid("Missing geometric set selection.") }; elements.append(entity)
                }
                let name = try producer.quotedString(set.name, usage: &usage)
                let expression = "\(set.family.rawValue)(\(name),\(try referenceList(elements)))"
                let entity = try producer.appendEntity(expression, usage: &usage)
                try usage.charge(entities: 1); wireSets[set.id] = entity
            }
            for representation in source.representations { _ = try representationEntity(representation.id, depth: 1) }
            for instance in source.instances { _ = try instanceEntity(instance.id, depth: 1) }
            for owner in source.originalSTEPGroups {
                try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<Int>.stride)
                let name = try producer.quotedString(owner.name, usage: &usage)
                let description = try owner.description.map { try producer.quotedString($0, usage: &usage) } ?? "$"
                wireGroupOwners[owner.id] = try producer.appendEntity("GROUP(\(name),\(description))", usage: &usage)
            }
            for group in source.groups { _ = try groupEntity(group.id, depth: 1) }
            for association in source.productAssociations {
                try usage.charge(work: 2)
                guard let definition = productDefinitions[association.definitionID], definition > 0,
                      let representation = wireRepresentations[association.representationID] else {
                    throw invalid("Independent product association lacks actual parent entity correspondence.")
                }
                let shape = try producer.appendEntity("PRODUCT_DEFINITION_SHAPE('','',#\(definition))", usage: &usage)
                _ = try producer.appendEntity("SHAPE_DEFINITION_REPRESENTATION(#\(shape),#\(representation))", usage: &usage)
            }
            try usage.check()
        }
        mutating func validateStandardRoots() throws {
            var incoming = Set<IndependentShapeReference>()
            for set in source.geometricSets { for child in set.members { try usage.charge(entities: 1, work: 1); incoming.insert(.item(child)) } }
            for representation in source.representations { for child in representation.members { try usage.charge(entities: 1, work: 1); incoming.insert(child) } }
            for definition in source.definitions { try usage.charge(entities: 1, work: 1); incoming.insert(.representation(definition.representationID)) }
            for group in source.groups { for child in group.members { try usage.charge(entities: 1, work: 1); incoming.insert(child) } }
            for association in source.curvePositionFrames.values { try usage.charge(entities: 1, work: 1); incoming.insert(.frame(association.frameID)) }
            for association in source.surfacePositionFrames.values { try usage.charge(entities: 1, work: 1); incoming.insert(.frame(association.frameID)) }
            try usage.charge(entities: source.roots.count, work: source.roots.count)
            let roots = Set(source.roots)
            func check(_ reference: IndependentShapeReference) throws {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export has no proved standard carrier for additional authored root selectors.
                // Preserve a root that is also selected by another standard association before accepting that Native-only distinction.
                guard roots.contains(reference) == !incoming.contains(reference) else {
                    throw IndependentShapeExchangeError.metadataLoss("Explicit source roots differ from the standard association roots.")
                }
            }
            for frame in source.frames { try usage.charge(work: 1); try check(.frame(frame.id)) }
            for item in source.items { try usage.charge(work: 1); try check(.item(item.id)) }
            for set in source.geometricSets { try usage.charge(work: 1); try check(.geometricSet(set.id)) }
            for representation in source.representations { try usage.charge(work: 1); try check(.representation(representation.id)) }
            for instance in source.instances { try usage.charge(work: 1); try check(.instance(instance.id)) }
            for group in source.groups { try usage.charge(work: 1); try check(.group(group.id)) }
        }
        mutating func bindItem(_ id: IndependentShapeItemID, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?) throws {
            try usage.charge(entities: 1, work: 1)
            if let previous = unitsByItem[id], previous.length != units.length {
                throw unsupported("One original item has conflicting STEP length units.")
            }
            guard let item = originalItems[id] else { throw invalid("Original item binding is missing.") }
            let lengthGain = try originalLengthSource?.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &usage)
            if let previous = lengthGainsByItem[id] {
                guard try previous.subtracting(lengthGain, usage: &usage).canonicalSign == 0 else {
                    throw unsupported("One original item has conflicting exact STEP length laws.")
                }
            } else { try usage.charge(entities: 1); lengthGainsByItem[id] = lengthGain }
            lengthSourcesByItem[id] = originalLengthSource
            let depends: Bool
            switch item.geometry {
            case .curve(let id, _):
                guard let curve = source.geometry.curves[id] else { throw invalid("Original bound curve is missing.") }
                depends = try IndependentSTEPAngularLaw.usesAngularCoordinates(curve: curve, usage: &usage)
            case .surface(let id):
                guard let surface = source.geometry.surfaces[id] else { throw invalid("Original bound surface is missing.") }
                depends = try IndependentSTEPAngularLaw.usesAngularCoordinates(surface: surface, usage: &usage)
            }
            if depends {
                let gain = try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &usage)
                if let previous = angularGainsByItem[id] {
                    guard try IndependentSTEPAngularLaw.equivalent(previous, gain, usage: &usage) else {
                        throw unsupported("One original item has conflicting angular coordinate laws.")
                    }
                } else { try usage.charge(entities: 1); angularGainsByItem[id] = gain }
            }
            unitsByItem[id] = units
            angularSourcesByItem[id] = originalAngularSource
        }
        mutating func representationEntity(_ id: IndependentShapeRepresentationID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let retained = wireRepresentations[id] { return retained }
            guard let representation = representations[id], let context = wireContexts[representation.contextID] else { throw invalid("Missing representation source/context.") }
            var items: [Int] = []
            for member in representation.members { try usage.charge(entities: 1, work: 1); items.append(try reference(member, depth: depth + 1)) }
            let name = try producer.quotedString(representation.name, usage: &usage)
            // Product correspondence, when present, is emitted from actual source associations below.
            // AP242's representation membership remains the original selected graph, including nested maps.
            let entity = try producer.appendEntity("\(representation.family.rawValue)(\(name),\(try referenceList(items)),#\(context))", usage: &usage)
            try usage.charge(entities: 1); wireRepresentations[id] = entity
            return entity
        }
        mutating func definitionEntity(_ id: IndependentShapeDefinitionID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let retained = wireDefinitions[id] { return retained }
            guard let definition = definitions[id], let representation = representations[definition.representationID] else { throw invalid("Missing map definition.") }
            // FIXME(INCOMPLETE_IMPLEMENTATION): STEP publication needs a legal source carrier for the original IGES forward definition and distinct DE label.
            // A REPRESENTATION_MAP inverse origin must not replace that forward operation or discard the retained label.
            guard definition.originalIGES == nil else { throw IndependentShapeExchangeError.metadataLoss("Original IGES definition needs its legal STEP carrier.") }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP export cannot retain an implicit-identity map origin without adding a source frame.
            // Prove a legal standard absence transport before IGES-origin nil can succeed; never synthesize a frame/membership.
            guard let originID = definition.originFrameID else { throw IndependentShapeExchangeError.metadataLoss("Implicit mapping origin has no faithful STEP transport.") }
            guard let origin = wireFrames[originID] else { throw invalid("Missing original mapping frame.") }
            let source = try representationEntity(representation.id, depth: depth + 1)
            let entity = try producer.appendEntity("REPRESENTATION_MAP(#\(origin),#\(source))", usage: &usage)
            try usage.charge(entities: 1); wireDefinitions[id] = entity
            return entity
        }
        mutating func instanceEntity(_ id: IndependentShapeInstanceID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let retained = wireInstances[id] { return retained }
            guard let instance = instances[id] else { throw invalid("Missing mapped instance.") }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original IGES408 scale/matrix/translation law lacks a STEP source carrier.
            // Public egress must preserve every original factor before this family can succeed.
            guard instance.originalIGES == nil else { throw IndependentShapeExchangeError.metadataLoss("Original IGES instance source requires its legal STEP carrier.") }
            let definition = try definitionEntity(instance.target, depth: depth + 1)
            let target = try producer.mappingTarget(instance.placement, originalSource: instance.originalSTEPPlacement, name: instance.placementName, units: unitsByInstance[id] ?? standaloneUnits, usage: &usage)
            let name = try producer.quotedString(instance.name, usage: &usage)
            let entity = try producer.appendEntity("MAPPED_ITEM(\(name),#\(definition),#\(target))", usage: &usage)
            try usage.charge(entities: 1); wireInstances[id] = entity
            return entity
        }
        mutating func groupEntity(_ id: IndependentShapeGroupID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let retained = wireGroups[id] { return retained }
            guard let group = groups[id] else { throw invalid("Missing group assignment.") }
            guard allowsGroupSemanticLoss || (group.family == .unordered && group.backPointerMembers.isEmpty) else {
                throw IndependentShapeExchangeError.metadataLoss("STEP set assignment cannot retain original ordered or inverse-pointer group semantics.")
            }
            let name = try producer.quotedString(group.name, usage: &usage)
            let description: String
            if let text = group.description { description = try producer.quotedString(text, usage: &usage) } else { description = "$" }
            let owner: Int
            if let sourceID = group.originalSTEPGroupID, let existing = wireGroupOwners[sourceID] {
                owner = existing
            } else {
                owner = try producer.appendEntity("GROUP(\(name),\(description))", usage: &usage)
                guard group.originalSTEPGroupID == nil else { throw invalid("Missing emitted original GROUP owner.") }
            }
            var members: [Int] = []
            var emitted: Set<Int> = []
            for member in group.members {
                try usage.charge(entities: 1, work: 1, bytes: 2 * MemoryLayout<Int>.stride)
                let target = try reference(member, depth: depth + 1)
                if emitted.insert(target).inserted { members.append(target) }
            }
            let assignment = try producer.appendEntity("APPLIED_GROUP_ASSIGNMENT(#\(owner),\(try referenceList(members)))", usage: &usage)
            try usage.charge(entities: 1); wireGroups[id] = assignment
            return assignment
        }
        mutating func reference(_ ref: IndependentShapeReference, depth: Int) throws -> Int {
            switch ref {
            case .body(let selector): guard let binding = bodyBindings[selector] else { throw invalid("Missing original emitted Body selection.") }; return binding.entityID
            case .item(let id): guard let entity = wireItems[id] else { throw invalid("Missing item selection.") }; return entity
            case .frame(let id): guard let entity = wireFrames[id] else { throw invalid("Missing original frame.") }; return entity
            case .geometricSet(let id): guard let entity = wireSets[id] else { throw invalid("Missing geometric set.") }; return entity
            case .representation(let id): return try representationEntity(id, depth: depth)
            case .instance(let id): return try instanceEntity(id, depth: depth)
            case .group(let id): return try groupEntity(id, depth: depth)
            }
        }
        mutating func referenceList(_ ids: [Int]) throws -> String {
            // Every decimal ID uses at most 20 characters plus one separator and the two tuple delimiters.
            let amount = ids.count.multipliedReportingOverflow(by: 21)
            let capacity = amount.partialValue.addingReportingOverflow(2)
            guard !amount.overflow, !capacity.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("STEP reference-list size overflow.") }
            try usage.charge(work: amount.partialValue)
            var value = "("; value.reserveCapacity(capacity.partialValue)
            for (index, id) in ids.enumerated() { if index > 0 { value += "," }; value += "#\(id)" }
            value += ")"; return value
        }
        mutating func checkDepth(_ depth: Int) throws {
            try usage.charge(work: 1)
            guard depth <= usage.limits.maximumNesting else { throw IndependentShapeExchangeError.resourceLimitExceeded("Independent STEP writer nesting ceiling.") }
        }
        func invalid(_ value: String) -> IndependentShapeExchangeError { .invalidAssociation(value) }
        func unsupported(_ value: String) -> IndependentShapeExchangeError { .unsupportedSemantics(value) }
    }
}
