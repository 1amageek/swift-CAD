/// Structural fields impose no new ceiling absent from the existing public query.
/// The same original caller still bounds cumulative work, storage, visits and depths;
/// publication separately checks its existing candidate/component/result limits.
enum NativeExactPublicLimits {
    static func unboundedStructure() throws -> ExactGeometricRelationLimits {
        try .init(cells: .init(maximumStoredCells: Int.max, maximumRootsPerStack: Int.max),
            topology: .init(maximumGeneratedCells: Int.max, maximumRootsPerStack: Int.max,
                maximumClosures: Int.max, maximumAttachmentPieces: Int.max,
                maximumComponents: Int.max), maximumStrata: Int.max,
            maximumProjectionSpans: Int.max)
    }
}
