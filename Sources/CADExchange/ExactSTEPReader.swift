import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct ExactSTEPReader: Sendable {
    let entities: [Int: String]
    let lengthUnit: LengthUnit
    let processingBudget: ExchangeProcessingBudget
    let tolerance: ModelingTolerance
    var representationItems: Set<Int>? = nil

    static func originalMappingSource(entityID: Int, entities: [Int: String], units: UnitSystem, contextEntityID: Int,
        processingBudget: ExchangeProcessingBudget, tolerance: ModelingTolerance,
        usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPPlacementSource {
        let reader = ExactSTEPReader(entities: entities, lengthUnit: units.length,
            processingBudget: processingBudget, tolerance: tolerance)
        var producer = IndependentProducer(reader: reader)
        let lengthSource = try producer.contextLengthSource(entityID: contextEntityID, usage: &usage)
        return try producer.mappingSource(entityID: entityID, units: units, originalLengthSource: lengthSource, usage: &usage)
    }

    static func originalMappingTarget(entityID: Int, entities: [Int: String], units: UnitSystem,
        processingBudget: ExchangeProcessingBudget, tolerance: ModelingTolerance,
        usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D {
        let reader = ExactSTEPReader(entities: entities, lengthUnit: units.length,
            processingBudget: processingBudget, tolerance: tolerance)
        var producer = IndependentProducer(reader: reader)
        return try producer.mappingTarget(entityID: entityID, units: units, usage: &usage)
    }

    static func bodyContextUnits(entities: [Int: String], names: [Int: String], processingBudget: ExchangeProcessingBudget,
                                 tolerance: ModelingTolerance, usage: inout IndependentShapeExchangeUsage) throws -> [Int: UnitSystem] {
        let reader = ExactSTEPReader(entities: entities, lengthUnit: .meter, processingBudget: processingBudget, tolerance: tolerance)
        var producer: any IndependentSTEPGeometryReading = IndependentProducer(reader: reader)
        return try STEPBodyUnitContextResolver.resolve(fields: STEPAssemblySyntax(entities: entities), names: names,
            producer: &producer, usage: &usage)
    }

    static func readIndependent(entities: [Int: String], processingBudget: ExchangeProcessingBudget,
                                tolerance: ModelingTolerance, standaloneItems: [Int], productDefinitions: [Int: AssemblyDefinitionID] = [:],
                                bodySources: [Int: SubshapeID] = [:], bodySourceGraph: DesignGraph? = nil,
                                usage: inout IndependentShapeExchangeUsage) throws -> (source: IndependentShapeSource, units: UnitSystem)? {
        // This private reader seed supplies the parsed table, deadline and tolerance only.
        // Its ordinary B-rep lengthUnit is never consumed by IndependentProducer: every
        // primitive Builder receives the actual context units resolved below or by its representation.
        let reader = ExactSTEPReader(entities: entities, lengthUnit: .meter,
            processingBudget: processingBudget, tolerance: tolerance)
        var producer: any IndependentSTEPGeometryReading = IndependentProducer(reader: reader)
        try usage.charge(entities: entities.count, work: entities.count)
        let fields = STEPAssemblySyntax(entities: entities)
        let entityIDs = try independentEntityIDs(fields: fields, bodySources: bodySources, usage: &usage)
        var hasIndependentGraph = false
        for id in entityIDs {
            try usage.charge(work: 1)
            if ["REPRESENTATION", "SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION", "APPLIED_GROUP_ASSIGNMENT", "GROUP"].contains(try fields.name(id)) { hasIndependentGraph = true }
        }
        guard hasIndependentGraph || !standaloneItems.isEmpty else { return nil }
        let originalUnits = try DefaultIndependentSTEPUnitAssociationResolver().resolveOriginal(entityIDs: entityIDs,
            primitiveRootEntityIDs: standaloneItems, fields: fields, producer: &producer, usage: &usage)
        guard let source = try DefaultIndependentSTEPGraphReader().read(entityIDs: entityIDs,
            standaloneItemEntityIDs: standaloneItems, fields: fields, ambientOriginalAngularSource: originalUnits.originalAngularSource, ambientOriginalLengthSource: originalUnits.originalLengthSource, ambientContexts: originalUnits.ambientContexts, productDefinitions: productDefinitions, bodySources: bodySources, bodySourceGraph: bodySourceGraph,
            standaloneUnits: originalUnits.units, tolerance: tolerance, producer: &producer, usage: &usage) else { return nil }
        return (source: source, units: originalUnits.units)
    }

    /// Partitions actual representation ownership before either graph consumes its numeric context.
    private static func independentEntityIDs(fields: STEPAssemblySyntax, bodySources: [Int: SubshapeID], usage: inout IndependentShapeExchangeUsage) throws -> [Int] {
        let ids = Array(fields.entities.keys)
        try usage.charge(entities: ids.count, work: ids.count)
        var excluded = Set<Int>(), selectedContexts = Set<Int>(), foreignContexts = Set<Int>()
        let families = Set(["REPRESENTATION", "SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"])
        for id in ids {
            try usage.charge(work: fields.entities[id]!.utf8.count)
            let kind = try fields.name(id)
            if kind == "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT" {
                let a = try fields.arguments(id)
                guard a.count == 4 else { throw ImportError.invalidData("Malformed original representation carrier identity.") }
                let role = try fields.arguments(fields.reference(a[1])), source = try fields.arguments(fields.reference(a[2]))
                guard role.count == 2, source.count == 1 else { throw ImportError.invalidData("Malformed original carrier role/source.") }
                let decodedRole = try fields.decodedString(role[0], limits: STEPStringLimits(maximumInputBytes: usage.limits.maximumBytes,
                    maximumOutputBytes: usage.limits.maximumBytes, maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                try usage.charge(work: decodedRole.consumedWork)
                guard source[0].hasPrefix("IDENTIFIER("), source[0].hasSuffix(")") else { throw ImportError.invalidData("Original carrier namespace must be a typed identifier.") }
                let decodedSource = try fields.decodedString(String(source[0].dropFirst(11).dropLast()), limits: STEPStringLimits(maximumInputBytes: usage.limits.maximumBytes,
                    maximumOutputBytes: usage.limits.maximumBytes, maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                try usage.charge(work: decodedSource.consumedWork)
                if decodedRole.value == "representationCarrier", decodedSource.value == STEPSourceIdentityRole.namespace {
                    let targets = try fields.list(a[3])
                    guard targets.count == 1, let target = targets.first, try fields.name(target) == "SHAPE_REPRESENTATION" else {
                        throw ImportError.invalidData("Original carrier identity must select its actual representation.")
                    }
                    try usage.charge(entities: 1, work: 1); excluded.insert(target)
                }
            }
            if kind == "PROPERTY_DEFINITION_REPRESENTATION" {
                let a = try fields.arguments(id)
                guard a.count == 2 else { throw ImportError.invalidData("Malformed metadata representation ownership.") }
                try usage.charge(entities: 1, work: 1); excluded.insert(try fields.reference(a[1]))
            }
        }
        var ownershipRoots: [Int] = []
        for id in ids {
            try usage.charge(work: fields.entities[id]!.utf8.count)
            let kind = try fields.name(id)
            if families.contains(kind) || ["ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(kind) {
                try usage.charge(entities: 1, work: 1); ownershipRoots.append(id)
            }
        }
        let ownership = try STEPRepresentationGeometryOwnership.classify(fields: fields,
            entityIDs: ownershipRoots, maximumDepth: usage.limits.maximumNesting) { records, work in
                try usage.charge(entities: records, work: work)
            }
        for id in ids {
            try usage.charge(work: fields.entities[id]!.utf8.count)
            let kind = try fields.name(id)
            guard families.contains(kind) || ["ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", "DRAUGHTING_MODEL"].contains(kind) else { continue }
            let a = try fields.arguments(id)
            guard a.count == 3 else { throw ImportError.invalidData("Malformed representation ownership.") }
            let context = try fields.reference(a[2]), members = try fields.list(a[1])
            try usage.charge(entities: members.count + 1, work: members.count + 1)
            let body = ownership[id]?.contains(.body) == true
            let independent = ownership[id]?.contains(.independent) == true
            if body && independent && families.contains(kind) && !excluded.contains(id) {
                guard !bodySources.isEmpty else { throw IndependentShapeExchangeError.invalidAssociation("Mixed representation requires the actual original Body selector correspondence.") }
                selectedContexts.insert(context)
            } else if !families.contains(kind) || excluded.contains(id) || body {
                excluded.insert(id); foreignContexts.insert(context)
            } else { selectedContexts.insert(context) }
        }
        for context in foreignContexts where !selectedContexts.contains(context) { try usage.charge(entities: 1, work: 1); excluded.insert(context) }
        var result: [Int] = []
        for id in ids { try usage.charge(work: 1); if !excluded.contains(id) { result.append(id) } }
        return result
    }

    func readIndependentGeometry(usage: inout IndependentShapeExchangeUsage) throws -> IndependentSTEPGeometry {
        var builder = Builder(entities: entities, lengthUnit: lengthUnit,
            processingBudget: processingBudget, tolerance: tolerance, representationItems: nil)
        return try builder.buildIndependentGeometry(usage: &usage)
    }

    func read() throws -> BRepModel { try readWithTransfer().model }

    func readWithTransfer() throws -> ExactSTEPReadTransfer {
        try processingBudget.check(format: .step)
        var builder = Builder(
            entities: entities,
            lengthUnit: lengthUnit,
            processingBudget: processingBudget,
            tolerance: tolerance,
            representationItems: representationItems
        )
        let model = try builder.build()
        try processingBudget.check(format: .step)
        try model.validate(level: .exact, tolerance: tolerance)
        return ExactSTEPReadTransfer(model: model, bodies: builder.bodyEntityTransfer, faces: builder.faceEntityTransfer)
    }
}

private extension ExactSTEPReader {
    struct IndependentProducer: IndependentSTEPGeometryReading {
        let reader: ExactSTEPReader
        var builders: [UnitSystem: Builder] = [:]
        var paidEntities = Set<Int>()
        var originalAngularUnits: [Int: IndependentShapeAngularSource] = [:]
        var originalAngularContexts: [Int: IndependentShapeAngularSource] = [:]
        var activeAngularUnits = Set<Int>()
        var originalLengthUnits: [Int: OriginalSTEPLengthSource] = [:]
        var originalLengthContexts: [Int: OriginalSTEPLengthSource] = [:]
        var activeLengthUnits = Set<Int>()

        mutating func pay(_ id: Int, usage: inout IndependentShapeExchangeUsage) throws {
            guard let entity = reader.entities[id] else { throw ImportError.missingRequiredEntity("STEP primitive #\(id)") }
            if !paidEntities.contains(id) {
                try usage.charge(entities: 1, work: entity.utf8.count + 1)
                paidEntities.insert(id)
            } else { try usage.charge(work: 1) }
        }
        func builder(_ units: UnitSystem) -> Builder {
            Builder(entities: reader.entities, lengthUnit: units.length, processingBudget: reader.processingBudget,
                tolerance: reader.tolerance, representationItems: nil)
        }
        mutating func curve(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil, tolerance: ModelingTolerance,
                            usage: inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadCurve {
            try pay(entityID, usage: &usage)
            let fields = STEPAssemblySyntax(entities: reader.entities), kind = try fields.name(entityID)
            if kind == "TRIMMED_CURVE" {
                let a = try fields.arguments(entityID)
                guard a.count == 6, [".PARAMETER.", ".CARTESIAN.", ".UNSPECIFIED."].contains(a[5]), a[4] == ".T." || a[4] == ".F." else {
                    throw ImportError.invalidData("Invalid independent trimmed-curve selectors or sense.")
                }
                let basis = try fields.reference(a[1])
                guard try fields.name(basis) != "TRIMMED_CURVE" else { throw ImportError.invalidData("A trimmed curve cannot be another trimmed curve's basis.") }
                let original = try curve(entityID: basis, units: units, originalAngularSource: originalAngularSource, originalLengthSource: originalLengthSource, tolerance: tolerance, usage: &usage)
                let foreign: Curve3D
                if try IndependentSTEPAngularLaw.usesAngularCoordinates(curve: original.curve, usage: &usage) {
                    let law = try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &usage)
                    foreign = try IndependentShapeAngularCurveSelection.foreignCurve(basis: original.curve, law: law,
                        tolerance: tolerance, maximumSourceDepth: usage.limits.maximumNesting,
                        maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                        maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)
                } else { foreign = original.curve }
                let firstSelection = try trimSelector(a[2], preference: a[5], original: foreign, units: units, tolerance: tolerance, usage: &usage)
                let lastSelection = try trimSelector(a[3], preference: a[5], original: foreign, units: units, tolerance: tolerance, usage: &usage)
                let first = firstSelection.parameter
                let last = lastSelection.parameter
                let increasing = a[4] == ".T."
                guard first.isFinite, last.isFinite else { throw ImportError.invalidData("Trim selectors must be finite original parameters.") }
                let selection: (trim: CurveTrim, traversalSource: Curve3D?)
                if try IndependentSTEPAngularLaw.usesAngularCoordinates(curve: original.curve, usage: &usage),
                   case .physicalRadians(let gain) = try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &usage) {
                    let traversal = try IndependentShapeAngularCurveSelection.physicalArc(basis: original.curve, gain: gain,
                        first: first, last: last, increasing: increasing, tolerance: tolerance,
                        maximumSourceDepth: usage.limits.maximumNesting, maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                        maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)
                    selection = (.init(startParameter: 0, endParameter: 1), traversal)
                } else {
                    selection = try IndependentCurvePeriodicTrimResolver().selection(first: first, last: last,
                        increasing: increasing, on: foreign, tolerance: tolerance, usage: &usage)
                }
                let trim = selection.trim
                return .init(id: original.id, curve: original.curve, trim: trim,
                    basisEntityID: original.basisEntityID, basisName: original.basisName,
                    positionEntityID: original.positionEntityID, parameterLengthUnit: original.parameterLengthUnit,
                    trimmingSource: IndependentShapeTrimmingSource(first: firstSelection.selectors, second: lastSelection.selectors,
                        agreesWithBasis: increasing, preference: a[5] == ".PARAMETER." ? .parameter : (a[5] == ".CARTESIAN." ? .cartesian : .unspecified)), traversalSource: selection.traversalSource ?? (foreign == original.curve ? nil : foreign), linearSource: original.linearSource, splineSource: original.splineSource)
            }
            var b = builders.removeValue(forKey: units) ?? builder(units)
            defer { builders[units] = b }
            let id: CurveID = b.taggedID(namespace: 0x535445505F435256, entityID: entityID)
            let a = try fields.arguments(entityID, component: kind.isEmpty ? "REPRESENTATION_ITEM" : nil)
            guard let label = a.first else { throw ImportError.invalidData("STEP curve name is absent.") }
            let name = try fields.string(label)
            let splineSource: OriginalSTEPSplineCurveSource?
            if kind.isEmpty || kind == "B_SPLINE_CURVE_WITH_KNOTS" {
                splineSource = try originalSplineCurve(entityID: entityID, usage: &usage)
            } else { splineSource = nil }
            let linearSource: OriginalSTEPLineSource?
            if kind == "LINE" {
                guard a.count == 3 else { throw ImportError.invalidData("Malformed original LINE.") }
                let vectorID = try fields.reference(a[2]); try pay(vectorID, usage: &usage)
                let vector = try fields.arguments(vectorID)
                guard try fields.name(vectorID) == "VECTOR", vector.count == 3 else { throw ImportError.invalidData("Malformed original LINE VECTOR.") }
                let label = try fields.decodedString(vector[0], limits: .init(maximumInputBytes: usage.limits.maximumBytes,
                    maximumOutputBytes: usage.limits.maximumBytes - usage.consumedBytes,
                    maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                try usage.charge(work: label.consumedWork, bytes: label.outputBytes)
                linearSource = try .init(location: originalElement(a[1], expected: "CARTESIAN_POINT", usage: &usage),
                    direction: originalElement(vector[1], expected: "DIRECTION", usage: &usage),
                    vectorID: .init(highBits: 0x535445504C564543, lowBits: UInt64(vectorID)), vectorName: label.value,
                    magnitude: b.number(vector[2], label: "original vector magnitude"), lengthUnit: units.length,
                    originalLengthSource: originalLengthSource)
            } else { linearSource = nil }
            let curve: Curve3D
            if let cached = b.geometry.curves[id] { curve = cached }
            else if kind == "LINE" {
                guard let linearSource else { throw ImportError.invalidData("Original LINE source is absent.") }
                let word = try linearSource.originalOperationWord(tolerance: tolerance,
                    maximumDepth: usage.limits.maximumAlgebraicDepth, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)
                curve = .originalAffineWord(try OriginalAffineWordCurve3D(source: .line(Line3D(origin: .origin, direction: .unitX)),
                    operationWord: word, tolerance: tolerance, remainingSourceDepth: usage.limits.maximumNesting,
                    maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage))
                b.geometry.curves[id] = curve
            } else if kind == "CIRCLE" || kind == "ELLIPSE" || kind == "HYPERBOLA" || kind == "PARABOLA" {
                guard a.count == (kind == "ELLIPSE" || kind == "HYPERBOLA" ? 4 : 3) else { throw ImportError.invalidData("Malformed independent STEP conic.") }
                let local: Curve3D
                switch kind {
                case "CIRCLE": local = .circle(Circle3D(center: .origin, normal: .unitZ, radius: try b.number(a[2], label: "circle radius")))
                case "ELLIPSE": local = .analytic(.ellipse(center: .origin, normal: .unitZ, majorAxis: .unitX,
                    majorRadius: try b.number(a[2], label: "ellipse major radius"), minorRadius: try b.number(a[3], label: "ellipse minor radius")))
                case "HYPERBOLA": local = .analytic(.hyperbola(Hyperbola3D(center: .origin, normal: .unitZ, transverseAxis: .unitX,
                    transverseRadius: try b.number(a[2], label: "hyperbola radius"), conjugateRadius: try b.number(a[3], label: "hyperbola radius"))))
                default: local = .analytic(.parabola(Parabola3D(vertex: .origin, normal: .unitZ, axis: .unitX,
                    focalLength: try b.number(a[2], label: "parabola focal length"))))
                }
                let position = try mappingSource(entityID: fields.reference(a[1]), units: units,
                    originalLengthSource: originalLengthSource, usage: &usage)
                let law = try position.originalNormalizedAffineSource(usage: &usage, maximumSourceDepth: usage.limits.maximumNesting, localCoordinatesInModelUnits: true)
                let word = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: tolerance,
                    maximumDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)
                curve = .originalAffineWord(try OriginalAffineWordCurve3D(source: local, operationWord: word,
                    tolerance: tolerance, remainingSourceDepth: usage.limits.maximumNesting,
                    maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage))
                b.geometry.curves[id] = curve
            } else {
                try preflightSpline(entityID, surface: false, usage: &usage)
                var originalBuilder = builder(.init(length: .meter, angle: .radian))
                let original = Curve3D.bSpline(try originalBuilder.buildBSplineCurve(fields.entity(entityID), entityID: entityID, retainingLogicalAssertions: true))
                let word = try IndependentSTEPLengthLaw.coordinateWord(source: originalLengthSource, units: units,
                    tolerance: tolerance, usage: &usage)
                curve = .originalAffineWord(try OriginalAffineWordCurve3D(source: original, operationWord: word,
                    tolerance: tolerance, remainingSourceDepth: usage.limits.maximumNesting,
                    maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage))
                b.geometry.curves[id] = curve
            }
            let originalCurve = curve
            let trim: CurveTrim?
            if case .closed(let lower, let upper) = originalCurve.parameterDomain { trim = .init(startParameter:lower,endParameter:upper) }
            else { trim = nil }
            let positioned = ["CIRCLE", "ELLIPSE", "HYPERBOLA", "PARABOLA"].contains(kind)
            return .init(id:id,curve:originalCurve,trim:trim,basisEntityID:entityID,basisName:name,
                positionEntityID: positioned ? try fields.reference(a[1]) : nil,
                parameterLengthUnit: kind == "PARABOLA" ? units.length : nil, linearSource: linearSource, splineSource: splineSource)
        }
        mutating func trimSelector(_ selector: String, preference: String, original: Curve3D, units: UnitSystem,
                                   tolerance: ModelingTolerance, usage: inout IndependentShapeExchangeUsage) throws -> (parameter: Double, selectors: [IndependentShapeTrimmingSource.Selector]) {
            let fields = STEPAssemblySyntax(entities: reader.entities)
            guard selector.first == "(", selector.last == ")" else { throw ImportError.invalidData("Malformed trimming SET.") }
            let values = try fields.split(String(selector.dropFirst().dropLast()))
            guard values.count == 1 || values.count == 2 else { throw ImportError.invalidData("A trim needs one point, one parameter, or both.") }
            var numerical: Double?, cartesian: Point3D?
            var selectors: [IndependentShapeTrimmingSource.Selector] = []
            for value in values {
                try usage.charge(work: value.utf8.count + 1)
                if value.hasPrefix("PARAMETER_VALUE("), value.last == ")" {
                    guard numerical == nil else { throw ImportError.invalidData("Repeated parameter trimming selector.") }
                    let parameter = try builder(units).number(String(value.dropFirst(16).dropLast()), label: "original trim parameter")
                    numerical = parameter; selectors.append(.parameter(parameter))
                } else {
                    guard cartesian == nil else { throw ImportError.invalidData("Repeated Cartesian trimming selector.") }
                    let point = try fields.reference(value); try pay(point, usage: &usage)
                    var b = builder(units); let value = try b.buildPoint(point); cartesian = value; selectors.append(.point(value))
                }
            }
            if let numerical, let cartesian {
                try usage.charge(work: 16)
                let point = try original.point(at: numerical, tolerance: tolerance)
                guard (point - cartesian).length <= tolerance.distance else { throw ImportError.invalidData("Mixed trim selectors identify different original points.") }
            }
            if preference != ".CARTESIAN.", let numerical { return (numerical, selectors) }
            if cartesian == nil, let numerical { return (numerical, selectors) }
            guard let cartesian else { throw ImportError.invalidData("Empty trim selectors.") }
            return (try IndependentCurveTrimResolver().parameter(of: cartesian, on: original, tolerance: tolerance, usage: &usage), selectors)
        }
        mutating func surface(entityID:Int, units:UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil, tolerance:ModelingTolerance,
                              usage:inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadSurface {
            try pay(entityID,usage:&usage)
            let fields = STEPAssemblySyntax(entities:reader.entities), kind = try fields.name(entityID)
            let isSpline: Bool
            if kind.isEmpty { isSpline = try fields.hasComponent(entityID, named: "B_SPLINE_SURFACE") }
            else { isSpline = kind == "B_SPLINE_SURFACE_WITH_KNOTS" }
            var b = builders.removeValue(forKey:units) ?? builder(units)
            defer { builders[units] = b }
            if kind.isEmpty { try preflightSpline(entityID,surface:true,usage:&usage) }
            if ["PLANE", "CYLINDRICAL_SURFACE", "CONICAL_SURFACE", "SPHERICAL_SURFACE", "TOROIDAL_SURFACE"].contains(kind) {
                let a = try fields.arguments(entityID)
                let expected = kind == "PLANE" ? 2 : (kind == "CONICAL_SURFACE" || kind == "TOROIDAL_SURFACE" ? 4 : 3)
                guard a.count == expected else { throw ImportError.invalidData("Malformed original positioned surface.") }
                let local: Surface3D
                switch kind {
                case "PLANE": local = .plane(Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX))
                case "CYLINDRICAL_SURFACE": local = .cylinder(Cylinder3D(origin: .origin, axis: .unitZ,
                    radius: try b.number(a[2], label: "original cylinder radius")))
                case "CONICAL_SURFACE":
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Original STEP radius/semi-angle axial-height cone law needs its retained Geometry producer.
                    // This public independent reader must not promote rounded apex and slant-parameter conversion into the original surface authority.
                    throw IndependentShapeExchangeError.unsupportedSemantics("Original STEP axial-height cone producer is not implemented.")
                default:
                    let native: Surface3D
                    if kind == "SPHERICAL_SURFACE" {
                        native = .analytic(.sphere(center: .origin, radius: try b.number(a[2], label: "original sphere radius")))
                    } else {
                        native = .analytic(.torus(center: .origin, axis: .unitZ,
                            majorRadius: try b.number(a[2], label: "original torus major radius"),
                            minorRadius: try b.number(a[3], label: "original torus minor radius")))
                    }
                    let rotation = try AffineTransform3D(basisX: -.unitY, basisY: .unitX, basisZ: .unitZ, translation: .zero)
                    local = .affineImage(try OriginalImageSurface3D(source: native, transform: rotation, tolerance: tolerance))
                }
                let position = try mappingSource(entityID: fields.reference(a[1]), units: units,
                    originalLengthSource: originalLengthSource, usage: &usage)
                let law = try position.originalNormalizedAffineSource(usage: &usage, maximumSourceDepth: usage.limits.maximumNesting, localCoordinatesInModelUnits: true)
                let word = try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: tolerance,
                    maximumDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)
                let angularLaw: IndependentShapeAngularSource.CoordinateLaw?
                if kind == "PLANE" { angularLaw = nil }
                else { angularLaw = try IndependentSTEPAngularLaw.coordinateLaw(source: originalAngularSource, units: units, usage: &usage) }
                let selectedLocal: Surface3D
                if case .some(.physicalRadians(let gain)) = angularLaw {
                    selectedLocal = try IndependentShapeAngularSurfaceSelection.physical(local: local, gain: gain,
                        tolerance: tolerance, usage: &usage)
                } else { selectedLocal = local }
                let positioned = Surface3D.procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: selectedLocal,
                    operationWord: word, tolerance: tolerance, remainingSourceDepth: usage.limits.maximumNesting,
                    maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)))
                let surface: Surface3D
                if case .some(.canonicalGain(let gain)) = angularLaw {
                    let identity = try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)
                    surface = .parameterImage(try OriginalImageSurface3D(source: positioned,
                        uParameterGain: gain, vParameterGain: kind == "CYLINDRICAL_SURFACE" ? .binary(1) : gain,
                        transform: identity, tolerance: tolerance))
                } else { surface = positioned }
                let id: SurfaceID = b.taggedID(namespace: 0x535445505F535246, entityID: entityID)
                b.geometry.surfaces[id] = surface
                return .init(id: id, surface: surface, basisName: try fields.string(a[0]), positionEntityID: try fields.reference(a[1]))
            }
            if isSpline {
                if !kind.isEmpty { try preflightSpline(entityID, surface: true, usage: &usage) }
                var originalBuilder = builder(.init(length: .meter, angle: .radian))
                let metadata = try originalSplineSurface(entityID: entityID, usage: &usage)
                let original = Surface3D.bSpline(try originalBuilder.buildBSplineSurface(fields.entity(entityID), entityID: entityID, retainingLogicalAssertions: true))
                let word = try IndependentSTEPLengthLaw.coordinateWord(source: originalLengthSource, units: units,
                    tolerance: tolerance, usage: &usage)
                let surface = Surface3D.procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: original,
                    operationWord: word, tolerance: tolerance, remainingSourceDepth: usage.limits.maximumNesting,
                    maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                    maximumAlgebraicDepth: usage.limits.maximumAlgebraicDepth, usage: &usage)))
                let id: SurfaceID = b.taggedID(namespace: 0x535445505F535246, entityID: entityID)
                b.geometry.surfaces[id] = surface
                let a = try fields.arguments(entityID, component: kind.isEmpty ? "REPRESENTATION_ITEM" : nil)
                guard let label = a.first else { throw ImportError.invalidData("STEP spline surface name is absent.") }
                return .init(id: id, surface: surface, basisName: try fields.string(label), splineSource: metadata)
            }
            let id = try b.buildSurface(entityID)
            guard let surface = b.geometry.surfaces[id] else { throw ImportError.missingRequiredEntity("STEP surface law.") }
            let a = try fields.arguments(entityID,component:kind.isEmpty ? "REPRESENTATION_ITEM" : nil)
            guard let label = a.first else { throw ImportError.invalidData("STEP surface name is absent.") }
            return .init(id:id,surface:surface,basisName:try fields.string(label))
        }
        mutating func originalSplineCurve(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPSplineCurveSource {
            let fields = STEPAssemblySyntax(entities: reader.entities)
            let original = try IndependentSTEPSplineFields(fields: fields, entityID: entityID, surface: false)
            guard original.basis.count == 5, original.knots.count == 3 else { throw ImportError.invalidData("Malformed original spline curve metadata.") }
            let ids = try fields.list(original.basis[1])
            try usage.charge(entities: ids.count, work: ids.count)
            let storage = ids.count.multipliedReportingOverflow(by: MemoryLayout<OriginalSTEPPlacementElement>.stride)
            guard !storage.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original spline point storage overflow.") }
            try usage.charge(bytes: storage.partialValue)
            var points: [OriginalSTEPPlacementElement] = []; points.reserveCapacity(ids.count)
            for id in ids { points.append(try originalElement("#\(id)", expected: "CARTESIAN_POINT", usage: &usage)) }
            return try .init(controlPoints: points,
                curveForm: originalSplineToken(original.basis[2], as: OriginalSTEPSplineCurveForm.self),
                closed: originalSplineToken(original.basis[3], as: OriginalSTEPLogical.self),
                selfIntersect: originalSplineToken(original.basis[4], as: OriginalSTEPLogical.self),
                knotSpecification: originalSplineToken(original.knots[2], as: OriginalSTEPSplineKnotSpecification.self), isRational: original.rational != nil)
        }
        mutating func originalSplineSurface(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPSplineSurfaceSource {
            let fields = STEPAssemblySyntax(entities: reader.entities)
            let original = try IndependentSTEPSplineFields(fields: fields, entityID: entityID, surface: true)
            guard original.basis.count == 7, original.knots.count == 5 else { throw ImportError.invalidData("Malformed original spline surface metadata.") }
            let rows = try fields.split(String(original.basis[2].dropFirst().dropLast()))
            try usage.charge(entities: rows.count, work: rows.count)
            let wireRowStorage = rows.count.multipliedReportingOverflow(by: MemoryLayout<[OriginalSTEPPlacementElement]>.stride)
            guard !wireRowStorage.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original surface row storage overflow.") }
            try usage.charge(bytes: wireRowStorage.partialValue)
            var wirePoints: [[OriginalSTEPPlacementElement]] = []
            for row in rows {
                let ids = try fields.list(row)
                try usage.charge(entities: ids.count, work: ids.count)
                let storage = ids.count.multipliedReportingOverflow(by: MemoryLayout<OriginalSTEPPlacementElement>.stride)
                guard !storage.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original surface point storage overflow.") }
                try usage.charge(bytes: storage.partialValue)
                var points: [OriginalSTEPPlacementElement] = []; points.reserveCapacity(ids.count)
                for id in ids { points.append(try originalElement("#\(id)", expected: "CARTESIAN_POINT", usage: &usage)) }
                wirePoints.append(points)
            }
            guard let first = wirePoints.first, first.count >= 2, wirePoints.count >= 2 else { throw ImportError.invalidData("Original spline surface needs two controls per axis.") }
            let nativeRowStorage = first.count.multipliedReportingOverflow(by: MemoryLayout<[OriginalSTEPPlacementElement]>.stride)
            guard !nativeRowStorage.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original native surface row storage overflow.") }
            try usage.charge(bytes: nativeRowStorage.partialValue)
            var nativePoints: [[OriginalSTEPPlacementElement]] = []
            for v in first.indices {
                try usage.charge(entities: wirePoints.count, work: wirePoints.count)
                let storage = wirePoints.count.multipliedReportingOverflow(by: MemoryLayout<OriginalSTEPPlacementElement>.stride)
                guard !storage.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original native surface point storage overflow.") }
                try usage.charge(bytes: storage.partialValue)
                var points: [OriginalSTEPPlacementElement] = []; points.reserveCapacity(wirePoints.count)
                for u in wirePoints.indices {
                    guard wirePoints[u].count == first.count else { throw ImportError.invalidData("Nonrectangular original surface control records.") }
                    points.append(wirePoints[u][v])
                }
                nativePoints.append(points)
            }
            return try .init(controlPointRows: nativePoints,
                surfaceForm: originalSplineToken(original.basis[3], as: OriginalSTEPSplineSurfaceForm.self),
                uClosed: originalSplineToken(original.basis[4], as: OriginalSTEPLogical.self),
                vClosed: originalSplineToken(original.basis[5], as: OriginalSTEPLogical.self),
                selfIntersect: originalSplineToken(original.basis[6], as: OriginalSTEPLogical.self),
                knotSpecification: originalSplineToken(original.knots[4], as: OriginalSTEPSplineKnotSpecification.self), isRational: original.rational != nil)
        }
        func originalSplineToken<Value: RawRepresentable>(_ token: String, as type: Value.Type) throws -> Value where Value.RawValue == String {
            guard token.first == ".", token.last == ".", let value = Value(rawValue: String(token.dropFirst().dropLast())) else {
                throw ImportError.invalidData("Unknown original spline enumeration or logical token.")
            }
            return value
        }
        mutating func preflightSpline(_ id:Int, surface:Bool, usage:inout IndependentShapeExchangeUsage) throws {
            let fields = STEPAssemblySyntax(entities:reader.entities)
            let original = try IndependentSTEPSplineFields(fields: fields, entityID: id, surface: surface)
            let a = original.basis, k = original.knots
            let axisCount = surface ? 2 : 1
            guard a.count == (surface ? 7 : 5), k.count == (surface ? 5 : 3) else { throw ImportError.invalidData("Malformed STEP spline data.") }
            let rows = surface ? try fields.split(String(a[2].dropFirst().dropLast())) : [a[1]]
            var firstCount:Int?
            for row in rows {
                let points = try fields.list(row)
                try usage.charge(entities:points.count,work:points.count*4)
                guard !points.isEmpty, firstCount == nil || firstCount == points.count else { throw ImportError.invalidData("Nonrectangular STEP spline net.") }
                firstCount = points.count
                for point in points { try pay(point,usage:&usage) }
            }
            for axis in 0..<axisCount {
                guard let degree = Int(a[axis]), let count = surface ? (axis == 0 ? rows.count : firstCount) : firstCount,
                      degree > 0, degree < count else { throw ImportError.invalidData("Invalid STEP spline degree/control count.") }
                let raw = try fields.split(String(k[axis].dropFirst().dropLast()))
                var sum = 0
                for value in raw {
                    guard let m = Int(value), m > 0 else { throw ImportError.invalidData("Invalid STEP knot multiplicity.") }
                    let next = sum.addingReportingOverflow(m)
                    guard !next.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("STEP knot expansion count overflow.") }
                    sum = next.partialValue
                }
                guard sum == count+degree+1 else { throw ImportError.invalidData("STEP knot multiplicities do not match original degree/control count.") }
                try usage.charge(entities:sum,work:sum)
            }
        }
        mutating func contextUnits(entityID:Int,usage:inout IndependentShapeExchangeUsage) throws -> UnitSystem {
            try pay(entityID,usage:&usage)
            let fields = STEPAssemblySyntax(entities:reader.entities), a = try fields.arguments(entityID,component:"GLOBAL_UNIT_ASSIGNED_CONTEXT")
            guard a.count == 1 else { throw ImportError.invalidData("Malformed STEP unit context.") }
            var length:LengthUnit?, angle:AngleUnit?
            for id in try fields.list(a[0]) {
                try pay(id,usage:&usage)
                if try fields.hasComponent(id, named: "LENGTH_UNIT") {
                    guard length == nil else { throw ImportError.invalidData("Competing STEP length units.") }
                    let source = try lengthSource(id, fields: fields, depth: 0, usage: &usage)
                    let gain = try source.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
                    // Presentation is selected by exact normative measure, never by a conversion-unit name.
                    // A different foreign law remains authoritative in the retained descriptor and uses canonical metre presentation.
                    try usage.charge(entities: 7, work: 7)
                    let menu: [(LengthUnit, String)] = [(.micrometer, "0.000001"), (.meter, "1"),
                        (.millimeter, "0.001"), (.centimeter, "0.01"), (.kilometer, "1000"), (.inch, "0.0254"), (.foot, "0.3048")]
                    var presentation = LengthUnit.meter
                    for (unit, literal) in menu {
                        let coefficient = try OriginalSTEPDecimal.coefficient(literal, usage: &usage)
                        if try gain.subtracting(coefficient, usage: &usage).isZero { presentation = unit; break }
                    }
                    length = presentation
                }
                if try fields.hasComponent(id,named:"PLANE_ANGLE_UNIT") {
                    guard angle == nil else { throw ImportError.invalidData("Competing STEP angle units.") }
                    angle = try planeAngleUnit(id, fields: fields, usage: &usage)
                }
            }
            guard let length, let angle else { throw ImportError.invalidData("STEP context is missing original length/angle units.") }
            return .init(length:length,angle:angle)
        }
        mutating func contextLengthSource(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPLengthSource {
            if let source = originalLengthContexts[entityID] { try usage.charge(work: 1); return source }
            try pay(entityID, usage: &usage)
            let fields = STEPAssemblySyntax(entities: reader.entities)
            let a = try fields.arguments(entityID, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
            guard a.count == 1 else { throw ImportError.invalidData("Malformed original length context.") }
            var selected: OriginalSTEPLengthSource?
            for id in try fields.list(a[0]) {
                try pay(id, usage: &usage)
                if try fields.hasComponent(id, named: "LENGTH_UNIT") {
                    guard selected == nil else { throw ImportError.invalidData("Competing original length units.") }
                    selected = try lengthSource(id, fields: fields, depth: 0, usage: &usage)
                }
            }
            guard let selected else { throw ImportError.invalidData("Original length unit is missing.") }
            _ = try selected.exactGain(maximumDepth: usage.limits.maximumNesting, usage: &usage)
            try usage.charge(entities: 1, work: 1); originalLengthContexts[entityID] = selected
            return selected
        }
        private mutating func lengthSource(_ id: Int, fields: any STEPFieldReading,
            depth: Int, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPLengthSource {
            guard depth <= usage.limits.maximumNesting else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original length chain depth.") }
            try usage.charge(work: 1)
            if let source = originalLengthUnits[id] { return source }
            guard activeLengthUnits.insert(id).inserted else { throw ImportError.invalidData("Cyclic original length conversion.") }
            defer { activeLengthUnits.remove(id) }
            try pay(id, usage: &usage)
            guard try fields.hasComponent(id, named: "LENGTH_UNIT") else { throw ImportError.invalidData("Original conversion base is not a length unit.") }
            let identity = PortableIdentity128(highBits: 0x535445504C454E55, lowBits: UInt64(id))
            let source: OriginalSTEPLengthSource
            if try fields.hasComponent(id, named: "SI_UNIT") {
                let a = try fields.arguments(id, component: "SI_UNIT")
                guard a.count == 2, a[1] == ".METRE.", try fields.arguments(id, component: "NAMED_UNIT") == ["*"],
                    !(try fields.hasComponent(id, named: "CONVERSION_BASED_UNIT")) else { throw ImportError.invalidData("Malformed original SI length unit.") }
                let prefix: IndependentShapeSIPrefix?
                if a[0] == "$" { prefix = nil }
                else {
                    guard a[0].first == ".", a[0].last == ".",
                        let value = IndependentShapeSIPrefix(rawValue: String(a[0].dropFirst().dropLast())) else { throw ImportError.invalidData("Unknown original length prefix.") }
                    prefix = value
                }
                source = .init(id: identity, law: .metre(prefix: prefix))
            } else {
                guard try fields.hasComponent(id, named: "CONVERSION_BASED_UNIT") else { throw IndependentShapeExchangeError.unsupportedSemantics("Original length unit requires an SI or conversion law.") }
                let named = try fields.arguments(id, component: "NAMED_UNIT")
                let conversion = try fields.arguments(id, component: "CONVERSION_BASED_UNIT")
                guard named.count == 1, conversion.count == 2 else { throw ImportError.invalidData("Malformed original length conversion.") }
                let name = try fields.decodedString(conversion[0], limits: .init(maximumInputBytes: usage.limits.maximumBytes,
                    maximumOutputBytes: usage.limits.maximumBytes - usage.consumedBytes,
                    maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                try usage.charge(work: name.consumedWork, bytes: name.outputBytes)
                let dimensions = try fields.reference(named[0]); try pay(dimensions, usage: &usage)
                guard try fields.name(dimensions) == "DIMENSIONAL_EXPONENTS" else { throw ImportError.invalidData("Original length dimensions are missing.") }
                let exponents = try fields.arguments(dimensions, component: nil)
                guard exponents.count == 7 else { throw ImportError.invalidData("Original length dimensions require seven exponents.") }
                try usage.charge(entities: 7, work: 7)
                let measureID = try fields.reference(conversion[1]); try pay(measureID, usage: &usage)
                let family = try fields.name(measureID)
                let kind: OriginalSTEPLengthConversion.MeasureKind
                let measure: [String]
                switch family {
                case "LENGTH_MEASURE_WITH_UNIT": kind = .lengthMeasureWithUnit; measure = try fields.arguments(measureID, component: nil)
                case "MEASURE_WITH_UNIT": kind = .measureWithUnit; measure = try fields.arguments(measureID, component: nil)
                default:
                    guard family.isEmpty, try fields.hasComponent(measureID, named: "MEASURE_WITH_UNIT"),
                        try fields.hasComponent(measureID, named: "LENGTH_MEASURE_WITH_UNIT") else { throw ImportError.invalidData("Original length factor requires its real measure record.") }
                    kind = .complexLengthMeasureWithUnit; measure = try fields.arguments(measureID, component: "MEASURE_WITH_UNIT")
                }
                guard measure.count == 2, measure[0].hasPrefix("LENGTH_MEASURE("), measure[0].last == ")" else { throw ImportError.invalidData("Original length factor is not a length measure.") }
                let factor = String(measure[0].dropFirst("LENGTH_MEASURE(".count).dropLast())
                try usage.charge(work: factor.utf8.count, bytes: factor.utf8.count)
                let base = try lengthSource(fields.reference(measure[1]), fields: fields, depth: depth + 1, usage: &usage)
                source = .init(id: identity, law: .conversion(.init(name: name.value,
                    dimensionsID: .init(highBits: 0x535445504C454E44, lowBits: UInt64(dimensions)), dimensions: exponents,
                    measureID: .init(highBits: 0x535445504C454E4D, lowBits: UInt64(measureID)), measureKind: kind, factorLiteral: factor, base: base)))
            }
            try usage.charge(entities: 1, work: 1); originalLengthUnits[id] = source
            return source
        }
        mutating func contextAngularSource(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> IndependentShapeAngularSource {
            if let source = originalAngularContexts[entityID] { try usage.charge(work: 1); return source }
            try pay(entityID, usage: &usage)
            let fields = STEPAssemblySyntax(entities: reader.entities), a = try fields.arguments(entityID, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
            guard a.count == 1 else { throw ImportError.invalidData("Malformed original angular context.") }
            var source: IndependentShapeAngularSource?
            for id in try fields.list(a[0]) {
                try pay(id, usage: &usage)
                if try fields.hasComponent(id, named: "PLANE_ANGLE_UNIT") {
                    guard source == nil else { throw ImportError.invalidData("Competing original angular units.") }
                    source = try angularSource(id, fields: fields, depth: 1, usage: &usage)
                }
            }
            guard let source else { throw ImportError.invalidData("Original angular unit is missing.") }
            try usage.charge(entities: 1, work: 1); originalAngularContexts[entityID] = source
            return source
        }
        private mutating func angularSource(_ id: Int, fields: any STEPFieldReading, depth: Int, usage: inout IndependentShapeExchangeUsage) throws -> IndependentShapeAngularSource {
            try usage.charge(work: 1)
            guard depth <= usage.limits.maximumNesting else { throw IndependentShapeExchangeError.resourceLimitExceeded("Original angular chain depth.") }
            if let value = originalAngularUnits[id] { return value }
            guard activeAngularUnits.insert(id).inserted else { throw ImportError.invalidData("Cyclic original angular conversion.") }
            defer { activeAngularUnits.remove(id) }
            try pay(id, usage: &usage)
            guard try fields.hasComponent(id, named: "PLANE_ANGLE_UNIT") else { throw ImportError.invalidData("Angular factor unit is not a plane-angle unit.") }
            let identity = IndependentShapeAngularUnitID(highBits: 0x53544550414E4755, lowBits: UInt64(id))
            let value: IndependentShapeAngularSource
            if try fields.hasComponent(id, named: "SI_UNIT") {
                let si = try fields.arguments(id, component: "SI_UNIT")
                guard si.count == 2, si[1] == ".RADIAN.", try fields.arguments(id, component: "NAMED_UNIT") == ["*"],
                      !(try fields.hasComponent(id, named: "CONVERSION_BASED_UNIT")) else { throw ImportError.invalidData("Malformed original SI radian unit.") }
                let prefix: IndependentShapeSIPrefix?
                if si[0] == "$" { prefix = nil }
                else {
                    guard si[0].hasPrefix("."), si[0].hasSuffix("."), let original = IndependentShapeSIPrefix(rawValue: String(si[0].dropFirst().dropLast())) else { throw ImportError.invalidData("Unknown original SI angular prefix.") }
                    prefix = original
                }
                value = .init(id: identity, law: .radian(prefix: prefix))
            } else {
                guard try fields.hasComponent(id, named: "CONVERSION_BASED_UNIT") else { throw IndependentShapeExchangeError.unsupportedSemantics("Original angular unit requires a conversion or SI law.") }
                let named = try fields.arguments(id, component: "NAMED_UNIT"), conversion = try fields.arguments(id, component: "CONVERSION_BASED_UNIT")
                guard named.count == 1, conversion.count == 2 else { throw ImportError.invalidData("Malformed angular conversion fields.") }
                let name = try fields.decodedString(conversion[0], limits: STEPStringLimits(maximumInputBytes: usage.limits.maximumBytes, maximumOutputBytes: usage.limits.maximumBytes, maximumWork: usage.limits.maximumIterations - usage.consumedWork))
                try usage.charge(work: name.consumedWork)
                let dimensionsID = try fields.reference(named[0]); try pay(dimensionsID, usage: &usage)
                guard try fields.name(dimensionsID) == "DIMENSIONAL_EXPONENTS" else { throw ImportError.invalidData("Original angular dimensions are missing.") }
                let dimensionFields = try fields.arguments(dimensionsID, component: nil)
                try usage.charge(entities: dimensionFields.count, work: dimensionFields.count)
                guard dimensionFields.count == 7 else { throw ImportError.invalidData("Angular dimensions require seven exponents.") }
                var dimensions: [Double] = []
                for field in dimensionFields {
                    try usage.charge(work: field.utf8.count)
                    guard let exponent = Double(field), exponent.isFinite, exponent == 0 else { throw ImportError.invalidData("Original angular dimensions must all be zero.") }
                    dimensions.append(exponent)
                }
                let measureID = try fields.reference(conversion[1]); try pay(measureID, usage: &usage)
                let family = try fields.name(measureID), measureKind: IndependentShapeAngularConversion.MeasureKind
                let measure: [String]
                if family == "PLANE_ANGLE_MEASURE_WITH_UNIT" { measureKind = .planeAngleMeasureWithUnit; measure = try fields.arguments(measureID, component: nil) }
                else if family == "MEASURE_WITH_UNIT" { measureKind = .measureWithUnit; measure = try fields.arguments(measureID, component: nil) }
                else {
                    guard family.isEmpty, try fields.hasComponent(measureID, named: "MEASURE_WITH_UNIT"),
                          try fields.hasComponent(measureID, named: "PLANE_ANGLE_MEASURE_WITH_UNIT") else { throw ImportError.invalidData("Original angular factor requires its real angle measure.") }
                    measureKind = .complexPlaneAngleMeasureWithUnit; measure = try fields.arguments(measureID, component: "MEASURE_WITH_UNIT")
                }
                guard measure.count == 2, measure[0].hasPrefix("PLANE_ANGLE_MEASURE("), measure[0].hasSuffix(")"),
                      let factor = Double(measure[0].dropFirst(20).dropLast()), factor.isFinite, factor > 0 else { throw ImportError.invalidData("Original angular factor must be a positive finite angle measure.") }
                let base = try angularSource(fields.reference(measure[1]), fields: fields, depth: depth + 1, usage: &usage)
                let conversionValue = IndependentShapeAngularConversion(name: name.value, factor: factor,
                    interpretation: factor == AngleUnit.degree.toInternal(1) ? .canonicalDegree : .binary,
                    dimensionsID: .init(highBits: 0x53544550414E4744, lowBits: UInt64(dimensionsID)), dimensions: dimensions,
                    measureID: .init(highBits: 0x53544550414E474D, lowBits: UInt64(measureID)), measureKind: measureKind, base: base)
                value = .init(id: identity, law: .conversion(conversionValue))
            }
            try usage.charge(entities: 1, work: 1); originalAngularUnits[id] = value
            return value
        }
        private mutating func planeAngleUnit(_ id: Int, fields: any STEPFieldReading, usage: inout IndependentShapeExchangeUsage) throws -> AngleUnit {
            let source = try angularSource(id, fields: fields, depth: 1, usage: &usage)
            if case .conversion(let conversion) = source.law, conversion.interpretation == .canonicalDegree, case .radian(nil) = conversion.base.law { return .degree }
            return .radian
        }

        private mutating func originalElement(_ token: String, expected: String,
            usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPPlacementElement {
            let fields = STEPAssemblySyntax(entities: reader.entities)
            let id = try fields.reference(token)
            try pay(id, usage: &usage)
            guard try fields.name(id) == expected else { throw ImportError.invalidData("Original placement element has the wrong family.") }
            let values = try fields.arguments(id)
            guard values.count == 2 else { throw ImportError.invalidData("Malformed original placement element.") }
            try usage.charge(entities: 1, work: values[1].utf8.count + 1)
            var separators = 0
            for byte in values[1].utf8 where byte == 44 {
                separators += 1
                guard separators <= 2 else { throw ImportError.invalidData("Original placement requires exactly three coordinates.") }
            }
            guard separators == 2 else { throw ImportError.invalidData("Original placement requires exactly three coordinates.") }
            let coordinates = try fields.numbers(values[1])
            guard coordinates.count == 3 else { throw ImportError.invalidData("Original placement requires three coordinates.") }
            let name = try fields.decodedString(values[0], limits: .init(maximumInputBytes: usage.limits.maximumBytes,
                maximumOutputBytes: usage.limits.maximumBytes - usage.consumedBytes,
                maximumWork: usage.limits.maximumIterations - usage.consumedWork))
            try usage.charge(work: name.consumedWork, bytes: name.outputBytes)
            return .init(id: .init(highBits: 0x53544550504C454D, lowBits: UInt64(id)), name: name.value,
                coordinates: .init(x: coordinates[0], y: coordinates[1], z: coordinates[2]))
        }

        mutating func mappingSource(entityID: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource? = nil,
                                    usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPPlacementSource {
            try pay(entityID, usage: &usage)
            let fields = STEPAssemblySyntax(entities: reader.entities)
            let arguments = try fields.arguments(entityID)
            func optionalDirection(_ token: String, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPPlacementElement? {
                token == "$" ? nil : try originalElement(token, expected: "DIRECTION", usage: &usage)
            }
            switch try fields.name(entityID) {
            case "AXIS2_PLACEMENT_3D":
                guard arguments.count == 4 else { throw ImportError.invalidData("Malformed original axis placement.") }
                return try .axis2(.init(lengthUnit: units.length,
                    location: originalElement(arguments[1], expected: "CARTESIAN_POINT", usage: &usage),
                    axis: optionalDirection(arguments[2], usage: &usage),
                    referenceDirection: optionalDirection(arguments[3], usage: &usage), originalLengthSource: originalLengthSource))
            case "CARTESIAN_TRANSFORMATION_OPERATOR_3D":
                guard arguments.count == 6 || arguments.count == 8 else { throw ImportError.invalidData("Malformed original uniform operator.") }
                let offset = arguments.count == 8 ? 2 : 0
                let scale: Double?
                if arguments[4 + offset] == "$" { scale = nil }
                else {
                    guard let value = Double(arguments[4 + offset]), value.isFinite, value > 0 else {
                        throw ImportError.invalidData("Original uniform scale must be finite and positive.")
                    }
                    scale = value
                }
                return try .cartesian(.init(lengthUnit: units.length,
                    location: originalElement(arguments[3 + offset], expected: "CARTESIAN_POINT", usage: &usage),
                    axis1: optionalDirection(arguments[1 + offset], usage: &usage),
                    axis2: optionalDirection(arguments[2 + offset], usage: &usage),
                    axis3: optionalDirection(arguments[5 + offset], usage: &usage), scale: scale, originalLengthSource: originalLengthSource))
            default: throw ImportError.invalidData("Unknown original standard placement family.")
            }
        }
        mutating func mappingOrigin(entityID: Int, units: UnitSystem, usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D {
            let source = try mappingSource(entityID: entityID, units: units, usage: &usage)
            return try source.derivedAffineTransform(tolerance: reader.tolerance, maximumDepth: usage.limits.maximumAlgebraicDepth, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)
        }
        mutating func mappingTarget(entityID: Int, units: UnitSystem, usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D {
            let source = try mappingSource(entityID: entityID, units: units, usage: &usage)
            return try source.derivedAffineTransform(tolerance: reader.tolerance, maximumDepth: usage.limits.maximumAlgebraicDepth, maximumSourceDepth: usage.limits.maximumNesting, usage: &usage)
        }

    }
    struct Builder: Sendable {
        let entities: [Int: String]
        let lengthUnit: LengthUnit
        let processingBudget: ExchangeProcessingBudget
        let tolerance: ModelingTolerance
        let representationItems: Set<Int>?

        var bodyEntityTransfer: [Int: BodyID] = [:]
        var faceEntityTransfer: [Int: FaceID] = [:]
        var geometry = GeometryStore()
        var bodies: [BodyID: Body] = [:]
        var shells: [ShellID: Shell] = [:]
        var faces: [FaceID: Face] = [:]
        var loops: [LoopID: Loop] = [:]
        var edges: [EdgeID: Edge] = [:]
        var vertices: [VertexID: Vertex] = [:]

        var pointCache: [Int: Point3D] = [:]
        var directionCache: [Int: Vector3D] = [:]
        var lineCache: [Int: CurveID] = [:]
        var curveTrimCache: [Int: CurveTrim] = [:]
        var planeCache: [Int: SurfaceID] = [:]
        var surfacesBeingBuilt: Set<Int> = []
        var vertexCache: [Int: VertexID] = [:]
        var edgeCache: [Int: EdgeID] = [:]
        var edgeGeometryEntities: [EdgeID: Int] = [:]
        var edgeCurveSameSense: [EdgeID: Bool] = [:]
        var intersectionPcurves: [CurveID: [Surface3D: SurfaceParameterCurve]] = [:]
        var exactTransferTrims: [CurveID: CurveTrim] = [:]
        var implicitIntersectionCache: [Surface3D: [Surface3D: [SurfaceSurfaceIntersection]]] = [:]
        var surfaceLiftTransferCurves: Set<CurveID> = []
        var certifiedIntersectionTransferCurves: Set<CurveID> = []
        var shellOwners: Set<Int> = []
        var orientedShellOwners: Set<Int> = []
        var faceOwners: Set<Int> = []
        var loopOwners: Set<Int> = []

        mutating func buildIndependentGeometry(usage: inout IndependentShapeExchangeUsage) throws -> IndependentSTEPGeometry {
            var curves: [IndependentSTEPCurve] = [], surfaces: [IndependentSTEPSurface] = []
            var consumedSets: Set<Int> = []
            var contextIDs: Set<Int> = []
            var representationCount = 0
            for entityID in entities.keys.sorted() {
                try processingBudget.check(format: .step)
                let entity = try requiredEntity(entityID, label: "independent representation")
                let name = try entityName(entity)
                guard name == "SHAPE_REPRESENTATION"
                    || name == "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION" else { continue }
                let args = try arguments(of: entity, named: name)
                guard args.count == 3 else { throw invalid("Standalone STEP representation is malformed.") }
                let context = try reference(args[2], label: "independent representation context")
                contextIDs.insert(context)
                let setIDs = try referenceList(args[1], label: "independent representation items")
                for setID in setIDs {
                    try processingBudget.check(format: .step)
                    guard consumedSets.insert(setID).inserted else {
                        throw unsupported("Standalone STEP set ownership is shared across representations.")
                    }
                    let set = try requiredEntity(setID, label: "independent geometry set")
                    let kind = try entityName(set)
                    guard kind == "GEOMETRIC_CURVE_SET" || kind == "GEOMETRIC_SET",
                        name != "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION" || kind == "GEOMETRIC_CURVE_SET" else {
                        throw unsupported("Standalone STEP representation has an unsupported item.")
                    }
                    let setArgs = try arguments(of: set, named: kind)
                    guard setArgs.count == 2 else { throw invalid("Standalone STEP set is malformed.") }
                    let itemName = try independentName(setArgs[0], usage: &usage)
                    let itemIDs = try referenceList(setArgs[1], label: "independent geometry elements")
                    guard itemIDs.count == 1, let itemID = itemIDs.first else {
                        throw unsupported("Standalone STEP named sets require exactly one source geometry item.")
                    }
                    if kind == "GEOMETRIC_CURVE_SET" {
                        let (curve, trim) = try independentCurve(itemID)
                        curves.append(.init(name: itemName, curve: curve, trim: trim))
                    } else {
                        let surfaceID = try buildSurface(itemID)
                        guard let surface = geometry.surfaces[surfaceID] else { throw missing("independent surface") }
                        try surface.validate(tolerance: tolerance)
                        surfaces.append(.init(name: itemName, surface: surface))
                    }
                }
                representationCount += 1
            }
            guard representationCount > 0, !curves.isEmpty || !surfaces.isEmpty, contextIDs.count == 1,
                let contextID = contextIDs.first else {
                throw unsupported("Standalone STEP requires nonempty geometry in one explicit representation context.")
            }
            let context = try requiredEntity(contextID, label: "independent context")
            let geometricContext = try complexArguments(of: context, named: "GEOMETRIC_REPRESENTATION_CONTEXT")
            guard geometricContext.count == 1, try integer(geometricContext[0], label: "context dimension") == 3 else {
                throw unsupported("Standalone STEP requires a three-dimensional geometry context.")
            }
            let units = try complexArguments(of: context, named: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
            guard units.count == 1 else { throw invalid("Standalone STEP context units are malformed.") }
            let unitIDs = try referenceList(units[0], label: "context units")
            var radians = 0, lengthUnits = 0
            guard Set(unitIDs).count == unitIDs.count else { throw invalid("Standalone STEP context has duplicate units.") }
            for unitID in unitIDs {
                try processingBudget.check(format: .step)
                let unit = try requiredEntity(unitID, label: "context unit")
                if unit.contains("LENGTH_UNIT()") { lengthUnits += 1 }
                if unit.contains("PLANE_ANGLE_UNIT()") {
                    guard unit.contains("SI_UNIT($,.RADIAN.)") else {
                        throw unsupported("Standalone STEP requires an explicit radian plane-angle unit.")
                    }
                    radians += 1
                }
            }
            guard radians == 1, lengthUnits == 1 else {
                throw invalid("Standalone STEP context requires exactly one length unit and one radian angle unit.")
            }
            for (entityID, entity) in entities {
                try processingBudget.check(format: .step)
                let name = try entityName(entity)
                if name == "GEOMETRIC_CURVE_SET" || name == "GEOMETRIC_SET" {
                    guard consumedSets.contains(entityID) else { throw unsupported("Standalone STEP contains an unowned geometry set.") }
                }
            }
            try processingBudget.check(format: .step)
            return .init(curves: curves, surfaces: surfaces, units: .init(length: lengthUnit, angle: .radian))
        }

        mutating func independentCurve(_ entityID: Int) throws -> (Curve3D, CurveTrim?) {
            try processingBudget.check(format: .step)
            let entity = try requiredEntity(entityID, label: "independent curve")
            if try entityName(entity) == "TRIMMED_CURVE" {
                let args = try arguments(of: entity, named: "TRIMMED_CURVE")
                guard args.count == 6, args[5] == ".PARAMETER." else {
                    throw unsupported("Standalone STEP trims require explicit parameter selectors.")
                }
                if args[0] == "'SWIFTCAD_ARC'" {
                    let curveID = try buildCurve(entityID)
                    guard let curve = geometry.curves[curveID] else { throw missing("independent arc") }
                    return (curve, nil)
                }
                let basisID = try reference(args[1], label: "independent trim basis")
                let curveID = try buildCurve(basisID)
                let curve = try independentStoredCurve(curveID, entityID: basisID)
                var start = try trimmingParameter(args[2]), end = try trimmingParameter(args[3])
                let sense = try boolean(args[4])
                guard start != end, sense == (end > start) else { throw invalid("Standalone STEP trim direction is inconsistent.") }
                switch curve {
                case .line, .analytic(.line):
                    let basis = try requiredEntity(basisID, label: "trimmed line basis")
                    let line = try arguments(of: basis, named: "LINE")
                    guard line.count == 3 else { throw invalid("Standalone STEP line is malformed.") }
                    let vector = try requiredEntity(reference(line[2], label: "line vector"), label: "line vector")
                    let args = try arguments(of: vector, named: "VECTOR")
                    guard args.count == 3, try number(args[2], label: "vector magnitude") == 1 else {
                        throw unsupported("Standalone STEP line parameters require a unit-magnitude vector.")
                    }
                    start = lengthUnit.toInternal(start); end = lengthUnit.toInternal(end)
                default: break
                }
                guard start.isFinite, end.isFinite, start != end,
                    try curve.parameterDomain.containsSpan(from: start, to: end, tolerance: tolerance) else {
                    throw invalid("Standalone STEP trim is outside its source parameter domain.")
                }
                return (curve, .init(startParameter: start, endParameter: end))
            }
            let curveID = try buildCurve(entityID)
            let curve = try independentStoredCurve(curveID, entityID: entityID)
            switch curve {
            case .line, .analytic(.line), .analytic(.hyperbola), .analytic(.parabola):
                throw unsupported("Standalone STEP unbounded curves require finite trims.")
            default: return (curve, nil)
            }
        }

        func independentStoredCurve(_ curveID: CurveID, entityID: Int) throws -> Curve3D {
            guard let curve = geometry.curves[curveID] else { throw missing("independent curve") }
            if case .line(let line) = curve {
                let entity = try requiredEntity(entityID, label: "line source")
                if try entityName(entity) == "LINE",
                   try arguments(of: entity, named: "LINE").first == "'SWIFTCAD_ANALYTIC'" {
                    return .analytic(.line(origin: line.origin, direction: line.direction))
                }
            }
            return curve
        }

        func independentName(_ token: String, usage: inout IndependentShapeExchangeUsage) throws -> String {
            try usage.check()
            let result = try STEPStringCodec().decode(token, limits: STEPStringLimits(
                maximumInputBytes: usage.limits.maximumBytes,
                maximumOutputBytes: usage.limits.maximumBytes - usage.consumedBytes,
                maximumWork: usage.limits.maximumIterations - usage.consumedWork))
            try usage.charge(work: result.consumedWork, bytes: result.outputBytes)
            return result.value
        }

        mutating func build() throws -> BRepModel {
            var representationItemCount = 0
            for entityID in (representationItems ?? Set(entities.keys)).sorted() {
                try processingBudget.check(format: .step)
                guard let entity = entities[entityID] else {
                    continue
                }
                if entity.trimmingCharacters(in: .whitespacesAndNewlines).first == "(" {
                    continue
                }
                switch try entityName(entity) {
                case "MANIFOLD_SOLID_BREP":
                    let arguments = try arguments(of: entity, named: "MANIFOLD_SOLID_BREP")
                    guard arguments.count == 2 else {
                        throw invalid("STEP MANIFOLD_SOLID_BREP #\(entityID) is malformed.")
                    }
                    let shellEntityID = try reference(arguments[1], label: "closed shell")
                    let shellID = try buildShell(shellEntityID, expectedName: "CLOSED_SHELL")
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodyEntityTransfer[entityID] = bodyID
                    bodies[bodyID] = Body(
                        id: bodyID,
                        solidComponents: [SolidShellComponent(outerShellID: shellID)]
                    )
                    representationItemCount += 1
                case "BREP_WITH_VOIDS":
                    let arguments = try arguments(of: entity, named: "BREP_WITH_VOIDS")
                    guard arguments.count == 3 else {
                        throw invalid("STEP BREP_WITH_VOIDS #\(entityID) is malformed.")
                    }
                    let outerEntityID = try reference(arguments[1], label: "outer closed shell")
                    let voidEntityIDs = try referenceList(arguments[2], label: "oriented void shell list")
                    guard !voidEntityIDs.isEmpty else {
                        throw invalid("STEP BREP_WITH_VOIDS #\(entityID) has no void shells.")
                    }
                    var shellIDs = [try buildShell(outerEntityID, expectedName: "CLOSED_SHELL")]
                    for voidEntityID in voidEntityIDs {
                        try processingBudget.check(format: .step)
                        shellIDs.append(try buildVoidShell(voidEntityID))
                    }
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodyEntityTransfer[entityID] = bodyID
                    bodies[bodyID] = Body(
                        id: bodyID,
                        solidComponents: [SolidShellComponent(
                            outerShellID: shellIDs[0],
                            voidShellIDs: Array(shellIDs.dropFirst())
                        )]
                    )
                    representationItemCount += 1
                case "SHELL_BASED_SURFACE_MODEL":
                    let arguments = try arguments(of: entity, named: "SHELL_BASED_SURFACE_MODEL")
                    guard arguments.count == 2 else {
                        throw invalid("STEP SHELL_BASED_SURFACE_MODEL #\(entityID) is malformed.")
                    }
                    let shellEntityIDs = try referenceList(arguments[1], label: "open shell list")
                    guard !shellEntityIDs.isEmpty else {
                        throw invalid("STEP sheet body #\(entityID) has no shells.")
                    }
                    var shellIDs: [ShellID] = []
                    for shellEntityID in shellEntityIDs {
                        try processingBudget.check(format: .step)
                        shellIDs.append(try buildShell(shellEntityID, expectedName: "OPEN_SHELL"))
                    }
                    let bodyID: BodyID = taggedID(namespace: 0x535445505F424F44, entityID: entityID)
                    bodyEntityTransfer[entityID] = bodyID
                    bodies[bodyID] = Body(id: bodyID, sheetShellIDs: shellIDs)
                    representationItemCount += 1
                default:
                    continue
                }
            }
            guard representationItemCount > 0 else {
                throw unsupported("STEP input does not contain an exact manifold solid or sheet model.")
            }
            return BRepModel(
                geometry: try topologyOwnedGeometry(),
                bodies: bodies,
                shells: shells,
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            )
        }

        func topologyOwnedGeometry() throws -> GeometryStore {
            var result = GeometryStore()
            for curveID in Set(edges.values.map(\.curveID)) {
                guard let curve = geometry.curves[curveID] else {
                    throw missing("STEP topology-owned curve \(curveID)")
                }
                result.curves[curveID] = curve
            }
            for surfaceID in Set(faces.values.map(\.surfaceID)) {
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP topology-owned surface \(surfaceID)")
                }
                result.surfaces[surfaceID] = surface
            }
            return result
        }

        mutating func buildShell(_ entityID: Int, expectedName: String) throws -> ShellID {
            guard shellOwners.insert(entityID).inserted else {
                throw unsupported("STEP shell #\(entityID) is shared by multiple bodies.")
            }
            let entity = try requiredEntity(entityID, label: "shell")
            let arguments = try arguments(of: entity, named: expectedName)
            guard arguments.count == 2 else {
                throw invalid("STEP shell #\(entityID) is malformed.")
            }
            let faceEntityIDs = try referenceList(arguments[1], label: "shell face list")
            guard !faceEntityIDs.isEmpty else {
                throw invalid("STEP shell #\(entityID) has no faces.")
            }
            let faceIDs = try faceEntityIDs.map { try buildFace($0) }
            let shellID: ShellID = taggedID(namespace: 0x535445505F53484C, entityID: entityID)
            shells[shellID] = Shell(id: shellID, faceIDs: faceIDs, orientation: .forward)
            return shellID
        }

        mutating func buildVoidShell(_ entityID: Int) throws -> ShellID {
            guard orientedShellOwners.insert(entityID).inserted else {
                throw unsupported("STEP oriented void shell #\(entityID) is referenced more than once.")
            }
            let entity = try requiredEntity(entityID, label: "oriented void shell")
            let arguments = try arguments(of: entity, named: "ORIENTED_CLOSED_SHELL")
            guard arguments.count == 4,
                  arguments[1].trimmingCharacters(in: .whitespacesAndNewlines) == "*",
                  try boolean(arguments[3]) == false else {
                throw unsupported(
                    "STEP oriented void shell #\(entityID) must derive its faces and use orientation FALSE."
                )
            }
            let baseEntityID = try reference(arguments[2], label: "void closed shell")
            let shellID = try buildShell(baseEntityID, expectedName: "CLOSED_SHELL")
            guard var shell = shells[shellID] else {
                throw missing("STEP void closed shell #\(baseEntityID)")
            }
            shell.orientation = .reversed
            shells[shellID] = shell
            return shellID
        }

        mutating func buildFace(_ entityID: Int) throws -> FaceID {
            guard faceOwners.insert(entityID).inserted else {
                throw unsupported("STEP face #\(entityID) is shared by multiple shells.")
            }
            let entity = try requiredEntity(entityID, label: "face")
            let arguments = try arguments(of: entity, named: "ADVANCED_FACE")
            guard arguments.count == 4 else {
                throw invalid("STEP ADVANCED_FACE #\(entityID) is malformed.")
            }
            let surfaceEntityID = try reference(arguments[2], label: "face surface")
            let surfaceID = try buildSurface(surfaceEntityID)
            guard let surface = geometry.surfaces[surfaceID] else {
                throw missing("STEP face surface #\(surfaceEntityID)")
            }
            let boundEntityIDs = try referenceList(arguments[1], label: "face bound list")
            guard !boundEntityIDs.isEmpty else {
                throw invalid("STEP face #\(entityID) has no bounds.")
            }
            var loopIDs: [LoopID] = []
            for boundEntityID in boundEntityIDs {
                try processingBudget.check(format: .step)
                loopIDs.append(try buildLoop(
                    boundEntityID,
                    surfaceEntityID: surfaceEntityID,
                    surface: surface
                ))
            }
            let faceID: FaceID = taggedID(namespace: 0x535445505F464143, entityID: entityID)
            faceEntityTransfer[entityID] = faceID
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: loopIDs,
                orientation: try orientation(arguments[3])
            )
            return faceID
        }

        mutating func buildLoop(
            _ boundEntityID: Int,
            surfaceEntityID: Int,
            surface: Surface3D
        ) throws -> LoopID {
            let bound = try requiredEntity(boundEntityID, label: "face bound")
            let boundName = try entityName(bound)
            guard boundName == "FACE_OUTER_BOUND" || boundName == "FACE_BOUND" else {
                throw unsupported("STEP face bound #\(boundEntityID) is not an exact edge bound.")
            }
            let boundArguments = try arguments(of: bound, named: boundName)
            guard boundArguments.count == 3 else {
                throw invalid("STEP face bound #\(boundEntityID) is malformed.")
            }
            let loopEntityID = try reference(boundArguments[1], label: "edge loop")
            guard loopOwners.insert(loopEntityID).inserted else {
                throw unsupported("STEP edge loop #\(loopEntityID) is shared by multiple faces.")
            }
            let loopEntity = try requiredEntity(loopEntityID, label: "edge loop")
            let loopArguments = try arguments(of: loopEntity, named: "EDGE_LOOP")
            guard loopArguments.count == 2 else {
                throw invalid("STEP EDGE_LOOP #\(loopEntityID) is malformed.")
            }
            var orientedEntityIDs = try referenceList(loopArguments[1], label: "oriented edge list")
            let boundOrientation = try boolean(boundArguments[2])
            if !boundOrientation {
                orientedEntityIDs.reverse()
            }
            var coedges: [Coedge] = []
            for orientedEntityID in orientedEntityIDs {
                try processingBudget.check(format: .step)
                let orientedEntity = try requiredEntity(orientedEntityID, label: "oriented edge")
                let orientedArguments = try arguments(of: orientedEntity, named: "ORIENTED_EDGE")
                guard orientedArguments.count == 5 else {
                    throw invalid("STEP ORIENTED_EDGE #\(orientedEntityID) is malformed.")
                }
                let edgeEntityID = try reference(orientedArguments[3], label: "edge curve")
                let edgeID = try buildEdge(edgeEntityID)
                var edgeOrientation = try orientation(orientedArguments[4])
                if !boundOrientation {
                    edgeOrientation = edgeOrientation == .forward ? .reversed : .forward
                }
                let parameterCurve = try parameterCurve(
                    for: edgeID,
                    orientation: edgeOrientation,
                    surfaceEntityID: surfaceEntityID,
                    surface: surface
                )
                try reconstructSurfaceLiftIfNeeded(
                    edgeID: edgeID,
                    orientation: edgeOrientation,
                    surface: surface,
                    orientedParameterCurve: parameterCurve
                )
                coedges.append(Coedge(
                    edgeID: edgeID,
                    orientation: edgeOrientation,
                    surfaceParameterCurve: parameterCurve
                ))
            }
            let loopID: LoopID = taggedID(namespace: 0x535445505F4C4F50, entityID: loopEntityID)
            loops[loopID] = Loop(
                id: loopID,
                role: boundName == "FACE_OUTER_BOUND" ? .outer : .inner,
                coedges: coedges
            )
            return loopID
        }

        mutating func buildEdge(_ entityID: Int) throws -> EdgeID {
            if let cached = edgeCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "edge curve")
            let arguments = try arguments(of: entity, named: "EDGE_CURVE")
            guard arguments.count == 5 else {
                throw invalid("STEP EDGE_CURVE #\(entityID) is malformed.")
            }
            let startVertexID = try buildVertex(reference(arguments[1], label: "edge start vertex"))
            let endVertexID = try buildVertex(reference(arguments[2], label: "edge end vertex"))
            let geometryEntityID = try reference(arguments[3], label: "edge geometry")
            let curveID = try buildCurve(geometryEntityID)
            let sameSense = try boolean(arguments[4])
            let transferCurve = geometry.curves[curveID]
            let edgeID: EdgeID = taggedID(namespace: 0x535445505F454447, entityID: entityID)
            edges[edgeID] = Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: curveTrimCache[geometryEntityID]
            )
            if let reconstructed = try associatedPlaneTorusCurve(
                surfaceCurveEntityID: geometryEntityID,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                guard let transferCurve,
                      case .bSpline = transferCurve,
                      let transferTrim = curveTrimCache[geometryEntityID] else {
                    throw invalid("STEP plane-torus intersection has incomplete transfer geometry.")
                }
                let exactCurve = Curve3D.analytic(.planeTorus(reconstructed))
                exactTransferTrims[curveID] = try ExactTransferTrimResolver(
                    tolerance: tolerance
                ).resolve(
                    transferCurve: transferCurve,
                    transferTrim: transferTrim,
                    exactCurve: exactCurve,
                    convention: "STEP"
                )
                geometry.curves[curveID] = exactCurve
            } else if let reconstructed = try associatedImplicitIntersection(
                surfaceCurveEntityID: geometryEntityID,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                guard let transferCurve,
                      case .bSpline = transferCurve,
                      let transferTrim = curveTrimCache[geometryEntityID],
                      let startPoint = vertices[startVertexID]?.point,
                      let endPoint = vertices[endVertexID]?.point else {
                    throw invalid("STEP implicit intersection has incomplete transfer geometry.")
                }
                let transferStart = try transferCurve.point(
                    at: sameSense ? transferTrim.startParameter : transferTrim.endParameter,
                    tolerance: tolerance
                )
                let transferEnd = try transferCurve.point(
                    at: sameSense ? transferTrim.endParameter : transferTrim.startParameter,
                    tolerance: tolerance
                )
                guard startPoint.isApproximatelyEqual(
                    to: transferStart,
                    tolerance: tolerance.distance
                ), endPoint.isApproximatelyEqual(
                    to: transferEnd,
                    tolerance: tolerance.distance
                ) else {
                    throw invalid(
                        "STEP implicit intersection edge vertices disagree with same_sense transfer geometry."
                    )
                }
                let exactTransferTrim = try ExactTransferTrimResolver(
                    tolerance: tolerance
                ).resolve(
                    transferCurve: transferCurve,
                    transferTrim: transferTrim,
                    exactCurve: reconstructed.curve,
                    convention: "STEP"
                )
                geometry.curves[curveID] = reconstructed.curve
                exactTransferTrims[curveID] = exactTransferTrim
                intersectionPcurves[curveID] = [
                    reconstructed.firstSurface: reconstructed.firstSurfaceParameterCurve,
                    reconstructed.secondSurface: reconstructed.secondSurfaceParameterCurve,
                ]
            } else if certifiedIntersectionTransferCurves.contains(curveID),
                      let reconstructed = try associatedCertifiedIntersection(
                          surfaceCurveEntityID: geometryEntityID,
                          startPoint: vertices[startVertexID]?.point,
                          endPoint: vertices[endVertexID]?.point
                      ) {
                guard let transferCurve,
                      case .bSpline = transferCurve,
                      let transferTrim = curveTrimCache[geometryEntityID] else {
                    throw invalid("STEP certified intersection has incomplete transfer geometry.")
                }
                exactTransferTrims[curveID] = try ExactTransferTrimResolver(
                    tolerance: tolerance
                ).resolve(
                    transferCurve: transferCurve,
                    transferTrim: transferTrim,
                    exactCurve: reconstructed.curve,
                    convention: "STEP"
                )
                geometry.curves[curveID] = reconstructed.curve
                intersectionPcurves[curveID] = [
                    reconstructed.firstSurface: reconstructed.firstSurfaceParameterCurve,
                    reconstructed.secondSurface: reconstructed.secondSurfaceParameterCurve,
                ]
            }
            guard let curve = geometry.curves[curveID],
                  let startPoint = vertices[startVertexID]?.point,
                  let endPoint = vertices[endVertexID]?.point else {
                throw missing("STEP edge curve geometry")
            }
            switch curve {
            case let .line(lineGeometry):
                let signedSpan = (endPoint - startPoint).dot(lineGeometry.direction)
                guard abs(signedSpan) > tolerance.distance,
                      (signedSpan > 0.0) == sameSense else {
                    throw invalid("STEP EDGE_CURVE #\(entityID) has an inconsistent same_sense value.")
                }
            case .bSpline:
                guard let geometryTrim = curveTrimCache[geometryEntityID] else {
                    throw invalid("STEP B-spline EDGE_CURVE has no explicit finite trim interval.")
                }
                let edgeTrim = sameSense
                    ? geometryTrim
                    : CurveTrim(
                        startParameter: geometryTrim.endParameter,
                        endParameter: geometryTrim.startParameter
                    )
                let expectedStart = try curve.point(
                    at: edgeTrim.startParameter,
                    tolerance: tolerance
                )
                let expectedEnd = try curve.point(
                    at: edgeTrim.endParameter,
                    tolerance: tolerance
                )
                guard startPoint.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ), endPoint.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ) else {
                    throw invalid(
                        "STEP B-spline EDGE_CURVE #\(entityID) endpoints disagree with same_sense."
                    )
                }
                edges[edgeID]?.trim = edgeTrim
            case .circle:
                let trim = try periodicEdgeTrim(
                    curve: curve,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    followsCurve: sameSense,
                    label: "STEP circle EDGE_CURVE #\(entityID)"
                )
                edges[edgeID]?.trim = trim
            case let .analytic(analytic):
                switch analytic {
                case let .line(_, direction):
                    let signedSpan = (endPoint - startPoint).dot(direction)
                    guard abs(signedSpan) > tolerance.distance,
                          (signedSpan > 0.0) == sameSense else {
                        throw invalid("STEP analytic line EDGE_CURVE #\(entityID) has inconsistent orientation.")
                    }
                case .circle, .ellipse:
                    let trim = try periodicEdgeTrim(
                        curve: curve,
                        startPoint: startPoint,
                        endPoint: endPoint,
                        followsCurve: sameSense,
                        label: "STEP analytic conic EDGE_CURVE #\(entityID)"
                    )
                    edges[edgeID]?.trim = trim
                case .hyperbola, .parabola:
                    let startParameter = try curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    ).parameter
                    let endParameter = try curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    ).parameter
                    let parameterTolerance: Double
                    switch analytic {
                    case .hyperbola:
                        parameterTolerance = tolerance.relative
                    case .parabola:
                        parameterTolerance = tolerance.distance
                    case .line, .circle, .arc, .ellipse, .planeTorus:
                        throw invalid("STEP open-conic dispatch is inconsistent.")
                    }
                    guard abs(endParameter - startParameter) > parameterTolerance,
                          (endParameter > startParameter) == sameSense else {
                        throw invalid("STEP analytic open conic EDGE_CURVE #\(entityID) has inconsistent orientation.")
                    }
                    edges[edgeID]?.trim = CurveTrim(
                        startParameter: startParameter,
                        endParameter: endParameter
                    )
                case .arc:
                    guard sameSense, curveTrimCache[geometryEntityID] != nil else {
                        throw invalid("STEP analytic arc EDGE_CURVE #\(entityID) has inconsistent trim semantics.")
                    }
                case .planeTorus:
                    guard let exactTransferTrim = exactTransferTrims[curveID] else {
                        throw invalid("STEP plane-torus edge has no exact transfer interval.")
                    }
                    edges[edgeID]?.trim = sameSense
                        ? exactTransferTrim
                        : CurveTrim(
                            startParameter: exactTransferTrim.endParameter,
                            endParameter: exactTransferTrim.startParameter
                        )
                }
            case .implicit:
                guard let exactTransferTrim = exactTransferTrims[curveID] else {
                    throw invalid("STEP implicit intersection edge has no derived transfer interval.")
                }
                edges[edgeID]?.trim = sameSense
                    ? exactTransferTrim
                    : CurveTrim(
                        startParameter: exactTransferTrim.endParameter,
                        endParameter: exactTransferTrim.startParameter
                    )
            case .surfaceLift:
                throw invalid("STEP curve decoding produced a surface-lift runtime curve without a source certificate.")
            case .certifiedIntersection:
                guard let exactTransferTrim = exactTransferTrims[curveID] else {
                    throw invalid("STEP certified intersection edge has no derived transfer interval.")
                }
                edges[edgeID]?.trim = sameSense
                    ? exactTransferTrim
                    : CurveTrim(
                        startParameter: exactTransferTrim.endParameter,
                        endParameter: exactTransferTrim.startParameter
                    )
            case .parameterImage:
                // The original image's geometry projection retains its foreign parameter authority.
                let first = try curve.parameterProjection(of:startPoint,tolerance:tolerance).parameter
                let last = try curve.parameterProjection(of:endPoint,tolerance:tolerance).parameter
                guard first.isFinite, last.isFinite, first != last else { throw invalid("Degenerate original parameter-image edge.") }
                edges[edgeID]?.trim = CurveTrim(startParameter:first,endParameter:last)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Native retained original-word/chart/connector families require original Body endpoint selection transport.
            // The neutral Body reader does not produce these families on this branch; never infer original trims from rounded projected vertices.
            case .originalAffineWord, .originalAngularTransport, .originalEndpointConnector, .originalConstructionChart, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
                throw invalid("Retained original Body curve requires its original directed endpoint producer.")
            case .rigidImage:
                throw invalid("STEP curve decoding produced an unsupported rigid-image runtime curve.")
            case .affineImage(let image):
                guard case .line(let original) = image.source, let line = curve.exactLinearLocus else {
                    throw invalid("STEP curve decoding produced an unsupported affine-image runtime curve.")
                }
                let signedSpan = (endPoint - startPoint).dot(line.direction)
                guard abs(signedSpan) > tolerance.distance, (signedSpan > 0) == sameSense else {
                    throw invalid("STEP affine LINE EDGE_CURVE #\(entityID) has inconsistent orientation.")
                }
                let vector = image.transform.applying(to: original.direction)
                let origin = image.transform.applying(to: original.origin)
                let startParameter = (startPoint-origin).dot(vector)/vector.dot(vector)
                let endParameter = (endPoint-origin).dot(vector)/vector.dot(vector)
                guard try curve.point(at:startParameter,tolerance:tolerance).isApproximatelyEqual(to:startPoint,tolerance:tolerance.distance),
                      try curve.point(at:endParameter,tolerance:tolerance).isApproximatelyEqual(to:endPoint,tolerance:tolerance.distance) else {
                    throw invalid("STEP affine LINE EDGE_CURVE #\(entityID) vertices leave its original line.")
                }
                edges[edgeID]?.trim = .init(startParameter: startParameter, endParameter: endParameter)
            }
            edgeGeometryEntities[edgeID] = geometryEntityID
            edgeCurveSameSense[edgeID] = sameSense
            edgeCache[entityID] = edgeID
            return edgeID
        }

        mutating func associatedPlaneTorusCurve(
            surfaceCurveEntityID: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> CertifiedPlaneTorusIntersectionCurve? {
            guard let startPoint, let endPoint else { return nil }
            let entity = try requiredEntity(surfaceCurveEntityID, label: "surface curve")
            guard try entityName(entity) == "SURFACE_CURVE" else { return nil }
            let arguments = try arguments(of: entity, named: "SURFACE_CURVE")
            guard arguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(surfaceCurveEntityID) is malformed.")
            }
            let associated = try referenceList(
                arguments[2],
                label: "surface curve associated geometry"
            )
            var surfaces: [Surface3D] = []
            for associatedEntityID in associated {
                let associatedEntity = try requiredEntity(
                    associatedEntityID,
                    label: "surface curve associated geometry"
                )
                if try entityName(associatedEntity) == "PCURVE" { continue }
                let surfaceID = try buildSurface(associatedEntityID)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP associated intersection surface")
                }
                surfaces.append(surface)
            }
            guard surfaces.count == 2 else { return nil }
            let plane = surfaces.first(where: { surface in
                switch surface {
                case .plane, .analytic(.plane): return true
                case .cylinder, .analytic, .bSpline, .procedural: return false
                }
            })
            let torus = surfaces.first(where: { surface in
                if case .analytic(.torus) = surface { return true }
                return false
            })
            guard let plane, let torus else { return nil }
            let candidates = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: torus,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            )
            var matches: [CertifiedPlaneTorusIntersectionCurve] = []
            for candidate in candidates {
                let exactCurve = Curve3D.analytic(.planeTorus(candidate))
                do {
                    _ = try exactCurve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try exactCurve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "STEP plane-torus surface association matches multiple exact intersection components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "STEP plane-torus surface association does not match its edge endpoints."
                )
            }
            return match
        }

        mutating func associatedImplicitIntersection(
            surfaceCurveEntityID: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> (
            curve: Curve3D,
            firstSurface: Surface3D,
            secondSurface: Surface3D,
            firstSurfaceParameterCurve: SurfaceParameterCurve,
            secondSurfaceParameterCurve: SurfaceParameterCurve
        )? {
            guard let startPoint, let endPoint else { return nil }
            let entity = try requiredEntity(surfaceCurveEntityID, label: "surface curve")
            guard try entityName(entity) == "SURFACE_CURVE" else { return nil }
            let arguments = try arguments(of: entity, named: "SURFACE_CURVE")
            guard arguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(surfaceCurveEntityID) is malformed.")
            }
            let associated = try referenceList(
                arguments[2],
                label: "surface curve associated geometry"
            )
            var surfaces: [Surface3D] = []
            for associatedEntityID in associated {
                let associatedEntity = try requiredEntity(
                    associatedEntityID,
                    label: "surface curve associated geometry"
                )
                if try entityName(associatedEntity) == "PCURVE" { continue }
                let surfaceID = try buildSurface(associatedEntityID)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP associated implicit-intersection surface")
                }
                surfaces.append(surface)
            }
            guard surfaces.count == 2,
                  surfaces.contains(where: { surface in
                      if case .bSpline = surface { return true }
                      return false
                  }) else {
                return nil
            }
            let intersections: [SurfaceSurfaceIntersection]
            if let cached = implicitIntersectionCache[surfaces[0]]?[surfaces[1]] {
                intersections = cached
            } else {
                intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                    first: surfaces[0],
                    second: surfaces[1],
                    tolerance: tolerance
                )
                implicitIntersectionCache[surfaces[0], default: [:]][surfaces[1]] = intersections
            }
            var matches: [SurfaceSurfaceIntersectionCurve] = []
            for intersection in intersections {
                guard case let .curve(candidate) = intersection else { continue }
                switch candidate.truth {
                case .implicit, .analyticBSpline:
                    break
                case .parametric, .analyticAnalytic, .quadraticTangency,
                     .analyticBSplineTangency:
                    continue
                }
                do {
                    _ = try candidate.curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try candidate.curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "STEP implicit surface association matches multiple exact intersection components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "STEP implicit surface association does not match its edge endpoints."
                )
            }
            return (
                match.curve,
                surfaces[0],
                surfaces[1],
                match.firstSurfaceParameterCurve,
                match.secondSurfaceParameterCurve
            )
        }

        mutating func associatedCertifiedIntersection(
            surfaceCurveEntityID: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> (
            curve: Curve3D,
            firstSurface: Surface3D,
            secondSurface: Surface3D,
            firstSurfaceParameterCurve: SurfaceParameterCurve,
            secondSurfaceParameterCurve: SurfaceParameterCurve
        )? {
            guard let startPoint, let endPoint else { return nil }
            let entity = try requiredEntity(surfaceCurveEntityID, label: "surface curve")
            guard try entityName(entity) == "SURFACE_CURVE" else { return nil }
            let arguments = try arguments(of: entity, named: "SURFACE_CURVE")
            guard arguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(surfaceCurveEntityID) is malformed.")
            }
            let associated = try referenceList(
                arguments[2],
                label: "surface curve associated geometry"
            )
            var surfaces: [Surface3D] = []
            for associatedEntityID in associated {
                let associatedEntity = try requiredEntity(
                    associatedEntityID,
                    label: "surface curve associated geometry"
                )
                if try entityName(associatedEntity) == "PCURVE" { continue }
                let surfaceID = try buildSurface(associatedEntityID)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("STEP associated certified-intersection surface")
                }
                if surfaces.contains(surface) == false {
                    surfaces.append(surface)
                }
            }
            guard surfaces.count == 2 else { return nil }
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: surfaces[0],
                second: surfaces[1],
                tolerance: tolerance
            )
            var matches: [SurfaceSurfaceIntersectionCurve] = []
            for intersection in intersections {
                guard case let .curve(candidate) = intersection,
                      case .certifiedIntersection = candidate.curve else {
                    continue
                }
                do {
                    _ = try candidate.curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try candidate.curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "STEP certified surface association matches multiple exact intersection components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "STEP certified surface association does not match its edge endpoints."
                )
            }
            guard case let .analyticAnalytic(exact) = match.truth else {
                throw invalid(
                    "STEP certified surface association lost its analytic intersection certificate."
                )
            }
            return (
                match.curve,
                surfaces[0],
                surfaces[1],
                exact.firstSurfaceParameterCurve,
                exact.secondSurfaceParameterCurve
            )
        }

        func periodicEdgeTrim(
            curve: Curve3D,
            startPoint: Point3D,
            endPoint: Point3D,
            followsCurve: Bool,
            label: String
        ) throws -> CurveTrim {
            let period = 2.0 * Double.pi
            let startParameter = try curve.parameterProjection(
                of: startPoint,
                tolerance: tolerance
            ).parameter
            var endParameter = try curve.parameterProjection(
                of: endPoint,
                tolerance: tolerance
            ).parameter
            if followsCurve {
                while endParameter <= startParameter + tolerance.angle {
                    endParameter += period
                }
            } else {
                while endParameter >= startParameter - tolerance.angle {
                    endParameter -= period
                }
            }
            let span = abs(endParameter - startParameter)
            guard span > tolerance.angle,
                  span < period - tolerance.angle else {
                throw unsupported("\(label) has a degenerate or full-period trim interval.")
            }
            return CurveTrim(
                startParameter: startParameter,
                endParameter: endParameter
            )
        }

        mutating func buildVertex(_ entityID: Int) throws -> VertexID {
            if let cached = vertexCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "vertex point")
            let arguments = try arguments(of: entity, named: "VERTEX_POINT")
            guard arguments.count == 2 else {
                throw invalid("STEP VERTEX_POINT #\(entityID) is malformed.")
            }
            let point = try buildPoint(reference(arguments[1], label: "vertex geometry"))
            let vertexID: VertexID = taggedID(namespace: 0x535445505F565458, entityID: entityID)
            vertices[vertexID] = Vertex(id: vertexID, point: point)
            vertexCache[entityID] = vertexID
            return vertexID
        }

        mutating func buildCurve(_ entityID: Int) throws -> CurveID {
            if let cached = lineCache[entityID] {
                return cached
            }
            let edgeGeometry = try requiredEntity(entityID, label: "edge geometry")
            let geometryName = try entityName(edgeGeometry)
            let curveEntityID: Int
            if geometryName == "SURFACE_CURVE" {
                let surfaceCurveArguments = try arguments(of: edgeGeometry, named: "SURFACE_CURVE")
                guard surfaceCurveArguments.count == 4 else {
                    throw invalid("STEP SURFACE_CURVE #\(entityID) is malformed.")
                }
                curveEntityID = try reference(surfaceCurveArguments[1], label: "surface curve 3D curve")
                _ = try referenceList(surfaceCurveArguments[2], label: "surface curve associated geometry")
                let masterRepresentation = surfaceCurveArguments[3]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard masterRepresentation == ".PCURVE_S1."
                        || masterRepresentation == ".CURVE_3D." else {
                    throw unsupported("STEP SURFACE_CURVE #\(entityID) has an unsupported master representation.")
                }
            } else if geometryName == "LINE"
                || geometryName == "CIRCLE"
                || geometryName == "ELLIPSE"
                || geometryName == "HYPERBOLA"
                || geometryName == "PARABOLA"
                || geometryName == "TRIMMED_CURVE"
                || geometryName.isEmpty {
                curveEntityID = entityID
            } else {
                throw unsupported("STEP edge geometry #\(entityID) is not a supported exact curve.")
            }
            if let cached = lineCache[curveEntityID] {
                lineCache[entityID] = cached
                if let trim = curveTrimCache[curveEntityID] {
                    curveTrimCache[entityID] = trim
                }
                return cached
            }
            let entity = try requiredEntity(curveEntityID, label: "curve")
            let curveID: CurveID = taggedID(namespace: 0x535445505F435256, entityID: curveEntityID)
            let concreteName = try entityName(entity)
            if concreteName == "LINE" {
                let lineArguments = try arguments(of: entity, named: "LINE")
                guard lineArguments.count == 3 else {
                    throw unsupported("STEP edge geometry #\(curveEntityID) is not a supported LINE.")
                }
                let origin = try buildPoint(reference(lineArguments[1], label: "line origin"))
                let vectorEntityID = try reference(lineArguments[2], label: "line vector")
                let vectorEntity = try requiredEntity(vectorEntityID, label: "vector")
                let vectorArguments = try arguments(of: vectorEntity, named: "VECTOR")
                guard vectorArguments.count == 3 else {
                    throw invalid("STEP VECTOR #\(vectorEntityID) is malformed.")
                }
                let direction = try buildDirection(reference(vectorArguments[1], label: "vector direction"))
                let magnitude = try number(vectorArguments[2], label: "vector magnitude")
                guard magnitude > 0.0 else {
                    throw invalid("STEP VECTOR #\(vectorEntityID) has a non-positive magnitude.")
                }
                let internalMagnitude = lengthUnit.toInternal(magnitude)
                if internalMagnitude == 1 {
                    let line = Line3D(origin: origin, direction: direction)
                    try line.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .line(line)
                } else {
                    // STEP LINE's parameter multiplies the complete VECTOR, including model-unit magnitude.
                    let basis = try ExactAnalyticFrame.directBasis(for: direction, tolerance: tolerance)
                    let frame = try AffineTransform3D(basisX: direction * internalMagnitude, basisY: basis.u, basisZ: basis.v,
                        translation: Vector3D(x: origin.x, y: origin.y, z: origin.z))
                    geometry.curves[curveID] = .affineImage(try AffineImageCurve3D(
                        source: .line(Line3D(origin: .origin, direction: .unitX)), transform: frame, tolerance: tolerance))
                }
            } else if concreteName == "CIRCLE" {
                let parsed = try parseCircle(entity, entityID: curveEntityID)
                let expectedReference = try parsed.isAnalytic
                    ? ExactAnalyticFrame.analyticBasis(for: parsed.normal, tolerance: tolerance).u
                    : ExactAnalyticFrame.directBasis(for: parsed.normal, tolerance: tolerance).u
                let circleArguments = try arguments(of: entity, named: "CIRCLE")
                let placement = try buildAxisPlacement(
                    reference(circleArguments[1], label: "circle placement")
                )
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP circle #\(curveEntityID) uses an unsupported parameter frame.")
                }
                if parsed.isAnalytic {
                    geometry.curves[curveID] = .analytic(.circle(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius
                    ))
                } else {
                    geometry.curves[curveID] = .circle(Circle3D(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius
                    ))
                }
            } else if concreteName == "ELLIPSE" {
                let ellipseArguments = try arguments(of: entity, named: "ELLIPSE")
                guard ellipseArguments.count == 4, isAnalyticMarker(ellipseArguments[0]) else {
                    throw unsupported("STEP ellipse #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(ellipseArguments[1], label: "ellipse placement")
                )
                let ellipse = AnalyticCurve3D.ellipse(
                    center: placement.origin,
                    normal: placement.axis,
                    majorAxis: placement.reference,
                    majorRadius: lengthUnit.toInternal(
                        try number(ellipseArguments[2], label: "ellipse major radius")
                    ),
                    minorRadius: lengthUnit.toInternal(
                        try number(ellipseArguments[3], label: "ellipse minor radius")
                    )
                )
                try ellipse.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(ellipse)
            } else if concreteName == "HYPERBOLA" {
                let hyperbolaArguments = try arguments(of: entity, named: "HYPERBOLA")
                guard hyperbolaArguments.count == 4,
                      isAnalyticMarker(hyperbolaArguments[0]) else {
                    throw unsupported("STEP hyperbola #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(hyperbolaArguments[1], label: "hyperbola placement")
                )
                let hyperbola = Hyperbola3D(
                    center: placement.origin,
                    normal: placement.axis,
                    transverseAxis: placement.reference,
                    transverseRadius: lengthUnit.toInternal(
                        try number(hyperbolaArguments[2], label: "hyperbola transverse radius")
                    ),
                    conjugateRadius: lengthUnit.toInternal(
                        try number(hyperbolaArguments[3], label: "hyperbola conjugate radius")
                    )
                )
                try hyperbola.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(.hyperbola(hyperbola))
            } else if concreteName == "PARABOLA" {
                let parabolaArguments = try arguments(of: entity, named: "PARABOLA")
                guard parabolaArguments.count == 3,
                      isAnalyticMarker(parabolaArguments[0]) else {
                    throw unsupported("STEP parabola #\(curveEntityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(parabolaArguments[1], label: "parabola placement")
                )
                let parabola = Parabola3D(
                    vertex: placement.origin,
                    normal: placement.axis,
                    axis: placement.reference,
                    focalLength: lengthUnit.toInternal(
                        try number(parabolaArguments[2], label: "parabola focal distance")
                    )
                )
                try parabola.validate(tolerance: tolerance)
                geometry.curves[curveID] = .analytic(.parabola(parabola))
            } else if concreteName == "TRIMMED_CURVE" {
                let trimmedArguments = try arguments(of: entity, named: "TRIMMED_CURVE")
                guard trimmedArguments.count == 6,
                      trimmedArguments[5].uppercased() == ".PARAMETER." else {
                    throw unsupported("STEP trimmed curve #\(curveEntityID) is outside the supported parameter-trim contract.")
                }
                let marker = trimmedArguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let basisEntityID = try reference(trimmedArguments[1], label: "trimmed curve basis")
                let startParameter = try trimmingParameter(trimmedArguments[2])
                let endParameter = try trimmingParameter(trimmedArguments[3])
                let senseAgreement = try boolean(trimmedArguments[4])
                guard abs(endParameter - startParameter) > tolerance.distance,
                      senseAgreement == (endParameter > startParameter) else {
                    throw invalid("STEP trimmed curve #\(curveEntityID) has inconsistent parameter orientation.")
                }
                let trim = CurveTrim(startParameter: startParameter, endParameter: endParameter)
                switch marker {
                case "'SWIFTCAD_ARC'":
                    let basisEntity = try requiredEntity(basisEntityID, label: "trimmed curve basis")
                    let parsed = try parseCircle(basisEntity, entityID: basisEntityID)
                    guard parsed.isAnalytic else {
                        throw unsupported("STEP analytic arc #\(curveEntityID) requires an analytic circle basis.")
                    }
                    let lower = min(startParameter, endParameter)
                    let upper = max(startParameter, endParameter)
                    let arc = AnalyticCurve3D.arc(
                        center: parsed.center,
                        normal: parsed.normal,
                        radius: parsed.radius,
                        startAngle: lower,
                        endAngle: upper
                    )
                    try arc.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(arc)
                case "'SWIFTCAD_BSPLINE_TRIM'":
                    let basisEntity = try requiredEntity(
                        basisEntityID,
                        label: "B-spline trim basis"
                    )
                    let basisCurve = Curve3D.bSpline(try buildBSplineCurve(
                        basisEntity,
                        entityID: basisEntityID
                    ))
                    guard try basisCurve.parameterDomain.containsSpan(
                            from: startParameter,
                            to: endParameter,
                            tolerance: tolerance
                          ) else {
                        throw unsupported("STEP B-spline trim #\(curveEntityID) requires a bounded rational B-spline basis containing its trim interval.")
                    }
                    geometry.curves[curveID] = basisCurve
                default:
                    throw unsupported("STEP trimmed curve #\(curveEntityID) has an unsupported semantic marker.")
                }
                curveTrimCache[curveEntityID] = trim
                curveTrimCache[entityID] = trim
            } else {
                let bSpline = try buildBSplineCurve(entity, entityID: curveEntityID)
                geometry.curves[curveID] = .bSpline(bSpline)
                let representationArguments = try complexArguments(
                    of: entity,
                    named: "REPRESENTATION_ITEM"
                )
                guard representationArguments.count == 1 else {
                    throw invalid(
                        "STEP B-spline curve #\(curveEntityID) has malformed representation metadata."
                    )
                }
                let representationName = representationArguments[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if representationName == "'SWIFTCAD_SURFACE_LIFT'" {
                    surfaceLiftTransferCurves.insert(curveID)
                } else if representationName == "'SWIFTCAD_CERTIFIED_CURVE'" {
                    certifiedIntersectionTransferCurves.insert(curveID)
                }
                guard case let .closed(lower, upper) = bSpline.domain else {
                    throw invalid("STEP B-spline curve #\(curveEntityID) has no finite knot domain.")
                }
                let trim = CurveTrim(startParameter: lower, endParameter: upper)
                curveTrimCache[curveEntityID] = trim
                curveTrimCache[entityID] = trim
            }
            lineCache[curveEntityID] = curveID
            lineCache[entityID] = curveID
            return curveID
        }

        mutating func reconstructSurfaceLiftIfNeeded(
            edgeID: EdgeID,
            orientation: Orientation,
            surface: Surface3D,
            orientedParameterCurve: SurfaceParameterCurve
        ) throws {
            guard let edge = edges[edgeID],
                  surfaceLiftTransferCurves.contains(edge.curveID) else {
                return
            }
            guard case let .bSpline(derivedCurve) = geometry.curves[edge.curveID],
                  let sameSense = edgeCurveSameSense[edgeID],
                  case let .closed(lower, upper) = derivedCurve.domain else {
                throw invalid("STEP surface-lift transfer has incomplete derived curve metadata.")
            }
            let edgeParameterCurve = orientation == .forward
                ? orientedParameterCurve
                : try orientedParameterCurve.reversed(tolerance: tolerance)
            let modelParameterCurve = sameSense
                ? edgeParameterCurve
                : try edgeParameterCurve.reversed(tolerance: tolerance)
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: .bSpline(derivedCurve),
                from: lower,
                to: upper,
                surface: surface,
                parameterCurve: modelParameterCurve,
                options: CurveSurfaceCorrespondenceValidationOptions(
                    maximumSubdivisionDepth: 24,
                    maximumCellCount: 65_536
                ),
                tolerance: tolerance
            )
            let lift = SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: modelParameterCurve
            )
            try lift.validate(tolerance: tolerance)
            geometry.curves[edge.curveID] = .surfaceLift(lift)
            edges[edgeID]?.trim = sameSense
                ? CurveTrim(startParameter: 0.0, endParameter: 1.0)
                : CurveTrim(startParameter: 1.0, endParameter: 0.0)
        }

        mutating func parseCircle(
            _ entity: String,
            entityID: Int
        ) throws -> (center: Point3D, normal: Vector3D, radius: Double, isAnalytic: Bool) {
            let circleArguments = try arguments(of: entity, named: "CIRCLE")
            guard circleArguments.count == 3 else {
                throw invalid("STEP CIRCLE #\(entityID) is malformed.")
            }
            let placement = try buildAxisPlacement(
                reference(circleArguments[1], label: "circle placement")
            )
            let radius = lengthUnit.toInternal(try number(circleArguments[2], label: "circle radius"))
            let circle = Circle3D(center: placement.origin, normal: placement.axis, radius: radius)
            try circle.validate(tolerance: tolerance)
            return (
                placement.origin,
                placement.axis,
                radius,
                isAnalyticMarker(circleArguments[0])
                    || circleArguments[0].trimmingCharacters(in: .whitespacesAndNewlines) == "'SWIFTCAD_ARC_BASIS'"
            )
        }

        func trimmingParameter(_ text: String) throws -> Double {
            let values = try splitTopLevel(tupleContent(text, label: "trimmed curve parameter set"))
            guard values.count == 1 else {
                throw unsupported("STEP trimmed curve parameter set must contain exactly one parameter value.")
            }
            let parameterArguments = try arguments(of: values[0], named: "PARAMETER_VALUE")
            guard parameterArguments.count == 1 else {
                throw invalid("STEP PARAMETER_VALUE is malformed.")
            }
            return try number(parameterArguments[0], label: "trimmed curve parameter")
        }

        mutating func buildSurface(_ entityID: Int) throws -> SurfaceID {
            if let cached = planeCache[entityID] {
                return cached
            }
            guard surfacesBeingBuilt.insert(entityID).inserted else {
                throw invalid("STEP surface references contain a cycle at #\(entityID).")
            }
            defer { surfacesBeingBuilt.remove(entityID) }
            let entity = try requiredEntity(entityID, label: "surface")
            let surfaceName = try entityName(entity)
            if surfaceName.isEmpty {
                let surface = try buildBSplineSurface(entity, entityID: entityID)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .bSpline(surface)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "OFFSET_SURFACE" {
                let offsetArguments = try arguments(of: entity, named: "OFFSET_SURFACE")
                guard offsetArguments.count == 4 else {
                    throw invalid("STEP OFFSET_SURFACE #\(entityID) is malformed.")
                }
                let selfIntersection = offsetArguments[3]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard [".T.", ".F.", ".U."].contains(selfIntersection) else {
                    throw invalid("STEP OFFSET_SURFACE #\(entityID) has a malformed self-intersection logical value.")
                }
                let basisEntityID = try reference(
                    offsetArguments[1],
                    label: "offset basis surface"
                )
                let basisSurfaceID = try buildSurface(basisEntityID)
                guard let basisSurface = geometry.surfaces[basisSurfaceID] else {
                    throw missing("STEP offset basis surface #\(basisEntityID)")
                }
                let surface = Surface3D.procedural(.offset(OffsetSurface3D(
                    source: basisSurface,
                    distance: lengthUnit.toInternal(try number(
                        offsetArguments[2],
                        label: "offset distance"
                    ))
                )))
                try surface.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(
                    namespace: 0x535445505F535246,
                    entityID: entityID
                )
                geometry.surfaces[surfaceID] = surface
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "CYLINDRICAL_SURFACE" {
                let cylinderArguments = try arguments(of: entity, named: "CYLINDRICAL_SURFACE")
                guard cylinderArguments.count == 3 else {
                    throw invalid("STEP CYLINDRICAL_SURFACE #\(entityID) is malformed.")
                }
                let placement = try buildAxisPlacement(
                    reference(cylinderArguments[1], label: "cylinder placement")
                )
                let isAnalytic = isAnalyticMarker(cylinderArguments[0])
                let expectedReference = try isAnalytic
                    ? ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                    : ExactAnalyticFrame.directBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP cylinder #\(entityID) uses an unsupported parameter frame.")
                }
                let cylinder = Cylinder3D(
                    origin: placement.origin,
                    axis: placement.axis,
                    radius: lengthUnit.toInternal(try number(cylinderArguments[2], label: "cylinder radius"))
                )
                try cylinder.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = isAnalytic
                    ? .analytic(.cylinder(
                        origin: cylinder.origin,
                        axis: cylinder.axis,
                        radius: cylinder.radius
                    ))
                    : .cylinder(cylinder)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "CONICAL_SURFACE" {
                let coneArguments = try arguments(of: entity, named: "CONICAL_SURFACE")
                guard coneArguments.count == 4, isAnalyticMarker(coneArguments[0]) else {
                    throw unsupported("STEP conical surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(coneArguments[1], label: "cone placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                let encodedRadius = try number(coneArguments[2], label: "cone placement radius")
                let halfAngle = try number(coneArguments[3], label: "cone half angle")
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle,
                      abs(lengthUnit.toInternal(encodedRadius)) <= tolerance.distance else {
                    throw unsupported("STEP cone #\(entityID) uses an unsupported placement or non-apex radius.")
                }
                let analytic = AnalyticSurface3D.cone(
                    apex: placement.origin,
                    axis: placement.axis,
                    halfAngle: halfAngle
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "SPHERICAL_SURFACE" {
                let sphereArguments = try arguments(of: entity, named: "SPHERICAL_SURFACE")
                guard sphereArguments.count == 3, isAnalyticMarker(sphereArguments[0]) else {
                    throw unsupported("STEP spherical surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(sphereArguments[1], label: "sphere placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance).u
                guard placement.axis.dot(.unitZ) >= 1.0 - tolerance.angle,
                      placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP sphere #\(entityID) uses an unsupported parameter frame.")
                }
                let analytic = AnalyticSurface3D.sphere(
                    center: placement.origin,
                    radius: lengthUnit.toInternal(try number(sphereArguments[2], label: "sphere radius"))
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            if surfaceName == "TOROIDAL_SURFACE" {
                let torusArguments = try arguments(of: entity, named: "TOROIDAL_SURFACE")
                guard torusArguments.count == 4, isAnalyticMarker(torusArguments[0]) else {
                    throw unsupported("STEP toroidal surface #\(entityID) is outside the supported analytic contract.")
                }
                let placement = try buildAxisPlacement(
                    reference(torusArguments[1], label: "torus placement")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP torus #\(entityID) uses an unsupported parameter frame.")
                }
                let analytic = AnalyticSurface3D.torus(
                    center: placement.origin,
                    axis: placement.axis,
                    majorRadius: lengthUnit.toInternal(
                        try number(torusArguments[2], label: "torus major radius")
                    ),
                    minorRadius: lengthUnit.toInternal(
                        try number(torusArguments[3], label: "torus minor radius")
                    )
                )
                try analytic.validate(tolerance: tolerance)
                let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
                geometry.surfaces[surfaceID] = .analytic(analytic)
                planeCache[entityID] = surfaceID
                return surfaceID
            }
            let planeArguments = try arguments(of: entity, named: "PLANE")
            guard planeArguments.count == 2 else {
                throw unsupported("STEP face geometry #\(entityID) is not a supported PLANE.")
            }
            let placement = try buildAxisPlacement(
                reference(planeArguments[1], label: "plane placement")
            )
            let plane = Plane3D(origin: placement.origin, normal: placement.axis)
            try plane.validate(tolerance: tolerance)
            let surfaceID: SurfaceID = taggedID(namespace: 0x535445505F535246, entityID: entityID)
            if isAnalyticMarker(planeArguments[0]) {
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: placement.axis, tolerance: tolerance).u
                guard placement.reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("STEP analytic plane #\(entityID) uses an unsupported parameter frame.")
                }
                geometry.surfaces[surfaceID] = .analytic(.plane(
                    origin: plane.origin,
                    normal: plane.normal
                ))
            } else {
                geometry.surfaces[surfaceID] = .plane(plane)
            }
            planeCache[entityID] = surfaceID
            return surfaceID
        }

        mutating func buildBSplineCurve(_ entity: String, entityID: Int, retainingLogicalAssertions: Bool = false) throws -> BSplineCurve3D {
            let original = try IndependentSTEPSplineFields(fields: STEPAssemblySyntax(entities: entities), entityID: entityID, surface: false)
            let curveArguments = original.basis, knotArguments = original.knots
            let rational = original.rational != nil, rationalArguments = original.rational ?? []
            guard curveArguments.count == 5,
                  knotArguments.count == 3,
                  (!rational || rationalArguments.count == 1),
                  retainingLogicalAssertions || (try boolean(curveArguments[3]) == false && boolean(curveArguments[4]) == false) else {
                throw unsupported("STEP B-spline curve #\(entityID) must be open and non-self-intersecting.")
            }
            let degree = try integer(curveArguments[0], label: "B-spline curve degree")
            let pointIDs = try referenceList(curveArguments[1], label: "B-spline curve control points")
            var controlPoints: [Point3D] = []
            for pointID in pointIDs {
                controlPoints.append(try buildPoint(pointID))
            }
            let multiplicities = try integerList(knotArguments[0], label: "B-spline curve knot multiplicities")
            let distinctKnots = try arbitraryNumberList(knotArguments[1], label: "B-spline curve knots")
            let weights = rational ? try arbitraryNumberList(rationalArguments[0], label: "B-spline curve weights")
                : Array(repeating:1.0,count:controlPoints.count)
            let curve = BSplineCurve3D(
                degree: degree,
                knots: try expandedKnots(
                    values: distinctKnots,
                    multiplicities: multiplicities,
                    label: "B-spline curve"
                ),
                controlPoints: controlPoints,
                weights: weights
            )
            try curve.validate(tolerance: tolerance)
            return curve
        }

        mutating func buildBSplineSurface(_ entity: String, entityID: Int, retainingLogicalAssertions: Bool = false) throws -> BSplineSurface3D {
            let original = try IndependentSTEPSplineFields(fields: STEPAssemblySyntax(entities: entities), entityID: entityID, surface: true)
            let surfaceArguments = original.basis, knotArguments = original.knots
            let rational = original.rational != nil, rationalArguments = original.rational ?? []
            guard surfaceArguments.count == 7,
                  knotArguments.count == 5,
                  (!rational || rationalArguments.count == 1),
                  retainingLogicalAssertions || (try boolean(surfaceArguments[4]) == false && boolean(surfaceArguments[5]) == false && boolean(surfaceArguments[6]) == false) else {
                throw unsupported("STEP B-spline surface #\(entityID) must be open and non-self-intersecting.")
            }
            let uDegree = try integer(surfaceArguments[0], label: "B-spline surface U degree")
            let vDegree = try integer(surfaceArguments[1], label: "B-spline surface V degree")
            let controlRows = try tupleRows(surfaceArguments[2], label: "B-spline surface control net")
            var controlPoints: [[Point3D]] = []
            for row in controlRows {
                let pointIDs = try referenceList(row, label: "B-spline surface control row")
                var points: [Point3D] = []
                for pointID in pointIDs {
                    points.append(try buildPoint(pointID))
                }
                controlPoints.append(points)
            }
            let uMultiplicities = try integerList(knotArguments[0], label: "B-spline surface U multiplicities")
            let vMultiplicities = try integerList(knotArguments[1], label: "B-spline surface V multiplicities")
            let uValues = try arbitraryNumberList(knotArguments[2], label: "B-spline surface U knots")
            let vValues = try arbitraryNumberList(knotArguments[3], label: "B-spline surface V knots")
            let weights: [[Double]]
            if rational {
                let weightRows = try tupleRows(rationalArguments[0], label: "B-spline surface weight net")
                weights = try weightRows.map { try arbitraryNumberList($0, label: "B-spline surface weight row") }
            } else {
                weights = controlPoints.map { Array(repeating:1.0,count:$0.count) }
            }
            guard let first = controlPoints.first, !first.isEmpty,
                  controlPoints.allSatisfy({ $0.count == first.count }),
                  weights.count == controlPoints.count,
                  weights.allSatisfy({ $0.count == first.count }) else {
                throw invalid("STEP B-spline surface #\(entityID) has a nonrectangular control/weight net.")
            }
            // STEP stores [u][v]; the original native surface stores [v][u].
            var nativePoints: [[Point3D]] = [], nativeWeights: [[Double]] = []
            nativePoints.reserveCapacity(first.count); nativeWeights.reserveCapacity(first.count)
            for v in first.indices {
                try processingBudget.check(format: .step)
                var points: [Point3D] = [], rowWeights: [Double] = []
                points.reserveCapacity(controlPoints.count); rowWeights.reserveCapacity(controlPoints.count)
                for u in controlPoints.indices { points.append(controlPoints[u][v]); rowWeights.append(weights[u][v]) }
                nativePoints.append(points); nativeWeights.append(rowWeights)
            }
            let surface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: try expandedKnots(
                    values: uValues,
                    multiplicities: uMultiplicities,
                    label: "B-spline surface U"
                ),
                vKnots: try expandedKnots(
                    values: vValues,
                    multiplicities: vMultiplicities,
                    label: "B-spline surface V"
                ),
                controlPoints: nativePoints,
                weights: nativeWeights
            )
            try surface.validate(tolerance: tolerance)
            return surface
        }

        mutating func buildPoint(_ entityID: Int) throws -> Point3D {
            if let cached = pointCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "cartesian point")
            let arguments = try arguments(of: entity, named: "CARTESIAN_POINT")
            guard arguments.count == 2 else {
                throw invalid("STEP CARTESIAN_POINT #\(entityID) is malformed.")
            }
            let values = try numberList(arguments[1], expectedCount: 3, label: "cartesian coordinates")
            let point = Point3D(
                x: lengthUnit.toInternal(values[0]),
                y: lengthUnit.toInternal(values[1]),
                z: lengthUnit.toInternal(values[2])
            )
            try point.validate()
            pointCache[entityID] = point
            return point
        }

        mutating func buildDirection(_ entityID: Int) throws -> Vector3D {
            if let cached = directionCache[entityID] {
                return cached
            }
            let entity = try requiredEntity(entityID, label: "direction")
            let arguments = try arguments(of: entity, named: "DIRECTION")
            guard arguments.count == 2 else {
                throw invalid("STEP DIRECTION #\(entityID) is malformed.")
            }
            let values = try numberList(arguments[1], expectedCount: 3, label: "direction ratios")
            let direction = try Vector3D(x: values[0], y: values[1], z: values[2]).normalized(
                tolerance: tolerance.distance
            )
            directionCache[entityID] = direction
            return direction
        }

        mutating func buildAxisPlacement(
            _ entityID: Int
        ) throws -> (origin: Point3D, axis: Vector3D, reference: Vector3D) {
            let entity = try requiredEntity(entityID, label: "axis placement")
            let placementArguments = try arguments(of: entity, named: "AXIS2_PLACEMENT_3D")
            guard placementArguments.count == 4 else {
                throw invalid("STEP AXIS2_PLACEMENT_3D #\(entityID) is malformed.")
            }
            let origin = try buildPoint(reference(placementArguments[1], label: "placement origin"))
            let axis = placementArguments[2] == "$" ? Vector3D.unitZ : try buildDirection(reference(placementArguments[2], label: "placement axis"))
            let proposed = placementArguments[3] == "$"
                ? Self.defaultReference(for:axis)
                : try buildDirection(reference(placementArguments[3], label: "placement reference direction"))
            // ISO build_axes projects the supplied reference into the normal plane.
            let referenceDirection = try (proposed-axis*proposed.dot(axis)).normalized(tolerance:tolerance.distance)
            return (origin, axis, referenceDirection)
        }

        static func defaultReference(for axis:Vector3D) -> Vector3D {
            axis == .unitX || axis == -Vector3D.unitX ? .unitY : .unitX
        }

        func parameterCurve(
            for edgeID: EdgeID,
            orientation: Orientation,
            surfaceEntityID: Int,
            surface: Surface3D
        ) throws -> SurfaceParameterCurve {
            guard let edge = edges[edgeID],
                  let startVertex = vertices[edge.startVertexID],
                  let endVertex = vertices[edge.endVertexID],
                  let edgeGeometryEntityID = edgeGeometryEntities[edgeID] else {
                throw missing("STEP exact edge topology")
            }
            let edgeGeometryEntity = try requiredEntity(edgeGeometryEntityID, label: "surface curve")
            guard try entityName(edgeGeometryEntity) == "SURFACE_CURVE" else {
                throw unsupported("STEP exact coedge requires an explicit SURFACE_CURVE p-curve.")
            }
            let surfaceCurveArguments = try arguments(of: edgeGeometryEntity, named: "SURFACE_CURVE")
            guard surfaceCurveArguments.count == 4 else {
                throw invalid("STEP SURFACE_CURVE #\(edgeGeometryEntityID) is malformed.")
            }
            let associatedGeometry = try referenceList(
                surfaceCurveArguments[2],
                label: "surface curve associated geometry"
            )
            guard let curve = geometry.curves[edge.curveID],
                  let curveSameSense = edgeCurveSameSense[edgeID] else {
                throw missing("STEP edge 3D curve")
            }
            let modelStart = curveSameSense ? startVertex.point : endVertex.point
            let modelEnd = curveSameSense ? endVertex.point : startVertex.point
            var matchingPcurves: [Int] = []
            for pcurveEntityID in associatedGeometry {
                try processingBudget.check(format: .step)
                let pcurveEntity = try requiredEntity(pcurveEntityID, label: "p-curve")
                guard try entityName(pcurveEntity) == "PCURVE" else {
                    continue
                }
                let pcurveArguments = try arguments(of: pcurveEntity, named: "PCURVE")
                guard pcurveArguments.count == 3 else {
                    throw invalid("STEP PCURVE #\(pcurveEntityID) is malformed.")
                }
                if try reference(pcurveArguments[1], label: "p-curve basis surface") == surfaceEntityID {
                    matchingPcurves.append(pcurveEntityID)
                }
            }
            let masterRepresentation = surfaceCurveArguments[3]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               let sourceParameterCurve = intersectionPcurves[edge.curveID]?[surface] {
                guard let exactTransferTrim = exactTransferTrims[edge.curveID] else {
                    throw missing("STEP implicit intersection exact transfer trim")
                }
                let startParameter = exactTransferTrim.startParameter
                let endParameter = exactTransferTrim.endParameter
                let increasingParameterCurve = try sourceParameterCurve.trimmed(
                    from: min(startParameter, endParameter),
                    to: max(startParameter, endParameter),
                    curveDomain: curve.parameterDomain,
                    tolerance: tolerance
                )
                let modelParameterCurve = endParameter > startParameter
                    ? increasingParameterCurve
                    : try increasingParameterCurve.reversed(tolerance: tolerance)
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               case let .analytic(.planeTorus(planeTorus)) = curve,
               associatedGeometry.contains(surfaceEntityID) {
                let role: SurfaceIntersectionSurfaceRole
                if surface == planeTorus.planeSurface {
                    role = .first
                } else if surface == planeTorus.torusSurface {
                    role = .second
                } else {
                    throw invalid(
                        "STEP plane-torus coedge surface is not one of its exact source surfaces."
                    )
                }
                let exactIntersection = try CertifiedAnalyticAnalyticIntersectionCurve(
                    planeTorusCurve: planeTorus,
                    firstSurface: planeTorus.planeSurface,
                    secondSurface: planeTorus.torusSurface,
                    tolerance: tolerance
                )
                let period = 2.0 * Double.pi
                guard let exactTransferTrim = exactTransferTrims[edge.curveID] else {
                    throw missing("STEP plane-torus exact transfer trim")
                }
                let startParameter = exactTransferTrim.startParameter
                let endParameter = exactTransferTrim.endParameter
                guard endParameter - startParameter <= period + tolerance.angle else {
                    throw invalid("STEP plane-torus coedge trim exceeds one period.")
                }
                let modelParameterCurve = SurfaceParameterCurve.certifiedAnalyticPair(
                    try CertifiedAnalyticPairSurfaceParameterCurve(
                        intersection: exactIntersection,
                        role: role,
                        startFraction: startParameter / period,
                        endFraction: endParameter / period,
                        tolerance: tolerance
                    )
                )
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            if matchingPcurves.isEmpty,
               masterRepresentation == ".CURVE_3D.",
               associatedGeometry.filter({ $0 == surfaceEntityID }).count == 1 {
                let modelParameterCurve = try ExactAssociatedSurfacePcurveBuilder().build(
                    curve: curve,
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    tolerance: tolerance
                )
                let edgeParameterCurve = curveSameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                return orientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
            }
            guard matchingPcurves.count == 1, let pcurveEntityID = matchingPcurves.first else {
                throw invalid("STEP coedge requires exactly one p-curve for face surface #\(surfaceEntityID).")
            }
            let pcurveEntity = try requiredEntity(pcurveEntityID, label: "p-curve")
            let pcurveArguments = try arguments(of: pcurveEntity, named: "PCURVE")
            let representationEntityID = try reference(pcurveArguments[2], label: "p-curve representation")
            let representationEntity = try requiredEntity(representationEntityID, label: "p-curve representation")
            let representationArguments = try arguments(
                of: representationEntity,
                named: "DEFINITIONAL_REPRESENTATION"
            )
            guard representationArguments.count == 3 else {
                throw invalid("STEP DEFINITIONAL_REPRESENTATION #\(representationEntityID) is malformed.")
            }
            let curveEntityIDs = try referenceList(representationArguments[1], label: "p-curve item list")
            guard curveEntityIDs.count == 1, let curveEntityID = curveEntityIDs.first else {
                throw invalid("STEP p-curve representation must contain exactly one curve.")
            }
            let curveEntity = try requiredEntity(curveEntityID, label: "2D p-curve")
            let modelParameterCurve: SurfaceParameterCurve
            switch try entityName(curveEntity) {
            case "LINE":
                modelParameterCurve = try parameterLineCurve(
                    try line2D(curveEntityID),
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            case "ELLIPSE":
                modelParameterCurve = try parameterEllipseCurve(
                    try ellipse2D(curveEntityID),
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    modelCurve: curve,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            case "":
                modelParameterCurve = try parameterBSplineCurve(
                    curveEntity,
                    modelStart: modelStart,
                    modelEnd: modelEnd,
                    surface: surface,
                    pcurveEntityID: pcurveEntityID
                )
            default:
                throw unsupported("STEP PCURVE #\(pcurveEntityID) uses an unsupported 2D curve.")
            }
            let edgeParameterCurve = curveSameSense
                ? modelParameterCurve
                : try modelParameterCurve.reversed(tolerance: tolerance)
            return orientation == .forward
                ? edgeParameterCurve
                : try edgeParameterCurve.reversed(tolerance: tolerance)
        }

        func parameterLineCurve(
            _ parameterLine: (originX: Double, originY: Double, directionX: Double, directionY: Double),
            modelStart: Point3D,
            modelEnd: Point3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let encodedOrigin = SurfaceParameter(
                u: parameterLine.originX,
                v: parameterLine.originY
            )
            let modelParameterStart = try ExactSurfaceParameterCodec.decode(
                encodedOrigin,
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let reconstructedStart = try surface.point(
                u: modelParameterStart.u,
                v: modelParameterStart.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) origin disagrees with its 3D curve.")
            }
            let projectedEnd = try surface.parameterProjection(
                of: modelEnd,
                    tolerance: tolerance
            )
            let modelParameterEnd = try matchingParameterEnd(
                projectedEnd,
                line: parameterLine,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let reconstructedEnd = try surface.point(
                u: modelParameterEnd.u,
                v: modelParameterEnd.v,
                    tolerance: tolerance
            )
            guard reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) end disagrees with its 3D curve.")
            }
            return .polyline([
                modelParameterStart,
                modelParameterEnd,
            ])
        }

        func parameterEllipseCurve(
            _ ellipse: STEPParameterEllipse,
            modelStart: Point3D,
            modelEnd: Point3D,
            modelCurve: Curve3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let startMatch = try matchingEllipseParameter(
                try surface.parameterProjection(
                    of: modelStart,
                        tolerance: tolerance
                ),
                ellipse: ellipse,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let endMatch = try matchingEllipseParameter(
                try surface.parameterProjection(
                    of: modelEnd,
                        tolerance: tolerance
                ),
                ellipse: ellipse,
                on: surface,
                pcurveEntityID: pcurveEntityID
            )
            let reconstructedStart = try surface.point(
                u: startMatch.parameter.u,
                v: startMatch.parameter.v,
                    tolerance: tolerance
            )
            let reconstructedEnd = try surface.point(
                u: endMatch.parameter.u,
                v: endMatch.parameter.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ), reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse endpoints disagree with its 3D curve.")
            }

            let modelParameter = try modelCurve.parameterProjection(
                of: modelStart,
                    tolerance: tolerance
            ).parameter
            let modelTangent = try modelCurve.differentialGeometry(
                at: modelParameter,
                    tolerance: tolerance
            ).tangent
            let encodedDerivative = ellipse.derivative(at: startMatch.ellipseParameter)
            let decodedOrigin = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x, v: ellipse.center.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let decodedDerivativePoint = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(
                    u: ellipse.center.x + encodedDerivative.x,
                    v: ellipse.center.y + encodedDerivative.y
                ),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let differential = try surface.differentialGeometry(
                u: startMatch.parameter.u,
                v: startMatch.parameter.v,
                    tolerance: tolerance
            )
            let surfaceTangent = differential.tangentU
                * (decodedDerivativePoint.u - decodedOrigin.u)
                + differential.tangentV
                * (decodedDerivativePoint.v - decodedOrigin.v)
            let alignment = surfaceTangent.dot(modelTangent)
            guard abs(alignment) > tolerance.angle else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse tangent is inconsistent with its 3D curve.")
            }

            var endParameter = endMatch.ellipseParameter
            if alignment > 0.0 {
                while endParameter <= startMatch.ellipseParameter + tolerance.angle {
                    endParameter += 2.0 * Double.pi
                }
            } else {
                while endParameter >= startMatch.ellipseParameter - tolerance.angle {
                    endParameter -= 2.0 * Double.pi
                }
            }
            guard abs(endParameter - startMatch.ellipseParameter)
                    <= 2.0 * Double.pi + tolerance.angle else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) ellipse trim exceeds one period.")
            }

            let decodedCenter = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x, v: ellipse.center.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let major = ellipse.majorVector
            let minor = ellipse.minorVector
            let decodedMajor = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x + major.x, v: ellipse.center.y + major.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            let decodedMinor = try ExactSurfaceParameterCodec.decode(
                SurfaceParameter(u: ellipse.center.x + minor.x, v: ellipse.center.y + minor.y),
                on: surface,
                unit: lengthUnit,
                tolerance: tolerance
            )
            return .harmonic(
                center: Point2D(x: decodedCenter.u, y: decodedCenter.v),
                cosine: Point2D(
                    x: decodedMajor.u - decodedCenter.u,
                    y: decodedMajor.v - decodedCenter.v
                ),
                sine: Point2D(
                    x: decodedMinor.u - decodedCenter.u,
                    y: decodedMinor.v - decodedCenter.v
                ),
                startParameter: startMatch.ellipseParameter,
                endParameter: endParameter
            )
        }

        func parameterBSplineCurve(
            _ entity: String,
            modelStart: Point3D,
            modelEnd: Point3D,
            surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameterCurve {
            let curveArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE")
            let knotArguments = try complexArguments(of: entity, named: "B_SPLINE_CURVE_WITH_KNOTS")
            let rationalArguments = try complexArguments(of: entity, named: "RATIONAL_B_SPLINE_CURVE")
            guard curveArguments.count == 5,
                  knotArguments.count == 3,
                  rationalArguments.count == 1,
                  try boolean(curveArguments[3]) == false,
                  try boolean(curveArguments[4]) == false else {
                throw unsupported("STEP p-curve B-spline must be open and non-self-intersecting.")
            }
            let degree = try integer(curveArguments[0], label: "p-curve B-spline degree")
            let pointIDs = try referenceList(curveArguments[1], label: "p-curve control points")
            var controlPoints: [Point2D] = []
            for pointID in pointIDs {
                let pointEntity = try requiredEntity(pointID, label: "2D B-spline control point")
                let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
                guard pointArguments.count == 2 else {
                    throw invalid("STEP 2D B-spline control point #\(pointID) is malformed.")
                }
                let values = try numberList(
                    pointArguments[1],
                    expectedCount: 2,
                    label: "2D B-spline control point"
                )
                let decoded = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(u: values[0], v: values[1]),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance
                )
                controlPoints.append(Point2D(x: decoded.u, y: decoded.v))
            }
            let multiplicities = try integerList(
                knotArguments[0],
                label: "p-curve B-spline knot multiplicities"
            )
            let distinctKnots = try arbitraryNumberList(
                knotArguments[1],
                label: "p-curve B-spline knots"
            )
            let curve = BSplineCurve2D(
                degree: degree,
                knots: try expandedKnots(
                    values: distinctKnots,
                    multiplicities: multiplicities,
                    label: "p-curve B-spline"
                ),
                controlPoints: controlPoints,
                weights: try arbitraryNumberList(
                    rationalArguments[0],
                    label: "p-curve B-spline weights"
                )
            )
            try curve.validate(tolerance: tolerance)
            let parameterCurve = SurfaceParameterCurve.bSpline(curve)
            let start = try parameterCurve.startParameter(tolerance: tolerance)
            let end = try parameterCurve.endParameter(tolerance: tolerance)
            let reconstructedStart = try surface.point(
                u: start.u,
                v: start.v,
                    tolerance: tolerance
            )
            let reconstructedEnd = try surface.point(
                u: end.u,
                v: end.v,
                    tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ), reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) B-spline endpoints disagree with its 3D curve.")
            }
            return parameterCurve
        }

        func matchingParameterEnd(
            _ projection: SurfaceParameterProjection,
            line: (originX: Double, originY: Double, directionX: Double, directionY: Double),
            on surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> SurfaceParameter {
            let base = SurfaceParameter(u: projection.u, v: projection.v)
            let uOffsets = periodicOffsets(for: surface.uDomain)
            let vOffsets = periodicOffsets(for: surface.vDomain)
            let tolerance = ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: lengthUnit, tolerance: tolerance)
            var best: (parameter: SurfaceParameter, distance: Double)?
            for uOffset in uOffsets {
                for vOffset in vOffsets {
                    let candidate = SurfaceParameter(
                        u: base.u + uOffset,
                        v: base.v + vOffset
                    )
                    let encoded = ExactSurfaceParameterCodec.encode(candidate, on: surface, unit: lengthUnit)
                    let offsetX = encoded.u - line.originX
                    let offsetY = encoded.v - line.originY
                    let residual = abs(offsetX * line.directionY - offsetY * line.directionX)
                    let distance = offsetX * line.directionX + offsetY * line.directionY
                    guard residual <= tolerance, distance > tolerance else {
                        continue
                    }
                    if best == nil || distance < best!.distance {
                        best = (candidate, distance)
                    }
                }
            }
            guard let best else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) has no continuous periodic endpoint match.")
            }
            return best.parameter
        }

        func matchingEllipseParameter(
            _ projection: SurfaceParameterProjection,
            ellipse: STEPParameterEllipse,
            on surface: Surface3D,
            pcurveEntityID: Int
        ) throws -> (parameter: SurfaceParameter, ellipseParameter: Double) {
            let uOffsets = periodicOffsets(for: surface.uDomain)
            let vOffsets = periodicOffsets(for: surface.vDomain)
            let tolerance = ExactSurfaceParameterCodec.encodedTolerance(on: surface, unit: lengthUnit, tolerance: tolerance)
            var best: (parameter: SurfaceParameter, ellipseParameter: Double, residual: Double)?
            for uOffset in uOffsets {
                for vOffset in vOffsets {
                    let candidate = SurfaceParameter(
                        u: projection.u + uOffset,
                        v: projection.v + vOffset
                    )
                    let encoded = ExactSurfaceParameterCodec.encode(candidate, on: surface, unit: lengthUnit)
                    let point = Point2D(x: encoded.u, y: encoded.v)
                    let residual = ellipse.residual(of: point)
                    guard residual <= tolerance else {
                        continue
                    }
                    let match = (
                        parameter: candidate,
                        ellipseParameter: ellipse.parameter(of: point),
                        residual: residual
                    )
                    if let current = best {
                        if match.residual < current.residual {
                            best = match
                        }
                    } else {
                        best = match
                    }
                }
            }
            guard let best else {
                throw invalid("STEP PCURVE #\(pcurveEntityID) has no exact ellipse endpoint match.")
            }
            return (best.parameter, best.ellipseParameter)
        }

        func periodicOffsets(for domain: ParameterDomain) -> [Double] {
            guard case let .periodic(period) = domain else {
                return [0.0]
            }
            return [-period, 0.0, period]
        }

        func line2D(_ entityID: Int) throws -> (
            originX: Double,
            originY: Double,
            directionX: Double,
            directionY: Double
        ) {
            let entity = try requiredEntity(entityID, label: "2D line")
            let lineArguments = try arguments(of: entity, named: "LINE")
            guard lineArguments.count == 3 else {
                throw invalid("STEP 2D LINE #\(entityID) is malformed.")
            }
            let pointEntityID = try reference(lineArguments[1], label: "2D line origin")
            let pointEntity = try requiredEntity(pointEntityID, label: "2D cartesian point")
            let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
            guard pointArguments.count == 2 else {
                throw invalid("STEP 2D CARTESIAN_POINT #\(pointEntityID) is malformed.")
            }
            let point = try numberList(pointArguments[1], expectedCount: 2, label: "2D coordinates")
            let vectorEntityID = try reference(lineArguments[2], label: "2D line vector")
            let vectorEntity = try requiredEntity(vectorEntityID, label: "2D vector")
            let vectorArguments = try arguments(of: vectorEntity, named: "VECTOR")
            guard vectorArguments.count == 3,
                  try number(vectorArguments[2], label: "2D vector magnitude") > 0.0 else {
                throw invalid("STEP 2D VECTOR #\(vectorEntityID) is malformed.")
            }
            let directionEntityID = try reference(vectorArguments[1], label: "2D vector direction")
            let directionEntity = try requiredEntity(directionEntityID, label: "2D direction")
            let directionArguments = try arguments(of: directionEntity, named: "DIRECTION")
            guard directionArguments.count == 2 else {
                throw invalid("STEP 2D DIRECTION #\(directionEntityID) is malformed.")
            }
            let direction = try numberList(directionArguments[1], expectedCount: 2, label: "2D direction ratios")
            let normalized = try normalized2D(x: direction[0], y: direction[1])
            return (
                point[0],
                point[1],
                normalized.x,
                normalized.y
            )
        }

        func ellipse2D(_ entityID: Int) throws -> STEPParameterEllipse {
            let entity = try requiredEntity(entityID, label: "2D ellipse")
            let ellipseArguments = try arguments(of: entity, named: "ELLIPSE")
            guard ellipseArguments.count == 4 else {
                throw invalid("STEP 2D ELLIPSE #\(entityID) is malformed.")
            }
            let placementEntityID = try reference(ellipseArguments[1], label: "2D ellipse placement")
            let placementEntity = try requiredEntity(placementEntityID, label: "2D axis placement")
            let placementArguments = try arguments(of: placementEntity, named: "AXIS2_PLACEMENT_2D")
            guard placementArguments.count == 3 else {
                throw invalid("STEP AXIS2_PLACEMENT_2D #\(placementEntityID) is malformed.")
            }
            let pointEntityID = try reference(placementArguments[1], label: "2D placement origin")
            let pointEntity = try requiredEntity(pointEntityID, label: "2D cartesian point")
            let pointArguments = try arguments(of: pointEntity, named: "CARTESIAN_POINT")
            guard pointArguments.count == 2 else {
                throw invalid("STEP 2D CARTESIAN_POINT #\(pointEntityID) is malformed.")
            }
            let center = try numberList(pointArguments[1], expectedCount: 2, label: "2D coordinates")
            let directionEntityID = try reference(placementArguments[2], label: "2D placement direction")
            let directionEntity = try requiredEntity(directionEntityID, label: "2D direction")
            let directionArguments = try arguments(of: directionEntity, named: "DIRECTION")
            guard directionArguments.count == 2 else {
                throw invalid("STEP 2D DIRECTION #\(directionEntityID) is malformed.")
            }
            let direction = try numberList(
                directionArguments[1],
                expectedCount: 2,
                label: "2D direction ratios"
            )
            let normalized = try normalized2D(x: direction[0], y: direction[1])
            return try STEPParameterEllipse(
                center: Point2D(x: center[0], y: center[1]),
                majorDirection: Point2D(x: normalized.x, y: normalized.y),
                majorRadius: try number(ellipseArguments[2], label: "2D ellipse major radius"),
                minorRadius: try number(ellipseArguments[3], label: "2D ellipse minor radius"),
                tolerance: tolerance.distance
            )
        }

        func normalized2D(x: Double, y: Double) throws -> (x: Double, y: Double) {
            let length = hypot(x, y)
            guard length.isFinite, length > tolerance.distance else {
                throw invalid("STEP 2D direction has zero length.")
            }
            return (x / length, y / length)
        }

        func requiredEntity(_ entityID: Int, label: String) throws -> String {
            guard let entity = entities[entityID] else {
                throw missing("\(label) #\(entityID)")
            }
            return entity
        }

        func entityName(_ entity: String) throws -> String {
            let trimmed = entity.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "(" {
                return ""
            }
            guard let opening = trimmed.firstIndex(of: "("), opening > trimmed.startIndex else {
                throw invalid("STEP entity syntax is malformed.")
            }
            return String(trimmed[..<opening]).uppercased()
        }

        func isAnalyticMarker(_ text: String) -> Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines) == "'SWIFTCAD_ANALYTIC'"
        }

        func complexArguments(of entity: String, named name: String) throws -> [String] {
            let marker = "\(name)("
            var searchStart = entity.startIndex
            var markerRange: Range<String.Index>?
            while let candidate = entity.range(
                of: marker,
                range: searchStart..<entity.endIndex
            ) {
                let isComponentBoundary: Bool
                if candidate.lowerBound == entity.startIndex {
                    isComponentBoundary = true
                } else {
                    let preceding = entity[entity.index(before: candidate.lowerBound)]
                    isComponentBoundary = preceding == "(" || preceding.isWhitespace
                }
                if isComponentBoundary {
                    markerRange = candidate
                    break
                }
                searchStart = candidate.upperBound
            }
            guard let markerRange else {
                throw unsupported("STEP complex entity does not contain \(name).")
            }
            let opening = entity.index(before: markerRange.upperBound)
            var cursor = entity.index(after: opening)
            let contentStart = cursor
            var depth = 1
            var inString = false
            while cursor < entity.endIndex {
                let character = entity[cursor]
                if character == "'" {
                    inString.toggle()
                } else if !inString {
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                        if depth == 0 {
                            return try splitTopLevel(String(entity[contentStart..<cursor]))
                        }
                    }
                }
                cursor = entity.index(after: cursor)
            }
            throw invalid("STEP complex \(name) component is unterminated.")
        }

        func arguments(of entity: String, named expectedName: String) throws -> [String] {
            let trimmed = entity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard try entityName(trimmed) == expectedName,
                  let opening = trimmed.firstIndex(of: "("),
                  trimmed.last == ")" else {
                throw unsupported("STEP entity is not a supported \(expectedName).")
            }
            let contentStart = trimmed.index(after: opening)
            let contentEnd = trimmed.index(before: trimmed.endIndex)
            return try splitTopLevel(String(trimmed[contentStart..<contentEnd]))
        }

        func splitTopLevel(_ text: String) throws -> [String] {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            var values: [String] = []
            var depth = 0
            var inString = false
            var start = text.startIndex
            var cursor = text.startIndex
            while cursor < text.endIndex {
                let character = text.unicodeScalars[cursor]
                if character == "'" {
                    let next = text.unicodeScalars.index(after: cursor)
                    if inString, next < text.endIndex, text.unicodeScalars[next] == "'" {
                        cursor = text.unicodeScalars.index(after: next)
                        continue
                    }
                    inString.toggle()
                } else if !inString {
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                    } else if character == ",", depth == 0 {
                        values.append(String(text[start..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines))
                        start = text.unicodeScalars.index(after: cursor)
                    }
                    guard depth >= 0 else {
                        throw invalid("STEP tuple syntax is malformed.")
                    }
                }
                cursor = text.unicodeScalars.index(after: cursor)
            }
            guard !inString, depth == 0 else {
                throw invalid("STEP tuple syntax is unterminated.")
            }
            values.append(String(text[start..<text.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard values.allSatisfy({ !$0.isEmpty }) else {
                throw invalid("STEP tuple contains an empty value.")
            }
            return values
        }

        func reference(_ text: String, label: String) throws -> Int {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.first == "#",
                  value.dropFirst().allSatisfy(\.isNumber),
                  let entityID = Int(value.dropFirst()) else {
                throw invalid("STEP \(label) reference is malformed.")
            }
            return entityID
        }

        func referenceList(_ text: String, label: String) throws -> [Int] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try reference($0, label: label) }
        }

        func numberList(_ text: String, expectedCount: Int, label: String) throws -> [Double] {
            let content = try tupleContent(text, label: label)
            let values = try splitTopLevel(content).map { try number($0, label: label) }
            guard values.count == expectedCount else {
                throw invalid("STEP \(label) must contain \(expectedCount) values.")
            }
            return values
        }

        func arbitraryNumberList(_ text: String, label: String) throws -> [Double] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try number($0, label: label) }
        }

        func integerList(_ text: String, label: String) throws -> [Int] {
            let content = try tupleContent(text, label: label)
            return try splitTopLevel(content).map { try integer($0, label: label) }
        }

        func tupleRows(_ text: String, label: String) throws -> [String] {
            try splitTopLevel(tupleContent(text, label: label))
        }

        func expandedKnots(
            values: [Double],
            multiplicities: [Int],
            label: String
        ) throws -> [Double] {
            guard !values.isEmpty, values.count == multiplicities.count,
                  multiplicities.allSatisfy({ $0 > 0 }) else {
                throw invalid("STEP \(label) knot data is inconsistent.")
            }
            var knots: [Double] = []
            for (value, multiplicity) in zip(values, multiplicities) {
                knots.append(contentsOf: repeatElement(value, count: multiplicity))
            }
            return knots
        }

        func tupleContent(_ text: String, label: String) throws -> String {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.first == "(", value.last == ")" else {
                throw invalid("STEP \(label) tuple is malformed.")
            }
            return String(value.dropFirst().dropLast())
        }

        func number(_ text: String, label: String) throws -> Double {
            guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
                throw invalid("STEP \(label) is not a finite number.")
            }
            return value
        }

        func integer(_ text: String, label: String) throws -> Int {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw invalid("STEP \(label) is not an integer.")
            }
            return value
        }

        func boolean(_ text: String) throws -> Bool {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case ".T.": true
            case ".F.": false
            default: throw invalid("STEP logical value is malformed.")
            }
        }

        func orientation(_ text: String) throws -> Orientation {
            try boolean(text) ? .forward : .reversed
        }

        func taggedID<Tag>(namespace: UInt64, entityID: Int) -> TaggedID<Tag> {
            TaggedID<Tag>(highBits: namespace, lowBits: UInt64(entityID))
        }

        func invalid(_ message: String) -> ImportError {
            .invalidData(message)
        }

        func missing(_ label: String) -> ImportError {
            .missingRequiredEntity(label)
        }

        func unsupported(_ message: String) -> KernelError {
            KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: message
            )
        }
    }
}
