import CADCore

public protocol SurfaceDifferentialEnclosing: Sendable {
    func enclosure(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceDifferentialEnclosure

    func enclosure(of surface: Surface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SurfaceDifferentialEnclosure
}
