import CADCore
import CADGeometry

/// Original shared curve controls and explicit standard spline assertions.
public struct OriginalSTEPSplineCurveSource: Equatable, Sendable {
    public let controlPoints: [OriginalSTEPPlacementElement]
    public let curveForm: OriginalSTEPSplineCurveForm
    public let closed: OriginalSTEPLogical
    public let selfIntersect: OriginalSTEPLogical
    public let knotSpecification: OriginalSTEPSplineKnotSpecification
    public let isRational: Bool
    public init(controlPoints: [OriginalSTEPPlacementElement], curveForm: OriginalSTEPSplineCurveForm,
        closed: OriginalSTEPLogical, selfIntersect: OriginalSTEPLogical,
        knotSpecification: OriginalSTEPSplineKnotSpecification, isRational: Bool) {
        self.controlPoints = controlPoints; self.curveForm = curveForm; self.closed = closed
        self.selfIntersect = selfIntersect; self.knotSpecification = knotSpecification; self.isRational = isRational
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPSplineCurveSource: Codable {
    private enum Keys: String, CodingKey { case controlPoints, curveForm, closed, selfIntersect, knotSpecification, isRational }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 6)
        let c = try decoder.container(keyedBy: Keys.self)
        try c.validateOnlyExpectedKeys([.controlPoints, .curveForm, .closed, .selfIntersect, .knotSpecification, .isRational], in: decoder)
        controlPoints = try OriginalSTEPPlacementDecoding.retainedArray(OriginalSTEPPlacementElement.self,
            from: c.superDecoder(forKey: .controlPoints))
        curveForm = try c.decode(OriginalSTEPSplineCurveForm.self, forKey: .curveForm)
        closed = try c.decode(OriginalSTEPLogical.self, forKey: .closed)
        selfIntersect = try c.decode(OriginalSTEPLogical.self, forKey: .selfIntersect)
        knotSpecification = try c.decode(OriginalSTEPSplineKnotSpecification.self, forKey: .knotSpecification)
        isRational = try c.decode(Bool.self, forKey: .isRational)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(controlPoints, forKey: .controlPoints); try c.encode(curveForm, forKey: .curveForm)
        try c.encode(closed, forKey: .closed); try c.encode(selfIntersect, forKey: .selfIntersect)
        try c.encode(knotSpecification, forKey: .knotSpecification); try c.encode(isRational, forKey: .isRational)
    }
}
#endif
