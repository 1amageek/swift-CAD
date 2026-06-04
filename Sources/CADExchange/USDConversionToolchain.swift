import Foundation

public protocol USDConversionToolchain: Sendable {
    func writeUSDC(fromUSDA url: URL, to sink: any ByteSink) throws
    func writeUSDZ(fromUSDA url: URL, to sink: any ByteSink) throws
}

public protocol USDImportToolchain: Sendable {
    func writeUSDA(fromUSD url: URL, to sink: any ByteSink) throws
}
