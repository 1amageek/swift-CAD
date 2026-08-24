import CADCore

/// Produces the complete discrete event set in the requested curve and
/// surface ranges. Implementations must throw a typed error when completeness
/// cannot be certified and must report a continuous overlap as
/// `KernelError.Code.nonDiscreteIntersection`; an empty array therefore
/// certifies that no discrete event exists in the requested ranges.
public protocol CurveSurfaceIntersecting: Sendable {
    func intersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]
}
