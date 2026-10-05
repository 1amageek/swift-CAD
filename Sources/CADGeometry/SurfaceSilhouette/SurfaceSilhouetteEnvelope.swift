/// A complete closed-domain cover issued only after every rectangle is decided.
public struct SurfaceSilhouetteEnvelope: Sendable {
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
         coincidentDomains: [SurfaceParameterBox] = [], components: [SurfaceSilhouetteComponent] = [], contacts: [SurfaceSilhouetteContact] = [], algebraicContacts: [SurfaceSilhouetteAlgebraicContact] = [], singularStations: [SurfaceSilhouetteSingularStation] = [], originalPlaneAtlases: [SurfaceSilhouettePlaneAtlas] = []) {
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
        usage: inout SurfaceSilhouetteUsage) throws {
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.emit(.beginRecord(type: "original-silhouette-envelope-v1"), usage: &usage)
        try emitter.field("surface", usage: &usage); try emitter.write(surface, usage: &usage)
        try emitter.field("domain", usage: &usage); try emitter.write(domain, usage: &usage)
        try emitter.field("view", usage: &usage); try emitter.write(view, usage: &usage)
        try emitter.field("curves", usage: &usage); try emitter.emit(.beginArray(count: curves.count), usage: &usage)
        for curve in curves { try curve.writeOriginalProvenance(to: &emitter, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("contacts", usage: &usage); try emitter.emit(.beginArray(count: contacts.count), usage: &usage)
        for contact in contacts { try contact.writeOriginalProvenance(to: &emitter, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("algebraicContacts", usage: &usage); try emitter.emit(.beginArray(count: algebraicContacts.count), usage: &usage)
        for contact in algebraicContacts { try contact.writeOriginalProvenance(to: &emitter, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("singularStations", usage: &usage); try emitter.emit(.beginArray(count: singularStations.count), usage: &usage)
        for station in singularStations { try emitter.write(station, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("originalPlaneAtlases", usage: &usage); try emitter.emit(.beginArray(count: originalPlaneAtlases.count), usage: &usage)
        for atlas in originalPlaneAtlases { try emitter.write(atlas, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("components", usage: &usage); try emitter.emit(.beginArray(count: components.count), usage: &usage)
        for component in components { try emitter.write(component, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("excludedDomains", usage: &usage); try emitter.emit(.beginArray(count: excludedDomains.count), usage: &usage)
        for domain in excludedDomains { try emitter.write(domain, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("coincidentDomains", usage: &usage); try emitter.emit(.beginArray(count: coincidentDomains.count), usage: &usage)
        for domain in coincidentDomains { try emitter.write(domain, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage); try emitter.emit(.endRecord, usage: &usage)
    }

}
