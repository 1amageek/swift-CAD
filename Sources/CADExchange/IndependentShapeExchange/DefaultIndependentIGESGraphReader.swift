import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Reconstructs real 308/408/402 associations without a Body or value-based deduplication.
public struct DefaultIndependentIGESGraphReader: IndependentIGESGraphReading {
    public init() {}
    public func read(entityPointers: [Int], standaloneItemPointers: [Int], fields: any IndependentIGESFieldReading,
                     units: UnitSystem, tolerance: ModelingTolerance, producer: inout any IndependentIGESGeometryReading,
                     usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentShapeSource? {
        try usage.requireExecution(execution)
        try units.validate(); try tolerance.validate()
        var builder = Builder(fields: fields, units: units, tolerance: tolerance, producer: producer, usage: usage, execution: consume execution)
        let result: IndependentShapeSource?
        do {
            result = try builder.read(entityPointers, standalone: standaloneItemPointers)
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
        let fields: any IndependentIGESFieldReading
        let units: UnitSystem
        let tolerance: ModelingTolerance
        var producer: any IndependentIGESGeometryReading
        let usage: IndependentShapeExchangeOwner
        var execution: OriginalQueryExecution
        var geometry = GeometryStore()
        var items: [Int: IndependentShapeItem] = [:]
        var frames: [Int: IndependentShapeFrame] = [:]
        var representations: [Int: IndependentShapeRepresentation] = [:]
        var definitions: [Int: IndependentShapeDefinition] = [:]
        var groups: [Int: IndependentShapeGroup] = [:]
        var instances: [Int: IndependentShapeInstance] = [:]
        var curveNames: [CurveID: String] = [:]
        var surfaceNames: [SurfaceID: String] = [:]
        var curvePositions: [CurveID: IndependentShapePositionFrame] = [:]
        var surfacePositions: [SurfaceID: IndependentShapePositionFrame] = [:]
        var active = Set<Int>()
        var context: IndependentShapeContext?
        var declaredDepth: [Int: Int] = [:]

        mutating func read(_ pointers: [Int], standalone: [Int]) throws -> IndependentShapeSource? {
            try usage.charge(entities: pointers.count, work: pointers.count, using: &execution)
            try sortWork(pointers.count)
            let sorted = pointers.sorted()
            var previous: Int?
            var relevant = false
            for pointer in sorted {
                try usage.charge(work: 1, using: &execution)
                guard pointer > 0, pointer % 2 == 1, previous != pointer else { throw invalid("Malformed/duplicate IGES directory identity.") }
                previous = pointer
                let e = try entity(pointer)
                if e.type == 308 || e.type == 408 || e.type == 402 { relevant = true }
            }
            guard relevant || !standalone.isEmpty else { return nil }
            for pointer in sorted {
                let e = try entity(pointer)
                if e.type == 308 { _ = try definition(pointer, depth: 1) }
                else if e.type == 408 || e.type == 402 { _ = try reference(pointer, depth: 1) }
            }
            for pointer in standalone { _ = try reference(pointer,depth:1) }
            // Every retained inverse group link must select its actual original member.
            for pointer in sorted {
                let member = try entity(pointer)
                for groupPointer in member.associationPointers {
                    try usage.charge(work: 1, using: &execution)
                    let owner = try entity(groupPointer)
                    guard owner.type == 402, [1, 7, 14, 15].contains(owner.form) else { continue }
                    var found = false
                    for token in owner.parameters.dropFirst(2) {
                        try usage.charge(work: 1, using: &execution)
                        if try integer(token) == pointer { found = true; break }
                    }
                    guard found else { throw invalid("IGES group backpointer selects an entity outside its members.") }
                }
            }
            var incoming = Set<IndependentShapeReference>()
            for representation in representations.values { for member in representation.members { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(member) } }
            for instance in instances.values {
                try usage.charge(work: definitions.count, using: &execution)
                guard let definition = definitions.values.first(where: { $0.id == instance.target }) else { throw invalid("Missing real IGES instance definition.") }
                try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.representation(definition.representationID))
            }
            for association in curvePositions.values { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(association.frameID)) }
            for association in surfacePositions.values { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(association.frameID)) }
            for instance in instances.values {
                if let frameID = instance.originalIGES?.matrixFrameID { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(frameID)) }
            }
            for definition in definitions.values {
                if let frameID = definition.originalIGES?.definingFrameID { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(.frame(frameID)) }
            }
            for group in groups.values { for member in group.members { try usage.charge(entities: 1, work: 1, using: &execution); incoming.insert(member) } }
            var roots: [IndependentShapeReference] = []
            for frame in frames.values { try root(.frame(frame.id), incoming, into: &roots) }
            for item in items.values { try root(.item(item.id), incoming, into: &roots) }
            for representation in representations.values { try root(.representation(representation.id), incoming, into: &roots) }
            for group in groups.values { try root(.group(group.id), incoming, into: &roots) }
            for instance in instances.values { try root(.instance(instance.id), incoming, into: &roots) }
            try sortWork(items.count + frames.count + representations.count + definitions.count + groups.count + instances.count + roots.count)
            let source = IndependentShapeSource(geometry: geometry, items: items.values.sorted { $0.id < $1.id },
                contexts: context.map { [$0] } ?? [], representations: representations.values.sorted { $0.id < $1.id },
                frames: frames.values.sorted { $0.id < $1.id }, definitions: definitions.values.sorted { $0.id < $1.id }, curveNames: curveNames, surfaceNames: surfaceNames,
                curvePositionFrames: curvePositions, surfacePositionFrames: surfacePositions,
                groups: groups.values.sorted { $0.id < $1.id }, instances: instances.values.sorted { $0.id < $1.id }, roots: roots.sorted())
            let remainingRecords = usage.limits.maximumEntities - usage.consumedEntities
            let remainingWork = usage.limits.maximumIterations - usage.consumedWork
            guard remainingRecords > 0, remainingWork > 0 else { throw resource("No IGES source-validation allowance.") }
                _ = try DefaultIndependentShapeSourceValidator().validate(source, tolerance: tolerance,
                limits: .init(maximumRecords: remainingRecords, maximumTextBytes: usage.limits.maximumBytes - usage.consumedSourceTextBytes,
                              maximumDepth: usage.limits.maximumNesting, maximumWork: remainingWork, maximumCurveSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth), using: &execution)
                return source
        }
        mutating func definition(_ pointer: Int, depth: Int) throws -> IndependentShapeDefinition {
            try checkDepth(depth)
            if let value = definitions[pointer] { return value }
            let e = try entity(pointer)
            guard e.type == 308, e.form == 0, e.parameters.count >= 4 else { throw invalid("Malformed original IGES308 definition.") }
            try enter(pointer)
            defer { active.remove(pointer) }
            let stated = try integer(e.parameters[1]), count = try integer(e.parameters[3])
            guard stated >= 0, count > 0 else { throw invalid("IGES308 requires nonnegative depth and real members.") }
            try exactCount(count, base: 4, actual: e.parameters.count)
            try usage.charge(entities: count, work: count, using: &execution)
            var members: [IndependentShapeReference] = []
            var childDepth: Int?
            for index in 0..<count {
                let child = try integer(e.parameters[index + 4])
                members.append(try reference(child, depth: depth + 1))
                if let value = try descendantTemplateDepth(members[members.count - 1], depth: depth + 1) {
                    childDepth = max(childDepth ?? value, value)
                }
            }
            let expectedDepth: Int
            if let childDepth {
                let next = childDepth.addingReportingOverflow(1)
                guard !next.overflow else { throw resource("IGES subfigure depth overflow.") }
                expectedDepth = next.partialValue
            } else { expectedDepth = 0 }
            guard stated == expectedDepth else { throw invalid("IGES308 declared depth disagrees with actual nested definitions.") }
            try sortWork(members.count); let sorted = members.sorted(); try unique(sorted)
            let context: IndependentShapeContext
            if let retained = self.context { context = retained }
            else {
                // Global model units are a real implicit IGES representation context; no authored context labels exist.
                context = .init(identifier: "", type: "", units: units)
                try usage.charge(entities: 1, using: &execution); self.context = context
            }
            let representation = IndependentShapeRepresentation(name: try string(e.parameters[2]), contextID: context.id, members: sorted)
            let definingFrameID: IndependentShapeFrameID?
            if e.transformationPointer == 0 { definingFrameID = nil }
            else {
                guard case .frame(let frameID) = try reference(e.transformationPointer, depth: depth + 1) else {
                    throw invalid("IGES308 defining matrix must select its actual Type124 frame.")
                }
                definingFrameID = frameID
            }
            let value = IndependentShapeDefinition(representationID: representation.id, originFrameID: nil,
                originalIGES: .init(directoryLabel: e.label, definingFrameID: definingFrameID))
            try usage.charge(entities: 3, work: 1, using: &execution)
            representations[pointer] = representation; definitions[pointer] = value; declaredDepth[pointer] = stated
            return value
        }
        mutating func reference(_ pointer: Int, depth: Int) throws -> IndependentShapeReference {
            try checkDepth(depth)
            let e = try entity(pointer)
            switch e.type {
            case 308:
                let original = try definition(pointer, depth: depth + 1)
                return .representation(original.representationID)
            case 408:
                if let value = instances[pointer] { return .instance(value.id) }
                guard e.form == 0, e.parameters.count == 6 else { throw invalid("Malformed IGES408 instance.") }
                try enter(pointer); defer { active.remove(pointer) }
                let selected = try definition(integer(e.parameters[1]), depth: depth + 1)
                let matrixFrameID: IndependentShapeFrameID?
                let matrixSource: OriginalIGESMatrixSource?
                if e.transformationPointer == 0 { matrixFrameID = nil; matrixSource = nil }
                else {
                    guard case .frame(let frameID) = try reference(e.transformationPointer, depth: depth + 1),
                          let frame = frames[e.transformationPointer], let original = frame.originalIGES else {
                        throw invalid("Original IGES408 matrix source is absent.")
                    }
                    matrixFrameID = frameID; matrixSource = original
                }
                try usage.charge(bytes: 3 * MemoryLayout<String>.stride, using: &execution)
                let original = OriginalIGESInstanceSource(matrixFrameID: matrixFrameID, scale: e.parameters[5],
                    translation: [e.parameters[2], e.parameters[3], e.parameters[4]], lengthUnit: units.length)
                let placement = try original.derivedAffineTransform(matrix: matrixSource, tolerance: tolerance,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
                let label: String
                if e.transformationPointer == 0 { label = "" }
                else { label = try entity(e.transformationPointer).label }
                let value = IndependentShapeInstance(name: e.label, placementName: label, target: selected.id, placement: placement, originalIGES: original)
                try usage.charge(entities: 1, using: &execution); instances[pointer] = value
                return .instance(value.id)
            case 402:
                if let value = groups[pointer] { return .group(value.id) }
                guard [1, 7, 14, 15].contains(e.form), e.transformationPointer == 0, e.parameters.count >= 2 else {
                    throw unsupported("Independent IGES group requires its actual standard family and no defining transform.")
                }
                let family: IndependentShapeGroupFamily
                switch e.form {
                case 1: family = .unorderedWithBackPointers
                case 7: family = .unordered
                case 14: family = .orderedWithBackPointers
                default: family = .ordered
                }
                try enter(pointer); defer { active.remove(pointer) }
                let count = try integer(e.parameters[1])
                guard count > 0 else { throw invalid("Empty IGES group.") }
                try exactCount(count, base: 2, actual: e.parameters.count)
                try usage.charge(entities: count, work: count, using: &execution)
                var members: [IndependentShapeReference] = [], inverse: [IndependentShapeReference] = []
                try usage.charge(bytes: count * 2 * MemoryLayout<IndependentShapeReference>.stride, using: &execution)
                for index in 0..<count {
                    let memberPointer = try integer(e.parameters[index + 2])
                    let member = try reference(memberPointer, depth: depth + 1)
                    members.append(member)
                    let originalMember = try entity(memberPointer)
                    var hasInverse = false
                    for target in originalMember.associationPointers {
                        try usage.charge(work: 1, using: &execution)
                        if target == pointer {
                            guard !hasInverse else { throw invalid("Duplicate original IGES group backpointer.") }
                            hasInverse = true
                        }
                    }
                    guard hasInverse || !family.requiresBackPointers else { throw invalid("Required original IGES group backpointer is absent.") }
                    if hasInverse { inverse.append(member) }
                }
                if !family.isOrdered { try sortWork(count); members.sort(); try unique(members) }
                try sortWork(inverse.count); inverse.sort()
                var distinctInverse: [IndependentShapeReference] = []
                try usage.charge(bytes: inverse.count * MemoryLayout<IndependentShapeReference>.stride, using: &execution)
                for member in inverse {
                    try usage.charge(work: 1, using: &execution)
                    if distinctInverse.last != member { distinctInverse.append(member) }
                }
                let value = IndependentShapeGroup(name: e.label, description: nil, members: members,
                    family: family, backPointerMembers: distinctInverse)
                try usage.charge(entities: 1, using: &execution); groups[pointer] = value
                return .group(value.id)
            case 124:
                if let frame = frames[pointer] { return .frame(frame.id) }
                guard (e.form == 0 || e.form == 1), e.transformationPointer == 0, e.parameters.count == 13 else {
                    throw invalid("Original IGES124 requires twelve coefficients and its legal nonnested form.")
                }
                try usage.charge(bytes: 12 * MemoryLayout<String>.stride, using: &execution)
                let original = OriginalIGESMatrixSource(coefficients: Array(e.parameters.dropFirst()), form: e.form, lengthUnit: units.length)
                let placement = try original.derivedAffineTransform(tolerance: tolerance,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, using: &execution)
                let frame = IndependentShapeFrame(name: e.label, placement: placement, originalIGES: original)
                try usage.charge(entities: 1, using: &execution); frames[pointer] = frame
                return .frame(frame.id)
            default: return try item(pointer)
            }
        }
        mutating func descendantTemplateDepth(_ reference: IndependentShapeReference, depth: Int) throws -> Int? {
            try checkDepth(depth)
            switch reference {
            case .instance(let id):
                try usage.charge(work: instances.count + definitions.count + declaredDepth.count, using: &execution)
                guard let instance = instances.values.first(where: { $0.id == id }),
                      let definition = definitions.first(where: { $0.value.id == instance.target }),
                      let actual = declaredDepth[definition.key] else { throw invalid("Missing child subfigure depth.") }
                return actual
            case .group(let id):
                try usage.charge(work: groups.count, using: &execution)
                guard let group = groups.values.first(where: { $0.id == id }) else { throw invalid("Missing child subfigure group.") }
                var maximum: Int?
                for child in group.members {
                    if let actual = try descendantTemplateDepth(child, depth: depth + 1) { maximum = max(maximum ?? actual, actual) }
                }
                return maximum
            default: return nil
            }
        }
        mutating func item(_ pointer: Int) throws -> IndependentShapeReference {
            if let value = items[pointer] { return .item(value.id) }
            let e = try entity(pointer)
            let value: IndependentShapeItem
            if [128,140,190,192,194,196,198].contains(e.type) {
                let original = try producer.surface(entityPointer: pointer, units: units, tolerance: tolerance, usage: usage, using: &execution)
                try usage.charge(entities: 2, work: original.basisName.utf8.count, using: &execution)
                geometry.surfaces[original.id] = original.surface; surfaceNames[original.id] = original.basisName
                value = .init(name: e.label, geometry: .surface(original.id))
            } else {
                let original = try producer.curve(entityPointer: pointer, units: units, tolerance: tolerance, usage: usage, using: &execution)
                try usage.charge(entities: 2, work: original.basisName.utf8.count, using: &execution)
                geometry.curves[original.id] = original.curve; curveNames[original.id] = original.basisName
                value = .init(name: e.label, geometry: .curve(original.id, trim: original.trim))
            }
            if e.transformationPointer != 0 {
                guard case .frame(let frameID) = try reference(e.transformationPointer, depth: 2) else {
                    throw invalid("Original primitive directory matrix must select its actual Type124 frame.")
                }
                try usage.charge(entities: 1, using: &execution)
                switch value.geometry {
                case .curve(let id, _): curvePositions[id] = .init(frameID: frameID)
                case .surface(let id): surfacePositions[id] = .init(frameID: frameID)
                }
            }
            try usage.charge(entities: 1, using: &execution); items[pointer] = value
            return .item(value.id)
        }
        mutating func entity(_ pointer: Int) throws -> IndependentIGESEntity {
            try usage.check(); let value = try fields.entity(pointer)
            try usage.charge(work: value.label.utf8.count + value.parameters.count + 1, using: &execution)
            for parameter in value.parameters { try usage.charge(work: parameter.utf8.count, using: &execution) }
            guard value.pointer == pointer else { throw invalid("IGES parser returned foreign directory identity.") }
            return value
        }
        mutating func integer(_ value: String) throws -> Int { try usage.charge(work: value.utf8.count, using: &execution); return try fields.integer(value) }
        mutating func string(_ value: String) throws -> String { try usage.charge(work: value.utf8.count, using: &execution); return try fields.string(value) }
        mutating func exactCount(_ count: Int, base: Int, actual: Int) throws {
            let end = count.addingReportingOverflow(base)
            guard count >= 0, !end.overflow else { throw resource("IGES member count overflow.") }
            // The parent separates generic tails before this specified-family count check.
            guard end.partialValue == actual else { throw invalid("IGES specified association member extent differs from its original count.") }
        }
        mutating func enter(_ pointer: Int) throws {
            try usage.charge(entities: 1, work: 1, using: &execution)
            guard active.insert(pointer).inserted else { throw invalid("Cyclic IGES subfigure/group association.") }
        }
        mutating func sortWork(_ count: Int) throws {
            let levels = count == 0 ? 0 : Int.bitWidth - count.leadingZeroBitCount
            let amount = count.multipliedReportingOverflow(by: levels + 1)
            guard !amount.overflow else { throw resource("IGES sorting work overflow.") }
            try usage.charge(work: amount.partialValue, using: &execution)
        }
        mutating func unique(_ members: [IndependentShapeReference]) throws {
            guard members.count > 1 else { return }
            for index in 1..<members.count { try usage.charge(work: 1, using: &execution); guard members[index - 1] != members[index] else { throw invalid("Duplicate IGES group/subfigure member.") } }
        }
        mutating func root(_ reference: IndependentShapeReference, _ incoming: Set<IndependentShapeReference>, into roots: inout [IndependentShapeReference]) throws {
            try usage.charge(work: 1, using: &execution)
            if !incoming.contains(reference) { try usage.charge(entities: 1, using: &execution); roots.append(reference) }
        }
        mutating func checkDepth(_ depth: Int) throws {
            try usage.charge(work: 1, using: &execution)
            guard depth <= usage.limits.maximumNesting else { throw resource("IGES graph caller nesting ceiling.") }
        }
        func invalid(_ message: String) -> IndependentShapeExchangeError { .invalidAssociation(message) }
        func unsupported(_ message: String) -> IndependentShapeExchangeError { .unsupportedSemantics(message) }
        func resource(_ message: String) -> IndependentShapeExchangeError { .resourceLimitExceeded(message) }
    }
}
