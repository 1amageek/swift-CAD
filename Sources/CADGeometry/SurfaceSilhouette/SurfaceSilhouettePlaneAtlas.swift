import CADCore

/// Complete original native plane-curve incidence retained by a drawing envelope.
public struct SurfaceSilhouettePlaneAtlas: Sendable {
    public struct Station: Sendable {
        public let originalContact: SurfaceSilhouetteAlgebraicContact
        public let incidentCurveIndices: [Int]
        public let incidentAtUpperEnd: [Bool]
        public let regularGermCount: Int
        public let isolatedGermCount: Int
        public let sourceDepth: Int

        public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
            usage: inout SurfaceSilhouetteUsage) throws {
            var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
            try emitter.write(self, usage: &usage)
        }

        /// Visits the upper's retained refinement and station with one reference namespace.
        /// The upper owns their actual issuer/refinement association; no bounds-based identity is inferred.
        public func writeOriginalProvenance(admittedContact: SurfaceSilhouetteAlgebraicContact,
            to sink: any SurfaceSilhouetteProvenanceWriting, usage: inout SurfaceSilhouetteUsage) throws {
            var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
            try emitter.emit(.beginRecord(type: "original-silhouette-admitted-atlas-station-v1"), usage: &usage)
            try emitter.field("originalStation", usage: &usage); try emitter.write(self, usage: &usage)
            try emitter.field("admittedContact", usage: &usage)
            try admittedContact.writeOriginalProvenance(to: &emitter, usage: &usage)
            try emitter.emit(.endRecord, usage: &usage)
        }
    }
    public let surface: Surface3D
    public let view: Vector3D
    public let originalDomain: SurfaceParameterBox
    public let curveIndices: [Int]
    public let stations: [Station]
    private enum Original: Sendable {
        case rational(OriginalRationalPlaneCurveAtlas)
        case field(OriginalFieldPlaneAtlas)
    }
    private let original: Original

    init(field: OriginalSurfaceSilhouetteField, original: OriginalRationalPlaneCurveAtlas,
        curveIndices: [Int], stations: [Station]) {
        surface = field.surface; view = field.view; originalDomain = original.projection.domain
        self.original = .rational(original); self.curveIndices = curveIndices; self.stations = stations
    }
    init(field: OriginalSurfaceSilhouetteField, original: OriginalFieldPlaneAtlas,
        curveIndices: [Int], stations: [Station]) {
        surface = field.surface; view = field.view; originalDomain = original.projection.domain
        self.original = .field(original); self.curveIndices = curveIndices; self.stations = stations
    }
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        usage: inout SurfaceSilhouetteUsage) throws {
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.write(self, usage: &usage)
    }

}
