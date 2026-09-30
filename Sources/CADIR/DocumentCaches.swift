import CADCore
import CADTopology

public struct DocumentCaches: Codable, Sendable {
    public var brep: BRepCache?
    public var meshes: [BodyID: MeshCache]

    public init(brep: BRepCache? = nil, meshes: [BodyID: MeshCache] = [:]) {
        self.brep = brep
        self.meshes = meshes
    }

    public func validateMetadataFreshness(
        for document: CADDocument,
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions = .standard,
        purpose: MeshArtifactPurpose = .unspecified,
        limits: TessellationLimits = .standard,
        kernelVersion: SchemaVersion = .current
    ) throws {
        try tolerance.validate()
        try document.validate(tolerance: tolerance)
        try tessellationOptions.validate()
        try kernelVersion.validate()
        let expectedSourceFingerprint = try document.sourceFingerprint(tolerance: tolerance)
        if let brep {
            try brep.validateMetadataFreshness(
                for: document,
                sourceFingerprint: expectedSourceFingerprint,
                tolerance: tolerance,
                kernelVersion: kernelVersion
            )
        }
        guard !meshes.isEmpty else {
            return
        }
        guard let brep else {
            throw CacheValidationError.missingBRepCache
        }
        for (bodyID, meshCache) in meshes {
            guard bodyID == meshCache.bodyID else {
                throw CacheValidationError.staleMeshCache(
                    bodyID: bodyID,
                    reason: "Mesh cache table key does not match the cached body ID."
                )
            }
            try meshCache.validateMetadataFreshness(
                for: document,
                sourceFingerprint: expectedSourceFingerprint,
                brep: brep,
                tolerance: tolerance,
                tessellationOptions: tessellationOptions,
                purpose: purpose,
                limits: limits,
                kernelVersion: kernelVersion
            )
        }
    }
}

public struct BRepCache: Codable, Sendable {
    public var designRevision: DocumentRevision
    public var parameterRevision: DocumentRevision
    private var sourceFingerprintRecord: CacheSourceFingerprint
    public var kernelVersion: SchemaVersion
    public var tolerance: ModelingTolerance
    public var model: BRepModel
    public var subshapes: SubshapeIndex

    /// The fingerprint of the source this cache was evaluated from. A cache an evaluation made
    /// hashes its source only when this is first read (`CacheSourceFingerprint`).
    public var sourceFingerprint: CADDocumentSourceFingerprint {
        get throws { try sourceFingerprintRecord.resolve() }
    }

    /// Records `fingerprint` as the source this cache was made from.
    public mutating func replaceSourceFingerprint(with fingerprint: CADDocumentSourceFingerprint) {
        sourceFingerprintRecord = .value(fingerprint)
    }

