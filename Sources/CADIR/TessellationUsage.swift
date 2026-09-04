import CADCore

/// The cumulative resources one tessellation invocation, or one artifact it
/// produced, accounts for.
///
/// The dimensions match `TessellationResource`, so a recorded usage can be
/// compared against any `TessellationLimits` without knowing which geometry
/// produced it. This type owns the byte model: `CADKernel` charges an in-flight
/// invocation with the same constants, so a recorded usage and a charged budget
/// are admitted or refused by the same ceilings.
public struct TessellationUsage: Codable, Hashable, Sendable {
    /// The bytes one emitted vertex accounts for: its position and its normal.
    public static let bytesPerVertex =
        MemoryLayout<Point3D>.stride + MemoryLayout<Vector3D>.stride

    /// The bytes one emitted index accounts for.
    public static let bytesPerIndex = MemoryLayout<UInt32>.stride

    public var vertexCount: Int
    public var indexCount: Int
    public var triangleCount: Int
    public var byteCount: Int

    public init(
        vertexCount: Int,
        indexCount: Int,
        triangleCount: Int,
        byteCount: Int
    ) {
        self.vertexCount = vertexCount
        self.indexCount = indexCount
        self.triangleCount = triangleCount
        self.byteCount = byteCount
    }

    public static let zero = TessellationUsage(
        vertexCount: 0,
        indexCount: 0,
        triangleCount: 0,
        byteCount: 0
    )

    /// The usage a materialized mesh accounts for.
    ///
    /// A mesh that already exists occupies the memory this counts, so the byte
    /// product cannot overflow for a mesh this process holds. The arithmetic is
    /// still checked, because the value is also decoded from a cache this
    /// process did not produce.
    public init(mesh: Mesh) throws {
        let vertexCount = mesh.positions.count
        let indexCount = mesh.indices.count
        let vertexBytes = try Self.product(vertexCount, Self.bytesPerVertex)
        let indexBytes = try Self.product(indexCount, Self.bytesPerIndex)
        self.init(
            vertexCount: vertexCount,
            indexCount: indexCount,
            triangleCount: indexCount / 3,
            byteCount: try Self.sum(vertexBytes, indexBytes)
        )
    }

    /// The amount recorded for one resource dimension.
    public func amount(for resource: TessellationResource) -> Int {
        switch resource {
        case .vertexCount: vertexCount
        case .indexCount: indexCount
        case .triangleCount: triangleCount
        case .byteCount: byteCount
        }
    }

    /// Rejects a usage that no invocation could have produced.
    public func validate() throws {
        for resource in TessellationResource.allCases {
            let value = amount(for: resource)
            guard value >= 0 else {
                throw TessellationError.invalidUsage(resource, recorded: value)
            }
        }
    }

    /// The first dimension `limits` does not admit, in declaration order, or
    /// `nil` when every dimension is admitted.
    public func firstResourceExceeding(
        _ limits: TessellationLimits
    ) -> TessellationResource? {
        TessellationResource.allCases.first { resource in
            amount(for: resource) > limits.limit(for: resource)
        }
    }

    private static func product(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw TessellationError.resourceExhausted(
                .byteCount,
                requested: Int.max,
                limit: TessellationLimits.hardCeiling.maximumByteCount
            )
        }
        return result.partialValue
    }

    private static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw TessellationError.resourceExhausted(
                .byteCount,
                requested: Int.max,
                limit: TessellationLimits.hardCeiling.maximumByteCount
            )
        }
        return result.partialValue
    }
}
