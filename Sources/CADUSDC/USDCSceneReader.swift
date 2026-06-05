import Foundation
import OpenUSD
import OpenUSDC

public struct USDCSceneReader: USDSceneReader {
    private let reader: OpenUSDC.USDCReader

    public init(reader: OpenUSDC.USDCReader = OpenUSDC.USDCReader()) {
        self.reader = reader
    }

    public func read(from data: Data) throws -> USDScene {
        try reader.read(from: data)
    }

    public func read(from data: Data, options: USDReadingOptions) throws -> USDScene {
        try reader.read(from: data, options: options)
    }

    public func readLayer(from data: Data) throws -> USDCLayer {
        try reader.readLayer(from: data)
    }

    public func readCrate(from data: Data) throws -> USDCCrateFile {
        try reader.readCrate(from: data)
    }
}
