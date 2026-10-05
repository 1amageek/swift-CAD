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

    func intersections(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,maximumSubdivisionDepth:Int,
        consumeWork:@escaping @Sendable (Int)throws->Void) throws -> [CurveSurfaceIntersection]

    func intersections(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int?) throws -> [CurveSurfaceIntersection]

}

public extension CurveSurfaceIntersecting {
    func intersections(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,maximumSubdivisionDepth:Int,
        consumeWork:@escaping @Sendable (Int)throws->Void) throws -> [CurveSurfaceIntersection] {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy custom curve-surface producers
        // do not expose original inner traversal admission. Bounded classifiers
        // require an actual conformer implementation before their results may be
        // used as complete same-invocation crossing evidence.
        throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:tolerance,
            message:"This curve-surface producer does not forward invocation admission.")
    }
    func intersections(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> [CurveSurfaceIntersection] {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected legacy producers do not
        // retain independent original source/algebra and optional byte admission.
        // Selected ray/contact callers require a real witness implementation
        // before this path can publish complete original crossing evidence.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve-surface producer does not implement selected original admission.")
    }

}
