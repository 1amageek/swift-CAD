import CADCore
import CADGeometry
import CADIR

/// Uses actual unit associations rather than imposing one unit on independent representations.
public struct DefaultIndependentSTEPUnitAssociationResolver: IndependentSTEPUnitAssociationResolving {
    public init() {}

    public func resolve(entityIDs: [Int], primitiveRootEntityIDs: [Int], fields: any STEPFieldReading,
        producer: inout any IndependentSTEPGeometryReading, usage: inout IndependentShapeExchangeUsage) throws -> UnitSystem {
        try resolveOriginal(entityIDs: entityIDs, primitiveRootEntityIDs: primitiveRootEntityIDs, fields: fields, producer: &producer, usage: &usage).units
    }
    public func resolveOriginal(entityIDs: [Int], primitiveRootEntityIDs: [Int], fields: any STEPFieldReading,
                        producer: inout any IndependentSTEPGeometryReading,
                        usage: inout IndependentShapeExchangeUsage) throws -> IndependentSTEPOriginalUnitAssociation {
        try usage.charge(entities: entityIDs.count, work: entityIDs.count)
        let levels = entityIDs.isEmpty ? 0 : Int.bitWidth - entityIDs.count.leadingZeroBitCount
        let sorting = entityIDs.count.multipliedReportingOverflow(by: levels + 1)
        guard !sorting.overflow else { throw resource("Independent unit association sort work overflow.") }
        try usage.charge(work: sorting.partialValue)
        let ids = entityIDs.sorted()
        var previous: Int?
        var contextIDs: [Int] = []
        var representedContexts = Set<Int>()
        var representedPrimitives = Set<Int>()
        for id in ids {
            guard id > 0, previous != id else { throw invalid("Malformed or duplicated STEP unit association identity.") }
            previous = id
            // Reserve the complete lexical field scans before shared syntax operations allocate.
            let scans = try fields.entity(id).utf8.count.multipliedReportingOverflow(by: 4)
            guard !scans.overflow else { throw resource("Independent unit association field work overflow.") }
            try usage.charge(work: scans.partialValue)
            if try fields.hasComponent(id, named: "GLOBAL_UNIT_ASSIGNED_CONTEXT") {
                try usage.charge(entities: 1, work: 1)
                contextIDs.append(id)
            }
            let family = try fields.name(id)
            guard ["REPRESENTATION", "SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION",
                   "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"].contains(family) else { continue }
            let arguments = try fields.arguments(id, component: nil)
            guard arguments.count == 3 else { throw invalid("Malformed original independent representation.") }
            try usage.charge(entities: 1, work: 1)
            representedContexts.insert(try fields.reference(arguments[2]))
            for member in try fields.list(arguments[1]) {
                try usage.charge(entities: 1, work: 1)
                representedPrimitives.insert(member)
                let text = try fields.entity(member)
                try usage.charge(work: text.utf8.count)
                let name = try fields.name(member)
                if name == "GEOMETRIC_SET" || name == "GEOMETRIC_CURVE_SET" {
                    let set = try fields.arguments(member, component: nil)
                    guard set.count == 2 else { throw invalid("Malformed independent geometric-set association.") }
                    for selection in try fields.list(set[1]) {
                        try usage.charge(entities: 1, work: 1)
                        representedPrimitives.insert(selection)
                    }
                }
            }
        }
        var hasUnassociatedPrimitive = false
        for id in primitiveRootEntityIDs {
            try usage.charge(work: 1)
            if !representedPrimitives.contains(id) { hasUnassociatedPrimitive = true }
        }
        var allUnits: UnitSystem?
        var competingUnits = false
        var ambientUnits: UnitSystem?
        var firstContextUnits: UnitSystem?
        var firstAngularSource: IndependentShapeAngularSource?, ambientAngularSource: IndependentShapeAngularSource?
        var firstLengthSource: OriginalSTEPLengthSource?, ambientLengthSource: OriginalSTEPLengthSource?
        var allAngularSource: IndependentShapeAngularSource?
        var allLengthGain: ExactRationalCoefficient?, ambientLengthGain: ExactRationalCoefficient?
        var ambientContexts: [IndependentShapeContext] = []
        for id in contextIDs {
            let units = try producer.contextUnits(entityID: id, usage: &usage)
            let originalLengthSource = try producer.contextLengthSource(entityID: id, usage: &usage)
            let originalAngularSource = try producer.contextAngularSource(entityID: id, usage: &usage)
            let lengthGain = try originalLengthSource.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
            try units.validate()
            try usage.charge(work: 1)
            if firstContextUnits == nil { firstContextUnits = units; firstAngularSource = originalAngularSource; firstLengthSource = originalLengthSource }
            if let original = allUnits {
                if original.length != units.length { competingUnits = true }
                if hasUnassociatedPrimitive, let previous = allLengthGain,
                    !(try previous.subtracting(lengthGain, usage: &usage).isZero) { competingUnits = true }
                if hasUnassociatedPrimitive, let previous = allAngularSource,
                   !(try previous.isCoordinateLawEquivalent(to: originalAngularSource, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)) { competingUnits = true }
            } else { allUnits = units; allAngularSource = originalAngularSource; allLengthGain = lengthGain }
            if !representedContexts.contains(id) {
                if let original = ambientUnits, original.length != units.length {
                    throw invalid("Unassociated STEP unit descriptors declare competing ambient length units.")
                }
                if let previous = ambientLengthGain,
                   !(try previous.subtracting(lengthGain, usage: &usage).isZero) {
                    throw invalid("Unassociated STEP descriptors declare competing exact original length laws.")
                }
                if let previous = ambientAngularSource {
                    guard try previous.isCoordinateLawEquivalent(to: originalAngularSource, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage) else {
                        throw invalid("Unassociated STEP descriptors declare competing original angular coordinate laws.")
                    }
                }
                let contextFields = try fields.arguments(id, component: "REPRESENTATION_CONTEXT")
                guard contextFields.count == 2 else { throw invalid("Original ambient context identifier/type are absent.") }
                var text: [String] = []
                for literal in contextFields {
                    let decoded = try fields.decodedString(literal, limits: STEPStringLimits(
                        maximumInputBytes: usage.limits.maximumBytes,
                        maximumOutputBytes: usage.limits.maximumBytes,
                        maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                    try usage.charge(work: decoded.consumedWork); text.append(decoded.value)
                }
                try usage.charge(entities: 1, work: 1)
                ambientContexts.append(.init(id: .init(highBits: 0x53544550414D4243, lowBits: UInt64(id)),
                    identifier: text[0], type: text[1], units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource))
                if ambientUnits == nil { ambientUnits = units; ambientAngularSource = originalAngularSource; ambientLengthSource = originalLengthSource; ambientLengthGain = lengthGain }
            }
        }
        guard let firstContextUnits else {
            guard primitiveRootEntityIDs.isEmpty, representedContexts.isEmpty else {
                throw invalid("Independent geometry lacks an original unit context.")
            }
            // Unitless GROUP metadata has no coordinates. Metres are only the
            // document presentation convention; no foreign unit law is invented.
            return .init(units: .meters, originalAngularSource: nil, originalLengthSource: nil)
        }
        // Every representation must reference an actual context accepted above.
        try usage.charge(entities: contextIDs.count, work: contextIDs.count)
        let knownContexts = Set(contextIDs)
        for id in representedContexts {
            try usage.charge(work: 1)
            guard knownContexts.contains(id) else { throw invalid("Representation lacks its declared unit context.") }
        }
        if let ambientUnits { return .init(units: ambientUnits, originalAngularSource: ambientAngularSource, ambientContexts: ambientContexts, originalLengthSource: ambientLengthSource) }
        guard !hasUnassociatedPrimitive || !competingUnits else {
            throw invalid("Unassociated primitive has no unambiguous original length/angle unit association.")
        }
        return .init(units: firstContextUnits, originalAngularSource: hasUnassociatedPrimitive ? firstAngularSource : nil, originalLengthSource: hasUnassociatedPrimitive ? firstLengthSource : nil)
    }

    private func invalid(_ detail: String) -> IndependentShapeExchangeError { .invalidAssociation(detail) }
    private func resource(_ detail: String) -> IndependentShapeExchangeError { .resourceLimitExceeded(detail) }
}
