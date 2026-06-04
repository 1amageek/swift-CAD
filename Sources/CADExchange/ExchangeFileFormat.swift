import Foundation

public enum ExchangeFileFormat: String, CaseIterable, Codable, Sendable, Hashable {
    case swiftCAD
    case step
    case iges
    case stl
    case threeMF
    case obj
    case dxf
    case svg
    case glb
    case usd
    case usda
    case usdc
    case usdz
    case pdf

    public var displayName: String {
        switch self {
        case .swiftCAD: "Swift-CAD Native"
        case .step: "STEP"
        case .iges: "IGES"
        case .stl: "STL"
        case .threeMF: "3MF"
        case .obj: "OBJ"
        case .dxf: "DXF"
        case .svg: "SVG"
        case .glb: "GLB"
        case .usd: "USD"
        case .usda: "USDA"
        case .usdc: "USDC"
        case .usdz: "USDZ"
        case .pdf: "PDF"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .swiftCAD: ["swcad"]
        case .step: ["step", "stp"]
        case .iges: ["iges", "igs"]
        case .stl: ["stl"]
        case .threeMF: ["3mf"]
        case .obj: ["obj"]
        case .dxf: ["dxf"]
        case .svg: ["svg"]
        case .glb: ["glb"]
        case .usd: ["usd"]
        case .usda: ["usda"]
        case .usdc: ["usdc"]
        case .usdz: ["usdz"]
        case .pdf: ["pdf"]
        }
    }

    public var supportsImport: Bool {
        switch self {
        case .swiftCAD, .step, .iges, .stl, .threeMF, .obj, .dxf, .svg, .usd, .usda:
            true
        case .usdc:
            #if os(macOS)
            true
            #elseif CAD_ENABLE_USDC_READER
            true
            #else
            false
            #endif
        case .usdz:
            #if os(macOS)
            true
            #elseif CAD_ENABLE_USDZ_READER
            true
            #else
            false
            #endif
        case .glb, .pdf:
            false
        }
    }

    public var supportsExport: Bool {
        true
    }

    public static func format(forFileExtension fileExtension: String) -> ExchangeFileFormat? {
        let normalized = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return allCases.first { $0.fileExtensions.contains(normalized) }
    }
}
