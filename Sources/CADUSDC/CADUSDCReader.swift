import Foundation
import OpenUSD
import OpenUSDC

public struct CADUSDCReader: USDSceneReader {
    private let reader: USDCReader

    public init(reader: USDCReader = USDCReader()) {
        self.reader = reader
    }

    public func read(from data: Data) throws -> USDScene {
        try reader.read(from: data)
    }

    public func readLayer(from data: Data) throws -> USDCLayer {
        try reader.readLayer(from: data)
    }

    public func readCrate(from data: Data) throws -> USDCCrateFile {
        try reader.readCrate(from: data)
    }
}
