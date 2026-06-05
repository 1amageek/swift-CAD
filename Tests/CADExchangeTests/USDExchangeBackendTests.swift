import Foundation
import Testing
import CADCore
@testable import CADExchange

@Suite("USD Exchange Backend")
struct USDExchangeBackendTests {
    @Test(.timeLimit(.minutes(1)))
    func automaticUSDAImportUsesExpectedPlatformBackend() throws {
        let exchange = USDExchange(
            importBackend: .automatic,
            systemImportToolchain: USDAWritingUSDImportToolchain()
        )

        #if os(macOS)
        let model = try exchange.import(BorrowedBytes(Data("not usd".utf8)), as: .usd)
        #else
        let model = try exchange.import(BorrowedBytes(Data(backendTestUSDA.utf8)), as: .usda)
        #endif

        #expect(model.meshes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticBackendUsesSystemOnlyOnMacOS() throws {
        let exchange = USDExchange(
            importBackend: .automatic,
            systemImportToolchain: ThrowingUSDImportToolchain()
        )

        #if os(macOS)
        #expect(throws: ImportError.self) {
            _ = try exchange.import(BorrowedBytes(Data(backendTestUSDA.utf8)), as: .usda)
        }
        #else
        let model = try exchange.import(BorrowedBytes(Data(backendTestUSDA.utf8)), as: .usda)

        #expect(model.meshes.count == 1)
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func systemUSDBackendUsesSystemToolchain() throws {
        let exchange = USDExchange(
            importBackend: .systemUSD,
            systemImportToolchain: USDAWritingUSDImportToolchain()
        )

        let model = try exchange.import(BorrowedBytes(Data("not usd".utf8)), as: .usd)

        #expect(model.meshes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDCImportIsTraitGated() throws {
        let exchange = USDExchange(importBackend: .pureSwift)

        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdc".utf8)), as: .usdc)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_USDC_READER
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
    func pureSwiftUSDZImportIsTraitGated() throws {
        let exchange = USDExchange(importBackend: .pureSwift)

        do {
            _ = try exchange.import(BorrowedBytes(Data("not usdz".utf8)), as: .usdz)
            #expect(Bool(false))
        } catch let error as ImportError {
            #if CAD_ENABLE_USDZ_READER
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
        try sink.write(Data(backendTestUSDA.utf8))
    }
}

private struct ThrowingUSDImportToolchain: USDImportToolchain {
    func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws {
        throw ImportError.invalidData("System USD should not be used.")
    }
}

private let backendTestUSDA = """
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
