import CADCore
import CADIR
import CADUSD
import OpenUSD
import OpenUSDC
import OpenUSDZ

public struct USDExchange: Sendable {
    private let textReader: USDAReader
    private let binaryReader: USDCReader
    private let packageReader: USDZReader
    private let sceneImporter: any USDSceneImporting
    private let readingOptions: USDReadingOptions
    private let resourceLimits: ExchangeResourceLimits
    private let standaloneLayerValidator: USDStandaloneLayerValidator

    public init(
        tolerance: ModelingTolerance,
        sceneImporter: (any USDSceneImporting)? = nil,
        readingOptions: USDReadingOptions = .default,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.textReader = USDAReader()
        self.binaryReader = USDCReader()
        self.packageReader = USDZReader()
        self.sceneImporter = sceneImporter ?? SceneImporter(tolerance: tolerance)
        self.readingOptions = readingOptions
        self.resourceLimits = resourceLimits
        self.standaloneLayerValidator = USDStandaloneLayerValidator()
    }

    public func `import`(
        _ source: any ByteSource,
        as format: ExchangeFileFormat
    ) throws -> ImportedExchangeModel {
        guard format == .usd || format == .usda || format == .usdc || format == .usdz else {
            throw ImportError.unsupportedFormat(format.displayName)
        }
        try resourceLimits.validate()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        let resourceValidator = USDImportResourceValidator(limits: resourceLimits)
        return try source.withNoCopyData { data in
            let bytes = USDByteStorage(data: data).wholeSlice
            let containsUSDCSignature = USDCSignature.matches(bytes)
            let isText = format == .usda || (format == .usd && !containsUSDCSignature)
            try resourceValidator.validateInput(
                bytes,
                isText: isText,
                format: format,
                budget: budget
            )
            do {
                let result = try importUSD(
                    from: bytes,
                    as: format,
                    containsUSDCSignature: containsUSDCSignature
                )
                try resourceValidator.validateOutput(result, format: format, budget: budget)
                return ImportedExchangeModel(format: format, meshes: result.meshes, units: result.units)
            } catch let error as ImportError {
                throw error
            } catch let error as KernelError {
                throw error
            } catch let error as USDError {
                throw mapUSDError(error)
            } catch {
                throw ImportError.invalidData(error.localizedDescription)
            }
        }
    }

    private func importUSD(
        from bytes: USDByteSlice,
        as format: ExchangeFileFormat,
        containsUSDCSignature: Bool
    ) throws -> ImportResult {
        let scene: USDScene
        switch format {
        case .usd:
            scene = containsUSDCSignature
                ? try readStandaloneUSDC(from: bytes)
                : try readStandaloneUSDA(from: bytes)
        case .usda:
            scene = try readStandaloneUSDA(from: bytes)
        case .usdc:
            scene = try readStandaloneUSDC(from: bytes)
        case .usdz:
            scene = try packageReader.read(from: bytes, options: readingOptions)
        default:
            throw ImportError.unsupportedFormat(format.displayName)
        }
        return try sceneImporter.importScene(scene, named: format.displayName)
    }

    private func readStandaloneUSDA(from bytes: USDByteSlice) throws -> USDScene {
        let layer = try textReader.readSdfLayer(from: bytes)
        try standaloneLayerValidator.validate(layer)
        return try textReader.read(from: bytes, options: readingOptions)
    }

    private func readStandaloneUSDC(from bytes: USDByteSlice) throws -> USDScene {
        let layer = try binaryReader.readSdfLayer(from: bytes)
        try standaloneLayerValidator.validate(layer)
        return try binaryReader.read(from: bytes, options: readingOptions)
    }

    private func mapUSDError(_ error: USDError) -> ImportError {
        switch error {
        case let .invalidData(message):
            return .invalidData(message)
        case let .missingRequiredField(field):
            return .missingRequiredEntity(field)
        case let .unsupportedFeature(message):
            return .unsupportedFeature(message)
        case let .formatConstraint(message):
            return .formatConstraint(message)
        case let .formatVersion(message):
            return .unsupportedVersion(message)
        case let .securityViolation(message):
            return .securityViolation(message)
        case let .resourceUnavailable(message):
            return .resourceUnavailable(message)
        case let .notImplemented(message):
            return .unsupportedFeature(message)
        case let .composition(error):
            return .compositionFailure(kind: error.kind.rawValue, message: error.message)
        }
    }
}

private enum USDCSignature {
    private static let bytes = Array("PXR-USDC".utf8)

    static func matches(_ source: USDByteSlice) -> Bool {
        guard source.byteCount >= bytes.count else { return false }
        return source.withUnsafeBytes { sourceBytes in
            sourceBytes.prefix(bytes.count).elementsEqual(bytes)
        }
    }
}
