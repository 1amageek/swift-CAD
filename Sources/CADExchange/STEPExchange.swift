import Foundation
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology

public struct STEPExchange: IndependentSTEPGeometryExchanging, CertifiedDocumentGeometryExchanging {
    private let resourceLimits: ExchangeResourceLimits
    private let tolerance: ModelingTolerance
    private let allowsGroupSemanticLoss: Bool
    private let surfaceOverrides: [Surface3D: BSplineSurface3D]
    private let curveConversions: ExchangeCurveConversionPlan
    private let processingBudgetOverride: ExchangeProcessingBudget?

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
        surfaceOverrides = [:]; curveConversions = .init(); processingBudgetOverride = nil; allowsGroupSemanticLoss = false
    }

    init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits, surfaceOverrides: [Surface3D: BSplineSurface3D], curveConversions: ExchangeCurveConversionPlan = .init(), processingBudget: ExchangeProcessingBudget? = nil, allowsGroupSemanticLoss: Bool = false) {
        self.tolerance = tolerance; self.resourceLimits = resourceLimits; self.surfaceOverrides = surfaceOverrides; self.curveConversions = curveConversions; processingBudgetOverride = processingBudget; self.allowsGroupSemanticLoss = allowsGroupSemanticLoss
    }
    /// Used only after the parent has admitted the concrete original group losses.
    func permittingReportedGroupLoss() -> Self {
        Self(tolerance: tolerance, resourceLimits: resourceLimits, surfaceOverrides: surfaceOverrides,
            curveConversions: curveConversions, processingBudget: processingBudgetOverride, allowsGroupSemanticLoss: true)
    }
    public func write(_ evaluated: EvaluatedDocument, units: UnitSystem? = nil,
        geometryPolicy: ExchangeGeometryConversionPolicy, to sink: any ByteSink) throws -> [ExchangeSurfaceConversionGuarantee] {
        try conversionWrite(evaluated, units: units, policy: geometryPolicy, permitsCurveReports: false, to: sink).surfaceConversions
    }
    public func writeConverting(_ evaluated: EvaluatedDocument, units: UnitSystem? = nil,
        geometryPolicy: ExchangeGeometryConversionPolicy, to sink: any ByteSink) throws -> ExchangeGeometryConversionReport {
        try conversionWrite(evaluated, units: units, policy: geometryPolicy, permitsCurveReports: true, to: sink)
    }
    private func conversionWrite(_ evaluated: EvaluatedDocument, units: UnitSystem?, policy: ExchangeGeometryConversionPolicy,
        permitsCurveReports: Bool, to sink: any ByteSink) throws -> ExchangeGeometryConversionReport {
        try evaluated.validate()
        let local = evaluated.assembly?.local.model ?? evaluated.brep
        let ledger = try ExchangeConversionLedger(limits: resourceLimits, format: .step)
        var execution = try ledger.execution()
        var stores = [local.geometry]
        if let independent = evaluated.document.independentShapes { stores.append(independent.geometry) }
        let surfaces = try ExchangeSurfaceConversionPlanner().plan(stores: stores, policy: policy, format: .step,
            tolerance: tolerance, limits: resourceLimits, ledger: ledger, using: &execution)
        let curves = try ExchangeCurveConversionPlanner().plan(breps: [local], independent: evaluated.document.independentShapes,
            policy: policy, tolerance: tolerance, ledger: ledger, using: &execution, surfaceOverrides: surfaces.overrides)
        guard permitsCurveReports || curves.guarantees.isEmpty else {
            throw IndependentShapeExchangeError.unsupportedSemantics("The legacy surface-only result cannot report a curve conversion; use writeConverting.")
        }
        let remainingLimits = try ledger.remainingLimits()
        let output = DataByteSink()
        try STEPExchange(tolerance: tolerance, resourceLimits: remainingLimits,
            surfaceOverrides: surfaces.overrides, curveConversions: curves, processingBudget: surfaces.budget, allowsGroupSemanticLoss: allowsGroupSemanticLoss).write(evaluated, units: units, to: output)
        try ledger.snapshot().checkTime(); try sink.write(output.bytes)
        return .init(curveConversions: curves.guarantees, surfaceConversions: surfaces.guarantees)
    }
    public func write(_ document: CADDocument, units: UnitSystem? = nil,
        geometryPolicy: ExchangeGeometryConversionPolicy, to sink: any ByteSink) throws -> [ExchangeSurfaceConversionGuarantee] {
        try conversionWrite(document, units: units, policy: geometryPolicy, permitsCurveReports: false, to: sink).surfaceConversions
    }
    public func writeConverting(_ document: CADDocument, units: UnitSystem? = nil,
        geometryPolicy: ExchangeGeometryConversionPolicy, to sink: any ByteSink) throws -> ExchangeGeometryConversionReport {
        try conversionWrite(document, units: units, policy: geometryPolicy, permitsCurveReports: true, to: sink)
    }
    private func conversionWrite(_ document: CADDocument, units: UnitSystem?, policy: ExchangeGeometryConversionPolicy,
        permitsCurveReports: Bool, to sink: any ByteSink) throws -> ExchangeGeometryConversionReport {
        guard let independent = document.independentShapes, document.designGraph.nodes.isEmpty,
            document.assembly == nil, document.productAttributes.isEmpty else {
            return try conversionWrite(DocumentEvaluator(tolerance: tolerance).evaluateExact(document), units: units,
                policy: policy, permitsCurveReports: permitsCurveReports, to: sink)
        }
        let ledger = try ExchangeConversionLedger(limits: resourceLimits, format: .step)
        var execution = try ledger.execution()
        let surfaces = try ExchangeSurfaceConversionPlanner().plan(stores: [independent.geometry], policy: policy,
            format: .step, tolerance: tolerance, limits: resourceLimits, ledger: ledger, using: &execution)
        let curves = try ExchangeCurveConversionPlanner().plan(breps: [], independent: independent, policy: policy,
            tolerance: tolerance, ledger: ledger, using: &execution, surfaceOverrides: surfaces.overrides)
        guard permitsCurveReports || curves.guarantees.isEmpty else {
            throw IndependentShapeExchangeError.unsupportedSemantics("The legacy surface-only result cannot report a curve conversion; use writeConverting.")
        }
        let remainingLimits = try ledger.remainingLimits()
        let output = DataByteSink()
        try STEPExchange(tolerance: tolerance, resourceLimits: remainingLimits,
            surfaceOverrides: surfaces.overrides, curveConversions: curves, processingBudget: surfaces.budget, allowsGroupSemanticLoss: allowsGroupSemanticLoss).write(document, units: units, to: output)
        try ledger.snapshot().checkTime(); try sink.write(output.bytes)
        return .init(curveConversions: curves.guarantees, surfaceConversions: surfaces.guarantees)
    }

    public func write(
        brep: BRepModel,
        units: UnitSystem = .meters,
        to sink: any ByteSink
    ) throws {
        try units.validate()
        try tolerance.validate()
        try resourceLimits.validate()
        try brep.validate(level: .exact, tolerance: tolerance)
        try ExactSTEPWriter(
            resourceLimits: resourceLimits,
            tolerance: tolerance, surfaceOverrides: surfaceOverrides, curveConversions: curveConversions, processingBudget: processingBudgetOverride, allowsGroupSemanticLoss: allowsGroupSemanticLoss
        ).write(
            brep: brep,
            units: units,
            to: sink
        )
    }

    public func write(_ evaluated: EvaluatedDocument, units: UnitSystem? = nil, to sink: any ByteSink) throws {
        if evaluated.document.independentShapes != nil, evaluated.document.designGraph.nodes.isEmpty,
           evaluated.document.assembly == nil, evaluated.document.productAttributes.isEmpty {
            try write(evaluated.document, units: units, to: sink)
            return
        }
        let outputUnits = units ?? evaluated.document.units
        if evaluated.document.assembly != nil {
            try STEPAssemblyWriter(tolerance: tolerance, resourceLimits: resourceLimits, surfaceOverrides: surfaceOverrides, curveConversions: curveConversions, processingBudget: processingBudgetOverride, allowsGroupSemanticLoss: allowsGroupSemanticLoss)
                .write(evaluated, units: outputUnits, to: sink)
        } else {
            try outputUnits.validate(); try resourceLimits.validate()
            let resolved = try ProductAttributeResolver().resolve(evaluated, limits: ProductAttributeLimits(
                maximumRecords: resourceLimits.maximumEntities, maximumTargets: resourceLimits.maximumEntities,
                maximumDepth: resourceLimits.maximumNesting, maximumTextBytes: resourceLimits.maximumBytes,
                maximumWork: resourceLimits.maximumIterations))
            let attributes = STEPAttributesWriter()
            let names = try attributes.geometryNames(for: evaluated, resolved: resolved, limits: resourceLimits)
            let writer = ExactSTEPWriter(resourceLimits: resourceLimits, tolerance: tolerance, surfaceOverrides: surfaceOverrides, curveConversions: curveConversions, processingBudget: processingBudgetOverride, allowsGroupSemanticLoss: allowsGroupSemanticLoss)
            let processing = processingBudgetOverride ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
            var table = try ExactSTEPWriter.EntityTable(maximumEntities: resourceLimits.maximumEntities,
                tolerance: tolerance, maximumBytes: resourceLimits.maximumBytes, maximumStringWork: resourceLimits.maximumIterations,
                maximumSourceDepth: resourceLimits.maximumNesting, maximumAlgebraicDepth: resourceLimits.maximumAlgebraicDepth, processingBudget: processing, maximumSubdivisionDepth: resourceLimits.maximumCurveSubdivisionDepth)
            var execution = try table.execution()
            if evaluated.document.independentShapes != nil {
                table.independentUsage = try IndependentShapeExchangeOwner(limits: resourceLimits, format: .step, processing: processing,
                    originalBudget: table.originalBudget)
                try table.independentUsage!.charge(work: resolved.consumedWork, using: &execution)
            }
            let product = try writer.appendDefinition(brep: evaluated.brep, units: outputUnits,
                identifier: "SWIFTCAD", name: evaluated.document.metadata.name ?? "",
                additionalItems: [], bodyNames: names.bodies, faceNames: names.faces, table: &table, using: &execution)
            try STEPSourceIdentityWriter().append(uuid: evaluated.document.id.description, role: .documentCarrier,
                target: product.definition, table: &table, using: &execution)
            var transfer = STEPAttributeWriteTransfer()
            transfer.products[AssemblyDefinitionID()] = STEPAttributeProductRepresentation(definition: product.definition,
                definitionShape: product.definitionShape, representation: product.representation, context: product.context,
                geometryRepresentation: product.geometryRepresentation, carrier: product.carrier, bodies: product.bodies, faces: product.faces)
            let records = try attributes.records(for: evaluated, resolved: resolved, transfer: transfer,
                startingAt: table.entities.count + 1, limits: resourceLimits)
            for record in records { _ = try table.add(record, using: &execution) }
            if let independent = evaluated.document.independentShapes {
                guard var usage = table.independentUsage else { throw IndependentShapeExchangeError.invalidAssociation("Missing composed STEP caller ledger.") }
                try usage.validateDocument(evaluated.document, tolerance: tolerance, using: &execution)
                var bodyBindings: [SubshapeID: IndependentSTEPBodyBinding] = [:]
                for (selector, reference) in evaluated.subshapes.entries {
                    try usage.charge(entities: 1, work: 1, using: &execution)
                    guard case .body(let id) = reference else { continue }
                    guard let entities = product.bodies[id], entities.count == 1, let entity = entities.first else {
                        throw IndependentShapeExchangeError.invalidAssociation("Original Body selector has no sole emitted source entity.")
                    }
                    bodyBindings[selector] = try IndependentSTEPBodyBinding(entityID: entity, lengthUnit: outputUnits.length)
                }
                try writer.appendIndependent(independent, units: outputUnits, table: &table,
                    bodyBindings: bodyBindings, bodySourceGraph: evaluated.document.designGraph, usage: usage, using: &execution)
            }
            try writer.publish(table: table, to: sink, using: &execution)
        }
    }

    public func write(_ document: CADDocument, units: UnitSystem? = nil, to sink: any ByteSink) throws {
        guard let source = document.independentShapes else {
            try write(DocumentEvaluator(tolerance:tolerance).evaluateExact(document),units:units,to:sink)
            return
        }
        guard document.designGraph.nodes.isEmpty, document.assembly == nil, document.productAttributes.isEmpty else {
            try write(DocumentEvaluator(tolerance: tolerance).evaluateExact(document), units: units, to: sink)
            return
        }
        var usage = try IndependentShapeExchangeOwner(limits:resourceLimits,format:.step,processing:processingBudgetOverride ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration),consumedEntities:0,consumedWork:0,consumedBytes:0)
        var execution = try usage.execution()
        try usage.validateDocument(document,tolerance:tolerance, using: &execution)
        try ExactSTEPWriter(resourceLimits:resourceLimits,tolerance:tolerance,surfaceOverrides:surfaceOverrides,curveConversions:curveConversions,processingBudget:processingBudgetOverride,allowsGroupSemanticLoss:allowsGroupSemanticLoss)
            .writeIndependent(source,units:units ?? document.units,to:sink,usage:usage, using: &execution)
    }

    public func writeIndependentGeometry(_ model: IndependentSTEPGeometry, to sink: any ByteSink) throws {
        try ExactSTEPWriter(resourceLimits: resourceLimits, tolerance: tolerance)
            .writeIndependentGeometry(model, to: sink)
    }

    public func importIndependentGeometry(_ source: any ByteSource) throws -> IndependentSTEPGeometry {
        try tolerance.validate(); try resourceLimits.validate()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        return try source.withNoCopyData { data in
            try budget.check(format: .step)
            guard data.count <= resourceLimits.maximumBytes else {
                throw KernelError(phase: .exchange, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Standalone STEP input exceeds its byte budget.")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("STEP data is not UTF-8.")
            }
            let lexicalWork = try validateSTEPResourceBudget(text, budget: budget)
            try validateSTEPExchangeEnvelope(in: text)
            let sections = try stepDataSections(in: text)
            try rejectSTEPEntityMarkersOutsideDataSections(in: text, dataRanges: sections.map(\.contentRange))
            guard !sections.isEmpty else { throw ImportError.invalidData("Missing STEP DATA section.") }
            let entities = try stepEntities(in: sections.map(\.content).joined(separator: "\n"))
            guard !entities.isEmpty else { throw ImportError.invalidData("STEP DATA section contains no entities.") }
            guard entities.count <= resourceLimits.maximumEntities else {
                throw KernelError(phase: .exchange, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Standalone STEP input exceeds its entity budget.")
            }
            let additional = ["GEOMETRIC_CURVE_SET(", "GEOMETRIC_SET(",
                "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION("]
            let forbidden = ["PRODUCT(", "PRODUCT_CONTEXT(", "PRODUCT_DEFINITION(",
                "PRODUCT_DEFINITION_FORMATION(", "PRODUCT_DEFINITION_SHAPE(", "SHAPE_DEFINITION_REPRESENTATION(",
                "MANIFOLD_SOLID_BREP(", "BREP_WITH_VOIDS(", "SHELL_BASED_SURFACE_MODEL(",
                "ADVANCED_FACE(", "OFFSET_SURFACE(", "TRIANGULATED_FACE_SET(", "TESSELLATED_SHAPE_REPRESENTATION("]
            for entity in entities.values {
                try budget.check(format: .step)
                let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
                guard !forbidden.contains(where: { syntax.hasPrefix($0) }),
                    isSupportedSTEPEntity(syntax: entity) || additional.contains(where: { syntax.hasPrefix($0) }) else {
                    throw KernelError(phase: .exchange, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Standalone STEP input contains unsupported or mixed topology semantics.")
                }
            }
            let length = try stepLengthUnit(in: entities, budget: budget)
            var usage = try IndependentShapeExchangeOwner(limits: resourceLimits, processing: budget,
                consumedEntities: entities.count, consumedWork: lexicalWork, consumedBytes: 0)
        var execution = try usage.execution()
            return try ExactSTEPReader(entities: entities, lengthUnit: length,
                processingBudget: budget, tolerance: tolerance).readIndependentGeometry(usage: usage, using: &execution)
        }
    }

    func validateIndependentSTEPOutput(_ text: String, budget: ExchangeProcessingBudget) throws {
        try validateSTEPResourceBudget(text, budget: budget)
        try budget.check(format: .step)
    }

    public func write(meshes: [BodyID: Mesh], units: UnitSystem = .meters, to sink: any ByteSink) throws {
        _ = meshes
        _ = units
        _ = sink
        throw KernelError(
            phase: .exchange,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "STEP export accepts exact B-rep only; mesh-to-STEP conversion is forbidden."
        )
    }

    public func `import`(_ source: any ByteSource) throws -> ImportedExchangeModel {
        try tolerance.validate()
        try resourceLimits.validate()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        return try source.withNoCopyData { data in
            try budget.check(format: .step)
            guard data.count <= resourceLimits.maximumBytes else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "STEP input exceeds the configured byte limit."
                )
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("STEP data is not UTF-8.")
            }
            return try importText(text, budget: budget)
        }
    }

    /// Explicit partial import retains a dependency-closed supported graph and returns every loss.
    public func `import`(_ source: any ByteSource, policy: ExchangeImportPolicy) throws -> ImportedExchangeModel {
        switch policy {
        case .strict: return try self.import(source)
        case let .allowPartial(accepting):
            try resourceLimits.validate()
            let processing = processingBudgetOverride ?? ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
            guard source.count <= resourceLimits.maximumBytes else { throw exchangeResourceLimitError(format: .step, detail: "input exceeds byte ceiling") }
            return try source.withNoCopyData { data in
                try processing.check(format: .step)
                guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidData("STEP data is not valid UTF-8.") }
                let lexicalWork = try validateSTEPResourceBudget(text, budget: processing)
                try validateSTEPExchangeEnvelope(in: text)
                let sections = try stepDataSections(in: text)
                guard !sections.isEmpty else { throw ImportError.invalidData("Missing STEP DATA section.") }
                try rejectSTEPEntityMarkersOutsideDataSections(in: text, dataRanges: sections.map(\.contentRange))
                let entities = try stepEntities(in: sections.map(\.content).joined(separator: "\n"))
                var plannerLimits = resourceLimits
                guard lexicalWork < plannerLimits.maximumIterations else { throw exchangeResourceLimitError(format: .step, detail: "partial lexical work exhausted caller allowance") }
                plannerLimits.maximumIterations -= lexicalWork
                let plan = try STEPPartialImportPlanner(limits: plannerLimits, budget: processing).plan(entities: entities, accepting: accepting, isSupported: { isSupportedSTEPEntity(syntax: normalizedSTEPText(stepSyntaxOutsideStrings(in: $0))) })
                var remaining = plannerLimits
                remaining.maximumIterations -= plan.consumedWork
                remaining.maximumEntities -= plan.consumedEntities
                remaining.maximumBytes -= plan.consumedBytes
                guard remaining.maximumIterations > 0, remaining.maximumEntities > 0, remaining.maximumBytes > 0 else {
                    throw exchangeResourceLimitError(format: .step, detail: "partial planner exhausted caller allowance")
                }
                func admitReconstruction(_ bytes: Int) throws {
                    try processing.check(format: .step)
                    guard bytes >= 0, bytes < remaining.maximumBytes, bytes < remaining.maximumIterations else {
                        throw exchangeResourceLimitError(format: .step, detail: "partial reconstruction exceeds cumulative caller allowance")
                    }
                    remaining.maximumBytes -= bytes; remaining.maximumIterations -= bytes
                }
                var payload = ""
                for id in plan.entities.keys.sorted() {
                    guard let entity = plan.entities[id] else { throw ImportError.missingRequiredEntity("Retained STEP record.") }
                    var digitCount = 1, quotient = id / 10
                    while quotient > 0 { digitCount += 1; quotient /= 10 }
                    let recordBytes = entity.utf8.count.addingReportingOverflow(digitCount + 4)
                    guard !recordBytes.overflow else { throw exchangeResourceLimitError(format: .step, detail: "partial record byte overflow") }
                    try admitReconstruction(recordBytes.partialValue)
                    payload += "#\(id)=\(entity);\n"
                }
                guard text.utf8.count < remaining.maximumIterations else { throw exchangeResourceLimitError(format: .step, detail: "partial reconstruction traversal ceiling") }
                remaining.maximumIterations -= text.utf8.count
                var retained = "", cursor = text.startIndex
                for (index, section) in sections.enumerated() {
                    let prefix = text[cursor..<section.contentRange.lowerBound]
                    try admitReconstruction(prefix.utf8.count)
                    retained += prefix
                    if index == 0 { try admitReconstruction(payload.utf8.count); retained += payload }
                    cursor = section.contentRange.upperBound
                }
                let suffix = text[cursor...]
                try admitReconstruction(suffix.utf8.count)
                retained += suffix
                try processing.check(format: .step)
                guard retained.utf8.count <= remaining.maximumBytes, remaining.maximumIterations > 0 else { throw exchangeResourceLimitError(format: .step, detail: "retained reconstruction exceeds caller ceiling") }
                var result = try STEPExchange(tolerance: tolerance, resourceLimits: remaining).importText(retained, budget: processing)
                result.preservationReport = plan.report
                return result
            }
        }
    }

    private func importText(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws -> ImportedExchangeModel {
        try validateSTEPResourceBudget(text, budget: budget)
        try budget.check(format: .step)
        try validateSTEPExchangeEnvelope(in: text)

        let dataSections = try stepDataSections(in: text)
        try budget.check(format: .step)
        try rejectSTEPEntityMarkersOutsideDataSections(in: text, dataRanges: dataSections.map(\.contentRange))
        guard !dataSections.isEmpty else {
            throw ImportError.invalidData("Missing STEP DATA section.")
        }
        let entities = try stepEntities(in: dataSections.map(\.content).joined(separator: "\n"))
        try budget.check(format: .step)
        // An empty DATA section is malformed input; a section holding only entities outside the
        // exact subset stays the reader's unsupported-capability refusal.
        guard !entities.isEmpty else {
            throw ImportError.invalidData("STEP DATA section contains no entities.")
        }
        guard entities.count <= resourceLimits.maximumEntities else {
            throw KernelError(
                phase: .exchange,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "STEP input exceeds the configured entity limit."
            )
        }
        let names = try validateSupportedSTEPEntities(entities, budget: budget)
        try budget.check(format: .step)
        if names.values.contains("TRIANGULATED_FACE_SET") {
            throw KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Tessellated STEP is a mesh exchange and cannot be imported as exact CAD geometry."
            )
        }
        let hasBodies = names.values.contains { ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains($0) }
        let hasMaterialDesignation = names.values.contains("MATERIAL_DESIGNATION")
        var sourceAdmission = try IndependentShapeExchangeOwner(limits: resourceLimits, format: .step, processing: budget,
            consumedEntities: entities.count, consumedWork: text.unicodeScalars.count, consumedBytes: text.utf8.count)
        var execution = try sourceAdmission.execution()
        let bodyContextUnits = hasBodies ? try ExactSTEPReader.bodyContextUnits(entities: entities, names: names,
            processingBudget: budget, tolerance: tolerance, usage: sourceAdmission, using: &execution) : [:]
        var materialIdentities: [Int: PhysicalMaterialID] = [:]
        var documentCarrier: STEPDocumentCarrierReadReceipt?
        if names.values.contains("PRODUCT_DEFINITION"), let assembled = try STEPAssemblyReader(tolerance: tolerance, resourceLimits: resourceLimits)
            .read(entities: entities, budget: budget, materialIdentities: &materialIdentities, documentCarrier: &documentCarrier, sourceAdmission: sourceAdmission, using: &execution) { return assembled }
        if !hasBodies {
            let independentUsage = sourceAdmission
            let independentItems = try independentSTEPItemRoots(entities:entities,names:names,budget:budget) { entities, work in
                try independentUsage.charge(entities:entities,work:work, using: &execution)
            }
            if let original = try ExactSTEPReader.readIndependent(entities: entities, processingBudget: budget,
                tolerance: tolerance, standaloneItems: independentItems, usage: independentUsage, using: &execution) {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public independent STEP import has no material-attribute composition owner.
                // Retain and validate actual material designation identities and attachments before publishing mixed independent shapes and materials.
                guard !hasMaterialDesignation else {
                    throw IndependentShapeExchangeError.unsupportedSemantics("Independent STEP material attributes require an explicit source composition owner.")
                }
                let document = CADDocument(units: original.units, independentShapes: original.source)
                try independentUsage.validateDocument(document,tolerance:tolerance, using: &execution)
                return ImportedExchangeModel(format: .step, document: document, units: original.units)
            }
        }
        let actualBodyIDs = names.filter { ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains($0.value) }.keys
        let lengthUnit: LengthUnit
        if actualBodyIDs.allSatisfy({ bodyContextUnits[$0] != nil }), let first = bodyContextUnits.values.first {
            guard bodyContextUnits.values.allSatisfy({ $0.length == first.length }) else {
                throw IndependentShapeExchangeError.invalidAssociation("Ordinary Body import has distinct actual Body coordinate units.")
            }
            lengthUnit = first.length
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Unassociated Body primitives still use the original single ambient unit profile.
            // Original foreign angular coordinates require a retained Body source context before this fallback can admit them.
            for (id, entity) in entities {
                try budget.check(format: .step)
                let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
                if syntax.contains("PLANE_ANGLE_UNIT()"), syntax.contains("CONVERSION_BASED_UNIT(") {
                    throw IndependentShapeExchangeError.unsupportedSemantics("Unassociated Body angular unit #\(id) needs an original source context.")
                }
            }
            lengthUnit = try stepLengthUnit(in: entities, budget: budget)
        }
        try budget.check(format: .step)
        let exact = try ExactSTEPReader(
            entities: entities,
            lengthUnit: lengthUnit,
            processingBudget: budget,
            tolerance: tolerance
        ).readWithTransfer()
        let brep = exact.model
        var transfer = STEPAttributeReadTransfer()
        transfer.materialIdentities = materialIdentities
        try budget.check(format: .step)
        guard !brep.bodies.isEmpty else {
            throw ImportError.invalidData("STEP model contains no bodies.")
        }
        let bodyExtractor = BRepBodySubmodelExtractor()
        var nodes: [FeatureID: FeatureNode] = [:]
        var order: [FeatureID] = []
        nodes.reserveCapacity(brep.bodies.count)
        order.reserveCapacity(brep.bodies.count)
        for (ordinal, bodyID) in brep.bodies.keys.sorted().enumerated() {
            try Task.checkCancellation()
            try budget.check(format: .step)
            let bodyModel = try bodyExtractor.extract(
                bodyIDs: Set([bodyID]),
                from: brep
            )
            guard let body = bodyModel.bodies[bodyID] else {
                throw TopologyError.missingReference(
                    "STEP body extraction did not retain body \(bodyID)."
                )
            }
            let featureID = FeatureID()
            nodes[featureID] = FeatureNode(
                id: featureID,
                name: "STEP Import \(ordinal + 1)",
                operation: .importedBRep(
                    ImportedBRepFeature(
                        model: bodyModel,
                        sourceUnits: UnitSystem(length: lengthUnit, angle: .radian)
                    )
                ),
                outputs: [FeatureOutput(role: body.kind == .solid ? .body : .sheet)]
            )
            order.append(featureID)
            for (entity, sourceID) in exact.bodies where sourceID == bodyID {
                transfer.geometry[entity] = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
                transfer.geometryUnits[entity] = lengthUnit
            }
            for (index, faceID) in bodyModel.faces.keys.sorted().enumerated() {
                for (entity, sourceID) in exact.faces where sourceID == faceID {
                    transfer.geometry[entity] = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.face.rawValue, ordinal: index)
                    transfer.geometryUnits[entity] = lengthUnit
                }
            }
        }
        var document = CADDocument(
            id: documentCarrier?.documentID ?? DocumentID(),
            units: UnitSystem(length: lengthUnit, angle: .radian),
            designGraph: DesignGraph(
                nodes: nodes,
                order: order
            )
        )
        if let carrier = documentCarrier { document.metadata.name = carrier.documentName.isEmpty ? nil : carrier.documentName }
        let independentUsage = sourceAdmission
        let independentItems = try independentSTEPItemRoots(entities: entities, names: names, budget: budget) { records, work in
            try independentUsage.charge(entities: records, work: work, using: &execution)
        }
        if let original = try ExactSTEPReader.readIndependent(entities: entities, processingBudget: budget,
            tolerance: tolerance, standaloneItems: independentItems,
            bodySources: transfer.geometry.filter { $0.value.role == GeneratedSubshapeRole.body.rawValue },
            bodySourceGraph: document.designGraph, usage: independentUsage, using: &execution) {
            document.independentShapes = original.source
        }
        try independentUsage.validateDocument(document, tolerance: tolerance, using: &execution)
        try document.validate(tolerance: tolerance)
        let base = try DocumentEvaluator(tolerance: tolerance).evaluateExact(document)
        document.productAttributes = try STEPAttributesReader().read(entities: entities, transfer: transfer,
            evaluated: base, limits: resourceLimits)
        try document.validate(tolerance: tolerance)
        let evaluated = document.productAttributes.isEmpty ? base : try DocumentEvaluator(tolerance: tolerance).evaluateExact(document)
        if !document.productAttributes.isEmpty {
            _ = try ProductAttributeResolver().resolve(evaluated, limits: ProductAttributeLimits(
                maximumRecords: resourceLimits.maximumEntities, maximumTargets: resourceLimits.maximumEntities,
                maximumDepth: resourceLimits.maximumNesting, maximumTextBytes: resourceLimits.maximumBytes,
                maximumWork: resourceLimits.maximumIterations))
        }
        return ImportedExchangeModel(
            format: .step,
            document: document,
            brep: brep,
            units: document.units
        )
    }

    @discardableResult
    private func validateSTEPResourceBudget(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws -> Int {
        let limits = resourceLimits
        var depth = 0
        var iterations = 0
        var inString = false
        var cursor = text.startIndex
        while cursor < text.endIndex {
            iterations += 1
            if iterations.isMultiple(of: 4_096) {
                try budget.check(format: .step)
            }
            guard iterations <= limits.maximumIterations else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "STEP parsing exceeded the configured iteration limit."
                )
            }
            let character = text.unicodeScalars[cursor]
            if character == "'" {
                let next = text.unicodeScalars.index(after: cursor)
                if next < text.endIndex, text.unicodeScalars[next] == "'" {
                    cursor = text.unicodeScalars.index(after: next)
                    continue
                }
                inString.toggle()
            } else if !inString {
                if character == "(" {
                    depth += 1
                    guard depth <= limits.maximumNesting else {
                        throw KernelError(
                            phase: .exchange,
                            code: .resourceLimitExceeded,
                            tolerance: tolerance,
                            message: "STEP nesting exceeded the configured limit."
                        )
                    }
                } else if character == ")" {
                    depth -= 1
                    guard depth >= 0 else {
                        throw ImportError.invalidData("STEP exchange contains unbalanced parentheses.")
                    }
                }
            }
            cursor = text.unicodeScalars.index(after: cursor)
        }
    guard !inString, depth == 0 else {
        throw ImportError.invalidData("STEP exchange contains an unterminated string or tuple.")
    }
    return iterations
}

}

