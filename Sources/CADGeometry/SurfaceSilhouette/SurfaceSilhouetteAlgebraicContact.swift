import CADCore

/// An original isolated zero retaining both algebraic parameter authorities.
public struct SurfaceSilhouetteAlgebraicContact: Sendable {
    public let surface: Surface3D
    public let view: Vector3D
    public let certifiedDomain: SurfaceParameterBox
    public let parameterEnclosure: SurfaceParameterBox
    public let spatialEnclosure: CoordinateEnclosure3D
    public let tolerance: ModelingTolerance
    private enum RootAuthority: Sendable {
        case critical(ExactBivariateCriticalPoint)
        case boundary(ExactBivariateSystemRoot)
        case polynomial(ExactPolynomialParameterPoint)
        case field(OriginalSingularFieldSystemRoot)
    }
    private let originalRoot: RootAuthority
    private let field: OriginalSurfaceSilhouetteField

    init(field: OriginalSurfaceSilhouetteField, originalRoot: ExactBivariateCriticalPoint,
         certifiedDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        self.originalRoot = .critical(originalRoot); self.field = field; surface = field.surface; view = field.view
        self.certifiedDomain = certifiedDomain; tolerance = field.tolerance
        parameterEnclosure = try originalRoot.enclosure(usage: &usage)
        guard parameterEnclosure.u.lower >= certifiedDomain.u.lower,
              parameterEnclosure.u.upper <= certifiedDomain.u.upper,
              parameterEnclosure.v.lower >= certifiedDomain.v.lower,
              parameterEnclosure.v.upper <= certifiedDomain.v.upper else {
            throw rationalAlgebraFailure("Original algebraic contact does not belong to its certified whole cell.")
        }
        let position = try field.evaluate(over: parameterEnclosure, usage: &usage).spatial
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original algebraic contact spatial bound is nonfinite.") }
            return try ScalarInterval(lower: value.lower, upper: value.upper)
        }
        spatialEnclosure = try CoordinateEnclosure3D(x: interval(position.x.value),
            y: interval(position.y.value), z: interval(position.z.value))
    }

    init(field: OriginalSurfaceSilhouetteField, originalRoot: ExactBivariateSystemRoot,
        certifiedDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        self.originalRoot = .boundary(originalRoot); self.field = field; surface = field.surface; view = field.view
        self.certifiedDomain = certifiedDomain; tolerance = field.tolerance
        parameterEnclosure = try originalRoot.enclosure(usage: &usage)
        guard parameterEnclosure.u.lower >= certifiedDomain.u.lower,
              parameterEnclosure.u.upper <= certifiedDomain.u.upper,
              parameterEnclosure.v.lower >= certifiedDomain.v.lower,
              parameterEnclosure.v.upper <= certifiedDomain.v.upper else {
            throw rationalAlgebraFailure("Original isolated boundary contact exceeds its certified source rectangle.")
        }
        let position = try field.evaluate(over: parameterEnclosure, usage: &usage).spatial
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original boundary contact spatial bound is nonfinite.") }
            return try ScalarInterval(lower: value.lower, upper: value.upper)
        }
        spatialEnclosure = try CoordinateEnclosure3D(x: interval(position.x.value),
            y: interval(position.y.value), z: interval(position.z.value))
    }

    init(field: OriginalSurfaceSilhouetteField, originalRoot: ExactPolynomialParameterPoint,
        certifiedDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        self.originalRoot = .polynomial(originalRoot); self.field = field
        surface = field.surface; view = field.view; self.certifiedDomain = certifiedDomain; tolerance = field.tolerance
        parameterEnclosure = try originalRoot.enclosure(usage: &usage)
        let position = try field.evaluate(over: parameterEnclosure, usage: &usage).spatial
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original polynomial contact spatial bound is nonfinite.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        spatialEnclosure = try .init(x: interval(position.x.value), y: interval(position.y.value), z: interval(position.z.value))
    }

    init(field: OriginalSurfaceSilhouetteField, originalRoot: OriginalSingularFieldSystemRoot,
        certifiedDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        self.originalRoot = .field(originalRoot); self.field = field
        surface = field.surface; view = field.view; self.certifiedDomain = certifiedDomain; tolerance = field.tolerance
        parameterEnclosure = try originalRoot.enclosure(usage: &usage)
        guard parameterEnclosure.u.lower >= certifiedDomain.u.lower,
            parameterEnclosure.u.upper <= certifiedDomain.u.upper,
            parameterEnclosure.v.lower >= certifiedDomain.v.lower,
            parameterEnclosure.v.upper <= certifiedDomain.v.upper else {
            throw rationalAlgebraFailure("Original field contact exceeds its complete source rectangle.")
        }
        let spatial = try field.evaluate(over: parameterEnclosure, usage: &usage).spatial
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original field contact spatial enclosure is nonfinite.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        spatialEnclosure = try .init(x: interval(spatial.x.value), y: interval(spatial.y.value), z: interval(spatial.z.value))
    }

    /// Refines the retained original pair under the same cumulative caller ledger.
    public func refined(maximumUWidth: Double, maximumVWidth: Double,
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        guard maximumUWidth.isFinite, maximumVWidth.isFinite,
              maximumUWidth > 0, maximumVWidth > 0 else {
            throw rationalAlgebraFailure("Original silhouette contact refinement needs finite positive native widths.")
        }
        switch originalRoot {
        case .field(let root):
            return try Self(field: field, originalRoot: root.refined(
                maximumUWidth: .originalDouble(maximumUWidth, usage: &usage),
                maximumVWidth: .originalDouble(maximumVWidth, usage: &usage),
                maximumDepth: usage.maximumDepth, usage: &usage), certifiedDomain: certifiedDomain, usage: &usage)
        case .polynomial(let root):
            return try Self(field: field, originalRoot: root.refined(maximumUWidth: maximumUWidth,
                maximumVWidth: maximumVWidth, maximumDepth: usage.maximumDepth, usage: &usage),
                certifiedDomain: certifiedDomain, usage: &usage)
        case .critical(let root):
            return try Self(field: field, originalRoot: root.refined(maximumUWidth: maximumUWidth,
                maximumVWidth: maximumVWidth, maximumDepth: usage.maximumDepth, usage: &usage),
                certifiedDomain: certifiedDomain, usage: &usage)
        case .boundary(let root):
            return try Self(field: field, originalRoot: root.refined(
                maximumUWidth: .originalDouble(maximumUWidth, usage: &usage),
                maximumVWidth: .originalDouble(maximumVWidth, usage: &usage),
                maximumDepth: usage.maximumDepth, usage: &usage),
                certifiedDomain: certifiedDomain, usage: &usage)
        }
    }

    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        usage: inout SurfaceSilhouetteUsage) throws {
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try writeOriginalProvenance(to: &emitter, usage: &usage)
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout SurfaceSilhouetteUsage) throws {
        try emitter.emit(.beginRecord(type: "original-silhouette-algebraic-contact-v1"), usage: &usage)
        try emitter.field("field", usage: &usage); try field.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("certifiedDomain", usage: &usage); try emitter.write(certifiedDomain, usage: &usage)
        try emitter.field("originalRoot", usage: &usage)
        switch originalRoot {
        case .critical(let root): try emitter.write(root, usage: &usage)
        case .boundary(let root): try emitter.write(root, usage: &usage)
        case .polynomial(let root): try emitter.write(root, usage: &usage)
        case .field(let root): try emitter.write(root, usage: &usage)
        }
        try emitter.field("parameterEnclosure", usage: &usage); try emitter.write(parameterEnclosure, usage: &usage)
        try emitter.field("spatialEnclosure", usage: &usage); try emitter.write(spatialEnclosure, usage: &usage)
        try emitter.emit(.endRecord, usage: &usage)
    }

}