    private enum CodingKeys: String, CodingKey {
        case designRevision, parameterRevision, sourceFingerprint, kernelVersion, tolerance, model, subshapes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        designRevision = try container.decode(DocumentRevision.self, forKey: .designRevision)
        parameterRevision = try container.decode(DocumentRevision.self, forKey: .parameterRevision)
        sourceFingerprintRecord = .value(try container.decode(CADDocumentSourceFingerprint.self, forKey: .sourceFingerprint))
        kernelVersion = try container.decode(SchemaVersion.self, forKey: .kernelVersion)
        tolerance = try container.decode(ModelingTolerance.self, forKey: .tolerance)
        model = try container.decode(BRepModel.self, forKey: .model)
        subshapes = try container.decode(SubshapeIndex.self, forKey: .subshapes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(designRevision, forKey: .designRevision)
        try container.encode(parameterRevision, forKey: .parameterRevision)
        try container.encode(try sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(kernelVersion, forKey: .kernelVersion)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(model, forKey: .model)
        try container.encode(subshapes, forKey: .subshapes)
    }

    public init(
        designRevision: DocumentRevision,
        parameterRevision: DocumentRevision,
        sourceFingerprint: CADDocumentSourceFingerprint,
        kernelVersion: SchemaVersion,
        tolerance: ModelingTolerance,
        model: BRepModel,
        subshapes: SubshapeIndex = SubshapeIndex()
    ) {
        self.init(
            designRevision: designRevision,
            parameterRevision: parameterRevision,
            sourceFingerprintRecord: .value(sourceFingerprint),
            kernelVersion: kernelVersion,
            tolerance: tolerance,
            model: model,
            subshapes: subshapes
        )
    }

    package init(
        designRevision: DocumentRevision,
        parameterRevision: DocumentRevision,
        sourceFingerprintRecord: CacheSourceFingerprint,
        kernelVersion: SchemaVersion,
        tolerance: ModelingTolerance,
        model: BRepModel,
        subshapes: SubshapeIndex
    ) {
        self.designRevision = designRevision
        self.parameterRevision = parameterRevision
        self.sourceFingerprintRecord = sourceFingerprintRecord
        self.kernelVersion = kernelVersion
        self.tolerance = tolerance
        self.model = model
        self.subshapes = subshapes
    }

    public func validateMetadataFreshness(
        for document: CADDocument,
        tolerance expectedTolerance: ModelingTolerance,
        kernelVersion expectedKernelVersion: SchemaVersion = .current
    ) throws {
        let expectedSourceFingerprint = try document.sourceFingerprint(tolerance: expectedTolerance)
        try validateMetadataFreshness(
            for: document,
            sourceFingerprint: expectedSourceFingerprint,
            tolerance: expectedTolerance,
            kernelVersion: expectedKernelVersion
        )
    }

    func validateMetadataFreshness(
        for document: CADDocument,
        sourceFingerprint expectedSourceFingerprint: CADDocumentSourceFingerprint,
        tolerance expectedTolerance: ModelingTolerance,
        kernelVersion expectedKernelVersion: SchemaVersion = .current
    ) throws {
        try expectedTolerance.validate()
        try document.validate(tolerance: expectedTolerance)
        try expectedKernelVersion.validate()
        guard designRevision == document.designGraph.revision else {
            throw CacheValidationError.staleBRepCache("Design revision does not match the source document.")
        }
        guard parameterRevision == document.parameters.revision else {
            throw CacheValidationError.staleBRepCache("Parameter revision does not match the source document.")
        }
        guard try sourceFingerprint == expectedSourceFingerprint else {
            throw CacheValidationError.staleBRepCache("Source fingerprint does not match the source document.")
        }
        guard kernelVersion == expectedKernelVersion else {
            throw CacheValidationError.staleBRepCache("Kernel version does not match the evaluator.")
        }
        guard tolerance == expectedTolerance else {
            throw CacheValidationError.staleBRepCache("Modeling tolerance does not match the evaluator.")
        }
        try model.validate(tolerance: expectedTolerance)
    }
}

public struct MeshCache: Codable, Sendable {
    public var bodyID: BodyID
    public var designRevision: DocumentRevision
    public var parameterRevision: DocumentRevision
    private var sourceFingerprintRecord: CacheSourceFingerprint
    public var kernelVersion: SchemaVersion
    public var tolerance: ModelingTolerance
    public var tessellationOptions: TessellationOptions
    /// The purpose this artifact was produced for. Reuse requires the
    /// requesting purpose to match, so an artifact is never shared across
    /// consumers that happen to agree on fidelity.
    public var purpose: MeshArtifactPurpose
    /// The resources this artifact accounts for, so a request whose limits are
    /// narrower than the ones that produced it refuses the artifact rather than
    /// inheriting a wider ceiling through the cache.
    public var recordedUsage: TessellationUsage
    public var mesh: Mesh

    /// The fingerprint of the source this artifact was evaluated from. An artifact an evaluation
    /// made hashes its source only when this is first read (`CacheSourceFingerprint`).
    public var sourceFingerprint: CADDocumentSourceFingerprint {
        get throws { try sourceFingerprintRecord.resolve() }
    }

