import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public protocol BRepFacePatchExtracting: Sendable {
    func extract(
        bodyID: BodyID,
        featureID: FeatureID,
        from model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingExtraction
    func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepSewingExtraction
}

extension BRepFacePatchExtracting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected ordinary-only extractors have no direct witness.
    // Production admitted extraction must fail until the provider passes the caller execution
    // through source patch construction and request validation; ordinary fallback is not success.
    public func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepSewingExtraction {
        throw KernelError(phase: .topology, code: .unsupportedCapability, featureID: featureID,
            tolerance: tolerance, message: "Face-patch extractor has no direct execution implementation.")
    }
}
