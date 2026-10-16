import CADCore
import CADGeometry

/// Original shared surface controls in native [v][u] order and assertions.
public struct OriginalSTEPSplineSurfaceSource: Equatable, Sendable {
    public let controlPointRows: [[OriginalSTEPPlacementElement]]
    public let surfaceForm: OriginalSTEPSplineSurfaceForm
    public let uClosed: OriginalSTEPLogical
    public let vClosed: OriginalSTEPLogical
    public let selfIntersect: OriginalSTEPLogical
    public let knotSpecification: OriginalSTEPSplineKnotSpecification
    public let isRational: Bool
    public init(controlPointRows: [[OriginalSTEPPlacementElement]], surfaceForm: OriginalSTEPSplineSurfaceForm,
        uClosed: OriginalSTEPLogical, vClosed: OriginalSTEPLogical, selfIntersect: OriginalSTEPLogical,
        knotSpecification: OriginalSTEPSplineKnotSpecification, isRational: Bool) {
        self.controlPointRows = controlPointRows; self.surfaceForm = surfaceForm
        self.uClosed = uClosed; self.vClosed = vClosed; self.selfIntersect = selfIntersect
        self.knotSpecification = knotSpecification; self.isRational = isRational
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPSplineSurfaceSource: Codable {
    private struct PointRow: Decodable {
        let elements: [OriginalSTEPPlacementElement]
        init(from decoder: Decoder) throws {
            elements = try OriginalSTEPPlacementDecoding.retainedArray(OriginalSTEPPlacementElement.self, from: decoder)
        }
    }
    private enum Keys: String, CodingKey { case controlPointRows, surfaceForm, uClosed, vClosed, selfIntersect, knotSpecification, isRational }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 7)
        let c = try decoder.container(keyedBy: Keys.self)
        try c.validateOnlyExpectedKeys([.controlPointRows, .surfaceForm, .uClosed, .vClosed, .selfIntersect, .knotSpecification, .isRational], in: decoder)
        let rows = try OriginalSTEPPlacementDecoding.retainedArray(PointRow.self,
            from: c.superDecoder(forKey: .controlPointRows))
        // The admitted PointRow and destination array each contain one immutable array owner per row.
        var allowance = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let bytes = rows.count.multipliedReportingOverflow(by: MemoryLayout<[OriginalSTEPPlacementElement]>.stride)
        guard !bytes.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original spline row storage overflow.") }
        try RationalAlgebraStorage.retain(bytes.partialValue / MemoryLayout<UInt32>.stride + (bytes.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1), of: UInt32.self, usage: &allowance)
        var originalRows: [[OriginalSTEPPlacementElement]] = []; originalRows.reserveCapacity(rows.count)
        for row in rows { try allowance.consumeWork(1); originalRows.append(row.elements) }
        controlPointRows = originalRows
        surfaceForm = try c.decode(OriginalSTEPSplineSurfaceForm.self, forKey: .surfaceForm)
        uClosed = try c.decode(OriginalSTEPLogical.self, forKey: .uClosed); vClosed = try c.decode(OriginalSTEPLogical.self, forKey: .vClosed)
        selfIntersect = try c.decode(OriginalSTEPLogical.self, forKey: .selfIntersect)
        knotSpecification = try c.decode(OriginalSTEPSplineKnotSpecification.self, forKey: .knotSpecification)
        isRational = try c.decode(Bool.self, forKey: .isRational)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(controlPointRows, forKey: .controlPointRows); try c.encode(surfaceForm, forKey: .surfaceForm)
        try c.encode(uClosed, forKey: .uClosed); try c.encode(vClosed, forKey: .vClosed)
        try c.encode(selfIntersect, forKey: .selfIntersect); try c.encode(knotSpecification, forKey: .knotSpecification)
        try c.encode(isRational, forKey: .isRational)
    }
}
#endif