func independentSTEPItemRoots(entities:[Int:String],names:[Int:String],budget:ExchangeProcessingBudget,
                                     charge:(Int,Int) throws -> Void) throws -> [Int] {
    let fields = STEPAssemblySyntax(entities:entities)
    var geometry = Set<Int>(), consumed = Set<Int>()
    for (id,entity) in entities {
        try budget.check(format: .step)
        try charge(1,entity.utf8.count+1)
        guard let name = names[id] else { throw ImportError.invalidData("Missing admitted STEP record name.") }
        let spline = name.isEmpty ? try fields.hasComponent(id,named:"B_SPLINE_CURVE")
            || fields.hasComponent(id,named:"B_SPLINE_SURFACE") : false
        if ["LINE","CIRCLE","ELLIPSE","HYPERBOLA","PARABOLA","TRIMMED_CURVE","PLANE",
            "CYLINDRICAL_SURFACE","CONICAL_SURFACE","SPHERICAL_SURFACE","TOROIDAL_SURFACE","OFFSET_SURFACE","AXIS2_PLACEMENT_3D"].contains(name)
            || spline {
            geometry.insert(id)
        }
        let selected:Int?
        switch name {
        case "TRIMMED_CURVE","OFFSET_SURFACE","SURFACE_CURVE","PCURVE": selected = 1
        case "EDGE_CURVE": selected = 3
        case "ADVANCED_FACE": selected = 2
        default: selected = nil
        }
        if let selected {
            let a = try fields.arguments(id)
            guard selected < a.count else { throw ImportError.invalidData("Malformed STEP geometry owner association.") }
            try charge(1,1); consumed.insert(try fields.reference(a[selected]))
        }
        if name == "DEFINITIONAL_REPRESENTATION" {
            let a = try fields.arguments(id)
            guard a.count == 3 else { throw ImportError.invalidData("Malformed STEP parameter representation.") }
            let items = try fields.list(a[1])
            for item in items { try charge(1,1); consumed.insert(item) }
        }
        if ["CIRCLE","ELLIPSE","HYPERBOLA","PARABOLA","PLANE","CYLINDRICAL_SURFACE","CONICAL_SURFACE",
            "SPHERICAL_SURFACE","TOROIDAL_SURFACE","REPRESENTATION_MAP"].contains(name) {
            let a = try fields.arguments(id), position = name == "REPRESENTATION_MAP" ? 0 : 1
            guard position < a.count else { throw ImportError.invalidData("Malformed STEP frame owner association.") }
            try charge(1,1); consumed.insert(try fields.reference(a[position]))
        }
        if ["SHAPE_REPRESENTATION","GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION",
            "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION","ADVANCED_BREP_SHAPE_REPRESENTATION",
            "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(name) {
            let a = try fields.arguments(id)
            guard a.count == 3 else { throw ImportError.invalidData("Malformed STEP representation membership.") }
            for item in try fields.list(a[1]) {
                try charge(1,1)
                if try fields.name(item) == "AXIS2_PLACEMENT_3D" { consumed.insert(item) }
            }
        }
    }
    // Presentation geometry has its own real standard owner and is not an independent shape root.
    var presentationStack = names.keys.filter { ["DRAUGHTING_CALLOUT", "CAMERA_MODEL_D3", "CAMERA_MODEL_D3_MULTI_CLIPPING"].contains(names[$0] ?? "") }
    var presentationVisited = Set<Int>()
    while let id = presentationStack.popLast() {
        try budget.check(format: .step)
        guard presentationVisited.insert(id).inserted else { continue }
        try charge(1, 1)
        consumed.insert(id)
        guard let record = entities[id] else { throw ImportError.missingRequiredEntity("Presentation dependency #\(id)") }
        let references = try STEPMetadataReferenceScanner.references(in: record)
        try charge(references.count, record.utf8.count)
        for reference in references { presentationStack.append(reference) }
    }
    try charge(geometry.count,geometry.count*(Int.bitWidth-geometry.count.leadingZeroBitCount+1))
    return geometry.filter { !consumed.contains($0) }.sorted()
}

