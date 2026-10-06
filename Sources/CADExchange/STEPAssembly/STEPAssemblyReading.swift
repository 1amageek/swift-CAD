public protocol STEPAssemblyReading: Sendable {
    func read(_ source: any ByteSource) throws -> ImportedExchangeModel
}
