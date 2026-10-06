import CADCore
import CADTopology
import CADGeometry

/// A named selection of one original law. Selection identity is not geometry identity.
public struct IndependentShapeItem: Equatable, Sendable {
    public enum Geometry: Hashable, Sendable {
        case curve(CurveID, trim: CurveTrim?)
        case surface(SurfaceID)

        #if !hasFeature(Embedded)
        private enum CodingKeys: String, CodingKey { case kind, id, trim }
        #endif

        #if !hasFeature(Embedded)
        private enum Kind: String, Codable { case curve, surface }
        #endif

        #if !hasFeature(Embedded)
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(Kind.self, forKey: .kind) {
            case .curve:
                try c.validateOnlyExpectedKeys([.kind, .id, .trim], in: decoder)
                guard c.contains(.trim) else { throw DecodingError.keyNotFound(CodingKeys.trim, .init(codingPath: c.codingPath, debugDescription: "Required nullable trim is absent.")) }
                self = .curve(try c.decode(CurveID.self, forKey: .id), trim: try c.decodeIfPresent(CurveTrim.self, forKey: .trim))
            case .surface:
                try c.validateOnlyExpectedKeys([.kind, .id], in: decoder)
                self = .surface(try c.decode(SurfaceID.self, forKey: .id))
            }
        }
        #endif

        #if !hasFeature(Embedded)
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .curve(let id, let trim): try c.encode(Kind.curve, forKey: .kind); try c.encode(id, forKey: .id); try c.encode(trim, forKey: .trim)
            case .surface(let id): try c.encode(Kind.surface, forKey: .kind); try c.encode(id, forKey: .id)
            }
        }
        #endif
    }
    public let id: IndependentShapeItemID
    public let name: String
    public let geometry: Geometry
    public let traversalSource: Curve3D?
    public let trimmingSource: IndependentShapeTrimmingSource?
    public init(id: IndependentShapeItemID = .init(), name: String = "", geometry: Geometry, trimmingSource: IndependentShapeTrimmingSource? = nil, traversalSource: Curve3D? = nil) {
        self.id = id; self.name = name; self.geometry = geometry; self.trimmingSource = trimmingSource; self.traversalSource = traversalSource
    }

    /// The selected law; original basis sharing and labels remain owned by GeometryStore.
    public func resolvedCurve(in store: GeometryStore) throws -> (curve: Curve3D, trim: CurveTrim?) {
        guard case .curve(let id, let trim) = geometry, let basis = store.curves[id] else {
            throw IndependentShapeSourceError.missingReference("Selected original curve basis.")
        }
        return (traversalSource ?? basis, trim)
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, geometry, trimmingSource, traversalSource }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .geometry, .trimmingSource, .traversalSource], in: decoder)
        id = try c.decode(IndependentShapeItemID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        geometry = try c.decode(Geometry.self, forKey: .geometry)
        guard c.contains(.trimmingSource) else { throw DecodingError.keyNotFound(CodingKeys.trimmingSource, .init(codingPath: decoder.codingPath, debugDescription: "Original trimming source must be explicitly nullable.")) }
        trimmingSource = try c.decodeIfPresent(IndependentShapeTrimmingSource.self, forKey: .trimmingSource)
        guard c.contains(.traversalSource) else { throw DecodingError.keyNotFound(CodingKeys.traversalSource, .init(codingPath: decoder.codingPath, debugDescription: "Directed traversal source must be explicitly nullable.")) }
        traversalSource = try c.decodeIfPresent(Curve3D.self, forKey: .traversalSource)
    }
    #endif
    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(geometry, forKey: .geometry)
        try c.encode(traversalSource, forKey: .traversalSource)
        if let trimmingSource { try c.encode(trimmingSource, forKey: .trimmingSource) } else { try c.encodeNil(forKey: .trimmingSource) }
    }
    #endif
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.geometry == rhs.geometry && lhs.trimmingSource == rhs.trimmingSource && lhs.traversalSource == rhs.traversalSource
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeItem: Codable {}
extension IndependentShapeItem.Geometry: Codable {}
#endif