    /// Records `fingerprint` as the source this artifact was made from.
    public mutating func replaceSourceFingerprint(with fingerprint: CADDocumentSourceFingerprint) {
        sourceFingerprintRecord = .value(fingerprint)
    }

    private enum CodingKeys: String, CodingKey {
        case bodyID, designRevision, parameterRevision, sourceFingerprint, kernelVersion, tolerance
        case tessellationOptions, purpose, recordedUsage, mesh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyID = try container.decode(BodyID.self, forKey: .bodyID)
        designRevision = try container.decode(DocumentRevision.self, forKey: .designRevision)
        parameterRevision = try container.decode(DocumentRevision.self, forKey: .parameterRevision)
        sourceFingerprintRecord = .value(try container.decode(CADDocumentSourceFingerprint.self, forKey: .sourceFingerprint))
        kernelVersion = try container.decode(SchemaVersion.self, forKey: .kernelVersion)
        tolerance = try container.decode(ModelingTolerance.self, forKey: .tolerance)
        tessellationOptions = try container.decode(TessellationOptions.self, forKey: .tessellationOptions)
        purpose = try container.decode(MeshArtifactPurpose.self, forKey: .purpose)
        recordedUsage = try container.decode(TessellationUsage.self, forKey: .recordedUsage)
        mesh = try container.decode(Mesh.self, forKey: .mesh)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bodyID, forKey: .bodyID)
        try container.encode(designRevision, forKey: .designRevision)
        try container.encode(parameterRevision, forKey: .parameterRevision)
        try container.encode(try sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(kernelVersion, forKey: .kernelVersion)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(tessellationOptions, forKey: .tessellationOptions)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(recordedUsage, forKey: .recordedUsage)
        try container.encode(mesh, forKey: .mesh)
    }

    public init(
        bodyID: BodyID,
        designRevision: DocumentRevision,
        parameterRevision: DocumentRevision,
        sourceFingerprint: CADDocumentSourceFingerprint,
        kernelVersion: SchemaVersion,
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions,
        purpose: MeshArtifactPurpose,
        recordedUsage: TessellationUsage,
        mesh: Mesh
    ) {
        self.init(
            bodyID: bodyID,
            designRevision: designRevision,
            parameterRevision: parameterRevision,
            sourceFingerprintRecord: .value(sourceFingerprint),
            kernelVersion: kernelVersion,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            purpose: purpose,
            recordedUsage: recordedUsage,
            mesh: mesh
        )
    }

    package init(
        bodyID: BodyID,
        designRevision: DocumentRevision,
        parameterRevision: DocumentRevision,
        sourceFingerprintRecord: CacheSourceFingerprint,
        kernelVersion: SchemaVersion,
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions,
        purpose: MeshArtifactPurpose,
        recordedUsage: TessellationUsage,
        mesh: Mesh
    ) {
        self.bodyID = bodyID
        self.designRevision = designRevision
        self.parameterRevision = parameterRevision
        self.sourceFingerprintRecord = sourceFingerprintRecord
        self.kernelVersion = kernelVersion
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
        self.purpose = purpose
        self.recordedUsage = recordedUsage
        self.mesh = mesh
    }

    /// Records the usage the supplied mesh accounts for, so a caller cannot
    /// declare a usage that disagrees with the artifact it stores.
    public init(
        bodyID: BodyID,
        designRevision: DocumentRevision,
        parameterRevision: DocumentRevision,
        sourceFingerprint: CADDocumentSourceFingerprint,
        kernelVersion: SchemaVersion,
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions,
        purpose: MeshArtifactPurpose,
        mesh: Mesh
    ) throws {
        self.init(
            bodyID: bodyID,
            designRevision: designRevision,
            parameterRevision: parameterRevision,
            sourceFingerprint: sourceFingerprint,
            kernelVersion: kernelVersion,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            purpose: purpose,
            recordedUsage: try TessellationUsage(mesh: mesh),
            mesh: mesh
        )
    }

