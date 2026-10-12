import CADCore

/// Exact source tuple and its source-bound L6 singleton witness.
public struct OriginalAngularPlaneExactPoint: Sendable {
    public typealias Original = OriginalAngularPlaneRelations<OriginalAnalyticCoordinateSnapshot,OriginalPlaneSnapshot>
    public let original: Original
    public let rootOrdinal: Int
    public let local: ExactGeometricGraphPoint<OriginalPiScalarDomain>
    public var parameter: OriginalPiValue { original.zeros.roots[rootOrdinal].parameter }
    public var phase: OriginalPiValue { original.zeros.roots[rootOrdinal].phase }
    public var childLabel: OriginalPiValue { original.zeros.roots[rootOrdinal].childLabel }
    public var position: [OriginalPiValue] { original.zeros.roots[rootOrdinal].position }
    public var derivative: [OriginalPiValue] { original.zeros.roots[rootOrdinal].derivative }
    public var uv: [OriginalPiValue] { original.decisions[rootOrdinal].uv }
    public var curveIncidents: [OriginalParameterTransport<OriginalAnalyticCoordinateSnapshot,OriginalPiScalarDomain>] {
        original.decisions[rootOrdinal].curveIncidents
    }
    public var planeIncidents: [OriginalParameterTransport<OriginalPlaneSnapshot,OriginalPiScalarDomain>] {
        original.decisions[rootOrdinal].planeIncidents
    }
    init(original:Original,rootOrdinal:Int,local:ExactGeometricGraphPoint<OriginalPiScalarDomain>) {
        self.original=original;self.rootOrdinal=rootOrdinal;self.local=local
    }
}
