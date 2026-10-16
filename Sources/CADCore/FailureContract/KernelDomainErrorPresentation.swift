#if hasFeature(Embedded)
/// Structural diagnostics for Core-owned errors when runtime reflection is unavailable.
/// This presentation does not classify failures or change their associated values.
@usableFromInline
enum KernelDomainErrorPresentation {
    @usableFromInline
    @_alwaysEmitIntoClient
    static func message(for error: Error) -> String {
        switch error {
        case let value as SchemaError: schema(value)
        case let value as UnitError: unit(value)
        case let value as ParameterError: parameter(value)
        case let value as GeometryError: geometry(value)
        case let value as SketchError: sketch(value)
        case let value as FeatureEvaluationError: feature(value)
        case let value as CacheValidationError: cache(value)
        case let value as TopologyError: topology(value)
        case let value as MaterialError: material(value)
        case let value as MeshArtifactPurposeError: purpose(value)
        case let value as TessellationError: tessellation(value)
        case let value as ExportError: export(value)
        case let value as ImportError: importError(value)
        case let value as PortableIdentityError: identity(value)
        case let value as PortableSourceEncodingError: sourceEncoding(value)
        case is CancellationError: "CancellationError()"
        default: "Unclassified source error; reflective diagnostic payload is unavailable on Embedded Swift."
        }
    }

    @usableFromInline
    static func sourceEncoding(_ value: PortableSourceEncodingError) -> String {
        switch value {
        case .invalidLimits: "PortableSourceEncodingError.invalidLimits"
        case let .resourceLimitExceeded(message):
            "PortableSourceEncodingError.resourceLimitExceeded(\(quoted(message)))"
        case .nonfiniteScalar: "PortableSourceEncodingError.nonfiniteScalar"
        case .canonicalKeyCollision: "PortableSourceEncodingError.canonicalKeyCollision"
        }
    }

    @usableFromInline
    static func quoted(_ value: String) -> String { "\"" + value + "\"" }

    @usableFromInline
    static func schema(_ value: SchemaError) -> String {
        switch value {
        case let .unsupportedVersion(version):
            "SchemaError.unsupportedVersion(major: \(version.major), minor: \(version.minor), patch: \(version.patch))"
        case let .invalidRevision(revision): "SchemaError.invalidRevision(\(revision))"
        case let .invalidMetadata(text): "SchemaError.invalidMetadata(\(quoted(text)))"
        case let .missingRequiredField(field): "SchemaError.missingRequiredField(\(quoted(field)))"
        case let .unknownDiscriminator(text): "SchemaError.unknownDiscriminator(\(quoted(text)))"
        case let .invalidPackage(text): "SchemaError.invalidPackage(\(quoted(text)))"
        }
    }

    @usableFromInline
    static func unit(_ value: UnitError) -> String {
        switch value {
        case let .incompatibleQuantity(operation, lhs, rhs):
            "UnitError.incompatibleQuantity(operation: \(quoted(operation)), lhs: \(lhs.rawValue), rhs: \(rhs.rawValue))"
        case let .expectedQuantity(operation, expected, actual):
            "UnitError.expectedQuantity(operation: \(quoted(operation)), expected: \(expected.rawValue), actual: \(actual.rawValue))"
        case .divisionByZero: "UnitError.divisionByZero"
        case let .invalidQuantityValue(number): "UnitError.invalidQuantityValue(\(number))"
        case .invalidUnitSystem: "UnitError.invalidUnitSystem"
        }
    }

    @usableFromInline
    static func parameter(_ value: ParameterError) -> String {
        switch value {
        case let .invalidName(name): "ParameterError.invalidName(\(quoted(name)))"
        case let .duplicateName(name): "ParameterError.duplicateName(\(quoted(name)))"
        case let .tableKeyMismatch(key, parameterID):
            "ParameterError.tableKeyMismatch(key: \(key.description), parameterID: \(parameterID.description))"
        case let .unknownReference(id): "ParameterError.unknownReference(\(id.description))"
        case let .unknownVariable(name): "ParameterError.unknownVariable(\(quoted(name)))"
        case let .cycleDetected(ids):
            "ParameterError.cycleDetected([\(ids.map { $0.description }.joined(separator: ", "))])"
        case let .kindMismatch(id, expected, actual):
            "ParameterError.kindMismatch(parameterID: \(id.description), expected: \(expected.rawValue), actual: \(actual.rawValue))"
        }
    }

