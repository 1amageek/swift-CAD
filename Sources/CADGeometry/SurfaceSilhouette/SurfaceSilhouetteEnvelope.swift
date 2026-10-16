import CADCore

/// A complete closed-domain cover issued only after every rectangle is decided.
public struct SurfaceSilhouetteEnvelope: Sendable {
    private let queryContext: SurfaceSilhouetteQueryContext
    public let surface: Surface3D
    public let domain: SurfaceParameterBox
    public let view: Vector3D
    public let curves: [OriginalSurfaceSilhouetteCurve]
    public let algebraicContacts: [SurfaceSilhouetteAlgebraicContact]
    public let contacts: [SurfaceSilhouetteContact]
    public let singularStations: [SurfaceSilhouetteSingularStation]
    public let originalPlaneAtlases: [SurfaceSilhouettePlaneAtlas]
    public let components: [SurfaceSilhouetteComponent]
    public let excludedDomains: [SurfaceParameterBox]
    /// Entire original source domains whose normal projection is identically zero.
    public let coincidentDomains: [SurfaceParameterBox]

    init(surface: Surface3D, domain: SurfaceParameterBox, view: Vector3D,
         curves: [OriginalSurfaceSilhouetteCurve], excludedDomains: [SurfaceParameterBox],
         coincidentDomains: [SurfaceParameterBox] = [], components: [SurfaceSilhouetteComponent] = [], contacts: [SurfaceSilhouetteContact] = [], algebraicContacts: [SurfaceSilhouetteAlgebraicContact] = [], singularStations: [SurfaceSilhouetteSingularStation] = [], originalPlaneAtlases: [SurfaceSilhouettePlaneAtlas] = [], using execution: inout OriginalQueryExecution) throws {
        queryContext = try .init(retaining: &execution)
        self.surface = surface; self.domain = domain; self.view = view
        self.components = components; self.singularStations = singularStations
        self.originalPlaneAtlases = originalPlaneAtlases
        self.contacts = contacts
        self.algebraicContacts = algebraicContacts
        self.curves = curves; self.excludedDomains = excludedDomains
        self.coincidentDomains = coincidentDomains
    }
    /// Visits every source entity; an envelope without curves can still contain point or whole-zero loci.
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        using execution: inout OriginalQueryExecution) throws {
        try queryContext.withExecution(using: &execution) { execution in
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.emit(.beginRecord(type: "original-silhouette-envelope-v1"), usage: &execution)
        try emitter.field("surface", usage: &execution); try emitter.write(surface, usage: &execution)
        try emitter.field("domain", usage: &execution); try emitter.write(domain, usage: &execution)
        try emitter.field("view", usage: &execution); try emitter.write(view, usage: &execution)
        try emitter.field("curves", usage: &execution); try emitter.emit(.beginArray(count: curves.count), usage: &execution)
        for curve in curves { try curve.writeOriginalProvenance(to: &emitter, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("contacts", usage: &execution); try emitter.emit(.beginArray(count: contacts.count), usage: &execution)
        for contact in contacts { try contact.writeOriginalProvenance(to: &emitter, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("algebraicContacts", usage: &execution); try emitter.emit(.beginArray(count: algebraicContacts.count), usage: &execution)
        for contact in algebraicContacts { try contact.writeOriginalProvenance(to: &emitter, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("singularStations", usage: &execution); try emitter.emit(.beginArray(count: singularStations.count), usage: &execution)
        for station in singularStations { try emitter.write(station, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("originalPlaneAtlases", usage: &execution); try emitter.emit(.beginArray(count: originalPlaneAtlases.count), usage: &execution)
        for atlas in originalPlaneAtlases { try emitter.write(atlas, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("components", usage: &execution); try emitter.emit(.beginArray(count: components.count), usage: &execution)
        for component in components { try emitter.write(component, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("excludedDomains", usage: &execution); try emitter.emit(.beginArray(count: excludedDomains.count), usage: &execution)
        for domain in excludedDomains { try emitter.write(domain, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution)
        try emitter.field("coincidentDomains", usage: &execution); try emitter.emit(.beginArray(count: coincidentDomains.count), usage: &execution)
        for domain in coincidentDomains { try emitter.write(domain, usage: &execution) }
        try emitter.emit(.endArray, usage: &execution); try emitter.emit(.endRecord, usage: &execution)
    
        }
    }

}
