import CADCore

/// Immutable original preparation and caller allowance for a domain-pair session.
public struct PreparedOriginalSurfaceIntersectionPair: OriginalSurfacePairIntersecting {
    private let first: PreparedSurfaceDifferentialEncloser
    private let second: PreparedSurfaceDifferentialEncloser
    private let admission: SurfaceSurfaceQueryAdmission
    public let tolerance: ModelingTolerance
    public var firstSurface: Surface3D { first.surface }
    public var secondSurface: Surface3D { second.surface }

    package init(first: Surface3D, second: Surface3D, tolerance: ModelingTolerance,
        admission: SurfaceSurfaceQueryAdmission) throws {
        try tolerance.validate(); try admission.step()
        self.first = try admission.prepare(first, tolerance: tolerance)
        self.second = try admission.prepare(second, tolerance: tolerance)
        self.tolerance = tolerance
        self.admission = admission
    }

    package init(selfSurface surface: Surface3D, tolerance: ModelingTolerance,
        admission: SurfaceSurfaceQueryAdmission) throws {
        try tolerance.validate(); try admission.step()
        let prepared = try admission.prepare(surface, tolerance: tolerance)
        self.first = prepared
        self.second = prepared
        self.tolerance = tolerance
        self.admission = admission
    }

    public func admitsFirstOrderContinuity(over box: SurfaceParameterBox) throws -> Bool {
        var usage = admission.algebraAdmission()
        return try first.admittingContinuousFirstOrder(over: box, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth, usage: &usage) != nil
    }

    public func firstDifferentialEnclosure(over box: SurfaceParameterBox) throws -> SurfaceDifferentialEnclosure {
        try admission.step()
        return try DefaultSurfaceDifferentialEncloser().publicEnclosure(
            admission.intervalJet(first, over: box, tolerance: tolerance), tolerance: tolerance)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The actual session uses the regular
    // original parametric SSI search and retained domain-pair publication.
    // Critical/coincident strata need their complete same-ledger producer before
    // the session represents the entire required self-contact domain.
    public func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> [SurfaceSurfaceIntersection] {
        try BoundedParametricSurfaceIntersector().intersections(first: first, over: firstBox,
            second: second, over: secondBox, options: options,
            tolerance: tolerance, admission: admission)
    }
}
