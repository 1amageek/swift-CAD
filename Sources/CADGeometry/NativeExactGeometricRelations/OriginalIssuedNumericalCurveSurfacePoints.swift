/// Exact authored tuple groups behind ordinary numerical representatives.
public struct OriginalIssuedNumericalCurveSurfacePoints: Sendable {
    public let geometry: any OriginalIssuedGeometricRelationReading
    /// Six values per exact point: original T, surface U/V, and XYZ.
    public let coordinates: ExactOriginalScalarTransferReceipt
    public let incidenceOrdinals: [Int]
    public let incidenceRanges: [Range<Int>]
    public var count: Int { incidenceRanges.count }

    init(geometry: any OriginalIssuedGeometricRelationReading,coordinates: ExactOriginalScalarTransferReceipt,
        incidenceOrdinals: [Int],incidenceRanges: [Range<Int>]) {
        self.geometry=geometry;self.coordinates=coordinates
        self.incidenceOrdinals=incidenceOrdinals;self.incidenceRanges=incidenceRanges
    }
}
