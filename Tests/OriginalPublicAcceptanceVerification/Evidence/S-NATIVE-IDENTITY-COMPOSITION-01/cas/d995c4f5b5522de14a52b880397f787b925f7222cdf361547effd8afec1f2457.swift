public enum SchemaError: Error, Equatable, Sendable {
    case unsupportedVersion(SchemaVersion)
    case invalidRevision(Int)
    case invalidMetadata(String)
    case missingRequiredField(String)
    case unknownDiscriminator(String)
    case invalidPackage(String)
}

public enum UnitError: Error, Equatable, Sendable {
    case incompatibleQuantity(operation: String, lhs: QuantityKind, rhs: QuantityKind)
    case expectedQuantity(operation: String, expected: QuantityKind, actual: QuantityKind)
    case divisionByZero
    case invalidQuantityValue(Double)
    case invalidUnitSystem
}

public enum ParameterError: Error, Equatable, Sendable {
    case invalidName(String)
    case duplicateName(String)
    case tableKeyMismatch(key: ParameterID, parameterID: ParameterID)
    case unknownReference(ParameterID)
    case unknownVariable(String)
    case cycleDetected([ParameterID])
    case kindMismatch(parameterID: ParameterID, expected: QuantityKind, actual: QuantityKind)
}

public enum GeometryError: Error, Equatable, Sendable {
    case invalidCoordinate(Double)
    case invalidVectorLength(Double)
    case invalidRadius(Double)
    case invalidDistance(Double)
    case invalidAngle(Double)
    case invalidTolerance(distance: Double, angle: Double)
    case invalidModelingTolerance(distance: Double, angle: Double, relative: Double)
    case invalidMatrixElementCount(Int)
}

public enum SketchError: Error, Equatable, Sendable {
    case unsupportedEntity(String)
    case unsupportedProfile(String)
    case disconnectedCurveChain(operation: String)
    case invalidReference(String)
    case openProfile
    case degenerateProfile
    case emptyProfile
    case unresolvedExpression
}

public enum FeatureEvaluationError: Error, Equatable, Sendable {
    case invalidGraph(String)
    case missingInput(String)
    case emptyResult(String)
    case invalidDistance(Double)
    case invalidDirection(Vector3D)
    case missingProfile(FeatureID, Int)
}

public enum CacheValidationError: Error, Equatable, Sendable {
    case missingBRepCache
    case staleBRepCache(String)
    case staleMeshCache(bodyID: BodyID, reason: String)
    /// A cached Mesh was produced for a different purpose than the one
    /// requesting it. The artifact is not stale; it belongs to another
    /// consumer.
    case meshCachePurposeMismatch(
        bodyID: BodyID,
        cached: MeshArtifactPurpose,
        requested: MeshArtifactPurpose
    )
    /// A cached Mesh records usage the requesting limits do not admit. The
    /// artifact is not stale; the request is narrower than the one that
    /// produced it.
    case meshCacheExceedsLimits(
        bodyID: BodyID,
        TessellationResource,
        recorded: Int,
        limit: Int
    )
}

public enum TopologyError: Error, Equatable, Sendable {
    case missingReference(String)
    case duplicateTopologyReference(String)
    case openLoop(LoopID)
    case degenerateLoop(LoopID)
    case invalidEdge(EdgeID)
    case invalidFaceSurface(FaceID)
    case invalidTrim(EdgeID)
    case invalidLoopRole(LoopID)
    case inconsistentEdgeOrientation(EdgeID)
    case missingSurface(SurfaceID)
    case openShell(ShellID)
    case nonManifoldEdge(EdgeID, count: Int)
    case unreferencedTopology(String)
}

public enum MaterialError: Error, Equatable, Sendable {
    case valueOutOfRange(field: String, value: Double)
}

public enum TessellationError: Error, Equatable, Sendable {
    case invalidTolerance
    case unsupportedFace(FaceID)
    case degenerateFace(FaceID)
    /// A supplied limit is not a positive representable value, or it widens the
    /// package hard ceiling instead of lowering it.
    case invalidLimit(TessellationResource, requested: Int)
    /// The invocation needs more of a resource than the supplied limits admit.
    /// `requested` is the cumulative amount the invocation reached or was
    /// estimated to reach, not the increment that crossed the limit.
    case resourceExhausted(TessellationResource, requested: Int, limit: Int)
    /// A recorded usage is not a value any invocation could have produced.
    case invalidUsage(TessellationResource, recorded: Int)
}

public enum ExportError: Error, Equatable, Sendable {
    case emptyMesh
    case invalidMesh(String)
    case unsupportedFeature(String)
    case triangleCountOverflow
    case fileWriteFailure(String)
    case externalToolUnavailable(String)
    case externalToolFailure(tool: String, output: String)
}

public enum ImportError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case unsupportedFeature(String)
    case invalidData(String)
    case formatConstraint(String)
    case unsupportedVersion(String)
    case securityViolation(String)
    case resourceUnavailable(String)
    case compositionFailure(kind: String, message: String)
    case missingRequiredEntity(String)
    case fileReadFailure(String)
}
