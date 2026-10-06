import CADCore

/// One admitted original support pair reused across selected closed box queries.
public protocol OriginalSurfacePairIntersecting: Sendable {
    var firstSurface: Surface3D { get }
    var secondSurface: Surface3D { get }
    var tolerance: ModelingTolerance { get }
    func admitsFirstOrderContinuity(over box: SurfaceParameterBox) throws -> Bool
    func firstDifferentialEnclosure(over box: SurfaceParameterBox) throws -> SurfaceDifferentialEnclosure
    func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> [SurfaceSurfaceIntersection]
}
