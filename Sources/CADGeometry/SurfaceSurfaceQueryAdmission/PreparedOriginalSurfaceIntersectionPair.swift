import CADCore

/// Immutable original preparation and caller allowance for a domain-pair session.
public struct PreparedOriginalSurfaceIntersectionPair: OriginalSurfacePairIntersecting {
    private let first: PreparedSurfaceDifferentialEncloser
    private let second: PreparedSurfaceDifferentialEncloser
    private let coincidentCone: OriginalCoincidentConeRelation?
    private let commonApexCone: OriginalCommonApexConeRelation?
    private let apexSphereCone: OriginalApexSphereConeSurfaceRelation?
    private let fullConeCone: OriginalFullConeConeSurfaceRelation?
    private let fullSphereCone: OriginalFullSphereConeSurfaceRelation?
    private let boundedSphereCone: OriginalBoundedSphereConeSurfaceRelation?
    private let coaxial: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>?
    private let admission: SurfaceSurfaceQueryAdmission
    public let tolerance: ModelingTolerance
    public var firstSurface: Surface3D { first.surface }
    public var secondSurface: Surface3D { second.surface }

    package init(first: Surface3D, second: Surface3D, tolerance: ModelingTolerance,
        admission: SurfaceSurfaceQueryAdmission) throws {
        try tolerance.validate(); try admission.step()
        self.first = try admission.prepare(first, tolerance: tolerance)
        self.second = try admission.prepare(second, tolerance: tolerance)
        self.coincidentCone = try OriginalCoincidentConePublicProducer().prepare(first:first,second:second,options:.init(),tolerance:tolerance,admission:admission)
        self.commonApexCone = try OriginalCommonApexConePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.fullConeCone = try OriginalFullConeConeSurfacePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.coaxial = try OriginalCoaxialSurfacePublicProducer().prepare(first: first, second: second, options: .init(), tolerance: tolerance, admission: admission)
        self.tolerance = tolerance
        self.admission = admission
    }

    package init(selfSurface surface: Surface3D, tolerance: ModelingTolerance,
        admission: SurfaceSurfaceQueryAdmission) throws {
        try tolerance.validate(); try admission.step()
        let prepared = try admission.prepare(surface, tolerance: tolerance)
        self.first = prepared
        self.second = prepared
        self.coincidentCone = nil
        self.commonApexCone = nil
        self.apexSphereCone = nil
        self.fullConeCone = nil
        self.fullSphereCone = nil
        self.boundedSphereCone = nil
        self.coaxial = nil
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
        if let coincidentCone, let result = try OriginalCoincidentConePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: coincidentCone) {
            return result.intersections
        }
        if let commonApexCone, let result = try OriginalCommonApexConePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: commonApexCone) {
            return result.intersections
        }
        if let apexSphereCone, let result = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: apexSphereCone) {
            return result.intersections
        }
        if let fullConeCone, let result = try OriginalFullConeConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: fullConeCone) {
            return result.intersections
        }
        if let fullSphereCone, let result = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: fullSphereCone) {
            return result.intersections
        }
        if let boundedSphereCone, let result = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: boundedSphereCone) {
            return result.intersections
        }
        if let coaxial, let result = try OriginalCoaxialSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission, retained: coaxial) {
            return result.intersections
        }
        if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: firstSurface,second: secondSurface,
            firstBox: firstBox,secondBox: secondBox,options: options,tolerance: tolerance,admission: admission) {
            return exact.intersections
        }
        if let native = try NativeSurfaceSurfacePointProducer().resolve(first: firstSurface,second: secondSurface,
            firstBox: firstBox,secondBox: secondBox,options: options,tolerance: tolerance,admission: admission) {
            return native.intersections
        }
        if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, admission: admission) {
            return native.intersections
        }
        let intersections = try BoundedParametricSurfaceIntersector().intersections(first: first,over: firstBox,
            second: second,over: secondBox,options: options,tolerance: tolerance,admission: admission)
        try CurrentTaskCancellationChecker().checkCancellation()
        return intersections
    }

    public func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult {
        if let coincidentCone, let result = try OriginalCoincidentConePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: coincidentCone) {
            return result
        }
        if let commonApexCone, let result = try OriginalCommonApexConePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: commonApexCone) {
            return result
        }
        if let apexSphereCone, let result = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: apexSphereCone) {
            return result
        }
        if let fullConeCone, let result = try OriginalFullConeConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: fullConeCone) {
            return result
        }
        if let fullSphereCone, let result = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: fullSphereCone) {
            return result
        }
        if let boundedSphereCone, let result = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: boundedSphereCone) {
            return result
        }
        if let coaxial, let result = try OriginalCoaxialSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission, retained: coaxial) {
            return result
        }
        if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission) {
            return exact
        }
        if let native = try NativeSurfaceSurfacePointProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance, includeRelations: true, admission: admission) {
            return native
        }
        if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: firstSurface, second: secondSurface,
            firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
            includeRelations: true, admission: admission) {
            return native
        }
        let intersections = try BoundedParametricSurfaceIntersector().intersections(first: first, over: firstBox,
            second: second, over: secondBox, options: options,
            tolerance: tolerance, admission: admission)
        try admission.reserve(count: 1, stride: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(intersections: intersections)
    }
}
