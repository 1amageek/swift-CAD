import CADCore

/// Invocation-exclusive source framing; immutable field owners retain original sharing.
struct SurfaceSilhouetteProvenanceEmitter {
    let sink: any SurfaceSilhouetteProvenanceWriting
    private var contexts: [OriginalSingularFieldContext] = []
    init(sink: any SurfaceSilhouetteProvenanceWriting) { self.sink = sink }

    func emit(_ event: SurfaceSilhouetteProvenanceEvent, usage: inout SurfaceSilhouetteUsage) throws {
        try usage.consumeWork()
        try sink.write(event, usage: &usage)
    }
    func field(_ name: String, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.field(name), usage: &usage)
    }
    func write(_ value: Int, usage: inout SurfaceSilhouetteUsage) throws { try emit(.integer(value), usage: &usage) }
    func write(_ value: Bool, usage: inout SurfaceSilhouetteUsage) throws { try emit(.boolean(value), usage: &usage) }
    func write(_ value: Double, usage: inout SurfaceSilhouetteUsage) throws { try emit(.floatingBits(value.bitPattern), usage: &usage) }
    func write(_ value: Surface3D, usage: inout SurfaceSilhouetteUsage) throws { try emit(.surface(value), usage: &usage) }

    mutating func write(_ value: OriginalSingularFieldContext, usage: inout SurfaceSilhouetteUsage) throws {
        guard value.depth <= usage.maximumDepth, value.coefficientDepth <= usage.maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Retained provenance field exceeds the caller's independent depth caps.")
        }
        for index in contexts.indices {
            try usage.consumeWork()
            if contexts[index] === value {
                try emit(.beginRecord(type: "fieldReference"), usage: &usage)
                try field("id", usage: &usage); try write(index, usage: &usage)
                try emit(.endRecord, usage: &usage); return
            }
        }
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldContext.self, usage: &usage)
        let id = contexts.count; contexts.append(value)
        try emit(.beginRecord(type: "fieldDefinition"), usage: &usage)
        try field("id", usage: &usage); try write(id, usage: &usage)
        try field("parameterDepth", usage: &usage); try write(value.depth, usage: &usage)
        try field("coefficientDepth", usage: &usage); try write(value.coefficientDepth, usage: &usage)
        try field("source", usage: &usage)
        switch value.source {
        case .rational: try emit(.text("rational"), usage: &usage)
        case .original(let root): try write(root, usage: &usage)
        case .extended(let root): try write(root, usage: &usage)
        }
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldElement, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "fieldValue"), usage: &usage)
        try field("owner", usage: &usage); try write(value.context, usage: &usage)
        try field("law", usage: &usage)
        switch value.storage {
        case .original(let numerator, let denominator):
            try emit(.beginRecord(type: "originalQuotient"), usage: &usage)
            try field("numerator", usage: &usage); try write(numerator, usage: &usage)
            try field("denominator", usage: &usage); try write(denominator, usage: &usage)
        case .extended(let numerator, let denominator):
            try emit(.beginRecord(type: "extendedQuotient"), usage: &usage)
            try field("numerator", usage: &usage); try write(numerator, usage: &usage)
            try field("denominator", usage: &usage); try write(denominator, usage: &usage)
        }
        try emit(.endRecord, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactRationalCoefficient, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "rational"), usage: &usage)
        try field("sign", usage: &usage); try write(value.canonicalSign, usage: &usage)
        try field("numerator", usage: &usage)
        try usage.consumeWork(value.canonicalNumeratorWords.count)
        try emit(.unsignedWords(value.canonicalNumeratorWords), usage: &usage)
        try field("denominator", usage: &usage)
        try usage.consumeWork(value.canonicalDenominatorWords.count)
        try emit(.unsignedWords(value.canonicalDenominatorWords), usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactBivariatePolynomial, usage: inout SurfaceSilhouetteUsage) throws {
        let terms = try value.orderedTerms(usage: &usage)
        try emit(.beginRecord(type: "rationalPolynomial"), usage: &usage)
        try field("terms", usage: &usage); try emit(.beginArray(count: terms.count), usage: &usage)
        for (power, coefficient) in terms {
            try emit(.beginRecord(type: "monomial"), usage: &usage)
            try field("u", usage: &usage); try write(power.u, usage: &usage)
            try field("v", usage: &usage); try write(power.v, usage: &usage)
            try field("coefficient", usage: &usage); try write(coefficient, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
        try emit(.endArray, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldPlanePolynomial, usage: inout SurfaceSilhouetteUsage) throws {
        let terms = try value.orderedTerms(usage: &usage)
        try emit(.beginRecord(type: "fieldPlanePolynomial"), usage: &usage)
        try field("owner", usage: &usage); try write(value.context, usage: &usage)
        try field("terms", usage: &usage); try emit(.beginArray(count: terms.count), usage: &usage)
        for (power, coefficient) in terms {
            try emit(.beginRecord(type: "monomial"), usage: &usage)
            try field("u", usage: &usage); try write(power.u, usage: &usage)
            try field("v", usage: &usage); try write(power.v, usage: &usage)
            try field("coefficient", usage: &usage); try write(coefficient, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
        try emit(.endArray, usage: &usage); try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactBivariateSystemRoot, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "rationalSystemRoot"), usage: &usage)
        try field("equations", usage: &usage); try emit(.beginArray(count: value.equations.count), usage: &usage)
        for equation in value.equations { try write(equation, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("projection", usage: &usage); try write(value.projectionRoot, usage: &usage)
        try field("fiber", usage: &usage)
        let count = value.fiber.coefficients.count
        try usage.consumeWork(try rationalAlgebraCount(count, max(1, count), multiply: true))
        try RationalAlgebraStorage.retain(count, of: (Int, ExactAlgebraicFieldElement).self, usage: &usage)
        let terms = value.fiber.coefficients.sorted { $0.key < $1.key }
        try emit(.beginArray(count: count), usage: &usage)
        for (degree, coefficient) in terms {
            try emit(.beginRecord(type: "fiberCoefficient"), usage: &usage)
            try field("degree", usage: &usage); try write(degree, usage: &usage)
            try field("numerator", usage: &usage); try write(coefficient.numerator, usage: &usage)
            try field("denominator", usage: &usage); try write(coefficient.denominator, usage: &usage)
            try emit(.endRecord, usage: &usage)
        }
        try emit(.endArray, usage: &usage)
        try field("fiberIsolation", usage: &usage); try write(value.fiberRoot, usage: &usage)
        try field("domain", usage: &usage); try write(value.sourceDomain, usage: &usage)
        try field("projectionMultiplicity", usage: &usage); try write(value.projectionMultiplicity, usage: &usage)
        try field("fiberMultiplicity", usage: &usage); try write(value.fiberMultiplicity, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactMonotoneGraphEndpoint, usage: inout SurfaceSilhouetteUsage) throws {
        switch value {
        case .authored(let original):
            try emit(.beginRecord(type: "authoredEndpoint"), usage: &usage)
            try field("value", usage: &usage); try write(original, usage: &usage)
        case .algebraic(let root):
            try emit(.beginRecord(type: "algebraicEndpoint"), usage: &usage)
            try field("root", usage: &usage); try write(root, usage: &usage)
        }
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldEndpoint, usage: inout SurfaceSilhouetteUsage) throws {
        switch value {
        case .authored(let original):
            try emit(.beginRecord(type: "authoredEndpoint"), usage: &usage)
            try field("value", usage: &usage); try write(original, usage: &usage)
        case .algebraic(let root):
            try emit(.beginRecord(type: "fieldEndpoint"), usage: &usage)
            try field("root", usage: &usage); try write(root, usage: &usage)
        }
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ScalarInterval, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ScalarInterval"), usage: &usage)
        try field("lower", usage: &usage)
        try write(value.lower, usage: &usage)
        try field("upper", usage: &usage)
        try write(value.upper, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceParameterBox"), usage: &usage)
        try field("u", usage: &usage)
        try write(value.u, usage: &usage)
        try field("v", usage: &usage)
        try write(value.v, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: Vector3D, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "Vector3D"), usage: &usage)
        try field("x", usage: &usage)
        try write(value.x, usage: &usage)
        try field("y", usage: &usage)
        try write(value.y, usage: &usage)
        try field("z", usage: &usage)
        try write(value.z, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: Point3D, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "Point3D"), usage: &usage)
        try field("x", usage: &usage)
        try write(value.x, usage: &usage)
        try field("y", usage: &usage)
        try write(value.y, usage: &usage)
        try field("z", usage: &usage)
        try write(value.z, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ModelingTolerance, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ModelingTolerance"), usage: &usage)
        try field("distance", usage: &usage)
        try write(value.distance, usage: &usage)
        try field("angle", usage: &usage)
        try write(value.angle, usage: &usage)
        try field("relative", usage: &usage)
        try write(value.relative, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactAlgebraicRealRoot, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ExactAlgebraicRealRoot"), usage: &usage)
        try field("polynomial", usage: &usage)
        try write(value.polynomial, usage: &usage)
        try field("isolation", usage: &usage)
        try write(value.isolation, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactUnivariateRootIsolator.Root, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ExactUnivariateRootIsolator.Root"), usage: &usage)
        try field("lower", usage: &usage)
        try write(value.lower, usage: &usage)
        try field("upper", usage: &usage)
        try write(value.upper, usage: &usage)
        try field("isRationalStation", usage: &usage)
        try write(value.isRationalStation, usage: &usage)
        try field("isolationDepth", usage: &usage)
        try write(value.isolationDepth, usage: &usage)
        try field("excludesLowerEndpoint", usage: &usage)
        try write(value.excludesLowerEndpoint, usage: &usage)
        try field("excludesUpperEndpoint", usage: &usage)
        try write(value.excludesUpperEndpoint, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: ExactAlgebraicFiberRootIsolator.Root, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "ExactAlgebraicFiberRootIsolator.Root"), usage: &usage)
        try field("lower", usage: &usage)
        try write(value.lower, usage: &usage)
        try field("upper", usage: &usage)
        try write(value.upper, usage: &usage)
        try field("excludesLower", usage: &usage)
        try write(value.excludesLower, usage: &usage)
        try field("excludesUpper", usage: &usage)
        try write(value.excludesUpper, usage: &usage)
        try field("isolationDepth", usage: &usage)
        try write(value.isolationDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldRoot.Isolation, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularFieldRoot.Isolation"), usage: &usage)
        try field("lower", usage: &usage)
        try write(value.lower, usage: &usage)
        try field("upper", usage: &usage)
        try write(value.upper, usage: &usage)
        try field("excludesLower", usage: &usage)
        try write(value.excludesLower, usage: &usage)
        try field("excludesUpper", usage: &usage)
        try write(value.excludesUpper, usage: &usage)
        try field("depth", usage: &usage)
        try write(value.depth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldPolynomial, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularFieldPolynomial"), usage: &usage)
        try field("context", usage: &usage)
        try write(value.context, usage: &usage)
        try field("coefficients", usage: &usage)
        try emit(.beginArray(count: value.coefficients.count), usage: &usage)
        for original in value.coefficients { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldSystemRoot, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularFieldSystemRoot"), usage: &usage)
        try field("equations", usage: &usage)
        try emit(.beginArray(count: value.equations.count), usage: &usage)
        for original in value.equations { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("projectionRoot", usage: &usage)
        try write(value.projectionRoot, usage: &usage)
        try field("fiberRoot", usage: &usage)
        try write(value.fiberRoot, usage: &usage)
        try field("u", usage: &usage)
        try write(value.u, usage: &usage)
        try field("v", usage: &usage)
        try write(value.v, usage: &usage)
        try field("sourceDomain", usage: &usage)
        try write(value.sourceDomain, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularFieldValueIsolation, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularFieldValueIsolation"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("lower", usage: &usage)
        try write(value.lower, usage: &usage)
        try field("upper", usage: &usage)
        try write(value.upper, usage: &usage)
        try field("sourceDepth", usage: &usage)
        try write(value.sourceDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalRationalZeroSetAuthority, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalRationalZeroSetAuthority"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("repeatedFactor", usage: &usage)
        try write(value.repeatedFactor, usage: &usage)
        try field("squareFree", usage: &usage)
        try write(value.squareFree, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalFieldZeroSetAuthority, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalFieldZeroSetAuthority"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("repeatedFactor", usage: &usage)
        try write(value.repeatedFactor, usage: &usage)
        try field("squareFree", usage: &usage)
        try write(value.squareFree, usage: &usage)
        try field("maximumAlgebraicDepth", usage: &usage)
        try write(value.maximumAlgebraicDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalRationalBinomialCusp, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalRationalBinomialCusp"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("oddCoordinateAlongU", usage: &usage)
        try write(value.oddCoordinateAlongU, usage: &usage)
        try field("characteristicExponent", usage: &usage)
        try write(value.characteristicExponent, usage: &usage)
        try field("branchMultiplicity", usage: &usage)
        try write(value.branchMultiplicity, usage: &usage)
        try field("parameterExponent", usage: &usage)
        try write(value.parameterExponent, usage: &usage)
        try field("gain", usage: &usage)
        try write(value.gain, usage: &usage)
        try field("centerU", usage: &usage)
        try write(value.centerU, usage: &usage)
        try field("centerV", usage: &usage)
        try write(value.centerV, usage: &usage)
        try field("parameterPowerCoordinate", usage: &usage)
        try write(value.parameterPowerCoordinate, usage: &usage)
        try field("u", usage: &usage)
        try write(value.u, usage: &usage)
        try field("v", usage: &usage)
        try write(value.v, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalRationalBinomialBranches, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalRationalBinomialBranches"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("factors", usage: &usage)
        try emit(.beginArray(count: value.factors.count), usage: &usage)
        for original in value.factors { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("originalPower", usage: &usage)
        try write(value.originalPower, usage: &usage)
        try field("reducedUDegree", usage: &usage)
        try write(value.reducedUDegree, usage: &usage)
        try field("reducedVDegree", usage: &usage)
        try write(value.reducedVDegree, usage: &usage)
        try field("centerU", usage: &usage)
        try write(value.centerU, usage: &usage)
        try field("centerV", usage: &usage)
        try write(value.centerV, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularRegularChart, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularRegularChart"), usage: &usage)
        try field("germ", usage: &usage)
        try write(value.germ, usage: &usage)
        try field("localDomain", usage: &usage)
        try write(value.localDomain, usage: &usage)
        try field("freeAlongU", usage: &usage)
        try write(value.freeAlongU, usage: &usage)
        try field("sourceDepth", usage: &usage)
        try write(value.sourceDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularResolution.Germ, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularResolution.Germ"), usage: &usage)
        try field("strictTransform", usage: &usage)
        try write(value.strictTransform, usage: &usage)
        try field("originalU", usage: &usage)
        try write(value.originalU, usage: &usage)
        try field("originalV", usage: &usage)
        try write(value.originalV, usage: &usage)
        try field("steps", usage: &usage)
        try emit(.beginArray(count: value.steps.count), usage: &usage)
        for original in value.steps { try write(original, usage: &usage) }
        try emit(.endArray, usage: &usage)
        try field("freeAlongU", usage: &usage)
        try write(value.freeAlongU, usage: &usage)
        try field("depth", usage: &usage)
        try write(value.depth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularResolution.Step, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularResolution.Step"), usage: &usage)
        try field("direction", usage: &usage)
        try write(value.direction, usage: &usage)
        try field("tangentValue", usage: &usage)
        if let original = value.tangentValue { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("removedExceptionalOrder", usage: &usage)
        try write(value.removedExceptionalOrder, usage: &usage)
        try field("sourceDepth", usage: &usage)
        try write(value.sourceDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: OriginalSingularChartIdentity, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "OriginalSingularChartIdentity"), usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("station", usage: &usage)
        try write(value.station, usage: &usage)
        try field("germOrdinal", usage: &usage)
        try write(value.germOrdinal, usage: &usage)
        try field("spanOrdinal", usage: &usage)
        try write(value.spanOrdinal, usage: &usage)
        try field("localDomain", usage: &usage)
        try write(value.localDomain, usage: &usage)
        try field("sourceDomain", usage: &usage)
        try write(value.sourceDomain, usage: &usage)
        try field("start", usage: &usage)
        try write(value.start, usage: &usage)
        try field("end", usage: &usage)
        try write(value.end, usage: &usage)
        try field("originalAnchor", usage: &usage)
        if let original = value.originalAnchor { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("halfBranchSector", usage: &usage)
        try write(value.halfBranchSector, usage: &usage)
        try field("halfBranchOrdinal", usage: &usage)
        try write(value.halfBranchOrdinal, usage: &usage)
        try field("halfBranchSide", usage: &usage)
        try write(value.halfBranchSide, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteFieldChartIdentity, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteFieldChartIdentity"), usage: &usage)
        try field("owner", usage: &usage)
        try write(value.owner, usage: &usage)
        try field("localDomain", usage: &usage)
        try write(value.localDomain, usage: &usage)
        try field("sourceDomain", usage: &usage)
        try write(value.sourceDomain, usage: &usage)
        try field("germOrdinal", usage: &usage)
        try write(value.germOrdinal, usage: &usage)
        try field("sectorOrdinal", usage: &usage)
        try write(value.sectorOrdinal, usage: &usage)
        try field("branchOrdinal", usage: &usage)
        try write(value.branchOrdinal, usage: &usage)
        try field("upperSide", usage: &usage)
        try write(value.upperSide, usage: &usage)
        try field("anchor", usage: &usage)
        try write(value.anchor, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteFreeParameterImage, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteFreeParameterImage"), usage: &usage)
        try field("start", usage: &usage)
        try write(value.start, usage: &usage)
        try field("end", usage: &usage)
        try write(value.end, usage: &usage)
        try field("normalizedDomain", usage: &usage)
        try write(value.normalizedDomain, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteOrderedFreeParameterImage, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteOrderedFreeParameterImage"), usage: &usage)
        try field("start", usage: &usage)
        try write(value.start, usage: &usage)
        try field("end", usage: &usage)
        try write(value.end, usage: &usage)
        try field("gain", usage: &usage)
        try write(value.gain, usage: &usage)
        try field("gainIsolation", usage: &usage)
        if let original = value.gainIsolation { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("width", usage: &usage)
        try write(value.width, usage: &usage)
        try field("sourceDepth", usage: &usage)
        try write(value.sourceDepth, usage: &usage)
        try field("normalizedDomain", usage: &usage)
        try write(value.normalizedDomain, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteCuspParameterImage, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteCuspParameterImage"), usage: &usage)
        try field("cusp", usage: &usage)
        try write(value.cusp, usage: &usage)
        try field("nativeCover", usage: &usage)
        try write(value.nativeCover, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
    mutating func write(_ value: SurfaceSilhouetteRamifiedParameterImage, usage: inout SurfaceSilhouetteUsage) throws {
        try emit(.beginRecord(type: "SurfaceSilhouetteRamifiedParameterImage"), usage: &usage)
        try field("identity", usage: &usage)
        try write(value.identity, usage: &usage)
        try field("original", usage: &usage)
        try write(value.original, usage: &usage)
        try field("sourceDomain", usage: &usage)
        try write(value.sourceDomain, usage: &usage)
        try field("start", usage: &usage)
        try write(value.start, usage: &usage)
        try field("end", usage: &usage)
        try write(value.end, usage: &usage)
        try field("retainedStart", usage: &usage)
        if let original = value.retainedStart { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("retainedEnd", usage: &usage)
        if let original = value.retainedEnd { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("originAtUpperEnd", usage: &usage)
        if let original = value.originAtUpperEnd { try write(original, usage: &usage) }
        else { try emit(.null, usage: &usage) }
        try field("normalizedDomain", usage: &usage)
        try write(value.normalizedDomain, usage: &usage)
        try field("coefficientWidth", usage: &usage)
        try write(value.coefficientWidth, usage: &usage)
        try field("refinementDepth", usage: &usage)
        try write(value.refinementDepth, usage: &usage)
        try emit(.endRecord, usage: &usage)
    }
}
