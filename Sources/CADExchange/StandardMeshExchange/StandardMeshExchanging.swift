import CADCore
import CADIR

/// Exchanges static mesh geometry, baking source scene placements into meshes.
/// Unsupported scene/material semantics fail rather than being discarded.
public protocol StandardMeshExchanging: Sendable {
    func read(_ source: any ByteSource, as format: ExchangeFileFormat,
              explicitUnit: LengthUnit?, resolver: (any StandardMeshBufferResolving)?) throws -> ImportedExchangeModel
    func write(meshes: [BodyID: Mesh], as format: ExchangeFileFormat,
               unit: LengthUnit, to sink: any ByteSink) throws
}
