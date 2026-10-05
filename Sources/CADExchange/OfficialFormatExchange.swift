import Foundation
import CADCore
import CADIR
import CADKernel

public struct OfficialFormatExchange: Sendable {
    private let nativeStore: NativePackageStore
    private let stepExchange: STEPExchange
    private let igesExchange: IGESExchange
    private let stlExporter: STLExporter
    private let threeMFExchange: ThreeMFExchange
    private let objExchange: OBJExchange
    private let dxfExchange: DXFExchange
    private let svgExchange: SVGExchange
    private let standardMeshExchange: any StandardMeshExchanging
    private let usdExporter: USDExporter
    private let usdExchange: USDExchange
    private let pdfExporter: PDFExporter

    public init(
        tolerance: ModelingTolerance,
        nativeStore: NativePackageStore? = nil,
        stepExchange: STEPExchange? = nil,
        igesExchange: IGESExchange? = nil,
        stlExporter: STLExporter? = nil,
        threeMFExchange: ThreeMFExchange? = nil,
        objExchange: OBJExchange? = nil,
        dxfExchange: DXFExchange? = nil,
        svgExchange: SVGExchange? = nil,
        standardMeshExchange: (any StandardMeshExchanging)? = nil,
        usdExporter: USDExporter? = nil,
        usdExchange: USDExchange? = nil,
        pdfExporter: PDFExporter? = nil
    ) {
        self.nativeStore = nativeStore ?? NativePackageStore(tolerance: tolerance)
        self.stepExchange = stepExchange ?? STEPExchange(tolerance: tolerance)
        self.igesExchange = igesExchange ?? IGESExchange(tolerance: tolerance)
        self.stlExporter = stlExporter ?? STLExporter(tolerance: tolerance)
        self.threeMFExchange = threeMFExchange ?? ThreeMFExchange(tolerance: tolerance)
        self.objExchange = objExchange ?? OBJExchange(tolerance: tolerance)
        self.dxfExchange = dxfExchange ?? DXFExchange(tolerance: tolerance)
        self.svgExchange = svgExchange ?? SVGExchange(tolerance: tolerance)
        self.standardMeshExchange = standardMeshExchange ?? StandardMeshExchange(tolerance: tolerance)
        self.usdExporter = usdExporter ?? USDExporter(tolerance: tolerance)
        self.usdExchange = usdExchange ?? USDExchange(tolerance: tolerance)
        self.pdfExporter = pdfExporter ?? PDFExporter(tolerance: tolerance)
    }

    public func write(
        _ evaluatedDocument: EvaluatedDocument,
        as format: ExchangeFileFormat,
        units overrideUnits: UnitSystem? = nil,
        to sink: any ByteSink
    ) throws {
        if evaluatedDocument.document.independentShapes != nil {
            try write(evaluatedDocument.document,as:format,units:overrideUnits,to:sink)
            return
        }
        try evaluatedDocument.validate()
        if !evaluatedDocument.document.productAttributes.isEmpty, format != .swiftCAD, format != .step {
            throw ProductAttributeError.unsupportedSemantics("This format cannot preserve document product attribute scopes and override provenance.")
        }
        let units = overrideUnits ?? evaluatedDocument.document.units
        switch format {
        case .swiftCAD:
            try nativeStore.writePackage(for: evaluatedDocument.document, to: sink)
        case .step:
            try stepExchange.write(evaluatedDocument, units: units, to: sink)
        case .iges:
            try igesExchange.write(brep: evaluatedDocument.brep, units: units, to: sink)
        case .stl:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try stlExporter.writeBinary(meshes: meshes, options: STLExportOptions(lengthUnit: units.length), to: sink)
        case .threeMF:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try threeMFExchange.write(meshes: meshes, unit: units.length, to: sink)
        case .obj:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try objExchange.write(meshes: meshes, unit: units.length, to: sink)
        case .dxf:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try dxfExchange.write(meshes: meshes, unit: units.length, to: sink)
        case .svg:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try svgExchange.write(meshes: meshes, unit: units.length, to: sink)
        case .glb, .gltf, .ply, .vrml:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try standardMeshExchange.write(meshes: meshes, as: format, unit: units.length, to: sink)
        case .usd:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try usdExporter.write(meshes: meshes, encoding: .usd, unit: units.length, to: sink)
        case .usda:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try usdExporter.write(meshes: meshes, encoding: .usda, unit: units.length, to: sink)
        case .usdc:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try usdExporter.write(meshes: meshes, encoding: .usdc, unit: units.length, to: sink)
        case .usdz:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try usdExporter.write(meshes: meshes, encoding: .usdz, unit: units.length, to: sink)
        case .pdf:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try pdfExporter.write(meshes: meshes, title: evaluatedDocument.document.metadata.name ?? "Swift-CAD Export", to: sink)
        }
    }

