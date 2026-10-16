import Foundation
import CADCore
import CADIR
import CADGeometry

/// Emits real original geometry, 308 templates, 408 instances and original 402 group families.
public struct DefaultIndependentIGESGraphWriter: IndependentIGESGraphWriting {
    private let allowsReportedPlacementProjection: Bool
    private let allowsReportedGroupProjection: Bool
    public init() { allowsReportedPlacementProjection = false; allowsReportedGroupProjection = false }
    init(allowsReportedPlacementProjection: Bool, allowsReportedGroupProjection: Bool = false) { self.allowsReportedPlacementProjection = allowsReportedPlacementProjection; self.allowsReportedGroupProjection = allowsReportedGroupProjection }
    public func write(_ source: IndependentShapeSource, units: UnitSystem, tolerance: ModelingTolerance,
                      producer: inout any IndependentIGESGeometryWriting, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data {
        try usage.requireExecution(execution)
        try units.validate(); try tolerance.validate()
        // FIXME(INCOMPLETE_IMPLEMENTATION): Public IGES graph export has no product-definition association carrier.
        // Preserve actual source owners through a legal property transport or an explicit reported loss policy before admission.
        guard source.productAssociations.isEmpty else { throw IndependentShapeExchangeError.metadataLoss("IGES product-associated independent representations require original product transport.") }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original foreign angular descriptors and scalar source metadata lack their actual IGES property transport.
        // The public writer must emit legal retained properties or report an explicitly authorized loss before these original chains can succeed.
        guard source.ambientOriginalAngularSource == nil, source.ambientContexts.isEmpty, source.surfaceAngularMeasures.isEmpty else {
            throw IndependentShapeExchangeError.metadataLoss("Original angular descriptor/scalar source requires IGES property transport.")
        }
        guard source.originalSTEPGroups.isEmpty || allowsReportedGroupProjection else {
            throw IndependentShapeExchangeError.metadataLoss("IGES cannot retain separate original STEP GROUP declarations without admitted information loss.")
        }
        guard !source.items.isEmpty || !source.frames.isEmpty || !source.groups.isEmpty || !source.instances.isEmpty else {
            throw ExchangePreservationError.emptyRetainedSource
        }
        for context in source.contexts {
            try usage.charge(work: 1, using: &execution)
            guard context.originalAngularSource == nil else {
                throw IndependentShapeExchangeError.metadataLoss("Original context angular chain requires IGES property transport.")
            }
        }
        let remainingRecords = usage.limits.maximumEntities - usage.consumedEntities
        let remainingWork = usage.limits.maximumIterations - usage.consumedWork
        guard remainingRecords > 0, remainingWork > 0 else { throw IndependentShapeExchangeError.resourceLimitExceeded("No IGES source-validation allowance.") }
        _ = try DefaultIndependentShapeSourceValidator().validate(source, tolerance: tolerance,
            limits: .init(maximumRecords: remainingRecords, maximumTextBytes: usage.limits.maximumBytes - usage.consumedSourceTextBytes,
                          maximumDepth: usage.limits.maximumNesting, maximumWork: remainingWork, maximumCurveSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth), using: &execution)
        var builder = Builder(source: source, units: units, tolerance: tolerance, allowsReportedPlacementProjection: allowsReportedPlacementProjection, allowsReportedGroupProjection: allowsReportedGroupProjection, producer: producer, usage: usage, execution: consume execution)
        let result: Data
        do {
            result = try builder.write()
        } catch {
            producer = builder.producer
            execution = consume builder.execution
            throw error
        }
        producer = builder.producer
        execution = consume builder.execution
        return result
    }
    private struct Builder: ~Copyable {
        let source: IndependentShapeSource
        let units: UnitSystem
        let tolerance: ModelingTolerance
        let allowsReportedPlacementProjection: Bool
        let allowsReportedGroupProjection: Bool
        var producer: any IndependentIGESGeometryWriting
        let usage: IndependentShapeExchangeOwner
        var execution: OriginalQueryExecution
        var representations: [IndependentShapeRepresentationID: IndependentShapeRepresentation] = [:]
        var definitions: [IndependentShapeDefinitionID: IndependentShapeDefinition] = [:]
        var definitionByRepresentation: [IndependentShapeRepresentationID: IndependentShapeDefinitionID] = [:]
        var instances: [IndependentShapeInstanceID: IndependentShapeInstance] = [:]
        var groups: [IndependentShapeGroupID: IndependentShapeGroup] = [:]
        var wireFrames: [IndependentShapeFrameID: Int] = [:]
        var wireItems: [IndependentShapeItemID: Int] = [:]
        var wireDefinitions: [IndependentShapeDefinitionID: Int] = [:]
        var definitionDepths: [IndependentShapeDefinitionID: Int] = [:]
        var wireInstances: [IndependentShapeInstanceID: Int] = [:]
        var wireGroups: [IndependentShapeGroupID: Int] = [:]

        mutating func write() throws -> Data {
            try preflight()
            for frame in source.frames {
                let pointer = try producer.frame(frame, units: units, usage: usage, using: &execution)
                try usage.charge(entities: 1, using: &execution); wireFrames[frame.id] = pointer
            }
            for item in source.items {
                let entity: Int
                switch item.geometry {
                case .curve: entity = try producer.curve(item, source: source, units: units, usage: usage, using: &execution)
                case .surface: entity = try producer.surface(item, source: source, units: units, usage: usage, using: &execution)
                }
                try usage.charge(entities: 1, using: &execution); wireItems[item.id] = entity
            }
            for definition in source.definitions { _ = try definitionEntity(definition.id, depth: 1) }
            for instance in source.instances { _ = try instanceEntity(instance.id, depth: 1) }
            for group in source.groups { _ = try groupEntity(group.id, depth: 1) }
            // Groups now exist, so inverse pointers are attached without recursively traversing inverse links.
            for group in source.groups {
                guard let groupPointer = wireGroups[group.id] else { throw invalid("Missing emitted original group.") }
                for member in group.backPointerMembers {
                    let memberPointer = try reference(member, depth: 1)
                    try producer.appendGroupBackPointer(groupPointer: groupPointer, memberPointer: memberPointer, usage: usage, using: &execution)
                }
            }
            return try producer.finish(units: units, usage: usage, using: &execution)
        }
        mutating func preflight() throws {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original STEP-normalized frame laws
            // have no legal IGES source carrier here. The public IGES graph writer
            // must preserve the raw ratios/defaults/operation sequence before success.
            for frame in source.frames {
                try usage.charge(work: 1, using: &execution)
                guard frame.originalSTEPPlacement == nil else { throw loss("Original normalized STEP frame source is not retained by the IGES producer.") }
            }
            for instance in source.instances {
                try usage.charge(work: 1, using: &execution)
                guard instance.originalSTEPPlacement == nil else { throw loss("Original normalized STEP target source is not retained by the IGES producer.") }
            }
            try usage.charge(work: source.curvePositionFrames.count + source.surfacePositionFrames.count, using: &execution)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Independent public IGES export has no proven entity-identity carrier for retained STEP primitive AXIS2 positions.
            // Preserve the original shared position entity and label before these source associations can succeed; never emit an unrelated Type124 placeholder.
            for association in source.curvePositionFrames.values {
                try usage.charge(work: source.frames.count, using: &execution)
                guard source.frames.first(where: { $0.id == association.frameID })?.originalIGES != nil else {
                    throw IndependentShapeExchangeError.metadataLoss("Original STEP primitive position identity has no faithful IGES transport.")
                }
            }
            for association in source.surfacePositionFrames.values {
                try usage.charge(work: source.frames.count, using: &execution)
                guard source.frames.first(where: { $0.id == association.frameID })?.originalIGES != nil else {
                    throw IndependentShapeExchangeError.metadataLoss("Original STEP surface position identity has no faithful IGES transport.")
                }
            }
            for context in source.contexts {
                try usage.charge(work: context.identifier.utf8.count + context.type.utf8.count + 1, using: &execution)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent IGES egress cannot retain separately named representation contexts.
                // Prove a legal standard owner for distinct context identities/labels before several or named Native contexts succeed.
                guard source.contexts.count == 1, context.identifier.isEmpty, context.type.isEmpty, context.units == units else {
                    throw loss("IGES global units cannot retain this original representation context metadata.")
                }
            }
            // IGES402 is a logical group, not a separately typed STEP geometric-set selection owner.
            guard source.geometricSets.isEmpty else { throw loss("IGES has no retained distinct geometric-set selection owner in this profile.") }
            for representation in source.representations {
                try usage.charge(entities: 1, work: 1, using: &execution); representations[representation.id] = representation
            }
            for definition in source.definitions {
                try usage.charge(entities: 2, work: 1, using: &execution)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent IGES export has no faithful separate explicit mapping-origin law transport yet.
                // Retain its original frame, scope and inverse-origin semantics before accepting a nonnil originFrameID.
                guard definition.originFrameID == nil else { throw unsupported("IGES explicit definition origin is not retained.") }
                // A 308 is one template/member representation owner. Distinct Native maps cannot be collapsed by value.
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public IGES export has no faithful transport for distinct maps sharing a representation identity.
                // Establish a real standard association retaining both owners before accepting that Native sharing distinction.
                guard definitionByRepresentation[definition.representationID] == nil else { throw loss("Several map definitions select one representation in IGES.") }
                definitionByRepresentation[definition.representationID] = definition.id; definitions[definition.id] = definition
            }
            guard definitionByRepresentation.count == representations.count else { throw loss("A representation without a real IGES template definition is not retained.") }
            for instance in source.instances { try usage.charge(entities: 1, work: 1, using: &execution); instances[instance.id] = instance }
            for group in source.groups {
                try usage.charge(entities: 1, work: group.name.utf8.count + 1, using: &execution)
                // Form7 has a directory label and memberships, but no nullable description field.
                guard group.description == nil || allowsReportedGroupProjection else { throw loss("IGES original group has no description transport without admitted information loss.") }
                groups[group.id] = group
            }
            for item in source.items {
                try usage.charge(work: item.name.utf8.count + 1, using: &execution)
                let name: String?
                switch item.geometry { case .curve(let id, _): name = source.curveNames[id]; case .surface(let id): name = source.surfaceNames[id] }
                guard let name, name.utf8.elementsEqual(item.name.utf8) else { throw loss("IGES directory label cannot retain distinct or absent basis/selection names.") }
            }
            try validateRoots()
        }
        mutating func validateRoots() throws {
            var incoming = Set<IndependentShapeReference>()
            for representation in source.representations { for member in representation.members { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(member) } }
            for instance in source.instances {
                guard let definition = definitions[instance.target] else { throw invalid("Missing actual IGES instance definition.") }
                try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.representation(definition.representationID))
            }
            for association in source.curvePositionFrames.values { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(association.frameID)) }
            for association in source.surfacePositionFrames.values { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(association.frameID)) }
            for instance in source.instances {
                if let frameID = instance.originalIGES?.matrixFrameID { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(frameID)) }
            }
            for definition in source.definitions {
                if let frameID = definition.originalIGES?.definingFrameID { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(frameID)) }
            }
            for group in source.groups { for member in group.members { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(member) } }
            try usage.charge(entities: source.roots.count, work: source.roots.count, using: &execution)
            let roots = Set(source.roots)
            func check(_ reference: IndependentShapeReference) throws {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Independent public IGES export has no retained additional-root selector owner.
                // Retain a root also selected by another association before accepting extra Native root metadata.
                guard roots.contains(reference) == !incoming.contains(reference) else { throw IndependentShapeExchangeError.metadataLoss("Explicit source roots differ from IGES association roots.") }
            }
            for frame in source.frames { try usage.charge(work: 1, using: &execution); try check(.frame(frame.id)) }
            for item in source.items { try usage.charge(work: 1, using: &execution); try check(.item(item.id)) }
            for representation in source.representations { try usage.charge(work: 1, using: &execution); try check(.representation(representation.id)) }
            for instance in source.instances { try usage.charge(work: 1, using: &execution); try check(.instance(instance.id)) }
            for group in source.groups { try usage.charge(work: 1, using: &execution); try check(.group(group.id)) }
        }
        mutating func definitionEntity(_ id: IndependentShapeDefinitionID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let value = wireDefinitions[id] { return value }
            guard let definition = definitions[id], let representation = representations[definition.representationID] else { throw invalid("Missing IGES template source.") }
            var members: [String] = []
            var childDepth: Int?
            for member in representation.members {
                try usage.charge(entities: 1, work: 1, using: &execution)
                members.append(String(try reference(member, depth: depth + 1)))
                if let actual = try descendantTemplateDepth(member, depth: depth + 1) {
                    childDepth = max(childDepth ?? actual, actual)
                }
            }
            let actualDepth: Int
            if let childDepth {
                let next = childDepth.addingReportingOverflow(1)
                guard !next.overflow else { throw resource("IGES template depth overflow.") }; actualDepth = next.partialValue
            } else { actualDepth = 0 }
            let name = try producer.string(representation.name, usage: usage, using: &execution)
            try usage.charge(entities: members.count + 4, work: members.count + 4, using: &execution)
            let parameters = ["308", String(actualDepth), name, String(members.count)] + members
            let definingPointer: Int
            if let original = definition.originalIGES, !original.adjustments.isEmpty {
                guard allowsReportedPlacementProjection else { throw loss("Original IGES definition adjustment order/shared frame requires an admitted placement projection.") }
                let matrix = original.definingFrameID.flatMap { id in source.frames.first(where: { $0.id == id })?.originalIGES }
                try usage.charge(work: source.frames.count, using: &execution)
                let word = try original.originalOperationWord(frame: matrix, tolerance: tolerance,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
                definingPointer = try appendExactMatrix(word, label: "", unit: units.length, usage: usage, using: &execution, producer: &producer)
            } else if let frameID = definition.originalIGES?.definingFrameID {
                guard let pointer = wireFrames[frameID] else { throw invalid("Missing original IGES definition forward frame.") }
                definingPointer = pointer
            } else { definingPointer = 0 }
            let entity = try producer.appendEntity(type: 308, form: 0,
                label: definition.originalIGES?.directoryLabel ?? "", transformationPointer: definingPointer,
                parameters: parameters, usage: usage, using: &execution)
            try usage.charge(entities: 2, using: &execution); wireDefinitions[id] = entity; definitionDepths[id] = actualDepth
            return entity
        }
        mutating func instanceEntity(_ id: IndependentShapeInstanceID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let value = wireInstances[id] { return value }
            guard let instance = instances[id] else { throw invalid("Missing original IGES instance.") }
            let definition = try definitionEntity(instance.target, depth: depth + 1)
            let entity: Int
            if let original = instance.originalIGES {
                guard original.lengthUnit == units.length else { throw loss("Original IGES instance unit must retain the actual global unit.") }
                let matrixFrame = original.matrixFrameID.flatMap { id in source.frames.first(where: { $0.id == id }) }
                try usage.charge(work: source.frames.count, using: &execution)
                let matrix = matrixFrame?.originalIGES
                let matrixPointer: Int
                if let frameID = original.matrixFrameID {
                    guard let pointer = wireFrames[frameID], let matrixFrame,
                        matrixFrame.name.utf8.elementsEqual(instance.placementName.utf8) else { throw loss("Original IGES instance matrix identity/label is inconsistent.") }
                    matrixPointer = pointer
                } else {
                    guard instance.placementName.isEmpty else { throw loss("Absent original matrix cannot retain an unrelated matrix label.") }
                    matrixPointer = 0
                }
                var translation = original.translation
                if !original.adjustments.isEmpty {
                    guard allowsReportedPlacementProjection else { throw loss("Original IGES instance adjustment order requires an admitted placement projection.") }
                    let word = try original.originalOperationWord(matrix: matrix, tolerance: tolerance,
                        maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
                    let prepared = try word.prepared(usage: &execution)
                    let coefficients = try prepared.exactRationalCoefficients(usage: &execution)
                    let matrixCoefficients: [ExactRationalCoefficient]?
                    if let matrix {
                        let word = try matrix.originalOperationWord(tolerance: tolerance,
                            maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
                        matrixCoefficients = try word.prepared(usage: &execution).exactRationalCoefficients(usage: &execution)
                    } else { matrixCoefficients = nil }
                    let gain = try OriginalIGESScalarSource.lengthGain(units.length, using: &execution)
                    try usage.charge(bytes: 3 * MemoryLayout<String>.stride, using: &execution)
                    translation = []
                    for row in 0..<3 {
                        let originalTranslation = matrixCoefficients?[row * 4 + 3] ?? .zero
                        let parameter = try coefficients[row * 4 + 3].subtracting(originalTranslation, usage: &execution).divided(by: gain, usage: &execution)
                        translation.append(try OriginalIGESDecimalWriting.literal(parameter, usage: usage, using: &execution))
                    }
                }
                try usage.charge(work: 6, bytes: 6 * MemoryLayout<String>.stride, using: &execution)
                entity = try producer.appendEntity(type: 408, form: 0, label: instance.name, transformationPointer: matrixPointer,
                    parameters: ["408", String(definition), translation[0], translation[1], translation[2], original.scale], usage: usage, using: &execution)
            } else {
                entity = try producer.instancePlacement(instance, definitionPointer: definition, units: units, usage: usage, using: &execution)
            }
            try usage.charge(entities: 1, using: &execution); wireInstances[id] = entity
            return entity
        }
        mutating func groupEntity(_ id: IndependentShapeGroupID, depth: Int) throws -> Int {
            try checkDepth(depth)
            if let value = wireGroups[id] { return value }
            guard let group = groups[id] else { throw invalid("Missing original IGES group.") }
            guard group.originalSTEPGroupID == nil || allowsReportedGroupProjection else {
                throw loss("IGES group projection requires admitted loss of original STEP GROUP-owner sharing.")
            }
            var members: [String] = []
            for member in group.members { try usage.charge(entities: 1, work: 1, using: &execution); members.append(String(try reference(member, depth: depth + 1))) }
            try usage.charge(entities: members.count + 2, work: members.count + 2, using: &execution)
            let parameters = ["402", String(members.count)] + members
            let form: Int
            switch group.family {
            case .unordered: form = 7
            case .unorderedWithBackPointers: form = 1
            case .ordered: form = 15
            case .orderedWithBackPointers: form = 14
            }
            let entity = try producer.appendEntity(type: 402, form: form, label: group.name, transformationPointer: 0, parameters: parameters, usage: usage, using: &execution)
            try usage.charge(entities: 1, using: &execution); wireGroups[id] = entity
            return entity
        }
        mutating func reference(_ value: IndependentShapeReference, depth: Int) throws -> Int {
            switch value {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public IGES independent graph export lacks original parent Body entity correspondence.
            // Preserve heterogeneous group membership through the actual Body producer before publication can succeed.
            case .body: throw unsupported("Original heterogeneous IGES Body membership requires the parent source producer.")
            case .item(let id): guard let wire = wireItems[id] else { throw invalid("Missing original IGES selection.") }; return wire
            case .instance(let id): return try instanceEntity(id, depth: depth)
            case .group(let id): return try groupEntity(id, depth: depth)
            case .representation(let id):
                guard let definition = definitionByRepresentation[id] else { throw invalid("Direct IGES definition selection has no original definition owner.") }
                return try definitionEntity(definition, depth: depth + 1)
            case .frame(let id): guard let wire = wireFrames[id] else { throw invalid("Missing original IGES frame.") }; return wire
            case .geometricSet: throw loss("IGES distinct geometric-set association is not retained.")
            }
        }
        mutating func descendantTemplateDepth(_ reference: IndependentShapeReference, depth: Int) throws -> Int? {
            try checkDepth(depth)
            switch reference {
            case .instance(let id):
                guard let instance = instances[id], let actual = definitionDepths[instance.target] else { throw invalid("Missing nested template depth.") }
                return actual
            case .group(let id):
                guard let group = groups[id] else { throw invalid("Missing nested template group.") }
                var maximum: Int?
                for child in group.members {
                    if let actual = try descendantTemplateDepth(child, depth: depth + 1) { maximum = max(maximum ?? actual, actual) }
                }
                return maximum
            default: return nil
            }
        }
        mutating func checkDepth(_ depth: Int) throws {
            try usage.charge(work: 1, using: &execution)
            guard depth <= usage.limits.maximumNesting else { throw resource("IGES graph writer nesting ceiling.") }
        }
        func invalid(_ message: String) -> IndependentShapeExchangeError { .invalidAssociation(message) }
        func unsupported(_ message: String) -> IndependentShapeExchangeError { .unsupportedSemantics(message) }
        func loss(_ message: String) -> IndependentShapeExchangeError { .metadataLoss(message) }
        func resource(_ message: String) -> IndependentShapeExchangeError { .resourceLimitExceeded(message) }
    }
}

private func appendExactMatrix(_ word: OriginalAffineOperationWord, label: String, unit: LengthUnit,
    usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution, producer: inout any IndependentIGESGeometryWriting) throws -> Int {
    let coefficients = try word.prepared(usage: &execution).exactRationalCoefficients(usage: &execution)
    let gain = try OriginalIGESScalarSource.lengthGain(unit, using: &execution)
    try usage.charge(work: 13, bytes: 13 * MemoryLayout<String>.stride, using: &execution)
    var parameters = ["124"]; parameters.reserveCapacity(13)
    for index in coefficients.indices {
        let value = index % 4 == 3 ? try coefficients[index].divided(by: gain, usage: &execution) : coefficients[index]
        parameters.append(try OriginalIGESDecimalWriting.literal(value, usage: usage, using: &execution))
    }
    return try producer.appendEntity(type: 124, form: word.orientationSign > 0 ? 0 : 1,
        label: label, transformationPointer: 0, parameters: parameters, usage: usage, using: &execution)
}
