import Foundation
import OpenUSD
import OpenUSDZ

public struct CADUSDZReader: USDSceneReader {
    private let reader: USDZReader

    public init(reader: USDZReader = USDZReader()) {
        self.reader = reader
    }

    public func read(from data: Data) throws -> USDScene {
        try reader.read(from: data)
    }

    public func readLayerGraph(from data: Data) throws -> USDZLayerGraph {
        try reader.readLayerGraph(from: data)
    }
}
