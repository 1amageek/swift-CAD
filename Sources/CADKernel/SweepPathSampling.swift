import CADCore

public protocol SweepPathSampling: Sendable {
    func frames(
        for curve: EvaluatedSketchCurve,
        distanceFraction: Double,
        preferredNormal: Vector3D?
    ) throws -> [SweepPathFrame]

    func straightPath(from frames: [SweepPathFrame]) throws -> SweepStraightPath?
}
