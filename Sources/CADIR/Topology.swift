import CADCore

public struct Body: Codable, Equatable, Sendable {
    public var id: BodyID
    public var shellIDs: [ShellID]
    public var kind: BodyKind
    public var name: String?
    public var material: MaterialID?

    public init(
        id: BodyID = BodyID(),
        shellIDs: [ShellID],
        kind: BodyKind = .solid,
        name: String? = nil,
        material: MaterialID? = nil
    ) {
        self.id = id
        self.shellIDs = shellIDs
        self.kind = kind
        self.name = name
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case shellIDs
        case kind
        case name
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BodyID.self, forKey: .id)
        shellIDs = try container.decode([ShellID].self, forKey: .shellIDs)
        kind = try container.decodeIfPresent(BodyKind.self, forKey: .kind) ?? .solid
        name = try container.decodeIfPresent(String.self, forKey: .name)
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(shellIDs, forKey: .shellIDs)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(material, forKey: .material)
    }
}

public enum BodyKind: String, Codable, Equatable, Sendable {
    case solid
    case sheet
}

public struct Shell: Codable, Equatable, Sendable {
    public var id: ShellID
    public var faceIDs: [FaceID]
    public var orientation: Orientation

    public init(id: ShellID = ShellID(), faceIDs: [FaceID], orientation: Orientation = .forward) {
        self.id = id
        self.faceIDs = faceIDs
        self.orientation = orientation
    }
}

public struct Face: Codable, Equatable, Sendable {
    public var id: FaceID
    public var surfaceID: SurfaceID
    public var loops: [LoopID]
    public var orientation: Orientation

    public init(id: FaceID = FaceID(), surfaceID: SurfaceID, loops: [LoopID], orientation: Orientation = .forward) {
        self.id = id
        self.surfaceID = surfaceID
        self.loops = loops
        self.orientation = orientation
    }
}

public enum LoopRole: String, Codable, Equatable, Sendable {
    case outer
    case inner
}

public struct Loop: Codable, Equatable, Sendable {
    public var id: LoopID
    public var role: LoopRole
    /// Ordered coedges form the oriented boundary of this loop.
    public var coedges: [Coedge]

    /// Computed boundary view for algorithms that consume ordered coedges.
    public var edges: [Coedge] {
        get { coedges }
        set { coedges = newValue }
    }

    public init(id: LoopID = LoopID(), role: LoopRole = .outer, edges: [Coedge]) {
        self.id = id
        self.role = role
        self.coedges = edges
    }

    public init(id: LoopID = LoopID(), role: LoopRole = .outer, coedges: [Coedge]) {
        self.id = id
        self.role = role
        self.coedges = coedges
    }
}

public struct Coedge: Codable, Equatable, Sendable {
    public var edgeID: EdgeID
    public var orientation: Orientation
    public var surfaceParameterCurve: SurfaceParameterCurve?

    public init(
        edgeID: EdgeID,
        orientation: Orientation = .forward,
        surfaceParameterCurve: SurfaceParameterCurve? = nil
    ) {
        self.edgeID = edgeID
        self.orientation = orientation
        self.surfaceParameterCurve = surfaceParameterCurve
    }
}

public struct Edge: Codable, Equatable, Sendable {
    public var id: EdgeID
    public var curveID: CurveID
    public var startVertexID: VertexID
    public var endVertexID: VertexID
    public var trim: CurveTrim?
    public var surfaceApproximationTolerance: Double?

    public init(
        id: EdgeID = EdgeID(),
        curveID: CurveID,
        startVertexID: VertexID,
        endVertexID: VertexID,
        trim: CurveTrim? = nil,
        surfaceApproximationTolerance: Double? = nil
    ) {
        self.id = id
        self.curveID = curveID
        self.startVertexID = startVertexID
        self.endVertexID = endVertexID
        self.trim = trim
        self.surfaceApproximationTolerance = surfaceApproximationTolerance
    }
}

public struct CurveTrim: Codable, Hashable, Sendable {
    public var startParameter: Double
    public var endParameter: Double

    public init(startParameter: Double, endParameter: Double) {
        self.startParameter = startParameter
        self.endParameter = endParameter
    }

    public func validate(on curve: Curve3D, edgeID: EdgeID, tolerance: ModelingTolerance = .standard) throws {
        try validateFiniteParameters(edgeID: edgeID, tolerance: tolerance)
        guard try curve.parameterDomain.containsSpan(
            from: startParameter,
            to: endParameter,
            tolerance: tolerance
        ) else {
            throw TopologyError.invalidTrim(edgeID)
        }
        let span = abs(endParameter - startParameter)
        switch curve {
        case .line:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case .circle:
            guard span > tolerance.angle,
                  span < (Double.pi * 2.0) - tolerance.angle else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case .bSpline:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        }
    }

    public func validateFiniteParameters(edgeID: EdgeID, tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite else {
            throw TopologyError.invalidTrim(edgeID)
        }
    }
}

public struct Vertex: Codable, Equatable, Sendable {
    public var id: VertexID
    public var point: Point3D

    public init(id: VertexID = VertexID(), point: Point3D) {
        self.id = id
        self.point = point
    }
}
