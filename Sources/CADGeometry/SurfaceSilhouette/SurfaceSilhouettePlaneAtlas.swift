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
            using execution: inout OriginalQueryExecution) throws {
        try originalContact.queryContext.withExecution(using: &execution) { execution in
            var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
            try emitter.write(self, usage: &execution)
        
        }
    }

        /// Visits the upper's retained refinement and station with one reference namespace.
        /// The upper owns their actual issuer/refinement association; no bounds-based identity is inferred.
        public func writeOriginalProvenance(admittedContact: SurfaceSilhouetteAlgebraicContact,
            to sink: any SurfaceSilhouetteProvenanceWriting, using execution: inout OriginalQueryExecution) throws {
        try originalContact.queryContext.withExecution(using: &execution) { execution in
            var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
            try emitter.emit(.beginRecord(type: "original-silhouette-admitted-atlas-station-v1"), usage: &execution)
            try emitter.field("originalStation", usage: &execution); try emitter.write(self, usage: &execution)
            try emitter.field("admittedContact", usage: &execution)
            try admittedContact.writeOriginalProvenance(to: &emitter, usage: &execution)
            try emitter.emit(.endRecord, usage: &execution)
        
        }
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
    private let queryContext: SurfaceSilhouetteQueryContext
    private let original: Original

    init(field: OriginalSurfaceSilhouetteField, original: OriginalRationalPlaneCurveAtlas,
        curveIndices: [Int], stations: [Station]) {
        queryContext = field.queryContext
        surface = field.surface; view = field.view; originalDomain = original.projection.domain
        self.original = .rational(original); self.curveIndices = curveIndices; self.stations = stations
    }
    init(field: OriginalSurfaceSilhouetteField, original: OriginalFieldPlaneAtlas,
        curveIndices: [Int], stations: [Station]) {
        queryContext = field.queryContext
        surface = field.surface; view = field.view; originalDomain = original.projection.domain
        self.original = .field(original); self.curveIndices = curveIndices; self.stations = stations
    }
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        using execution: inout OriginalQueryExecution) throws {
        try queryContext.withExecution(using: &execution) { execution in
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.write(self, usage: &execution)
    
        }
    }

}
