import Foundation
import Testing
import CADUSD
import CADUSDZ

@Suite("USDZ Archive Layers")
struct USDZArchiveLayerTests {
    @Test(.timeLimit(.minutes(1)))
    func openUSDSingleUSDZFixturesResolveDefaultLayerData() throws {
        let cases = [
            (archive: "single_usd.usdz", layer: "test.usd", source: "single/test.usd"),
            (archive: "single_usda.usdz", layer: "test.usda", source: "single/test.usda"),
            (archive: "single_usdc.usdz", layer: "test.usdc", source: "single/test.usdc"),
        ]

        for testCase in cases {
            let archive = try openUSDZArchive(testCase.archive)

            #expect(archive.defaultLayer?.path == testCase.layer)
            #expect(try archive.data(forLayerPath: testCase.layer) == openUSDZFixture(testCase.source))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDAnchoredReferencesUSDZResolvesContainedLayers() throws {
        let archive = try openUSDZArchive("anchored_refs.usdz")

        #expect(archive.entries.map(\.path) == ["root.usd", "ref.usd", "sub/ref.usdc", "sub/ref.usda"])
        #expect(try archive.data(forLayerPath: "root.usd") == openUSDZFixture("anchored_refs/root.usd"))
        #expect(try archive.data(forLayerPath: "ref.usd") == openUSDZFixture("anchored_refs/ref.usd"))
        #expect(try archive.data(forLayerPath: "sub/ref.usdc") == openUSDZFixture("anchored_refs/sub/ref.usdc"))
        #expect(try archive.data(forLayerPath: "sub/ref.usda") == openUSDZFixture("anchored_refs/sub/ref.usda"))
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDNestedReferencesUSDZResolvesNestedContainedLayers() throws {
        let archive = try openUSDZArchive("nested_anchored_refs.usdz")

        #expect(archive.entries.map(\.path) == ["anchored_refs.usdz"])
        #expect(
            try archive.data(forLayerPath: "anchored_refs.usdz[root.usd]")
                == openUSDZFixture("anchored_refs/root.usd")
        )
        #expect(
            try archive.data(forLayerPath: "anchored_refs.usdz[sub/ref.usdc]")
                == openUSDZFixture("anchored_refs/sub/ref.usdc")
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func containedLayerResolutionReportsTypedUSDZErrors() throws {
        let archive = try openUSDZArchive("anchored_refs.usdz")

        #expect(throws: USDImportError.self) {
            _ = try archive.data(forLayerPath: "missing.usd")
        }
        #expect(throws: USDImportError.self) {
            _ = try archive.data(forLayerPath: "root.usd[child.usd]")
        }
        #expect(throws: USDImportError.self) {
            _ = try archive.data(forLayerPath: "root.usd[child.usd")
        }
    }
}

private func openUSDZArchive(_ relativePath: String) throws -> USDZArchive {
    try USDZArchive(data: openUSDZFixture(relativePath))
}

private func openUSDZFixture(_ relativePath: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("OpenUSD")
        .appendingPathComponent("testUsdUsdzFileFormat")
        .appendingPathComponent(relativePath)
    return try Data(contentsOf: url)
}
