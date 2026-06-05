import Foundation
import CADUSD

#if CAD_ENABLE_USDC_READER
import CADUSDC
#endif

public struct USDZReader: USDSceneReader {
    public static let fileSignature: [UInt8] = [0x50, 0x4b]

    private let textReader: USDAReader

    public init(textReader: USDAReader = USDAReader()) {
        self.textReader = textReader
    }

    public func read(from data: Data) throws -> USDScene {
        guard data.starts(with: Self.fileSignature) else {
            throw USDImportError.invalidData("USDZ data is missing the ZIP signature.")
        }

        let archive = try USDZArchive(data: data)
        guard let defaultLayer = archive.defaultLayer else {
            throw USDImportError.invalidData("USDZ package contains no entries.")
        }
        guard defaultLayer.isUSDLayer else {
            throw USDImportError.unsupportedFeature("USDZ default layer must be the first file and use a USD extension.")
        }
        return try readLayer(defaultLayer)
    }

    private func readLayer(_ entry: USDZArchiveEntry) throws -> USDScene {
        switch entry.fileExtension {
        case "usda":
            return try textReader.read(from: entry.data)
        case "usd":
            if entry.data.starts(with: USDCReaderSignature.bytes) {
                return try readUSDC(entry.data)
            }
            return try textReader.read(from: entry.data)
        case "usdc":
            return try readUSDC(entry.data)
        default:
            throw USDImportError.unsupportedFeature("USDZ default layer \(entry.path) is not a USD layer.")
        }
    }

    private func readUSDC(_ data: Data) throws -> USDScene {
        #if CAD_ENABLE_USDC_READER
        return try USDCReader().read(from: data)
        #else
        throw USDImportError.unsupportedFeature("USDC default layers in USDZ require the USDCImport trait.")
        #endif
    }
}

private enum USDCReaderSignature {
    static let bytes = Data("PXR-USDC".utf8)
}
