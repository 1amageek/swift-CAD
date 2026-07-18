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
    private let glbExporter: GLBExporter
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
        glbExporter: GLBExporter? = nil,
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
        self.glbExporter = glbExporter ?? GLBExporter(tolerance: tolerance)
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
        try evaluatedDocument.validate()
        let units = overrideUnits ?? evaluatedDocument.document.units
        switch format {
        case .swiftCAD:
            try nativeStore.writePackage(for: evaluatedDocument.document, to: sink)
        case .step:
            try stepExchange.write(brep: evaluatedDocument.brep, units: units, to: sink)
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
        case .glb:
            let meshes = evaluatedDocument.meshes.materializedDictionary()
            try glbExporter.write(meshes: meshes, to: sink)
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

    public func `import`(_ source: any ByteSource, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
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
        case .glb, .pdf:
            throw ImportError.unsupportedFormat(format.displayName)
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
            return try self.import(MappedFileByteSource(url: url), as: format)
        } catch let error as ByteSourceError {
            throw ImportError.fileReadFailure(error.localizedDescription)
        } catch {
            throw error
        }
    }
}
