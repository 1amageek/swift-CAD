import CADCore

public protocol SurfaceDifferentialEnclosing: Sendable {
    func enclosure(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceDifferentialEnclosure
}
