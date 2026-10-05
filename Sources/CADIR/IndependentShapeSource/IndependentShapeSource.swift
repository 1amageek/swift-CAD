import CADCore
import CADTopology

/// The complete independent source graph. Arrays use canonical ID/reference order.
public struct IndependentShapeSource: Equatable, Sendable {
    public let geometry: GeometryStore
    public let items: [IndependentShapeItem]
    public let geometricSets: [IndependentShapeGeometricSet]
    public let contexts: [IndependentShapeContext]
    public let ambientContexts: [IndependentShapeContext]
    public let representations: [IndependentShapeRepresentation]
    public let frames: [IndependentShapeFrame]
    public let definitions: [IndependentShapeDefinition]
    public let curveNames: [CurveID: String]
    public let surfaceNames: [SurfaceID: String]
    public let curvePositionFrames: [CurveID: IndependentShapePositionFrame]
    public let surfacePositionFrames: [SurfaceID: IndependentShapePositionFrame]
    public let curveLinearSources: [CurveID: OriginalSTEPLineSource]
    public let curveSplineSources: [CurveID: OriginalSTEPSplineCurveSource]
    public let surfaceSplineSources: [SurfaceID: OriginalSTEPSplineSurfaceSource]
    public let surfaceAngularMeasures: [SurfaceID: IndependentShapeSurfaceAngularMeasure]
    public let originalSTEPGroups: [IndependentShapeSTEPGroup]
    public let groups: [IndependentShapeGroup]
    public let instances: [IndependentShapeInstance]
    public let ambientOriginalLengthSource: OriginalSTEPLengthSource?
    public let ambientOriginalAngularSource: IndependentShapeAngularSource?
    public let productAssociations: [IndependentShapeProductAssociation]
    public let roots: [IndependentShapeReference]
    public init(geometry: GeometryStore, items: [IndependentShapeItem], geometricSets: [IndependentShapeGeometricSet] = [],
                contexts: [IndependentShapeContext] = [], ambientContexts: [IndependentShapeContext] = [], representations: [IndependentShapeRepresentation] = [],
                frames: [IndependentShapeFrame] = [], definitions: [IndependentShapeDefinition] = [], curveNames: [CurveID: String] = [:], surfaceNames: [SurfaceID: String] = [:],
                curvePositionFrames: [CurveID: IndependentShapePositionFrame] = [:], surfacePositionFrames: [SurfaceID: IndependentShapePositionFrame] = [:], surfaceAngularMeasures: [SurfaceID: IndependentShapeSurfaceAngularMeasure] = [:], curveLinearSources: [CurveID: OriginalSTEPLineSource] = [:], curveSplineSources: [CurveID: OriginalSTEPSplineCurveSource] = [:], surfaceSplineSources: [SurfaceID: OriginalSTEPSplineSurfaceSource] = [:],
                groups: [IndependentShapeGroup] = [], originalSTEPGroups: [IndependentShapeSTEPGroup] = [], instances: [IndependentShapeInstance] = [], productAssociations: [IndependentShapeProductAssociation] = [], ambientOriginalAngularSource: IndependentShapeAngularSource? = nil, ambientOriginalLengthSource: OriginalSTEPLengthSource? = nil, roots: [IndependentShapeReference]) {
        self.geometry = geometry; self.items = items; self.geometricSets = geometricSets
        self.contexts = contexts; self.ambientContexts = ambientContexts; self.representations = representations; self.frames = frames; self.definitions = definitions
        self.curveNames = curveNames; self.surfaceNames = surfaceNames
        self.curvePositionFrames = curvePositionFrames; self.surfacePositionFrames = surfacePositionFrames; self.surfaceAngularMeasures = surfaceAngularMeasures; self.curveLinearSources = curveLinearSources; self.curveSplineSources = curveSplineSources; self.surfaceSplineSources = surfaceSplineSources
        self.originalSTEPGroups = originalSTEPGroups; self.groups = groups; self.instances = instances; self.productAssociations = productAssociations; self.ambientOriginalLengthSource = ambientOriginalLengthSource; self.ambientOriginalAngularSource = ambientOriginalAngularSource; self.roots = roots
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case geometry, items, geometricSets, contexts, ambientContexts, representations, frames, definitions, curveNames, surfaceNames, curvePositionFrames, surfacePositionFrames, surfaceAngularMeasures, curveLinearSources, curveSplineSources, surfaceSplineSources, groups, originalSTEPGroups, instances, productAssociations, ambientOriginalAngularSource, ambientOriginalLengthSource, roots }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.geometry, .items, .geometricSets, .contexts, .ambientContexts, .representations, .frames, .definitions, .curveNames, .surfaceNames, .curvePositionFrames, .surfacePositionFrames, .surfaceAngularMeasures, .curveLinearSources, .curveSplineSources, .surfaceSplineSources, .groups, .originalSTEPGroups, .instances, .productAssociations, .ambientOriginalAngularSource, .ambientOriginalLengthSource, .roots], in: decoder)
        geometry = try IndependentShapeMapCoding.decodeGeometry(from: c.superDecoder(forKey: .geometry))
        items = try c.decode([IndependentShapeItem].self, forKey: .items)
        geometricSets = try c.decode([IndependentShapeGeometricSet].self, forKey: .geometricSets)
        contexts = try c.decode([IndependentShapeContext].self, forKey: .contexts)
        ambientContexts = try c.decode([IndependentShapeContext].self, forKey: .ambientContexts)
        representations = try c.decode([IndependentShapeRepresentation].self, forKey: .representations)
        frames = try c.decode([IndependentShapeFrame].self, forKey: .frames)
        definitions = try c.decode([IndependentShapeDefinition].self, forKey: .definitions)
        curveNames = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .curveNames))
        surfaceNames = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .surfaceNames))
        curvePositionFrames = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .curvePositionFrames))
        surfacePositionFrames = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .surfacePositionFrames))
        surfaceAngularMeasures = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .surfaceAngularMeasures))
        curveLinearSources = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .curveLinearSources))
        curveSplineSources = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .curveSplineSources))
        surfaceSplineSources = try IndependentShapeMapCoding.decode(from: c.superDecoder(forKey: .surfaceSplineSources))
        originalSTEPGroups = try c.decode([IndependentShapeSTEPGroup].self, forKey: .originalSTEPGroups)
        groups = try c.decode([IndependentShapeGroup].self, forKey: .groups)
        instances = try c.decode([IndependentShapeInstance].self, forKey: .instances)
        ambientOriginalLengthSource = try c.decode(OriginalSTEPLengthSource?.self, forKey: .ambientOriginalLengthSource)
        ambientOriginalAngularSource = try c.decode(IndependentShapeAngularSource?.self, forKey: .ambientOriginalAngularSource)
        productAssociations = try c.decode([IndependentShapeProductAssociation].self, forKey: .productAssociations)
        roots = try c.decode([IndependentShapeReference].self, forKey: .roots)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try IndependentShapeMapCoding.encodeGeometry(geometry, to: c.superEncoder(forKey: .geometry))
        try c.encode(items, forKey: .items); try c.encode(geometricSets, forKey: .geometricSets)
        try c.encode(contexts, forKey: .contexts); try c.encode(ambientContexts, forKey: .ambientContexts); try c.encode(representations, forKey: .representations)
        try c.encode(frames, forKey: .frames)
        try c.encode(definitions, forKey: .definitions); try c.encode(groups, forKey: .groups); try c.encode(originalSTEPGroups, forKey: .originalSTEPGroups)
        try c.encode(ambientOriginalLengthSource, forKey: .ambientOriginalLengthSource)
        try c.encode(ambientOriginalAngularSource, forKey: .ambientOriginalAngularSource)
        try c.encode(productAssociations, forKey: .productAssociations)
        try c.encode(instances, forKey: .instances); try c.encode(roots, forKey: .roots)
        try IndependentShapeMapCoding.encode(curveNames, to: c.superEncoder(forKey: .curveNames))
        try IndependentShapeMapCoding.encode(surfaceNames, to: c.superEncoder(forKey: .surfaceNames))
        try IndependentShapeMapCoding.encode(curvePositionFrames, to: c.superEncoder(forKey: .curvePositionFrames))
        try IndependentShapeMapCoding.encode(surfacePositionFrames, to: c.superEncoder(forKey: .surfacePositionFrames))
        try IndependentShapeMapCoding.encode(surfaceAngularMeasures, to: c.superEncoder(forKey: .surfaceAngularMeasures))
        try IndependentShapeMapCoding.encode(curveLinearSources, to: c.superEncoder(forKey: .curveLinearSources))
        try IndependentShapeMapCoding.encode(curveSplineSources, to: c.superEncoder(forKey: .curveSplineSources))
        try IndependentShapeMapCoding.encode(surfaceSplineSources, to: c.superEncoder(forKey: .surfaceSplineSources))
    }
    #endif
    public static func == (a: Self, b: Self) -> Bool {
        guard a.geometry == b.geometry, a.items == b.items, a.geometricSets == b.geometricSets,
              a.contexts == b.contexts, a.ambientContexts == b.ambientContexts, a.representations == b.representations, a.frames == b.frames, a.definitions == b.definitions,
              a.curvePositionFrames == b.curvePositionFrames, a.surfacePositionFrames == b.surfacePositionFrames, a.surfaceAngularMeasures == b.surfaceAngularMeasures, a.curveLinearSources == b.curveLinearSources, a.curveSplineSources == b.curveSplineSources, a.surfaceSplineSources == b.surfaceSplineSources,
              a.groups == b.groups, a.originalSTEPGroups == b.originalSTEPGroups, a.instances == b.instances, a.productAssociations == b.productAssociations, a.ambientOriginalAngularSource == b.ambientOriginalAngularSource, a.ambientOriginalLengthSource == b.ambientOriginalLengthSource, a.roots == b.roots,
              a.curveNames.count == b.curveNames.count, a.surfaceNames.count == b.surfaceNames.count else { return false }
        for (id, name) in a.curveNames { guard let other = b.curveNames[id], name.utf8.elementsEqual(other.utf8) else { return false } }
        for (id, name) in a.surfaceNames { guard let other = b.surfaceNames[id], name.utf8.elementsEqual(other.utf8) else { return false } }
        return true
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeSource: Codable {}
#endif
