import CADCore

extension SurfaceSilhouetteProvenanceEmitter {
    mutating func write(_ value: SurfaceParameter, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceParameter"), usage: &usage)
        try field("u", usage: &usage)
        try write(value.u, usage: &usage)
        try field("v", usage: &usage)
        try write(value.v, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: CoordinateEnclosure3D, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "CoordinateEnclosure3D"), usage: &usage)
        try field("x", usage: &usage)
        try write(value.x, usage: &usage)
        try field("y", usage: &usage)
        try write(value.y, usage: &usage)
        try field("z", usage: &usage)
        try write(value.z, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactAlgebraicParameterPair, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ExactAlgebraicParameterPair"), usage: &usage)
        try field("projectionRoot", usage: &usage)
        try write(value.projectionRoot, usage: &usage)
        try field("fiberRoot", usage: &usage)
        try write(value.fiberRoot, usage: &usage)
        try field("sourceDomain", usage: &usage)
        try write(value.sourceDomain, usage: &usage)
        try field("fiber", usage: &usage); try write(value.fiber, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactPolynomialParameterPoint, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ExactPolynomialParameterPoint"), usage: &usage)
        try field("u", usage: &usage)
        try write(value.u, usage: &usage)
        try field("v", usage: &usage)
        try write(value.v, usage: &usage)
        try field("parameter", usage: &usage)
        try write(value.parameter, usage: &usage)
        try field("originalDomain", usage: &usage)
        try write(value.originalDomain, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteSingularStation, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteSingularStation"), usage: &usage)
        try field("branchMultiplicity", usage: &usage)
        try write(value.branchMultiplicity, usage: &usage)
        try field("characteristicExponent", usage: &usage)
        try write(value.characteristicExponent, usage: &usage)
        try field("retainedHalfBranchCount", usage: &usage)
        try write(value.retainedHalfBranchCount, usage: &usage)
        try field("curveIndex", usage: &usage)
        try write(value.curveIndex, usage: &usage)
        try field("curveParameterEnclosure", usage: &usage)
        try write(value.curveParameterEnclosure, usage: &usage)
        try field("originalU", usage: &usage)
        try write(value.originalU, usage: &usage)
        try field("originalV", usage: &usage)
        try write(value.originalV, usage: &usage)
        try field("originalParameterEnclosure", usage: &usage)
        try write(value.originalParameterEnclosure, usage: &usage)
        try field("spatialEnclosure", usage: &usage)
        try write(value.spatialEnclosure, usage: &usage)
        try field("kind", usage: &usage)
        switch value.kind { case .cusp: try emit(.text("cusp"), usage: &usage) }
        try field("originalCurve", usage: &usage)
        try value.originalCurve.writeOriginalProvenance(to: &self, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouettePlaneAtlas, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouettePlaneAtlas"), usage: &usage)
        try field("surface", usage: &usage)
        try write(value.surface, usage: &usage)
        try field("view", usage: &usage)
        try write(value.view, usage: &usage)
        try field("originalDomain", usage: &usage)
        try write(value.originalDomain, usage: &usage)
        try field("curveIndices", usage: &usage)
        try emit(.beginArray(count: value.curveIndices.count), usage: &usage)
        for original in value.curveIndices { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("stations", usage: &usage)
        try emit(.beginArray(count: value.stations.count), usage: &usage)
        for original in value.stations { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouettePlaneAtlas.Station, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouettePlaneAtlas.Station"), usage: &usage)
        try field("originalContact", usage: &usage)
        try value.originalContact.writeOriginalProvenance(to: &self, usage: &usage)
        try field("incidentCurveIndices", usage: &usage)
        try emit(.beginArray(count: value.incidentCurveIndices.count), usage: &usage)
        for original in value.incidentCurveIndices { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("incidentAtUpperEnd", usage: &usage)
        try emit(.beginArray(count: value.incidentAtUpperEnd.count), usage: &usage)
        for original in value.incidentAtUpperEnd { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("regularGermCount", usage: &usage)
        try write(value.regularGermCount, usage: &usage)
        try field("isolatedGermCount", usage: &usage)
        try write(value.isolatedGermCount, usage: &usage)
        try field("sourceDepth", usage: &usage)
        try write(value.sourceDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteComponent, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteComponent"), usage: &usage)
        try field("curveIndices", usage: &usage)
        try emit(.beginArray(count: value.curveIndices.count), usage: &usage)
        for original in value.curveIndices { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("joins", usage: &usage)
        try emit(.beginArray(count: value.joins.count), usage: &usage)
        for original in value.joins { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("isClosed", usage: &usage)
        try write(value.isClosed, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteComponent.Join, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteComponent.Join"), usage: &usage)
        try field("kind", usage: &usage)
        switch value.kind {
        case .continuation: try emit(.text("continuation"), usage: &usage)
        case .transverseCrossing: try emit(.text("transverseCrossing"), usage: &usage)
        case .tangentContact: try emit(.text("tangentContact"), usage: &usage)
        case .cusp: try emit(.text("cusp"), usage: &usage)
        case .singularIntersection: try emit(.text("singularIntersection"), usage: &usage)
        }
        try field("firstCurve", usage: &usage)
        try write(value.firstCurve, usage: &usage)
        try field("firstAtUpperEnd", usage: &usage)
        try write(value.firstAtUpperEnd, usage: &usage)
        try field("secondCurve", usage: &usage)
        try write(value.secondCurve, usage: &usage)
        try field("secondAtUpperEnd", usage: &usage)
        try write(value.secondAtUpperEnd, usage: &usage)
        try field("periodic", usage: &usage)
        try write(value.periodic, usage: &usage)
        try field("branchContactOrder", usage: &usage)
        if let original = value.branchContactOrder { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("originalIntersectionMultiplicity", usage: &usage)
        if let original = value.originalIntersectionMultiplicity { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactBivariateCriticalPoint, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "originalCriticalPoint"), usage: &usage)
        try field("original", usage: &usage); try write(value.original, usage: &usage)
        try field("parameters", usage: &usage); try write(value.retainedOriginalParameters, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactAlgebraicFiberPolynomial, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "originalAlgebraicFiber"), usage: &usage)
        try field("root", usage: &usage); try write(value.root, usage: &usage)
        let count = value.coefficients.count
        try usage.consumeWork(try rationalAlgebraCount(count, max(1, count), multiply: true))
        try RationalAlgebraStorage.retain(count, of: (Int, ExactAlgebraicFieldElement).self, usage: &usage)
        let terms = value.coefficients.sorted { $0.key < $1.key }
        try field("terms", usage: &usage); try emit(.beginArray(count: count), usage: &usage)
        for (degree, coefficient) in terms {
            try emit(.beginRecord(type: "fiberCoefficient"), usage: &usage)
            try field("degree", usage: &usage); try write(degree, usage: &usage)
            try field("numerator", usage: &usage); try write(coefficient.numerator, usage: &usage)
            try field("denominator", usage: &usage); try write(coefficient.denominator, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
        try emit(.endArray, usage: &usage); try emit(.endRecord, usage: &usage)
    }
}