    @usableFromInline
    static func geometry(_ value: GeometryError) -> String {
        switch value {
        case let .invalidCoordinate(number): "GeometryError.invalidCoordinate(\(number))"
        case let .invalidVectorLength(number): "GeometryError.invalidVectorLength(\(number))"
        case let .invalidRadius(number): "GeometryError.invalidRadius(\(number))"
        case let .invalidDistance(number): "GeometryError.invalidDistance(\(number))"
        case let .invalidAngle(number): "GeometryError.invalidAngle(\(number))"
        case let .invalidTolerance(distance, angle):
            "GeometryError.invalidTolerance(distance: \(distance), angle: \(angle))"
        case let .invalidModelingTolerance(distance, angle, relative):
            "GeometryError.invalidModelingTolerance(distance: \(distance), angle: \(angle), relative: \(relative))"
        case let .invalidMatrixElementCount(count): "GeometryError.invalidMatrixElementCount(\(count))"
        }
    }

    @usableFromInline
    static func sketch(_ value: SketchError) -> String {
        switch value {
        case let .unsupportedEntity(text): "SketchError.unsupportedEntity(\(quoted(text)))"
        case let .unsupportedProfile(text): "SketchError.unsupportedProfile(\(quoted(text)))"
        case let .disconnectedCurveChain(operation): "SketchError.disconnectedCurveChain(operation: \(quoted(operation)))"
        case let .invalidReference(text): "SketchError.invalidReference(\(quoted(text)))"
        case .openProfile: "SketchError.openProfile"
        case .degenerateProfile: "SketchError.degenerateProfile"
        case .emptyProfile: "SketchError.emptyProfile"
        case .unresolvedExpression: "SketchError.unresolvedExpression"
        }
    }

    @usableFromInline
    static func feature(_ value: FeatureEvaluationError) -> String {
        switch value {
        case let .invalidGraph(text): "FeatureEvaluationError.invalidGraph(\(quoted(text)))"
        case let .missingInput(text): "FeatureEvaluationError.missingInput(\(quoted(text)))"
        case let .emptyResult(text): "FeatureEvaluationError.emptyResult(\(quoted(text)))"
        case let .invalidDistance(number): "FeatureEvaluationError.invalidDistance(\(number))"
        case let .invalidDirection(direction):
            "FeatureEvaluationError.invalidDirection(x: \(direction.x), y: \(direction.y), z: \(direction.z))"
        case let .missingProfile(id, index): "FeatureEvaluationError.missingProfile(\(id.description), \(index))"
        }
    }

    @usableFromInline
    static func cache(_ value: CacheValidationError) -> String {
        switch value {
        case .missingBRepCache: "CacheValidationError.missingBRepCache"
        case let .staleBRepCache(text): "CacheValidationError.staleBRepCache(\(quoted(text)))"
        case let .staleMeshCache(bodyID, reason):
            "CacheValidationError.staleMeshCache(bodyID: \(bodyID.description), reason: \(quoted(reason)))"
        case let .meshCachePurposeMismatch(bodyID, cached, requested):
            "CacheValidationError.meshCachePurposeMismatch(bodyID: \(bodyID.description), cached: \(quoted(cached.rawValue)), requested: \(quoted(requested.rawValue)))"
        case let .meshCacheExceedsLimits(bodyID, resource, recorded, limit):
            "CacheValidationError.meshCacheExceedsLimits(bodyID: \(bodyID.description), \(resource.rawValue), recorded: \(recorded), limit: \(limit))"
        }
    }

