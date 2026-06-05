import Foundation
import OpenUSD
import OpenUSDZ

public struct PackageReader: USDSceneReader {
    private let reader: OpenUSDZ.USDZReader

    public init(reader: OpenUSDZ.USDZReader = OpenUSDZ.USDZReader()) {
        self.reader = reader
    }

    public func read(from data: Data) throws -> USDScene {
        try reader.read(from: data)
    }

    public func read(from data: Data, options: USDReadingOptions) throws -> USDScene {
        try reader.read(from: data, options: options)
    }

    public func read(from data: Data, rootLayerPath: String) throws -> USDScene {
        try reader.read(from: data, rootLayerPath: rootLayerPath)
    }

    public func read(
        from data: Data,
        rootLayerPath: String,
        options: USDReadingOptions
    ) throws -> USDScene {
        try reader.read(from: data, rootLayerPath: rootLayerPath, options: options)
    }

    public func readLayerGraph(from data: Data) throws -> USDZLayerGraph {
        try reader.readLayerGraph(from: data)
    }

    public func readLayerGraph(from data: Data, rootLayerPath: String) throws -> USDZLayerGraph {
        try reader.readLayerGraph(from: data, rootLayerPath: rootLayerPath)
    }

    @available(*, deprecated, message: "Use read(from:rootLayerPath:) instead.")
    public func read(from data: Data, at rootPath: String) throws -> USDScene {
        try read(from: data, rootLayerPath: rootPath)
    }

    @available(*, deprecated, message: "Use readLayerGraph(from:rootLayerPath:) instead.")
    public func readLayerGraph(from data: Data, at rootPath: String) throws -> USDZLayerGraph {
        try readLayerGraph(from: data, rootLayerPath: rootPath)
    }
}

@available(*, deprecated, renamed: "PackageReader")
public typealias USDZPackageReader = PackageReader

@available(*, deprecated, renamed: "PackageReader")
public typealias USDZReader = PackageReader
