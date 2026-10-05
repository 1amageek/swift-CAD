import Foundation

public protocol StandardMeshBufferResolving: Sendable {
    /// Returns owned bytes after admitting the resource size, without exceeding the bound.
    func readBuffer(uri: String, maximumBytes: Int) throws -> Data
}