    /// Publishes only after the caller accepts every concrete authored source-domain loss.
    @discardableResult
    public func write(_ evaluated: EvaluatedDocument, as format: ExchangeFileFormat,
                      units: UnitSystem? = nil, policy: ExchangeExportPolicy,
                      to sink: any ByteSink) throws -> ExchangePreservationReport {
        try evaluated.validate()
        let planner = DocumentExchangePreservationPlanner()
        let report = planner.report(for: evaluated.document, as: format)
        try planner.admit(report, policy: policy)
        if format == .swiftCAD {
            try write(evaluated, as: format, units: units, to: sink)
            return report
        }
        if format == .step {
            let storage = DataByteSink()
            let writer = report.lostDomains.contains(.independentShapes) ? stepExchange.permittingReportedGroupLoss() : stepExchange
            try writer.write(evaluated, units: units, to: storage)
            try sink.write(storage.bytes)
            return report
        }
        let outputUnits = units ?? evaluated.document.units
        try outputUnits.validate()
        // The original evaluated source/receipt remains intact. Actual format producers consume its real geometry.
        let storage = DataByteSink()
        if format == .iges {
            if planner.usesIndependentIGESProducer(for: evaluated.document) {
                try igesExchange.permittingReportedIndependentProjection(report).write(evaluated.document, units: outputUnits, to: storage)
            } else {
                try igesExchange.write(brep: evaluated.brep, units: outputUnits, to: storage)
            }
        } else {
            let meshes = evaluated.meshes.materializedDictionary()
            switch format {
            case .stl: try stlExporter.writeBinary(meshes: meshes, options: STLExportOptions(lengthUnit: outputUnits.length), to: storage)
            case .threeMF: try threeMFExchange.write(meshes: meshes, unit: outputUnits.length, to: storage)
            case .obj: try objExchange.write(meshes: meshes, unit: outputUnits.length, to: storage)
            case .dxf: try dxfExchange.write(meshes: meshes, unit: outputUnits.length, to: storage)
            case .svg: try svgExchange.write(meshes: meshes, unit: outputUnits.length, to: storage)
            case .glb, .gltf, .ply, .vrml: try standardMeshExchange.write(meshes: meshes, as: format, unit: outputUnits.length, to: storage)
            case .usd, .usda, .usdc, .usdz: try usdExporter.write(meshes: meshes, encoding: format == .usda ? .usda : (format == .usdc ? .usdc : (format == .usdz ? .usdz : .usd)), unit: outputUnits.length, to: storage)
            case .pdf: try pdfExporter.write(meshes: meshes, title: evaluated.document.metadata.name ?? "Swift-CAD Export", to: storage)
            case .swiftCAD, .step, .iges: throw ExchangePreservationError.unsupportedPolicyFormat
            }
        }
        try sink.write(storage.bytes)
        return report
    }

