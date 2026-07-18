import CADCore

protocol PlanarDraftConstraintSolving: Sendable {
    func displacements(
        for constraints: [VertexID: [PlanarDraftConstraint]],
        neutralNormal: Vector3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [VertexID: Vector3D]
}
