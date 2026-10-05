import CADCore
import CADGeometry
import CADIR
import CADTopology

extension DocumentCaches {
  public func validateFreshness(
    for document: CADDocument,
    tolerance: ModelingTolerance,
    tessellationOptions: TessellationOptions = .standard,
    purpose: MeshArtifactPurpose = .unspecified,
    limits: TessellationLimits = .standard,
    kernelVersion: SchemaVersion = .current
  ) throws {
    try validateFreshness(for: document, tolerance: tolerance,
      tessellationOptions: tessellationOptions, purpose: purpose, limits: limits,
      kernelVersion: kernelVersion,
      encodingLimits: PortableSourceEncodingLimits(maximumBytes: Int.max,
        maximumWork: Int.max, maximumDepth: Int.max))
  }

  /// Compares original cached and regenerated content under one caller encoding allowance.
  public func validateFreshness(
    for document: CADDocument,
    tolerance: ModelingTolerance,
    tessellationOptions: TessellationOptions = .standard,
    purpose: MeshArtifactPurpose = .unspecified,
    limits: TessellationLimits = .standard,
    kernelVersion: SchemaVersion = .current,
    encodingLimits: PortableSourceEncodingLimits
  ) throws {
    var contentEncoder = try PortableSourceEncoder(limits: encodingLimits)
    try validateMetadataFreshness(
      for: document,
      tolerance: tolerance,
      tessellationOptions: tessellationOptions,
      purpose: purpose,
      limits: limits,
      kernelVersion: kernelVersion
    )

    let expectedEvaluation = try DocumentEvaluator(
      tolerance: tolerance,
      tessellationOptions: tessellationOptions,
      tessellationLimits: limits,
      meshArtifactPurpose: purpose
    ).evaluateWithoutCacheValidation(document)

    guard let brep else {
      throw CacheValidationError.missingBRepCache
    }
    try brep.model.validate(tolerance: tolerance)
    try expectedEvaluation.brep.validate(tolerance: tolerance)
    try contentEncoder.value(BRepCacheContentSource(model: brep.model))
    let cachedContent = contentEncoder.bytes
    // The first immutable stream remains retained across the next append. Charge
    // its COW storage before mutation; one accumulator owns both source traversals.
    try contentEncoder.charge(bytes: cachedContent.count, work: cachedContent.count)
    try contentEncoder.value(BRepCacheContentSource(model: expectedEvaluation.brep))
    let combinedContent = contentEncoder.bytes
    let expectedContent = combinedContent[cachedContent.count...]
    try contentEncoder.charge(work: min(cachedContent.count, expectedContent.count))
    guard cachedContent.elementsEqual(expectedContent) else {
      throw CacheValidationError.staleBRepCache(
        "B-rep cache content does not match evaluation of the source document."
      )
    }

    let cachedMeshesFromBRep = try MeshTessellator(
      tolerance: tolerance,
      limits: limits
    ).tessellate(
      model: brep.model,
      options: tessellationOptions
    )
    let cachedBodyIDs = Set(meshes.keys)
    let cachedBRepBodyIDs = Set(cachedMeshesFromBRep.keys)
    if let missingBodyID = cachedBRepBodyIDs.subtracting(cachedBodyIDs)
      .sorted(by: { $0.description < $1.description })
      .first
    {
      throw CacheValidationError.staleMeshCache(
        bodyID: missingBodyID,
        reason: "Mesh cache is missing a body generated from the B-rep cache."
      )
    }
    if let extraBodyID = cachedBodyIDs.subtracting(cachedBRepBodyIDs)
      .sorted(by: { $0.description < $1.description })
      .first
    {
      throw CacheValidationError.staleMeshCache(
        bodyID: extraBodyID,
        reason: "Mesh cache contains a body not generated from the B-rep cache."
      )
    }

    for bodyID in cachedBRepBodyIDs.sorted() {
      guard let cachedMesh = meshes[bodyID]?.mesh,
        let expectedMesh = cachedMeshesFromBRep[bodyID],
        cachedMesh == expectedMesh
      else {
        throw CacheValidationError.staleMeshCache(
          bodyID: bodyID,
          reason: "Mesh cache content does not match tessellation of the B-rep cache."
        )
      }
    }
    guard
      meshMultiset(meshes.values.map(\.mesh))
        == meshMultiset(Array(expectedEvaluation.meshes.values))
    else {
      throw CacheValidationError.staleBRepCache(
        "Cached geometry content does not match evaluation of the source document."
      )
    }
  }
}

private func meshMultiset(_ meshes: [Mesh]) -> [Mesh: Int] {
  var counts: [Mesh: Int] = [:]
  for mesh in meshes {
    counts[mesh, default: 0] += 1
  }
  return counts
}
