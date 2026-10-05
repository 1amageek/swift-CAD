import CADCore
import CADGeometry

/// Original circular measurement and authored paper placement for one dimension stroke.
public struct DrawingRadialDimensionSource: Sendable {
    public let original: OriginalCircularMeasurement
    public let bodyID: BodyID?
    public let sourceFeatureID: FeatureID?
    public let sourceSketchEntityID: SketchEntityID?
    public let occurrenceIdentity: String?
    public let measurementIdentity: String
    public let identity: String
    public let kind: DrawingRadialDimensionKind
    public let frame: OrthographicProjectionFrame
    public let pointsPerMeter: Double
    public let translation: Point2D
    let accountingOwner: DrawingExchangeUsage

    public init(original: OriginalCircularMeasurement, bodyID: BodyID? = nil,
        sourceFeatureID: FeatureID? = nil, sourceSketchEntityID: SketchEntityID? = nil,
        occurrenceIdentity: String?, measurementIdentity: String, identity: String,
        kind: DrawingRadialDimensionKind, frame: OrthographicProjectionFrame,
        pointsPerMeter: Double, translation: Point2D,
        usage: inout DrawingExchangeUsage) throws {
        try usage.check()
        let isBodySource = bodyID != nil && sourceFeatureID == nil && sourceSketchEntityID == nil
        let isSketchSource = bodyID == nil && sourceFeatureID != nil && sourceSketchEntityID != nil
        guard isBodySource || isSketchSource else {
            throw ExportError.invalidMesh("Radial dimension requires one real body or original sketch feature/entity binding.")
        }
        guard !measurementIdentity.isEmpty, !identity.isEmpty,
            occurrenceIdentity == nil || occurrenceIdentity?.isEmpty == false,
            pointsPerMeter.isFinite, pointsPerMeter > 0,
            translation.x.isFinite, translation.y.isFinite,
            original.boundaryParameter.isFinite else {
            throw ExportError.invalidMesh("Radial dimension source lacks original identity or finite paper placement.")
        }
        var textBytes = 0
        for count in [measurementIdentity.utf8.count, identity.utf8.count, occurrenceIdentity?.utf8.count ?? 0] {
            let next = textBytes.addingReportingOverflow(count)
            guard !next.overflow else { throw ExportError.invalidMesh("Radial dimension identity size overflows.") }
            textBytes = next.partialValue
        }
        try usage.charge(entities: 1, work: textBytes)
        try usage.charge(bytes: MemoryLayout<Self>.stride)
        try usage.charge(bytes: textBytes)
        self.original = original; self.bodyID = bodyID
        self.sourceFeatureID = sourceFeatureID; self.sourceSketchEntityID = sourceSketchEntityID
        self.occurrenceIdentity = occurrenceIdentity
        self.measurementIdentity = measurementIdentity; self.identity = identity; self.kind = kind
        self.frame = frame; self.pointsPerMeter = pointsPerMeter; self.translation = translation
        accountingOwner = usage
    }
}