    @usableFromInline
    static func topology(_ value: TopologyError) -> String {
        switch value {
        case let .missingReference(text): "TopologyError.missingReference(\(quoted(text)))"
        case let .duplicateTopologyReference(text): "TopologyError.duplicateTopologyReference(\(quoted(text)))"
        case let .openLoop(id): "TopologyError.openLoop(\(id.description))"
        case let .degenerateLoop(id): "TopologyError.degenerateLoop(\(id.description))"
        case let .invalidEdge(id): "TopologyError.invalidEdge(\(id.description))"
        case let .invalidFaceSurface(id): "TopologyError.invalidFaceSurface(\(id.description))"
        case let .invalidTrim(id): "TopologyError.invalidTrim(\(id.description))"
        case let .invalidLoopRole(id): "TopologyError.invalidLoopRole(\(id.description))"
        case let .inconsistentEdgeOrientation(id): "TopologyError.inconsistentEdgeOrientation(\(id.description))"
        case let .missingSurface(id): "TopologyError.missingSurface(\(id.description))"
        case let .openShell(id): "TopologyError.openShell(\(id.description))"
        case let .nonManifoldEdge(id, count): "TopologyError.nonManifoldEdge(\(id.description), count: \(count))"
        case let .unreferencedTopology(text): "TopologyError.unreferencedTopology(\(quoted(text)))"
        }
    }

    @usableFromInline
    static func material(_ value: MaterialError) -> String {
        switch value {
        case let .valueOutOfRange(field, number): "MaterialError.valueOutOfRange(field: \(quoted(field)), value: \(number))"
        }
    }

    @usableFromInline
    static func purpose(_ value: MeshArtifactPurposeError) -> String {
        switch value {
        case .emptyPurpose: "MeshArtifactPurposeError.emptyPurpose"
        case let .whitespaceInPurpose(text): "MeshArtifactPurposeError.whitespaceInPurpose(\(quoted(text)))"
        }
    }

    @usableFromInline
    static func tessellation(_ value: TessellationError) -> String {
        switch value {
        case .invalidTolerance: "TessellationError.invalidTolerance"
        case let .unsupportedFace(id): "TessellationError.unsupportedFace(\(id.description))"
        case let .degenerateFace(id): "TessellationError.degenerateFace(\(id.description))"
        case let .invalidLimit(resource, requested):
            "TessellationError.invalidLimit(\(resource.rawValue), requested: \(requested))"
        case let .resourceExhausted(resource, requested, limit):
            "TessellationError.resourceExhausted(\(resource.rawValue), requested: \(requested), limit: \(limit))"
        case let .invalidUsage(resource, recorded):
            "TessellationError.invalidUsage(\(resource.rawValue), recorded: \(recorded))"
        }
    }

    @usableFromInline
    static func export(_ value: ExportError) -> String {
        switch value {
        case .emptyMesh: "ExportError.emptyMesh"
        case let .invalidMesh(text): "ExportError.invalidMesh(\(quoted(text)))"
        case let .unsupportedFeature(text): "ExportError.unsupportedFeature(\(quoted(text)))"
        case .triangleCountOverflow: "ExportError.triangleCountOverflow"
        case let .fileWriteFailure(text): "ExportError.fileWriteFailure(\(quoted(text)))"
        case let .externalToolUnavailable(text): "ExportError.externalToolUnavailable(\(quoted(text)))"
        case let .externalToolFailure(tool, output):
            "ExportError.externalToolFailure(tool: \(quoted(tool)), output: \(quoted(output)))"
        }
    }

    @usableFromInline
    static func importError(_ value: ImportError) -> String {
        switch value {
        case let .unsupportedFormat(text): "ImportError.unsupportedFormat(\(quoted(text)))"
        case let .unsupportedFeature(text): "ImportError.unsupportedFeature(\(quoted(text)))"
        case let .invalidData(text): "ImportError.invalidData(\(quoted(text)))"
        case let .formatConstraint(text): "ImportError.formatConstraint(\(quoted(text)))"
        case let .unsupportedVersion(text): "ImportError.unsupportedVersion(\(quoted(text)))"
        case let .securityViolation(text): "ImportError.securityViolation(\(quoted(text)))"
        case let .resourceUnavailable(text): "ImportError.resourceUnavailable(\(quoted(text)))"
        case let .compositionFailure(kind, message):
            "ImportError.compositionFailure(kind: \(quoted(kind)), message: \(quoted(message)))"
        case let .missingRequiredEntity(text): "ImportError.missingRequiredEntity(\(quoted(text)))"
        case let .fileReadFailure(text): "ImportError.fileReadFailure(\(quoted(text)))"
        }
    }

    @usableFromInline
    static func identity(_ value: PortableIdentityError) -> String {
        switch value {
        case .invalidCanonicalString: "PortableIdentityError.invalidCanonicalString"
        }
    }
}
#endif
