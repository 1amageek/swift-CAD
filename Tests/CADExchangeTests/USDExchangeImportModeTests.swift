import Foundation
import Testing
import CADCore
@testable import CADExchange

@Suite("USD Exchange Import Mode")
struct USDExchangeImportModeTests {
    @Test(.timeLimit(.minutes(1)))
    func automaticUSDAImportUsesExpectedPlatformMode() throws {
        let exchange = USDExchange(
            importMode: .automatic,
            systemToolchain: USDAWritingUSDImportToolchain()
        )

        #if os(macOS)
        let model = try exchange.import(BorrowedBytes(Data("not usd".utf8)), as: .usd)
        #else
        let model = try exchange.import(BorrowedBytes(Data(importModeTestUSDA.utf8)), as: .usda)
        #endif

        #expect(model.meshes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticImportModeUsesSystemOnlyOnMacOS() throws {
        let exchange = USDExchange(
            importMode: .automatic,
            systemToolchain: ThrowingUSDImportToolchain()
        )

        #if os(macOS)
        #expect(throws: ImportError.self) {
            _ = try exchange.import(BorrowedBytes(Data(importModeTestUSDA.utf8)), as: .usda)
        }
        #else
        let model = try exchange.import(BorrowedBytes(Data(importModeTestUSDA.utf8)), as: .usda)

        #expect(model.meshes.count == 1)
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticUSDCImportUsesExpectedPlatformMode() throws {
        let exchange = USDExchange(
            importMode: .automatic,
            systemToolchain: USDAWritingUSDImportToolchain()
        )

        #if os(macOS)
        let model = try exchange.import(BorrowedBytes(Data("not usdc".utf8)), as: .usdc)

        #expect(model.meshes.count == 1)
        #else
        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdc".utf8)), as: .usdc)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_BINARY_USD_IMPORT
            guard case .invalidData = error else {
                #expect(Bool(false))
                return
            }
            #else
            #expect(error == .unsupportedFormat("USDC"))
            #endif
        } catch {
            #expect(Bool(false))
        }
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticUSDZImportUsesExpectedPlatformMode() throws {
        let exchange = USDExchange(
            importMode: .automatic,
            systemToolchain: USDAWritingUSDImportToolchain()
        )

        #if os(macOS)
        let model = try exchange.import(BorrowedBytes(Data("not usdz".utf8)), as: .usdz)

        #expect(model.meshes.count == 1)
        #else
        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdz".utf8)), as: .usdz)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_USDZ_PACKAGE_IMPORT
            guard case .invalidData = error else {
                #expect(Bool(false))
                return
            }
            #else
            #expect(error == .unsupportedFormat("USDZ"))
            #endif
        } catch {
            #expect(Bool(false))
        }
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func systemImportModeUsesSystemToolchain() throws {
        let exchange = USDExchange(
            importMode: .system,
            systemToolchain: USDAWritingUSDImportToolchain()
        )

        let model = try exchange.import(BorrowedBytes(Data("not usd".utf8)), as: .usd)

        #expect(model.meshes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func systemUSDToolchainFlattensCompositionArcs() throws {
        #if os(macOS)
        guard systemUSDToolsAreAvailable(["usdcat", "usdchecker"]) else {
            return
        }
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SwiftCAD-system-usd-import-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let rootURL = directoryURL.appendingPathComponent("root.usda")
        let meshURL = directoryURL.appendingPathComponent("mesh.usda")
        var primaryError: Error?
        let sink = DataByteSink()

        do {
            try Data(systemUSDReferenceRootUSDA.utf8).write(to: rootURL)
            try Data(systemUSDReferencedMeshUSDA.utf8).write(to: meshURL)
            try SystemUSDConversionToolchain().writeUSDA(fromUSD: rootURL, to: sink)
        } catch {
            primaryError = error
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            if primaryError == nil {
                primaryError = error
            }
        }
        if let primaryError {
            throw primaryError
        }
        let output = try #require(String(data: sink.bytes, encoding: .utf8))

        #expect(output.contains("def Xform \"Root\""))
        #expect(output.contains("point3f[] points"))
        #expect(!output.contains("references ="))
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticTextUSDImportUsesPureSwiftReaderOffMacOS() throws {
        #if !os(macOS)
        let exchange = USDExchange(
            importMode: .automatic,
            systemToolchain: ThrowingUSDImportToolchain()
        )

        let model = try exchange.import(BorrowedBytes(Data(importModeTestUSDA.utf8)), as: .usd)

        #expect(model.meshes.count == 1)
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func swiftUSDCImportIsTraitGated() throws {
        let exchange = USDExchange(importMode: .pureSwift)

        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdc".utf8)), as: .usdc)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_BINARY_USD_IMPORT
            guard case .invalidData = error else {
                #expect(Bool(false))
                return
            }
            #else
            #expect(error == .unsupportedFormat("USDC"))
            #endif
        } catch {
            #expect(Bool(false))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func swiftUSDZImportIsTraitGated() throws {
        let exchange = USDExchange(importMode: .pureSwift)

        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdz".utf8)), as: .usdz)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_USDZ_PACKAGE_IMPORT
            guard case .invalidData = error else {
                #expect(Bool(false))
                return
            }
            #else
            #expect(error == .unsupportedFormat("USDZ"))
            #endif
        } catch {
            #expect(Bool(false))
        }
    }
}

private struct USDAWritingUSDImportToolchain: USDImportToolchain {
    func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws {
        try sink.write(Data(importModeTestUSDA.utf8))
    }
}

private struct ThrowingUSDImportToolchain: USDImportToolchain {
    func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws {
        throw ImportError.invalidData("System USD should not be used.")
    }
}

private func systemUSDToolsAreAvailable(_ names: [String]) -> Bool {
    let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var searchPaths = environmentPath.split(separator: ":").map(String.init)
    searchPaths.append(contentsOf: ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"])
    for name in names {
        var foundTool = false
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                foundTool = true
                break
            }
        }
        guard foundTool else {
            return false
        }
    }
    return true
}

private let importModeTestUSDA = """
#usda 1.0
(
    defaultPrim = "Triangle"
    metersPerUnit = 1
    upAxis = "Z"
)

def Mesh "Triangle"
{
    point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
    int[] faceVertexCounts = [3]
    int[] faceVertexIndices = [0, 1, 2]
    uniform token subdivisionScheme = "none"
}
"""

private let systemUSDReferenceRootUSDA = """
#usda 1.0
(
    defaultPrim = "Root"
    metersPerUnit = 1
    upAxis = "Z"
)

def Xform "Root" (
    references = @mesh.usda@</Triangle>
)
{
}
"""

private let systemUSDReferencedMeshUSDA = """
#usda 1.0

def Mesh "Triangle"
{
    point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
    int[] faceVertexCounts = [3]
    int[] faceVertexIndices = [0, 1, 2]
    uniform token subdivisionScheme = "none"
}
"""
