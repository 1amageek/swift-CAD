import OpenUSD

public protocol USDSceneImporting: Sendable {
    func importScene(
        _ scene: USDScene,
        named sourceName: String
    ) throws -> ImportResult
}
