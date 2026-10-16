import CADCore

/// An isolated original scalar zero with exact station and whole-cell definiteness proof.
public struct SurfaceSilhouetteContact: Sendable {
    public let surface: Surface3D
    public let view: Vector3D
    public let parameters: SurfaceParameter
    public let certifiedDomain: SurfaceParameterBox
    public let spatialEnclosure: CoordinateEnclosure3D
    public let tolerance: ModelingTolerance
    private let field: OriginalSurfaceSilhouetteField

    init(field: OriginalSurfaceSilhouetteField, station: SurfaceParameter,
         certifiedDomain: SurfaceParameterBox, usage: inout OriginalQueryExecution) throws {
        self.field = field
        surface = field.surface; view = field.view; parameters = station
        self.certifiedDomain = certifiedDomain; tolerance = field.tolerance
        let point = try field.evaluate(over: SurfaceParameterBox(
            u: ScalarInterval(lower: station.u, upper: station.u),
            v: ScalarInterval(lower: station.v, upper: station.v)), usage: &usage).spatial
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original isolated silhouette point is nonfinite.") }
            return try ScalarInterval(lower: value.lower, upper: value.upper)
        }
        spatialEnclosure = try CoordinateEnclosure3D(x: interval(point.x.value),
            y: interval(point.y.value), z: interval(point.z.value))
    }
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        using execution: inout OriginalQueryExecution) throws {
        try field.queryContext.withExecution(using: &execution) { execution in
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try writeOriginalProvenance(to: &emitter, usage: &execution)
    
        }
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout OriginalQueryExecution) throws {
        try emitter.emit(.beginRecord(type: "original-silhouette-contact-v1"), usage: &usage)
        try emitter.field("field", usage: &usage); try field.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("parameters", usage: &usage); try emitter.write(parameters, usage: &usage)
        try emitter.field("certifiedDomain", usage: &usage); try emitter.write(certifiedDomain, usage: &usage)
        try emitter.field("spatialEnclosure", usage: &usage); try emitter.write(spatialEnclosure, usage: &usage)
        try emitter.emit(.endRecord, usage: &usage)
    }

}
