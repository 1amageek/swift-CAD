import CADCore

/// The checked resource ceilings admitted for one complete tessellation
/// invocation.
///
/// The ceilings are generic counts and estimated bytes. This value neither
/// estimates CAD geometry nor selects a product policy: a consumer supplies the
/// limits and `CADKernel` charges the invocation against them.
///
/// A caller may lower ``hardCeiling`` but never widen it, so no consumer can
/// raise the package maximum by constructing its own limits.
///
/// The values below are derived from the measured Swift-CAD fixtures recorded
/// in `Sources/CADIR/DESIGN.md`, not from a presentation target.
public struct TessellationLimits: Codable, Hashable, Sendable {
    /// The cumulative number of emitted mesh vertices the invocation may reach.
    public var maximumVertexCount: Int
    /// The cumulative number of emitted triangle indices the invocation may reach.
    public var maximumIndexCount: Int
    /// The cumulative number of emitted triangles the invocation may reach.
    public var maximumTriangleCount: Int
    /// The cumulative estimated mesh storage, in bytes, the invocation may reach.
    public var maximumByteCount: Int

    public init(
        maximumVertexCount: Int,
        maximumIndexCount: Int,
        maximumTriangleCount: Int,
        maximumByteCount: Int
    ) {
        self.maximumVertexCount = maximumVertexCount
        self.maximumIndexCount = maximumIndexCount
        self.maximumTriangleCount = maximumTriangleCount
        self.maximumByteCount = maximumByteCount
    }

    /// The package maximum. No caller may exceed it.
    ///
    /// Derived from the largest measured invocation that completed on the
    /// reference machine (torus R=4 r=1 at an angular tolerance of 3.125e-3:
    /// 4,064,256 vertices, 24,288,864 indices, 8,096,288 triangles, 292.24 MB of
    /// mesh storage, 1.06 GB peak resident size). The measured peak-to-mesh-byte
    /// ratio across fixtures is 3.6x-4.5x, so a 384 MiB byte ceiling bounds peak
    /// growth near 1.7 GB.
    public static let hardCeiling = TessellationLimits(
        maximumVertexCount: 8_388_608,
        maximumIndexCount: 50_331_648,
        maximumTriangleCount: 16_777_216,
        maximumByteCount: 402_653_184
    )

    /// The limits a caller receives when it does not choose its own.
    ///
    /// Derived from the measured realistic fixtures at
    /// `TessellationOptions.standard`; the largest is a twelve-body cylinder
    /// assembly at 301,752 vertices, 904,896 indices, 301,632 triangles and
    /// 18.10 MB of mesh storage, which these limits admit with 7.4x byte
    /// headroom.
    public static let standard = TessellationLimits(
        maximumVertexCount: 2_097_152,
        maximumIndexCount: 12_582_912,
        maximumTriangleCount: 4_194_304,
        maximumByteCount: 134_217_728
    )

    /// The ceiling this value declares for one resource dimension.
    ///
    /// A consumer that reports exhaustion generically needs the matching
    /// ceiling without restating the mapping from dimension to stored property.
    public func limit(for resource: TessellationResource) -> Int {
        switch resource {
        case .vertexCount: maximumVertexCount
        case .indexCount: maximumIndexCount
        case .triangleCount: maximumTriangleCount
        case .byteCount: maximumByteCount
        }
    }

    /// Rejects limits that are not positive, and limits that widen the package
    /// hard ceiling rather than lowering it.
    public func validate() throws {
        try validate(
            maximumVertexCount,
            as: .vertexCount,
            ceiling: Self.hardCeiling.maximumVertexCount
        )
        try validate(
            maximumIndexCount,
            as: .indexCount,
            ceiling: Self.hardCeiling.maximumIndexCount
        )
        try validate(
            maximumTriangleCount,
            as: .triangleCount,
            ceiling: Self.hardCeiling.maximumTriangleCount
        )
        try validate(
            maximumByteCount,
            as: .byteCount,
            ceiling: Self.hardCeiling.maximumByteCount
        )
    }

    private func validate(
        _ value: Int,
        as resource: TessellationResource,
        ceiling: Int
    ) throws {
        guard value > 0, value <= ceiling else {
            throw TessellationError.invalidLimit(resource, requested: value)
        }
    }

    /// The limits that admit no more than both operands admit.
    ///
    /// Lowering is the only composition offered, so combining a caller's limits
    /// with another set can never widen either.
    public func lowered(to other: TessellationLimits) -> TessellationLimits {
        TessellationLimits(
            maximumVertexCount: min(maximumVertexCount, other.maximumVertexCount),
            maximumIndexCount: min(maximumIndexCount, other.maximumIndexCount),
            maximumTriangleCount: min(maximumTriangleCount, other.maximumTriangleCount),
            maximumByteCount: min(maximumByteCount, other.maximumByteCount)
        )
    }
}