private func validateSupportedSTEPEntities(_ entities: [Int: String], budget: ExchangeProcessingBudget) throws -> [Int:String] {
    let fields = STEPAssemblySyntax(entities: entities)
    var names: [Int:String] = [:]
    for id in entities.keys.sorted() {
        try budget.check(format: .step)
        guard let entity = entities[id] else {
            continue
        }
        let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
        guard isSupportedSTEPEntity(syntax: syntax) else {
            throw ImportError.invalidData("Unsupported STEP entity #\(id).")
        }
        names[id] = try fields.name(id)
    }
    return names
}

private func isSupportedSTEPEntity(syntax: String) -> Bool {
    let supportedPrefixes = [
        "APPLICATION_CONTEXT(",
        "APPLICATION_PROTOCOL_DEFINITION(",
        "PRODUCT_CONTEXT(",
        "EXTERNAL_SOURCE(",
        "IDENTIFICATION_ROLE(",
        "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT(",
        "MATERIAL_DESIGNATION(",
        "PRODUCT(",
        "PRODUCT_DEFINITION_FORMATION(",
        "PRODUCT_DEFINITION_CONTEXT(",
        "PRODUCT_DEFINITION(",
        "PRODUCT_DEFINITION_SHAPE(",
        "CARTESIAN_POINT(",
        "VERTEX_POINT(",
        "DIRECTION(",
        "VECTOR(",
        "LINE(",
        "CIRCLE(",
        "ELLIPSE(",
        "HYPERBOLA(",
        "PARABOLA(",
        "TRIMMED_CURVE(",
        "PCURVE(",
        "SURFACE_CURVE(",
        "DEFINITIONAL_REPRESENTATION(",
        "EDGE_CURVE(",
        "ORIENTED_EDGE(",
        "EDGE_LOOP(",
        "FACE_OUTER_BOUND(",
        "FACE_BOUND(",
        "AXIS2_PLACEMENT_2D(",
        "AXIS2_PLACEMENT_3D(",
        "PLANE(",
        "CYLINDRICAL_SURFACE(",
        "CONICAL_SURFACE(",
        "SPHERICAL_SURFACE(",
        "TOROIDAL_SURFACE(",
        "OFFSET_SURFACE(",
        "ADVANCED_FACE(",
        "OPEN_SHELL(",
        "CLOSED_SHELL(",
        "ORIENTED_CLOSED_SHELL(",
        "MANIFOLD_SOLID_BREP(",
        "BREP_WITH_VOIDS(",
        "SHELL_BASED_SURFACE_MODEL(",
        "SHAPE_REPRESENTATION(",
        "ADVANCED_BREP_SHAPE_REPRESENTATION(",
        "MANIFOLD_SURFACE_SHAPE_REPRESENTATION(",
        "NEXT_ASSEMBLY_USAGE_OCCURRENCE(",
        "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(",
        "ITEM_DEFINED_TRANSFORMATION(",
        "SHAPE_REPRESENTATION_RELATIONSHIP(",
        "REPRESENTATION_MAP(",
        "GEOMETRIC_SET(", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION(",
        "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION(", "GROUP(", "APPLIED_GROUP_ASSIGNMENT(",
        "MAPPED_ITEM(",
        "CARTESIAN_TRANSFORMATION_OPERATOR_3D(",
        "PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE(",
        "UNCERTAINTY_MEASURE_WITH_UNIT(",
        "CARTESIAN_POINT_LIST_3D(",
        "TRIANGULATED_FACE_SET(",
        "TESSELLATED_SHAPE_REPRESENTATION(",
        "SHAPE_DEFINITION_REPRESENTATION(",
        "LENGTH_MEASURE_WITH_UNIT(", "PLANE_ANGLE_MEASURE_WITH_UNIT(",
        "DIMENSIONAL_EXPONENTS(",
        "STYLED_ITEM(", "OVER_RIDING_STYLED_ITEM(", "CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM(",
        "COLOUR_RGB(", "DRAUGHTING_PRE_DEFINED_COLOUR(", "FILL_AREA_STYLE_COLOUR(", "FILL_AREA_STYLE(",
        "SURFACE_STYLE_FILL_AREA(", "SURFACE_SIDE_STYLE(", "SURFACE_STYLE_USAGE(",
        "SURFACE_STYLE_RENDERING(", "SURFACE_STYLE_RENDERING_WITH_PROPERTIES(", "SURFACE_STYLE_TRANSPARENT(",
        "PRESENTATION_STYLE_ASSIGNMENT(", "PRESENTATION_STYLE_BY_CONTEXT(", "DRAUGHTING_MODEL(", "MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION(",
        "PRESENTATION_LAYER_ASSIGNMENT(", "PROPERTY_DEFINITION(", "PROPERTY_DEFINITION_REPRESENTATION(", "PROPERTY_DEFINITION_RELATIONSHIP(", "CHARACTERIZED_OBJECT(",
        "REPRESENTATION(", "DESCRIPTIVE_REPRESENTATION_ITEM(", "SHAPE_ASPECT(", "GEOMETRIC_ITEM_SPECIFIC_USAGE(",
        "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(",
        "DERIVED_UNIT(", "DERIVED_UNIT_ELEMENT(", "MEASURE_WITH_UNIT(", "MEASURE_REPRESENTATION_ITEM(",
        "MASS_MEASURE_WITH_UNIT(", "VOLUME_MEASURE_WITH_UNIT(", "MASS_DENSITY_MEASURE_WITH_UNIT("
    ]
    if STEPMetadataNames.simpleNames.contains(where: { syntax.hasPrefix($0 + "(") }) { return true }
    if supportedPrefixes.contains(where: { syntax.hasPrefix($0) }) {
        return true
    }
    guard syntax.hasPrefix("("), syntax.hasSuffix(")") else {
        return false
    }
    return isSupportedSTEPComplexEntity(syntax)
}

private func isSupportedSTEPComplexEntity(_ syntax: String) -> Bool {
    if syntax.contains("GEOMETRIC_TOLERANCE("), STEPMetadataNames.tolerances.values.contains(where: { syntax.contains($0 + "()") }) { return true }
    if syntax.contains("MEASURE_REPRESENTATION_ITEM()"), syntax.contains("MEASURE_WITH_UNIT("),
       syntax.contains("REPRESENTATION_ITEM(") { return true }
    if syntax.contains("NAMED_UNIT("),
       (syntax.contains("MASS_UNIT()") || syntax.contains("VOLUME_UNIT()") || syntax.contains("MASS_DENSITY_UNIT()")) {
        return syntax.contains("SI_UNIT(") || syntax.contains("CONVERSION_BASED_UNIT(")
    }
    if syntax.contains("REPRESENTATION_RELATIONSHIP("),
       syntax.contains("REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION("),
       syntax.contains("SHAPE_REPRESENTATION_RELATIONSHIP()") { return true }
    if syntax.contains("B_SPLINE_CURVE("),
       syntax.contains("B_SPLINE_CURVE_WITH_KNOTS("),
       syntax.contains("REPRESENTATION_ITEM(") {
        return true
    }
    if syntax.contains("B_SPLINE_SURFACE("),
       syntax.contains("B_SPLINE_SURFACE_WITH_KNOTS("),
       syntax.contains("REPRESENTATION_ITEM(") {
        return true
    }
    if syntax.contains("GEOMETRIC_REPRESENTATION_CONTEXT("),
       syntax.contains("GLOBAL_UNIT_ASSIGNED_CONTEXT(("),
       syntax.contains("REPRESENTATION_CONTEXT(") {
        return true
    }
    if syntax.contains("GEOMETRIC_REPRESENTATION_CONTEXT(2)"),
       syntax.contains("PARAMETRIC_REPRESENTATION_CONTEXT()"),
       syntax.contains("REPRESENTATION_CONTEXT(") {
        return true
    }
    if syntax.contains("PLANE_ANGLE_UNIT()"), syntax.contains("NAMED_UNIT(") {
        return syntax.contains("SI_UNIT($,.RADIAN.)") || syntax.contains("CONVERSION_BASED_UNIT(")
    }
    if syntax.contains("PLANE_ANGLE_MEASURE_WITH_UNIT()"), syntax.contains("MEASURE_WITH_UNIT(") {
        return true
    }
    if syntax.contains("SOLID_ANGLE_UNIT()"),
       syntax.contains("SI_UNIT($,.STERADIAN.)") {
        return true
    }
    if syntax.contains("LENGTH_UNIT()"),
       syntax.contains("NAMED_UNIT(") {
        return (syntax.contains("SI_UNIT(") && syntax.contains(",.METRE.)"))
            || syntax.contains("CONVERSION_BASED_UNIT(")
    }
    return false
}

private func stepLengthUnit(in entities: [Int: String], budget: ExchangeProcessingBudget) throws -> LengthUnit {
    let syntax = STEPAssemblySyntax(entities: entities)
    var bodyContexts = Set<Int>()
    for id in entities.keys.sorted() {
        try budget.check(format: .step)
        let kind = try syntax.name(id)
        if ["ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION"].contains(kind) {
            let arguments = try syntax.arguments(id)
            guard arguments.count == 3 else { throw ImportError.invalidData("Malformed original Body representation context.") }
            bodyContexts.insert(try syntax.reference(arguments[2]))
        } else if kind == "SHAPE_REPRESENTATION" || kind == "REPRESENTATION" {
            let arguments = try syntax.arguments(id)
            guard arguments.count == 3 else { throw ImportError.invalidData("Malformed original representation context.") }
            for item in try syntax.list(arguments[1]) {
                try budget.check(format: .step)
                if ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(try syntax.name(item)) {
                    bodyContexts.insert(try syntax.reference(arguments[2]))
                }
            }
        }
    }
    for context in bodyContexts {
        try budget.check(format: .step)
        guard entities[context] != nil else { throw ImportError.missingRequiredEntity("Original Body unit context #\(context)") }
    }
    var lengthUnits: [LengthUnit] = []
    for id in entities.keys.sorted() {
        try budget.check(format: .step)
        if !bodyContexts.isEmpty, !bodyContexts.contains(id) { continue }
        guard let entity = entities[id], normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
            .contains("GLOBAL_UNIT_ASSIGNED_CONTEXT((") else {
                if bodyContexts.contains(id) { throw ImportError.invalidData("Body representation lacks its actual global unit context.") }
                continue
            }
        let fields = try syntax.arguments(id, component: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
        guard fields.count == 1 else { throw ImportError.invalidData("Malformed STEP unit context.") }
        var localUnits: [LengthUnit] = []
        for unitID in try syntax.list(fields[0]) {
            if let unit = try stepLengthUnit(from: syntax.entity(unitID), entities: entities) { localUnits.append(unit) }
        }
        guard localUnits.count == 1, let unit = localUnits.first else {
            throw ImportError.invalidData("STEP context must reference exactly one LENGTH_UNIT.")
        }
        lengthUnits.append(unit)
    }
    if lengthUnits.isEmpty { return .meter }
    guard Set(lengthUnits).count == 1, let unit = lengthUnits.first else {
        throw ImportError.invalidData("STEP ordinary exact geometry has conflicting context length units.")
    }
    return unit
}

private func stepGlobalUnitReferenceIDs(in entities: [Int: String]) throws -> [Int] {
    var ids: [Int] = []
    for id in entities.keys.sorted() {
        guard let entity = entities[id] else {
            continue
        }
        let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
        guard let range = syntax.range(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((") else {
            continue
        }
        guard let listContent = stepGlobalUnitReferenceListContent(in: syntax, from: range.upperBound) else {
            throw ImportError.invalidData("STEP GLOBAL_UNIT_ASSIGNED_CONTEXT reference list is malformed.")
        }
        ids.append(contentsOf: try stepReferenceListIDs(in: listContent, label: "STEP GLOBAL_UNIT_ASSIGNED_CONTEXT"))
    }
    return ids
}

private func stepGlobalUnitReferenceListContent(in text: String, from start: String.Index) -> String? {
    var cursor = start
    var depth = 1
    while cursor < text.endIndex {
        if text[cursor] == "(" {
            depth += 1
        } else if text[cursor] == ")" {
            depth -= 1
            if depth == 0 {
                return String(text[start..<cursor])
            }
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func stepReferenceListIDs(in text: String, label: String) throws -> [Int] {
    let references = text
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !references.isEmpty else {
        throw ImportError.invalidData("\(label) reference list is empty.")
    }
    return try references.map { reference in
        guard reference.first == "#" else {
            throw ImportError.invalidData("\(label) reference is malformed.")
        }
        let numberStart = reference.index(after: reference.startIndex)
        let numberText = reference[numberStart...]
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              let id = Int(numberText) else {
            throw ImportError.invalidData("\(label) reference is malformed.")
        }
        return id
    }
}

private func stepReferenceIDs(in text: String) -> [Int] {
    var ids: [Int] = []
    var searchStart = text.startIndex
    while let hashIndex = text[searchStart...].firstIndex(of: "#") {
        var numberEnd = text.index(after: hashIndex)
        while numberEnd < text.endIndex, text[numberEnd].isNumber {
            numberEnd = text.index(after: numberEnd)
        }
        if let id = Int(text[text.index(after: hashIndex)..<numberEnd]) {
            ids.append(id)
        }
        searchStart = numberEnd
    }
    return ids
}

func stepLengthUnit(from entity: String, entities: [Int: String]) throws -> LengthUnit? {
    let normalized = normalizedSTEPText(entity)
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    guard syntax.contains("LENGTH_UNIT()") else {
        return nil
    }
    if syntax.hasPrefix("(CONVERSION_BASED_UNIT(,"),
       normalized.hasPrefix("(CONVERSION_BASED_UNIT('INCH',") {
        try validateSTEPConversionFactor(for: .inch, in: entity, entities: entities)
        return .inch
    }
    if syntax.hasPrefix("(CONVERSION_BASED_UNIT(,"),
       normalized.hasPrefix("(CONVERSION_BASED_UNIT('FOOT',") {
        try validateSTEPConversionFactor(for: .foot, in: entity, entities: entities)
        return .foot
    }
    if syntax.contains("SI_UNIT(.MICRO.,.METRE.)") {
        return .micrometer
    }
    if syntax.contains("SI_UNIT(.MILLI.,.METRE.)") {
        return .millimeter
    }
    if syntax.contains("SI_UNIT(.CENTI.,.METRE.)") {
        return .centimeter
    }
    if syntax.contains("SI_UNIT(.KILO.,.METRE.)") {
        return .kilometer
    }
    if syntax.contains("SI_UNIT($,.METRE.)") {
        return .meter
    }
    throw ImportError.invalidData("Unsupported STEP length unit.")
}

private func validateSTEPConversionFactor(
    for unit: LengthUnit,
    in conversionEntity: String,
    entities: [Int: String]
) throws {
    guard let measureID = stepFirstReference(in: conversionEntity),
          let measureEntity = entities[measureID] else {
        throw ImportError.missingRequiredEntity("STEP conversion length factor")
    }
    let factor = try stepConversionFactor(from: measureEntity, entities: entities)
    let tolerance = max(1.0e-12, unit.metersPerUnit * 1.0e-12)
    guard abs(factor - unit.metersPerUnit) <= tolerance else {
        throw ImportError.invalidData("STEP conversion length factor does not match \(unit.rawValue).")
    }
}

private func stepConversionFactor(from entity: String, entities: [Int: String]) throws -> Double {
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    let prefix = "LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE("
    guard syntax.hasPrefix(prefix) else {
        throw ImportError.invalidData("STEP conversion length factor is malformed.")
    }
    let valueStart = syntax.index(syntax.startIndex, offsetBy: prefix.count)
    guard let valueEnd = syntax[valueStart...].firstIndex(of: ")") else {
        throw ImportError.invalidData("STEP conversion length factor is malformed.")
    }
    let valueText = String(syntax[valueStart..<valueEnd])
    guard let factor = Double(valueText), factor.isFinite, factor > 0.0 else {
        throw ImportError.invalidData("STEP conversion length factor must be a positive finite number.")
    }
    let references = stepReferenceIDs(in: syntax)
    guard references.count == 1,
          let unitEntity = entities[references[0]] else {
        throw ImportError.missingRequiredEntity("STEP conversion length base unit")
    }
    guard try stepSILengthUnit(from: unitEntity) == .meter else {
        throw ImportError.invalidData("STEP conversion length factor must reference metres.")
    }
    return factor
}

private func stepSILengthUnit(from entity: String) throws -> LengthUnit? {
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    guard syntax.contains("LENGTH_UNIT()") else {
        return nil
    }
    if syntax.contains("SI_UNIT(.MICRO.,.METRE.)") {
        return .micrometer
    }
    if syntax.contains("SI_UNIT(.MILLI.,.METRE.)") {
        return .millimeter
    }
    if syntax.contains("SI_UNIT(.CENTI.,.METRE.)") {
        return .centimeter
    }
    if syntax.contains("SI_UNIT(.KILO.,.METRE.)") {
        return .kilometer
    }
    if syntax.contains("SI_UNIT($,.METRE.)") {
        return .meter
    }
    throw ImportError.invalidData("Unsupported STEP length unit.")
}

private func normalizedSTEPText(_ text: String) -> String {
    text
        .uppercased()
        .filter { !$0.isWhitespace }
}

private func stepTriangleIndices(from mesh: Mesh) -> [(UInt32, UInt32, UInt32)] {
    var triangles: [(UInt32, UInt32, UInt32)] = []
    var index = 0
    while index < mesh.indices.count {
        let first = mesh.indices[index] + 1
        let second = mesh.indices[index + 1] + 1
        let third = mesh.indices[index + 2] + 1
        triangles.append((first, second, third))
        index += 3
    }
    return triangles
}

private struct STEPDataSection {
    let contentRange: Range<String.Index>
    let content: String
}

private func validateSTEPExchangeEnvelope(in text: String) throws {
    guard let startMarker = nextSTEPMarker("ISO-10303-21;", in: text, from: text.startIndex) else {
        throw ImportError.invalidData("Missing STEP header.")
    }
    guard text[..<startMarker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ImportError.invalidData("STEP header must be the first exchange record.")
    }
    guard let endMarker = nextSTEPMarker("END-ISO-10303-21;", in: text, from: startMarker.upperBound) else {
        throw ImportError.invalidData("STEP exchange terminator is missing.")
    }
    guard text[endMarker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ImportError.invalidData("STEP exchange terminator must be the final record.")
    }
}

private func stepDataSections(in text: String) throws -> [STEPDataSection] {
    var sections: [STEPDataSection] = []
    var searchStart = text.startIndex
    while let dataMarker = nextSTEPMarker("DATA;", in: text, from: searchStart) {
        guard let endMarker = nextSTEPMarker("ENDSEC;", in: text, from: dataMarker.upperBound) else {
            throw ImportError.invalidData("STEP DATA section is unterminated.")
        }
        let contentRange = dataMarker.upperBound..<endMarker.lowerBound
        sections.append(STEPDataSection(
            contentRange: contentRange,
            content: String(text[contentRange])
        ))
        searchStart = endMarker.upperBound
    }
    return sections
}

private func rejectSTEPEntityMarkersOutsideDataSections(
    in text: String,
    dataRanges: [Range<String.Index>]
) throws {
    var searchStart = text.startIndex
    while let hashIndex = nextSTEPHashOutsideString(in: text, from: searchStart) {
        if dataRanges.contains(where: { $0.contains(hashIndex) }) {
            searchStart = text.index(after: hashIndex)
            continue
        }
        var numberEnd = text.index(after: hashIndex)
        while numberEnd < text.endIndex, text[numberEnd].isNumber {
            numberEnd = text.index(after: numberEnd)
        }
        guard numberEnd > text.index(after: hashIndex) else {
            throw ImportError.invalidData("STEP entity or reference marker is malformed.")
        }
        throw ImportError.invalidData("STEP entity or reference marker is outside the DATA section.")
    }
}

private func nextSTEPMarker(
    _ marker: String,
    in text: String,
    from start: String.Index
) -> Range<String.Index>? {
    var cursor = start
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString,
           hasSTEPMarkerBoundary(before: cursor, in: text),
           let range = stepMarkerRange(marker, in: text, at: cursor) {
            return range
        }
        cursor = text.unicodeScalars.index(after: cursor)
    }
    return nil
}

private func stepMarkerRange(
    _ marker: String,
    in text: String,
    at index: String.Index
) -> Range<String.Index>? {
    var cursor = index
    for markerCharacter in marker.unicodeScalars {
        guard cursor < text.endIndex,
              String(text.unicodeScalars[cursor]).uppercased() == String(markerCharacter) else {
            return nil
        }
        cursor = text.unicodeScalars.index(after: cursor)
    }
    return index..<cursor
}

private func hasSTEPMarkerBoundary(before index: String.Index, in text: String) -> Bool {
    guard index > text.startIndex else {
        return true
    }
    let previous = text.unicodeScalars[text.unicodeScalars.index(before: index)]
    return !isSTEPIdentifierCharacter(previous)
}

private func isSTEPIdentifierCharacter(_ character: Unicode.Scalar) -> Bool {
    character.properties.isAlphabetic || character.properties.numericType != nil || character == "_"
}

private func stepEntities(in text: String) throws -> [Int: String] {
    var entities: [Int: String] = [:]
    var searchStart = text.startIndex
    while let hashIndex = nextSTEPHashOutsideString(in: text, from: searchStart) {
        var numberEnd = text.unicodeScalars.index(after: hashIndex)
        while numberEnd < text.endIndex, text.unicodeScalars[numberEnd].properties.numericType != nil {
            numberEnd = text.unicodeScalars.index(after: numberEnd)
        }

        guard numberEnd > text.unicodeScalars.index(after: hashIndex),
              let id = Int(text[text.unicodeScalars.index(after: hashIndex)..<numberEnd]) else {
            throw ImportError.invalidData("STEP entity or reference marker is malformed.")
        }
        guard let syntaxIndex = nextNonWhitespaceIndex(in: text, from: numberEnd) else {
            throw ImportError.invalidData("STEP entity or reference marker is unterminated.")
        }
        guard text.unicodeScalars[syntaxIndex] == "=" else {
            guard isSTEPReferenceTerminator(text.unicodeScalars[syntaxIndex]) else {
                throw ImportError.invalidData("STEP entity or reference marker is malformed.")
            }
            searchStart = syntaxIndex
            continue
        }

        let entityStart = text.unicodeScalars.index(after: syntaxIndex)
        var cursor = entityStart
        var inString = false
        while cursor < text.endIndex {
            let character = text.unicodeScalars[cursor]
            if character == "'" {
                let next = text.unicodeScalars.index(after: cursor)
                if next < text.endIndex, text.unicodeScalars[next] == "'" {
                    cursor = text.unicodeScalars.index(after: next)
                    continue
                }
                inString.toggle()
            }
            if character == ";", !inString {
                guard entities[id] == nil else {
                    throw ImportError.invalidData("STEP entity ID #\(id) is duplicated.")
                }
                entities[id] = String(text[entityStart..<cursor])
                searchStart = text.unicodeScalars.index(after: cursor)
                break
            }
            cursor = text.unicodeScalars.index(after: cursor)
        }
        if cursor >= text.endIndex {
            throw ImportError.invalidData("STEP entity #\(id) is unterminated.")
        }
    }
    return entities
}

private func nextNonWhitespaceIndex(in text: String, from start: String.Index) -> String.Index? {
    var cursor = start
    while cursor < text.endIndex {
        guard text.unicodeScalars[cursor].properties.isWhitespace else {
            return cursor
        }
        cursor = text.unicodeScalars.index(after: cursor)
    }
    return nil
}

private func isSTEPReferenceTerminator(_ character: Unicode.Scalar) -> Bool {
    character == "," || character == ")" || character == ";"
}

private func stepPoints(from entity: String, unit: LengthUnit) throws -> [Point3D] {
    guard let content = firstDoubleParenthesizedContent(in: entity) else {
        throw ImportError.invalidData("STEP point list has no coordinates.")
    }
    return try tupleContents(in: content).map { tuple in
        let values = try numericValues(from: tuple, expectedCount: 3, label: "STEP point")
        return Point3D(
            x: unit.toInternal(values[0]),
            y: unit.toInternal(values[1]),
            z: unit.toInternal(values[2])
        )
    }
}

private func stepFaceIndices(from entity: String, pointCount: Int) throws -> [UInt32] {
    guard let content = firstDoubleParenthesizedContent(in: entity) else {
        throw ImportError.invalidData("STEP face set has no indices.")
    }
    var indices: [UInt32] = []
    for tuple in try tupleContents(in: content) {
        let values = try numericValues(from: tuple, expectedCount: 3, label: "STEP face index")
        for value in values {
            guard value.rounded(.towardZero) == value else {
                throw ImportError.invalidData("STEP face index is not an integer.")
            }
            let maximumOneBasedIndex = min(Double(pointCount), Double(UInt32.max) + 1.0)
            guard value >= 1.0, value <= maximumOneBasedIndex else {
                throw ImportError.invalidData("STEP face index is out of range.")
            }
            let oneBasedIndex = Int(value)
            let zeroBasedIndex = oneBasedIndex - 1
            indices.append(UInt32(zeroBasedIndex))
        }
    }
    return indices
}

private func stepFirstReference(in entity: String) -> Int? {
    guard let hashIndex = nextSTEPHashOutsideString(in: entity, from: entity.startIndex) else {
        return nil
    }
    var numberEnd = entity.index(after: hashIndex)
    while numberEnd < entity.endIndex, entity[numberEnd].isNumber {
        numberEnd = entity.index(after: numberEnd)
    }
    return Int(entity[entity.index(after: hashIndex)..<numberEnd])
}

func firstDoubleParenthesizedContent(in text: String) -> String? {
    var searchStart = text.startIndex
    while let first = nextSTEPCharacterOutsideString("(", in: text, from: searchStart) {
        let second = text.unicodeScalars.index(after: first)
        if second < text.endIndex, text.unicodeScalars[second] == "(" {
            var depth = 0
            var cursor = first
            var inString = false
            while cursor < text.endIndex {
                if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
                    continue
                }
                if inString {
                    cursor = text.unicodeScalars.index(after: cursor)
                    continue
                }
                if text.unicodeScalars[cursor] == "(" {
                    depth += 1
                } else if text.unicodeScalars[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[text.unicodeScalars.index(after: first)..<cursor])
                    }
                }
                cursor = text.unicodeScalars.index(after: cursor)
            }
            return nil
        }
        searchStart = second
    }
    return nil
}

private func nextSTEPHashOutsideString(in text: String, from start: String.Index) -> String.Index? {
    nextSTEPCharacterOutsideString("#", in: text, from: start)
}

private func nextSTEPCharacterOutsideString(
    _ target: Unicode.Scalar,
    in text: String,
    from start: String.Index
) -> String.Index? {
    var cursor = start
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString, text.unicodeScalars[cursor] == target {
            return cursor
        }
        cursor = text.unicodeScalars.index(after: cursor)
    }
    return nil
}

private func updateSTEPStringState(in text: String, cursor: inout String.Index, inString: inout Bool) -> Bool {
    guard text.unicodeScalars[cursor] == "'" else {
        return false
    }
    let next = text.unicodeScalars.index(after: cursor)
    if next < text.endIndex, text.unicodeScalars[next] == "'" {
        cursor = text.unicodeScalars.index(after: next)
        return true
    }
    inString.toggle()
    cursor = next
    return true
}

private func stepSyntaxOutsideStrings(in text: String) -> String {
    var output = ""
    var cursor = text.startIndex
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString {
            output.unicodeScalars.append(text.unicodeScalars[cursor])
        }
        cursor = text.unicodeScalars.index(after: cursor)
    }
    return output
}

func tupleContents(in text: String) throws -> [String] {
    var tuples: [String] = []
    var tupleStart: String.Index?
    var depth = 0
    var cursor = text.startIndex
    while cursor < text.endIndex {
        let character = text[cursor]
        if character == "(" {
            if depth == 0 {
                tupleStart = text.index(after: cursor)
            }
            depth += 1
        } else if character == ")" {
            guard depth > 0 else {
                throw ImportError.invalidData("STEP tuple list contains unbalanced parentheses.")
            }
            depth -= 1
            if depth == 0, let start = tupleStart {
                tuples.append(String(text[start..<cursor]))
                tupleStart = nil
            }
        } else if depth == 0, character != ",", !character.isWhitespace {
            throw ImportError.invalidData("STEP tuple list contains unexpected content.")
        }
        cursor = text.index(after: cursor)
    }
    guard depth == 0 else {
        throw ImportError.invalidData("STEP tuple list contains unbalanced parentheses.")
    }
    guard !tuples.isEmpty else {
        throw ImportError.invalidData("STEP tuple list contains no tuples.")
    }
    return tuples
}

func numericValues(from tuple: String, expectedCount: Int, label: String) throws -> [Double] {
    let values = tuple
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard values.count == expectedCount else {
        throw ImportError.invalidData("\(label) has \(values.count) values.")
    }
    return try values.map { value in
        guard !value.isEmpty,
              let number = Double(value),
              number.isFinite else {
            throw ImportError.invalidData("\(label) contains a non-numeric value.")
        }
        return number
    }
}

func stepNumber(_ value: Double) -> String {
    String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
}

func stepName(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}
