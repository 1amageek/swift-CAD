import CADCore
import CADIR

/// Charges one tessellation invocation against its ``TessellationLimits``.
///
/// The budget is cumulative across the whole invocation rather than per body or
/// per face, so a model made of many admissible bodies cannot exceed the limits
/// by growing one body at a time. Every charge is checked before the counters
/// move, so a rejected charge leaves the budget unchanged.
struct TessellationBudget {
    /// Estimated storage for one emitted vertex: its position and its normal.
    ///
    /// `TessellationUsage` owns the byte model, so a charged budget and a
    /// recorded usage are admitted or refused by the same ceilings.
    static let bytesPerVertex = TessellationUsage.bytesPerVertex
    /// Estimated storage for one emitted triangle index.
    static let bytesPerIndex = TessellationUsage.bytesPerIndex

    private let limits: TessellationLimits
    private(set) var vertexCount = 0
    private(set) var indexCount = 0
    private(set) var triangleCount = 0
    private(set) var byteCount = 0
    /// The part of `vertexCount` the normal-consistency fallback duplicated to
    /// give a triangle its own flat-shaded corners. It is charged against the
    /// limits like any other vertex, but it is not part of the geometric
    /// emission the preflight estimates.
    private(set) var duplicatedVertexCount = 0

    /// - Throws: `TessellationError.invalidLimit` when the limits are not
    ///   positive representable values at or below the package hard ceiling.
    init(limits: TessellationLimits) throws {
        try limits.validate()
        self.limits = limits
    }

    /// The estimated storage a vertex and index count occupies.
    static func estimatedByteCount(vertices: Int, indices: Int) -> Int? {
        guard let vertexBytes = multipliedWithoutOverflow(vertices, bytesPerVertex),
              let indexBytes = multipliedWithoutOverflow(indices, bytesPerIndex) else {
            return nil
        }
        return addingWithoutOverflow(vertexBytes, indexBytes)
    }

    /// Charges emitted or estimated usage against the limits.
    ///
    /// - Throws: `TessellationError.resourceExhausted` naming the first
    ///   dimension the invocation would exceed. Arithmetic that would overflow
    ///   `Int` is reported as exhaustion of that dimension rather than trapping.
    mutating func charge(vertices: Int, indices: Int, duplicatedVertices: Int = 0) throws {
        precondition(vertices >= 0 && indices >= 0, "A tessellation charge is never negative.")
        precondition(
            duplicatedVertices >= 0 && duplicatedVertices <= vertices,
            "Duplicated vertices are a part of the charged vertices."
        )
        let nextVertexCount = try sum(
            vertexCount,
            vertices,
            as: .vertexCount,
            limit: limits.maximumVertexCount
        )
        let nextIndexCount = try sum(
            indexCount,
            indices,
            as: .indexCount,
            limit: limits.maximumIndexCount
        )
        let nextTriangleCount = try sum(
            triangleCount,
            indices / 3,
            as: .triangleCount,
            limit: limits.maximumTriangleCount
        )
        guard let bytes = Self.estimatedByteCount(vertices: vertices, indices: indices) else {
            throw TessellationError.resourceExhausted(
                .byteCount,
                requested: Int.max,
                limit: limits.maximumByteCount
            )
        }
        let nextByteCount = try sum(
            byteCount,
            bytes,
            as: .byteCount,
            limit: limits.maximumByteCount
        )
        vertexCount = nextVertexCount
        indexCount = nextIndexCount
        triangleCount = nextTriangleCount
        byteCount = nextByteCount
        duplicatedVertexCount += duplicatedVertices
    }

    /// Rejects an invocation whose actual emission outgrew the estimate that was
    /// admitted for it, so a preflight that is not conservative fails loudly
    /// instead of silently allocating past the admitted amount.
    ///
    /// The preflight estimates the geometric emission, so the vertices the
    /// normal-consistency fallback duplicates to flat-shade a triangle are
    /// excluded from the comparison. Those duplicates are still charged against
    /// the limits by `charge`, so they cannot grow the arrays without bound.
    func validateEmission(against admitted: TessellationBudget) throws {
        let geometricVertexCount = vertexCount - duplicatedVertexCount
        if geometricVertexCount > admitted.vertexCount {
            throw TessellationError.resourceExhausted(
                .vertexCount,
                requested: geometricVertexCount,
                limit: admitted.vertexCount
            )
        }
        if indexCount > admitted.indexCount {
            throw TessellationError.resourceExhausted(
                .indexCount,
                requested: indexCount,
                limit: admitted.indexCount
            )
        }
        if triangleCount > admitted.triangleCount {
            throw TessellationError.resourceExhausted(
                .triangleCount,
                requested: triangleCount,
                limit: admitted.triangleCount
            )
        }
        let geometricByteCount = Self.estimatedByteCount(
            vertices: geometricVertexCount,
            indices: indexCount
        ) ?? Int.max
        if geometricByteCount > admitted.byteCount {
            throw TessellationError.resourceExhausted(
                .byteCount,
                requested: geometricByteCount,
                limit: admitted.byteCount
            )
        }
    }

    private func sum(
        _ current: Int,
        _ increment: Int,
        as resource: TessellationResource,
        limit: Int
    ) throws -> Int {
        guard let total = addingWithoutOverflow(current, increment), total <= limit else {
            throw TessellationError.resourceExhausted(
                resource,
                requested: addingWithoutOverflow(current, increment) ?? Int.max,
                limit: limit
            )
        }
        return total
    }
}

/// The sum, or nil when it does not fit in `Int`.
private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int? {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? nil : result.partialValue
}

/// The product, or nil when it does not fit in `Int`.
private func multipliedWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int? {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? nil : result.partialValue
}
