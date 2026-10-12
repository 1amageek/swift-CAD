/// Retained exact sections avoid re-solving plane coordinates already fixed by its basis.
struct OriginalRollingPlaneGeometricRelations: OriginalIssuedGeometricRelationReading {
    let owner: any Sendable
    let surfacePlaneSections: [OriginalSurfacePlaneSection]
    var kind: ExactParametricRelationKind { .surfaceSurface }
    var pairs: [OriginalIssuedGeometricRelationPair] { [] }
    var exactPoints: [OriginalIssuedExactIntersectionPoint] { [] }
    var isEmpty: Bool { surfacePlaneSections.allSatisfy { $0.selection.cells.isEmpty } }
    var hasPositiveDimensionalSolutions: Bool {
        surfacePlaneSections.contains { $0.selection.cells.contains { $0.dimension > 0 } }
    }
    var hasPositiveDimensionalImage: Bool {
        surfacePlaneSections.contains { !$0.isConstant && $0.selection.cells.contains { $0.dimension > 0 } }
    }
}
