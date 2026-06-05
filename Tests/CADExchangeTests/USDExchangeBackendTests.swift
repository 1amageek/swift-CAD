import Foundation
import Testing
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
    func systemUSDBackendUsesSystemToolchain() throws {
        let exchange = USDExchange(
            importBackend: .systemUSD,
            systemImportToolchain: USDAWritingUSDImportToolchain()
        )

        let model = try exchange.import(BorrowedBytes(Data("not usd".utf8)), as: .usd)

        #expect(model.meshes.count == 1)
    }
}

private struct USDAWritingUSDImportToolchain: USDImportToolchain {
    func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws {
        try sink.write(Data(backendTestUSDA.utf8))
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
