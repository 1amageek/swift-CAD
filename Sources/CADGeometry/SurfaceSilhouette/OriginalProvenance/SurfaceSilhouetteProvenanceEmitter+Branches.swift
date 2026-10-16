import CADCore

extension SurfaceSilhouetteProvenanceEmitter {
    mutating func write(_ value: OriginalSingularFieldRoot, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "fieldRoot"), usage: &usage)
        try field("polynomial", usage: &usage); try write(value.polynomial, usage: &usage)
        try field("isolation", usage: &usage); try write(value.isolation, usage: &usage)
        try field("admissionDomain", usage: &usage)
        switch value.admissionDomain {
        case .parameter: try emit(.text("parameter"), usage: &usage)
        case .coefficient(let maximumDepth):
            try emit(.beginRecord(type: "coefficientAdmission"), usage: &usage)
            try field("maximumDepth", usage: &usage); try write(maximumDepth, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularResolution.Step.Direction, usage: inout OriginalQueryExecution) throws {
        switch value {
        case .vertical: try emit(.text("vertical"), usage: &usage)
        case .finite(let root):
            try emit(.beginRecord(type: "finiteTangent"), usage: &usage)
            try field("root", usage: &usage); try write(root, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
    }
    mutating func write(_ value: SurfaceSilhouetteRamifiedParameterImage.Identity, usage: inout OriginalQueryExecution) throws {
        switch value {
        case .rational(let original): try write(original, usage: &usage)
        case .field(let original): try write(original, usage: &usage)
        }
    }
    mutating func write(_ value: SurfaceSilhouetteAtlasEndpoint, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "rationalAtlasEndpoint"), usage: &usage)
        try field("original", usage: &usage); try write(value.original, usage: &usage)
        try field("location", usage: &usage)
        switch value.location {
        case .station(let root, let count):
            try emit(.beginRecord(type: "station"), usage: &usage)
            try field("root", usage: &usage); try write(root, usage: &usage)
            try field("completeHalfBranchCount", usage: &usage); try write(count, usage: &usage)
        case .fiber(let u, let root):
            try emit(.beginRecord(type: "fiber"), usage: &usage)
            try field("u", usage: &usage); try write(u, usage: &usage)
            try field("v", usage: &usage); try write(root, usage: &usage)
        }
        try emit(.endRecord, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteFieldAtlasEndpoint, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "fieldAtlasEndpoint"), usage: &usage)
        try field("original", usage: &usage); try write(value.original, usage: &usage)
        try field("completeIncidenceCount", usage: &usage); try write(value.completeIncidenceCount, usage: &usage)
        try field("location", usage: &usage)
        switch value.location {
        case .station(let root, let count):
            try emit(.beginRecord(type: "station"), usage: &usage)
            try field("root", usage: &usage); try write(root, usage: &usage)
            try field("completeHalfBranchCount", usage: &usage); try write(count, usage: &usage)
        case .fiber(let u, let root):
            try emit(.beginRecord(type: "fiber"), usage: &usage)
            try field("u", usage: &usage); try write(u, usage: &usage)
            try field("v", usage: &usage); try write(root, usage: &usage)
        }
        try emit(.endRecord, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "nativeSurfaceSpan"), usage: &usage)
        try field("source", usage: &usage); try write(Surface3D.bSpline(value.surface), usage: &usage)
        try field("uSpanIndex", usage: &usage); try write(value.uSpanIndex, usage: &usage)
        try field("vSpanIndex", usage: &usage); try write(value.vSpanIndex, usage: &usage)
        try field("uBounds", usage: &usage); try write(value.uBounds, usage: &usage)
        try field("vBounds", usage: &usage); try write(value.vBounds, usage: &usage)
        try field("uCycle", usage: &usage); try write(value.uCycle, usage: &usage)
        try field("vCycle", usage: &usage); try write(value.vCycle, usage: &usage)
        try field("uTranslation", usage: &usage); try write(value.originalUTranslation, usage: &usage)
        try field("vTranslation", usage: &usage); try write(value.originalVTranslation, usage: &usage)
        try field("baseUBounds", usage: &usage); try write(value.originalBaseUBounds, usage: &usage)
        try field("baseVBounds", usage: &usage); try write(value.originalBaseVBounds, usage: &usage)
        try field("tolerance", usage: &usage); try write(value.tolerance, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalExactBSplinePoleNormal, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "originalPoleNormal"), usage: &usage)
        try field("span", usage: &usage); try write(value.span, usage: &usage)
        try field("direction", usage: &usage)
        try emit(.text(value.direction == .constantU ? "constantU" : "constantV"), usage: &usage)
        try field("factorOrder", usage: &usage); try write(value.factorOrder, usage: &usage)
        try field("coefficients", usage: &usage); try emit(.beginArray(count: value.coefficients.count), usage: &usage)
        for coefficient in value.coefficients { try write(coefficient, usage: &usage) }
        try emit(.endArray, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalFieldSurfaceNormalLaw, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "originalFieldNormal"), usage: &usage)
        try field("homogeneous", usage: &usage); try emit(.beginArray(count: value.originalHomogeneous.count), usage: &usage)
        for coefficient in value.originalHomogeneous { try write(coefficient, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("normal", usage: &usage); try emit(.beginArray(count: value.normalNumerators.count), usage: &usage)
        for coefficient in value.normalNumerators { try write(coefficient, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("silhouette", usage: &usage); try write(value.silhouette, usage: &usage)
        try field("view", usage: &usage); try write(value.view, usage: &usage)
        try field("maximumAlgebraicDepth", usage: &usage); try write(value.maximumAlgebraicDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalRationalSurfacePolynomial, usage: inout OriginalQueryExecution) throws {
        try emit(.beginRecord(type: "originalSurfacePolynomial"), usage: &usage)
        try field("source", usage: &usage); try write(Surface3D.bSpline(value.source), usage: &usage)
        try field("domain", usage: &usage); try write(value.domain, usage: &usage)
        try field("uSpanIndex", usage: &usage); try write(value.uSpanIndex, usage: &usage)
        try field("vSpanIndex", usage: &usage); try write(value.vSpanIndex, usage: &usage)
        try field("homogeneous", usage: &usage); try emit(.beginArray(count: value.homogeneous.count), usage: &usage)
        for coefficient in value.homogeneous { try write(coefficient, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("normal", usage: &usage); try emit(.beginArray(count: value.normalNumerators.count), usage: &usage)
        for coefficient in value.normalNumerators { try write(coefficient, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("silhouette", usage: &usage); try write(value.silhouetteNumerator, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
}

extension SurfaceSilhouetteProvenanceEmitter {
    mutating func write(_ value: SurfaceSilhouetteTrimEndpoint, usage: inout OriginalQueryExecution) throws {
        try value.writeOriginalProvenance(to: &self, usage: &usage)
    }
}
