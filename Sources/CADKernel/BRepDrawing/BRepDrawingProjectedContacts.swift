import CADCore
import CADGeometry

/// Screen-incidence receipts, retaining exact native event expressions rather than visibility labels.
public struct BRepDrawingProjectedContacts: Sendable {
    public struct DepthContact: Sendable {
        public let original: SurfaceSilhouetteProjectedContact
        public let depthDifferenceSign: SurfaceSilhouetteProjectedContact.DepthDifferenceSign
    }
    public struct Entry: Sendable {
        public let projectedUseOrdinal: Int
        public let silhouetteSetOrdinal: Int
        public let silhouetteSpanOrdinal: Int
        public let usesExactTrimmedSpan: Bool
        public let partition: SurfaceSilhouetteProjectedPartition
        public let depthContacts: [DepthContact]
    }
    public struct Sector: Sendable {
        public let lower: SurfaceSilhouetteTrimEndpoint
        public let upper: SurfaceSilhouetteTrimEndpoint
        public let originalInteriorWitness: ExactRationalCoefficient
    }
    public struct Cell: Sendable {
        public let projectedUseOrdinal: Int
        public let originalSpanIndex: Int
        public let nativeRange: ScalarInterval
        public let partitionEntryRange: Range<Int>
        public let cuts: [SurfaceSilhouetteTrimEndpoint]
        public let silhouetteEventFreeSectors: [Sector]
        public let hasWholeRangeProjectedOverlap: Bool
    }
    public let projection: BRepDrawingPlacedProjection
    public let silhouettes: [BRepDrawingSilhouettes]
    public let entries: [Entry]
    public let cells: [Cell]

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try projection.validateCurrent(evaluated, using: &execution)
        for source in silhouettes { try source.validateCurrent(evaluated, using: &execution) }
    }
}
