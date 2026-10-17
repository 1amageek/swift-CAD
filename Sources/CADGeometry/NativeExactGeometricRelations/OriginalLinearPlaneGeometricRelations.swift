import CADCore

/// Retains every original T/UV component and its exact XYZ image/fibres.
final class OriginalLinearPlaneGeometricRelations: OriginalIssuedGeometricRelationReading {
    let original: OriginalLinearPlaneRelations
    let pairs: [OriginalIssuedGeometricRelationPair]
    let exactPoints: [OriginalIssuedExactIntersectionPoint]
    var kind: ExactParametricRelationKind { .curveSurface }
    var hasPositiveDimensionalSolutions: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalSolutions } }
    var hasPositiveDimensionalImage: Bool { pairs.contains { $0.geometry.hasPositiveDimensionalImage } }
    var isEmpty: Bool { pairs.allSatisfy { $0.geometry.isEmpty } }
    private let preparation: OriginalGeometryPreparationReceipt

    static func prepare(original: OriginalLinearPlaneRelations, pairs: [OriginalIssuedGeometricRelationPair],
        exactPoints: [OriginalIssuedExactIntersectionPoint], depth: OriginalQueryPreparationDepth,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> OriginalLinearPlaneGeometricRelations {
        try a.retainStorage(bytes: MemoryLayout<OriginalLinearPlaneRelations>.stride
            + MemoryLayout<[OriginalIssuedGeometricRelationPair]>.stride
            + MemoryLayout<[OriginalIssuedExactIntersectionPoint]>.stride
            + MemoryLayout<OriginalGeometryPreparationReceipt>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let preparation = try OriginalGeometryPreparationReceipt(tolerance: tolerance, depth: depth, using: &a)
        return .init(original: original, pairs: pairs, exactPoints: exactPoints, preparation: preparation)
    }

    private init(original: OriginalLinearPlaneRelations, pairs: [OriginalIssuedGeometricRelationPair],
        exactPoints: [OriginalIssuedExactIntersectionPoint], preparation: OriginalGeometryPreparationReceipt) {
        self.original = original; self.pairs = pairs; self.exactPoints = exactPoints; self.preparation = preparation
    }

    func admitProof(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws {
        try a.checkpoint()
        try a.admitSourceDepth(preparation.depth.sourceDepth)
        try a.admitDepth(value: preparation.depth.scalar.value, coefficient: preparation.depth.scalar.coefficient)
        try a.admitGeometricDepth(preparation.depth.geometricDepth)
        try a.admitTransportDepth(preparation.depth.transportDepth)
        try preparation.withContributionScopes(using: &a) { a in
            try preparation.admit(tolerance: preparation.tolerance, using: &a)
            try original.admitProof(limits: limits, using: &a)
            for pair in pairs {
                try a.consumeWork(1)
                try a.admitDepth(value: pair.geometry.depth.value, coefficient: pair.geometry.depth.coefficient)
            }
            try a.checkpoint()
        }
    }
}
