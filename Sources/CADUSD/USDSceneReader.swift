import Foundation

public protocol USDSceneReader: Sendable {
    func read(from data: Data) throws -> USDScene
}