    @discardableResult
    public func export(_ evaluated: EvaluatedDocument, as format: ExchangeFileFormat, units: UnitSystem? = nil,
                       policy: ExchangeExportPolicy, to url: URL) throws -> ExchangePreservationReport {
        var report = ExchangePreservationReport()
        do {
            try writeFileAtomically(to: url) { sink in report = try write(evaluated, as: format, units: units, policy: policy, to: sink) }
            return report
        } catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    @discardableResult
    public func write(_ evaluated: EvaluatedDocument, as format: ExchangeFileFormat, units: UnitSystem? = nil,
                      policy: ExchangeExportPolicy, geometryPolicy: ExchangeGeometryConversionPolicy,
                      to sink: any ByteSink) throws -> ExchangeGeometryWriteReport {
        guard format == .step || format == .iges else { throw ExchangePreservationError.unsupportedPolicyFormat }
        try evaluated.validate()
        let planner = DocumentExchangePreservationPlanner()
        let preservation = planner.report(for: evaluated.document, as: format)
        try planner.admit(preservation, policy: policy)
        let output = DataByteSink(), conversions: ExchangeGeometryConversionReport
        if format == .step {
            let writer = preservation.lostDomains.contains(.independentShapes) ? stepExchange.permittingReportedGroupLoss() : stepExchange
            conversions = try writer.writeConverting(evaluated, units: units, geometryPolicy: geometryPolicy, to: output)
        }
        else if planner.usesIndependentIGESProducer(for: evaluated.document) {
            conversions = try igesExchange.permittingReportedIndependentProjection(preservation).writeConverting(evaluated.document,
                units: units, geometryPolicy: geometryPolicy, to: output)
        } else { conversions = try igesExchange.writeConverting(brep: evaluated.brep, units: units ?? evaluated.document.units, geometryPolicy: geometryPolicy, to: output) }
        var losses = preservation.losses
        for conversion in conversions.surfaceConversions {
            losses.append(ExchangeInformationLoss(domain: .geometry, reason: .certifiedConversion,
                description: "Surface \(conversion.surfaceID) changed to a certified standard representation over its unchanged native UV domain."))
        }
        for conversion in conversions.curveConversions {
            losses.append(ExchangeInformationLoss(domain: .geometry, reason: .certifiedConversion,
                description: "Curve \(conversion.curveID) changed to a certified standard representation over its original directed selection [\(conversion.startParameter), \(conversion.endParameter)]."))
        }
        try sink.write(output.bytes)
        return ExchangeGeometryWriteReport(preservation: .init(losses: losses), surfaceConversions: conversions.surfaceConversions,
            curveConversions: conversions.curveConversions)
    }
    @discardableResult
    public func export(_ evaluated: EvaluatedDocument, as format: ExchangeFileFormat, units: UnitSystem? = nil,
                       policy: ExchangeExportPolicy, geometryPolicy: ExchangeGeometryConversionPolicy,
                       to url: URL) throws -> ExchangeGeometryWriteReport {
        var result: ExchangeGeometryWriteReport?
        do { try writeFileAtomically(to: url) { sink in result = try write(evaluated, as: format, units: units, policy: policy, geometryPolicy: geometryPolicy, to: sink) } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
        guard let result else { throw ExportError.fileWriteFailure("Certified exchange publication did not produce a report.") }
        return result
    }

    public func write(_ page: DrawingExchangePage, as format: ExchangeFileFormat,
                      outputUnit: LengthUnit = .millimeter, usage: inout DrawingExchangeUsage,
                      to sink: any ByteSink) throws {
        switch format {
        case .dxf: try dxfExchange.write(page, outputUnit: outputUnit, usage: &usage, to: sink)
        case .svg: try svgExchange.write(page, outputUnit: outputUnit, usage: &usage, to: sink)
        case .pdf: try pdfExporter.write(page, outputUnit: outputUnit, usage: &usage, to: sink)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
    }
    public func export(_ page: DrawingExchangePage, as format: ExchangeFileFormat,
                       outputUnit: LengthUnit = .millimeter, usage: inout DrawingExchangeUsage,
                       to url: URL) throws {
        do { try writeFileAtomically(to: url) { sink in
            try write(page, as: format, outputUnit: outputUnit, usage: &usage, to: sink)
        } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func write(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                      hatchSegments: [BRepDrawingHatchSegment] = [], regions: [BRepDrawingMaterialRegion] = [], as format: ExchangeFileFormat,
                      options: DrawingExchangeOptions = .init(), to sink: any ByteSink) throws {
        switch format {
        case .dxf: try dxfExchange.write(section, in: evaluated, hatchSegments: hatchSegments, regions: regions, options: options, to: sink)
        case .svg: try svgExchange.write(section, in: evaluated, hatchSegments: hatchSegments, regions: regions, options: options, to: sink)
        case .pdf: try pdfExporter.write(section, in: evaluated, hatchSegments: hatchSegments, regions: regions, options: options, to: sink)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
    }
    public func export(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                       hatchSegments: [BRepDrawingHatchSegment] = [], regions: [BRepDrawingMaterialRegion] = [], as format: ExchangeFileFormat,
                       options: DrawingExchangeOptions = .init(), to url: URL) throws {
        do { try writeFileAtomically(to: url) { sink in try write(section, in: evaluated,
            hatchSegments: hatchSegments, regions: regions, as: format, options: options, to: sink) } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func write(_ projection: BRepDrawingPlacedProjection, in evaluated: EvaluatedDocument,
                      as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(),
                      to sink: any ByteSink) throws {
        switch format {
        case .dxf: try dxfExchange.write(projection, in: evaluated, options: options, to: sink)
        case .svg: try svgExchange.write(projection, in: evaluated, options: options, to: sink)
        case .pdf: try pdfExporter.write(projection, in: evaluated, options: options, to: sink)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
    }
    public func export(_ projection: BRepDrawingPlacedProjection, in evaluated: EvaluatedDocument,
                       as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(), to url: URL) throws {
        do { try writeFileAtomically(to: url) { sink in
            try write(projection, in: evaluated, as: format, options: options, to: sink)
        } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func write(_ projection: BRepDrawingProjection, in evaluated: EvaluatedDocument,
                      as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(),
                      to sink: any ByteSink) throws {
        switch format {
        case .dxf: try dxfExchange.write(projection, in: evaluated, options: options, to: sink)
        case .svg: try svgExchange.write(projection, in: evaluated, options: options, to: sink)
        case .pdf: try pdfExporter.write(projection, in: evaluated, options: options, to: sink)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
    }
    public func export(_ projection: BRepDrawingProjection, in evaluated: EvaluatedDocument,
                       as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(), to url: URL) throws {
        do { try writeFileAtomically(to: url) { sink in
            try write(projection, in: evaluated, as: format, options: options, to: sink)
        } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func write(_ projection: BRepDrawingProjection, as format: ExchangeFileFormat,
                      options: DrawingExchangeOptions = .init(), to sink: any ByteSink) throws {
        switch format {
        case .dxf: try dxfExchange.write(projection, options: options, to: sink)
        case .svg: try svgExchange.write(projection, options: options, to: sink)
        case .pdf: try pdfExporter.write(projection, options: options, to: sink)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
    }
    public func export(_ projection: BRepDrawingProjection, as format: ExchangeFileFormat,
                       options: DrawingExchangeOptions = .init(), to url: URL) throws {
        do { try writeFileAtomically(to: url) { sink in try write(projection, as: format, options: options, to: sink) } }
        catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func write(_ document:CADDocument, as format:ExchangeFileFormat, units:UnitSystem? = nil, to sink:any ByteSink) throws {
        switch format {
        case .swiftCAD: try nativeStore.writePackage(for:document,to:sink)
        case .step: try stepExchange.write(document,units:units,to:sink)
        case .iges: try igesExchange.write(document,units:units,to:sink)
        default:
            if document.independentShapes != nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Other public exchange formats have no independent-curve/surface/group/placement source producer yet.
                // Establish actual original source availability and explicit format-loss handling before these paths can publish.
                throw IndependentShapeExchangeError.unsupportedSemantics("This format cannot yet retain independent CAD source.")
            }
            throw IndependentShapeExchangeError.unsupportedSemantics("This document format requires an evaluated mesh artifact.")
        }
    }

    public func export(_ document:CADDocument, as format:ExchangeFileFormat, units:UnitSystem? = nil, to url:URL) throws {
        do {
            try writeFileAtomically(to:url) { sink in try write(document,as:format,units:units,to:sink) }
        } catch let error as ByteSinkError { throw ExportError.fileWriteFailure(error.localizedDescription) }
    }

    public func `import`(_ source: any ByteSource, as format: ExchangeFileFormat,
                         policy: ExchangeImportPolicy) throws -> ImportedExchangeModel {
        switch policy {
        case .strict: return try self.import(source, as: format)
        case .allowPartial:
            switch format {
            case .step: return try stepExchange.import(source, policy: policy)
            case .iges: return try igesExchange.import(source, policy: policy)
            default: throw ExchangePreservationError.unsupportedPolicyFormat
            }
        }
    }

    public func `import`(_ source: any ByteSource, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        try Task.checkCancellation()
        guard format.supportsImport else {
            throw ImportError.unsupportedFormat(format.displayName)
        }
        switch format {
        case .swiftCAD:
            let document = try nativeStore.loadDocument(from: source)
            return ImportedExchangeModel(format: .swiftCAD, document: document, units: document.units)
        case .step:
            return try stepExchange.import(source)
        case .iges:
            return try igesExchange.import(source)
        case .stl:
            return try stlExporter.importBinary(source)
        case .threeMF:
            return try threeMFExchange.import(source)
        case .obj:
            return try objExchange.import(source)
        case .dxf:
            return try dxfExchange.import(source)
        case .svg:
            return try svgExchange.import(source)
        case .usd, .usda, .usdc, .usdz:
            return try usdExchange.import(source, as: format)
        case .glb, .gltf, .ply, .vrml:
            return try standardMeshExchange.read(source, as: format, explicitUnit: .meter, resolver: nil)
        case .pdf:
            throw ImportError.unsupportedFormat(format.displayName)
        }
    }

    /// Imports a mesh exchange format with an explicit fallback unit for
    /// unitless input. Embedded format metadata remains authoritative.
    public func `import`(
        _ source: any ByteSource,
        as format: ExchangeFileFormat,
        explicitUnit: LengthUnit?
    ) throws -> ImportedExchangeModel {
        try Task.checkCancellation()
        guard format.supportsImport else {
            throw ImportError.unsupportedFormat(format.displayName)
        }
        switch format {
        case .stl:
            return try stlExporter.importBinary(source, explicitUnit: explicitUnit)
        case .obj:
            return try objExchange.import(source, explicitUnit: explicitUnit)
        case .glb, .gltf, .ply, .vrml:
            return try standardMeshExchange.read(source, as: format, explicitUnit: explicitUnit, resolver: nil)
        default:
            return try self.import(source, as: format)
        }
    }

    public func export(
        _ evaluatedDocument: EvaluatedDocument,
        as format: ExchangeFileFormat,
        units overrideUnits: UnitSystem? = nil,
        to url: URL
    ) throws {
        do {
            try writeFileAtomically(to: url) { sink in
                try write(evaluatedDocument, as: format, units: overrideUnits, to: sink)
            }
        } catch let error as ByteSinkError {
            throw ExportError.fileWriteFailure(error.localizedDescription)
        }
    }

    public func export(_ evaluatedDocument: EvaluatedDocument, to url: URL) throws {
        guard let format = ExchangeFileFormat.format(forFileExtension: url.pathExtension) else {
            throw ExportError.invalidMesh("Unsupported file extension .\(url.pathExtension).")
        }
        try export(evaluatedDocument, as: format, units: nil, to: url)
    }

    public func `import`(from url: URL) throws -> ImportedExchangeModel {
        guard let format = ExchangeFileFormat.format(forFileExtension: url.pathExtension) else {
            throw ImportError.unsupportedFormat(url.pathExtension)
        }
        do {
            if [.glb, .gltf, .ply, .vrml].contains(format) {
                return try standardMeshExchange.read(MappedFileByteSource(url: url), as: format,
                    explicitUnit: .meter, resolver: LocalMeshBufferResolver(directory: url.deletingLastPathComponent()))
            }
            return try self.import(MappedFileByteSource(url: url), as: format)
        } catch let error as ByteSourceError {
            throw ImportError.fileReadFailure(error.localizedDescription)
        } catch {
            throw error
        }
    }

    public func `import`(
        from url: URL,
        explicitUnit: LengthUnit?
    ) throws -> ImportedExchangeModel {
        guard let format = ExchangeFileFormat.format(forFileExtension: url.pathExtension) else {
            throw ImportError.unsupportedFormat(url.pathExtension)
        }
        do {
            if [.glb, .gltf, .ply, .vrml].contains(format) {
                return try standardMeshExchange.read(MappedFileByteSource(url: url), as: format,
                    explicitUnit: explicitUnit, resolver: LocalMeshBufferResolver(directory: url.deletingLastPathComponent()))
            }
            return try self.import(
                MappedFileByteSource(url: url),
                as: format,
                explicitUnit: explicitUnit
            )
        } catch let error as ByteSourceError {
            throw ImportError.fileReadFailure(error.localizedDescription)
        } catch {
            throw error
        }
    }
}
