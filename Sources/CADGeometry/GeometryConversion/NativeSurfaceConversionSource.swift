import CADCore

public struct NativeSurfaceConversionSource: GeometrySurfaceConversionSource {
    public let surface: Surface3D
    private enum EnclosureStorage: Sendable {
        case originalPolynomialRuled(OriginalPolynomialRuledConversionSource)
        case originalNative(PreparedSurfaceDifferentialEncloser)
    }
    private let prepared: EnclosureStorage
    private let boundedPreparationTolerance: ModelingTolerance?
    private let boundedPreparationAdmission: GeometryConversionAdmission?

    public init(_ surface: Surface3D, tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        boundedPreparationTolerance = nil
        boundedPreparationAdmission = nil
        if case .procedural(.ruled(let ruled)) = surface,
           OriginalPolynomialRuledConversionSource.accepts(ruled) {
            prepared = .originalPolynomialRuled(try OriginalPolynomialRuledConversionSource(ruled, tolerance: tolerance))
        } else {
            prepared = .originalNative(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }
    public init(_ surface: Surface3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        self.surface = surface; boundedPreparationTolerance = tolerance
        boundedPreparationAdmission = admission
        try surface.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { _ in try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) },
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
        prepared = .originalNative(try PreparedSurfaceDifferentialEncloser(surface: surface,
            tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) }, maximumAlgebraicDepth: admission.maximumAlgebraicDepth))
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        guard let boundedPreparationAdmission,
            boundedPreparationAdmission.belongsToSameInvocation(as: admission),
            boundedPreparationTolerance == tolerance,
            parameters.u.lower.isFinite, parameters.u.upper.isFinite,
            parameters.v.lower.isFinite, parameters.v.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Bounded surface source requires its original paid preparation and finite box.")
        }
        let bytes = 2.multipliedReportingOverflow(by: MemoryLayout<(ScalarInterval, ParameterDomain)>.stride)
        guard !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Bounded surface domain buffer bytes overflow.")
        }
        try admission.chargeStorage(bytes: bytes.partialValue)
        for (range, domain) in [(parameters.u, surface.uDomain), (parameters.v, surface.vDomain)] {
            try admission.chargeWork()
            if case .closed(let lower, let upper) = domain {
                guard range.lower >= lower, range.upper <= upper else {
                    throw GeometryConversionError.invalidInput("Bounded surface query exceeds the original closed support.")
                }
            }
        }
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Point3D {
        let box = SurfaceParameterBox(u: try .init(lower: u, upper: u), v: try .init(lower: v, upper: v))
        try validate(over: box, tolerance: tolerance, admission: admission)
        guard case .originalNative(let original) = prepared else {
            throw GeometryConversionError.invalidInput("Bounded surface proposal has no original preparation.")
        }
        let bounds = try original.positionBounds(over: box, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        let point = Point3D(x: bounds.x.midpoint, y: bounds.y.midpoint, z: bounds.z.midpoint)
        try point.validate()
        return point
    }

    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> SurfaceDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, admission: admission)
        guard case .originalNative(let original) = prepared else {
            throw GeometryConversionError.invalidInput("Bounded surface query has no original preparation.")
        }
        return try original.enclosure(over: parameters, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        guard parameters.u.width.isFinite, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface conversion requires finite parameter extents.")
        }
        try parameters.validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
    }
    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try surface.point(u: u, v: v, tolerance: tolerance)
    }
    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        let result: SurfaceDifferentialEnclosure
        switch prepared {
        case .originalPolynomialRuled(let original): result = try original.enclosure(over: parameters, tolerance: tolerance)
        case .originalNative(let original): result = try original.enclosure(over: parameters, tolerance: tolerance)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}
