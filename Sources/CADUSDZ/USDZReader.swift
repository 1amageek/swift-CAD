import Foundation
import OpenUSD
import OpenUSDZ

public struct USDZReader: USDSceneReader {
    private let reader: OpenUSDZ.USDZReader

    public init(reader: OpenUSDZ.USDZReader = OpenUSDZ.USDZReader()) {
        self.reader = reader
    }

    public func read(from data: Data) throws -> USDScene {
        try reader.read(from: data)
    }

    public func read(from data: Data, at rootPath: String) throws -> USDScene {
        try reader.read(from: data, at: rootPath)
    }

    public func readLayerGraph(from data: Data) throws -> USDZLayerGraph {
        try reader.readLayerGraph(from: data)
    }

    public func readLayerGraph(from data: Data, at rootPath: String) throws -> USDZLayerGraph {
        try reader.readLayerGraph(from: data, at: rootPath)
    }
}
