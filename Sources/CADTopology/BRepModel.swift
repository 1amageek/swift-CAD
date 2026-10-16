import HashTreeCollections
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

  package static func originalValidationExecution() throws -> OriginalQueryExecution {
    OriginalQueryExecution(budget: try OriginalQueryBudget(),
      limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
        remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
  }

  private func validationInvocation(using execution: borrowing OriginalQueryExecution)
    -> OriginalBRepValidationInvocation {
    let limits = execution.effectiveLimits
    return OriginalBRepValidationInvocation(model: self,
      maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
      remainingSourceDepth: limits.remainingSourceDepth,
      maximumAlgebraicDepth: 32)
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try Self.originalValidationExecution()
    try validate(tolerance: tolerance, using: &execution)
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try validationInvocation(using: execution).validate(tolerance: tolerance, using: &execution)
  }

  public func validate(level: BRepValidationLevel, tolerance: ModelingTolerance) throws {
    var execution = try Self.originalValidationExecution()
    try validate(level: level, tolerance: tolerance, using: &execution)
  }

  public func validate(level: BRepValidationLevel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try validationInvocation(using: execution).validate(level: level, tolerance: tolerance, using: &execution)
  }

  public func diagnose(tolerance: ModelingTolerance) throws -> TopologyValidationReport {
    var execution = try Self.originalValidationExecution()
    return try diagnose(tolerance: tolerance, using: &execution)
  }

  public func diagnose(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> TopologyValidationReport {
    return try validationInvocation(using: execution).diagnose(tolerance: tolerance, using: &execution)
  }

  public func validatePcurves(tolerance: ModelingTolerance) throws {
    var execution = try Self.originalValidationExecution()
    try validatePcurves(tolerance: tolerance, using: &execution)
  }

  public func validatePcurves(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try validationInvocation(using: execution).validatePcurves(tolerance: tolerance, using: &execution)
  }

  public func volume(tolerance: ModelingTolerance) throws -> Double {
    var execution = try Self.originalValidationExecution()
    return try volume(tolerance: tolerance, using: &execution)
  }

  public func volume(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    return try validationInvocation(using: execution).volume(tolerance: tolerance, using: &execution)
  }

  public func volume(of bodyID: BodyID, tolerance: ModelingTolerance) throws -> Double {
    var execution = try Self.originalValidationExecution()
    return try volume(of: bodyID, tolerance: tolerance, using: &execution)
  }

  public func volume(of bodyID: BodyID, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    return try validationInvocation(using: execution).volume(of: bodyID, tolerance: tolerance, using: &execution)
  }

  public func signedVolume(ofShell shellID: ShellID, tolerance: ModelingTolerance) throws -> Double {
    var execution = try Self.originalValidationExecution()
    return try signedVolume(ofShell: shellID, tolerance: tolerance, using: &execution)
  }

  public func signedVolume(ofShell shellID: ShellID, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    return try validationInvocation(using: execution).signedVolume(ofShell: shellID, tolerance: tolerance, using: &execution)
  }

  func volumeAfterBaseValidation(tolerance: ModelingTolerance) throws -> Double {
    var execution = try Self.originalValidationExecution()
    return try volumeAfterBaseValidation(tolerance: tolerance, using: &execution)
  }

  func volumeAfterBaseValidation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
    return try validationInvocation(using: execution).volumeAfterBaseValidation(tolerance: tolerance, using: &execution)
  }

  public func orderedVertexIDs(for loopID: LoopID) throws -> [VertexID] {
    var execution = try Self.originalValidationExecution()
    return try orderedVertexIDs(for: loopID, using: &execution)
  }

  public func orderedVertexIDs(for loopID: LoopID, using execution: inout OriginalQueryExecution) throws -> [VertexID] {
    return try validationInvocation(using: execution).orderedVertexIDs(for: loopID, using: &execution)
  }

  public func orderedPoints(for loopID: LoopID) throws -> [Point3D] {
    var execution = try Self.originalValidationExecution()
    return try orderedPoints(for: loopID, using: &execution)
  }

  public func orderedPoints(for loopID: LoopID, using execution: inout OriginalQueryExecution) throws -> [Point3D] {
    return try validationInvocation(using: execution).orderedPoints(for: loopID, using: &execution)
  }

  /// Validates original incidence and geometry on the composing caller execution.
  package func validate(level: BRepValidationLevel, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
      maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
      throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
        message: "Bounded BRep validation requires nonnegative caller depths.")
    }
    try OriginalBRepValidationInvocation(model: self,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth)
      .validate(level: level, tolerance: tolerance, using: &execution)
  }

}

#if !hasFeature(Embedded)
extension BRepModel: Codable {}
#endif
