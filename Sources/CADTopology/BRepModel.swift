import CADCore
import CADGeometry

public struct BRepModel: Equatable, Sendable {
  public var geometry: GeometryStore
  public var bodies: PersistentMap<BodyID, Body>
  public var shells: PersistentMap<ShellID, Shell>
  public var faces: PersistentMap<FaceID, Face>
  public var loops: PersistentMap<LoopID, Loop>
  public var edges: PersistentMap<EdgeID, Edge>
  public var vertices: PersistentMap<VertexID, Vertex>

  public init(
    geometry: GeometryStore = GeometryStore(),
    bodies: [BodyID: Body] = [:],
    shells: [ShellID: Shell] = [:],
    faces: [FaceID: Face] = [:],
    loops: [LoopID: Loop] = [:],
    edges: [EdgeID: Edge] = [:],
    vertices: [VertexID: Vertex] = [:]
  ) {
    self.geometry = geometry
    self.bodies = PersistentMap(bodies)
    self.shells = PersistentMap(shells)
    self.faces = PersistentMap(faces)
    self.loops = PersistentMap(loops)
    self.edges = PersistentMap(edges)
    self.vertices = PersistentMap(vertices)
  }

  #if !hasFeature(Embedded)
  private enum CodingKeys: String, CodingKey {
    case geometry
    case bodies
    case shells
    case faces
    case loops
    case edges
    case vertices
  }
  #endif

  #if !hasFeature(Embedded)
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try container.validateOnlyExpectedKeys(
      [.geometry, .bodies, .shells, .faces, .loops, .edges, .vertices],
      in: decoder
    )
    geometry = try container.decode(GeometryStore.self, forKey: .geometry)
    bodies = try container.decode(
      PersistentMap<BodyID, Body>.self,
      forKey: .bodies
    )
    shells = try container.decode(
      PersistentMap<ShellID, Shell>.self,
      forKey: .shells
    )
    faces = try container.decode(
      PersistentMap<FaceID, Face>.self,
      forKey: .faces
    )
    loops = try container.decode(
      PersistentMap<LoopID, Loop>.self,
      forKey: .loops
    )
    edges = try container.decode(
      PersistentMap<EdgeID, Edge>.self,
      forKey: .edges
    )
    vertices = try container.decode(
      PersistentMap<VertexID, Vertex>.self,
      forKey: .vertices
    )
  }
  #endif

  #if !hasFeature(Embedded)
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(geometry, forKey: .geometry)
    try container.encode(bodies, forKey: .bodies)
    try container.encode(shells, forKey: .shells)
    try container.encode(faces, forKey: .faces)
    try container.encode(loops, forKey: .loops)
    try container.encode(edges, forKey: .edges)
    try container.encode(vertices, forKey: .vertices)
  }
  #endif

  private var validationInvocation: OriginalBRepValidationInvocation {
    OriginalBRepValidationInvocation(model: self)
  }

  public func validate(tolerance: ModelingTolerance) throws {
    try validationInvocation.validate(tolerance: tolerance)
  }

  public func validate(level: BRepValidationLevel, tolerance: ModelingTolerance) throws {
    try validationInvocation.validate(level: level, tolerance: tolerance)
  }

  /// Validates original incidence and geometry on the composing caller allowance.
  package func validate(level: BRepValidationLevel, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: @escaping @Sendable () throws -> Void,
    consumeStorage: (@Sendable (Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
      throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
        message: "Bounded BRep validation requires nonnegative caller depths.")
    }
    try OriginalBRepValidationInvocation(model: self,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      .validate(level: level, tolerance: tolerance)
  }

  public func diagnose(tolerance: ModelingTolerance) -> TopologyValidationReport {
    validationInvocation.diagnose(tolerance: tolerance)
  }

  public func validatePcurves(tolerance: ModelingTolerance) throws {
    try validationInvocation.validatePcurves(tolerance: tolerance)
  }

  public func volume(tolerance: ModelingTolerance) throws -> Double {
    try validationInvocation.volume(tolerance: tolerance)
  }

  public func volume(of bodyID: BodyID, tolerance: ModelingTolerance) throws -> Double {
    try validationInvocation.volume(of: bodyID, tolerance: tolerance)
  }

  public func signedVolume(ofShell shellID: ShellID, tolerance: ModelingTolerance) throws -> Double {
    try validationInvocation.signedVolume(ofShell: shellID, tolerance: tolerance)
  }

  func volumeAfterBaseValidation(tolerance: ModelingTolerance) throws -> Double {
    try validationInvocation.volumeAfterBaseValidation(tolerance: tolerance)
  }

  public func orderedVertexIDs(for loopID: LoopID) throws -> [VertexID] {
    try validationInvocation.orderedVertexIDs(for: loopID)
  }

  public func orderedPoints(for loopID: LoopID) throws -> [Point3D] {
    try validationInvocation.orderedPoints(for: loopID)
  }
}

#if !hasFeature(Embedded)
extension BRepModel: Codable {}
#endif
