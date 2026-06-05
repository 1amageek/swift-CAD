import Foundation
import CADCore
import CADIR
import CADUSD
import OpenUSD

#if CAD_ENABLE_BINARY_USD_IMPORT
import CADUSDC
#endif

#if CAD_ENABLE_USDZ_PACKAGE_IMPORT
import CADUSDZ
#endif

public enum USDImportMode: Sendable, Equatable {
    case automatic
    case system
    case pureSwift
}

public struct USDExchange: Sendable {
    private let textReader: USDAReader
    private let importMode: USDImportMode
    private let systemToolchain: any USDImportToolchain

    public init(
        textReader: USDAReader = USDAReader(),
        importMode: USDImportMode = .automatic,
        systemToolchain: any USDImportToolchain = SystemUSDConversionToolchain()
    ) {
        self.textReader = textReader
        self.importMode = importMode
        self.systemToolchain = systemToolchain
    }

    public func `import`(_ source: any ByteSource, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        try source.withNoCopyData { data in
            do {
                let result = try importUSD(from: data, as: format)
                return ImportedExchangeModel(format: format, meshes: result.meshes, units: result.units)
            } catch let error as ImportError {
                throw error
            } catch let error as USDImportError {
                throw mapUSDImportError(error)
            } catch {
                throw ImportError.invalidData(error.localizedDescription)
            }
        }
    }

    private func importUSD(from data: Data, as format: ExchangeFileFormat) throws -> ImportResult {
        guard format == .usd || format == .usda || format == .usdc || format == .usdz else {
            throw ImportError.unsupportedFormat(format.displayName)
        }
        if shouldUseSystemImport {
            let scene = try readWithSystemUSD(from: data, fileExtension: format.rawValue)
            return try SceneImporter().importScene(scene, named: format.displayName)
        }
        return try importWithSwiftReader(from: data, as: format)
    }

    private func importWithSwiftReader(from data: Data, as format: ExchangeFileFormat) throws -> ImportResult {
        switch format {
        case .usd:
            if data.starts(with: USDCSignature.bytes) {
                return try importUSDCWithSwiftReader(from: data, sourceName: format.displayName)
            }
            let scene = try textReader.read(from: data)
            return try SceneImporter().importScene(scene, named: format.displayName)
        case .usda:
            let scene = try textReader.read(from: data)
            return try SceneImporter().importScene(scene, named: format.displayName)
        case .usdc:
            return try importUSDCWithSwiftReader(from: data, sourceName: format.displayName)
        case .usdz:
            return try importUSDZWithSwiftReader(from: data, sourceName: format.displayName)
        default:
            throw ImportError.unsupportedFormat(format.displayName)
        }
    }

    private var shouldUseSystemImport: Bool {
        switch importMode {
        case .automatic:
            #if os(macOS)
            true
            #else
            false
            #endif
        case .system:
            true
        case .pureSwift:
            false
        }
    }

    private func readWithSystemUSD(from data: Data, fileExtension: String) throws -> USDScene {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SwiftCAD-usd-import-\(UUID().uuidString)",
            isDirectory: true
        )
        let inputURL = directoryURL.appendingPathComponent("scene").appendingPathExtension(fileExtension)
        var importedScene: USDScene?
        var primaryError: Error?

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: inputURL)
            let sink = DataByteSink()
            try systemToolchain.writeUSDA(fromUSD: inputURL, to: sink)
            importedScene = try textReader.read(from: sink.bytes)
        } catch {
            primaryError = error
        }

        if fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.removeItem(at: directoryURL)
            } catch {
                if primaryError == nil {
                    primaryError = ImportError.fileReadFailure(
                        "Failed to remove temporary USD import directory: \(error.localizedDescription)"
                    )
                }
            }
        }

        if let importedScene {
            return importedScene
        }
        if let primaryError {
            throw primaryError
        }
        throw ImportError.invalidData("System USD import produced no scene.")
    }

    private func importUSDCWithSwiftReader(from data: Data, sourceName: String) throws -> ImportResult {
        #if CAD_ENABLE_BINARY_USD_IMPORT
        return try CADUSDC.USDCMeshImporter().importMeshes(from: data, named: sourceName)
        #else
        throw ImportError.unsupportedFormat(ExchangeFileFormat.usdc.displayName)
        #endif
    }

    private func importUSDZWithSwiftReader(from data: Data, sourceName: String) throws -> ImportResult {
        #if CAD_ENABLE_USDZ_PACKAGE_IMPORT
        return try CADUSDZ.USDZMeshImporter().importMeshes(from: data, named: sourceName)
        #else
        throw ImportError.unsupportedFormat(ExchangeFileFormat.usdz.displayName)
        #endif
    }

    private func mapUSDImportError(_ error: USDImportError) -> ImportError {
        switch error {
        case let .invalidData(message):
            return .invalidData(message)
        case let .missingRequiredField(field):
            return .missingRequiredEntity(field)
        case let .unsupportedFeature(message):
            return .invalidData("Unsupported USD feature: \(message)")
        case let .notImplemented(message):
            return .invalidData(message)
        }
    }
}

private enum USDCSignature {
    static let bytes = Data("PXR-USDC".utf8)
}