    public func validateMetadataFreshness(
        for document: CADDocument,
        brep: BRepCache,
        tolerance expectedTolerance: ModelingTolerance,
        tessellationOptions expectedTessellationOptions: TessellationOptions,
        purpose expectedPurpose: MeshArtifactPurpose = .unspecified,
        limits: TessellationLimits = .standard,
        kernelVersion expectedKernelVersion: SchemaVersion = .current
    ) throws {
        let expectedSourceFingerprint = try document.sourceFingerprint(tolerance: expectedTolerance)
        try validateMetadataFreshness(
            for: document,
            sourceFingerprint: expectedSourceFingerprint,
            brep: brep,
            tolerance: expectedTolerance,
            tessellationOptions: expectedTessellationOptions,
            purpose: expectedPurpose,
            limits: limits,
            kernelVersion: expectedKernelVersion
        )
    }

    func validateMetadataFreshness(
        for document: CADDocument,
        sourceFingerprint expectedSourceFingerprint: CADDocumentSourceFingerprint,
        brep: BRepCache,
        tolerance expectedTolerance: ModelingTolerance,
        tessellationOptions expectedTessellationOptions: TessellationOptions,
        purpose expectedPurpose: MeshArtifactPurpose,
        limits: TessellationLimits,
        kernelVersion expectedKernelVersion: SchemaVersion = .current
    ) throws {
        try expectedTolerance.validate()
        try document.validate(tolerance: expectedTolerance)
        try expectedTessellationOptions.validate()
        try expectedKernelVersion.validate()
        guard designRevision == document.designGraph.revision,
              designRevision == brep.designRevision else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Design revision does not match the source document or B-rep cache."
            )
        }
        guard parameterRevision == document.parameters.revision,
              parameterRevision == brep.parameterRevision else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Parameter revision does not match the source document or B-rep cache."
            )
        }
        guard try sourceFingerprint == expectedSourceFingerprint,
              try sourceFingerprint == brep.sourceFingerprint else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Source fingerprint does not match the source document or B-rep cache."
            )
        }
        guard kernelVersion == expectedKernelVersion,
              kernelVersion == brep.kernelVersion else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Kernel version does not match the evaluator or B-rep cache."
            )
        }
        guard tolerance == expectedTolerance,
              tolerance == brep.tolerance else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Modeling tolerance does not match the evaluator or B-rep cache."
            )
        }
        guard tessellationOptions == expectedTessellationOptions else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Tessellation options do not match the evaluator."
            )
        }
        guard brep.model.bodies[bodyID] != nil else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Cached body does not exist in the B-rep cache."
            )
        }
        try expectedPurpose.validate()
        try purpose.validate()
        guard purpose == expectedPurpose else {
            throw CacheValidationError.meshCachePurposeMismatch(
                bodyID: bodyID,
                cached: purpose,
                requested: expectedPurpose
            )
        }
        try limits.validate()
        try recordedUsage.validate()
        // The recorded usage must describe the artifact it is stored with, so a
        // narrow request cannot be admitted by a usage the producer understated.
        guard recordedUsage == (try TessellationUsage(mesh: mesh)) else {
            throw CacheValidationError.staleMeshCache(
                bodyID: bodyID,
                reason: "Recorded usage does not describe the cached mesh."
            )
        }
        if let exceeded = recordedUsage.firstResourceExceeding(limits) {
            throw CacheValidationError.meshCacheExceedsLimits(
                bodyID: bodyID,
                exceeded,
                recorded: recordedUsage.amount(for: exceeded),
                limit: limits.limit(for: exceeded)
            )
        }
        try mesh.validate(tolerance: expectedTolerance)
    }
}
