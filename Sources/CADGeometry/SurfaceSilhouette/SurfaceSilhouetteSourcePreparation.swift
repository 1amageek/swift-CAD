import CADCore

/// Original source reduction with chart-preserving authority and retained offset law.
struct SurfaceSilhouetteSourcePreparation: Sendable {
    let source: Surface3D
    let nativeSource: BSplineSurface3D?
    let offsetDistances: [Double]
    let nativeWordImages: [OriginalAffineWordSurface3D]
    let nativeTolerance: ModelingTolerance

    init(original: Surface3D, tolerance: ModelingTolerance,
         usage: inout OriginalQueryExecution) throws {
        var current = original
        var distances: [Double] = []
        var depth = 0
        while case let .procedural(.offset(offset)) = current {
            depth = try rationalAlgebraCount(depth, 1)
            try usage.visitSilhouetteSource(depth: depth)
            if offset.distance != 0 {
                try RationalAlgebraStorage.retain(1, of: Double.self, usage: &usage)
                distances.append(offset.distance)
            }
            current = offset.source
        }
        // Admit the complete source chain before the existing recursive exact
        // chart reducer inspects it. Do not repeat that full scan per layer.
        if case let .procedural(.offset(offset)) = original {
            try GeometryStructuralComparisonWork.charge(surface: original, using: &usage)
            if let equivalent = try offset.exactChartPreservingSurface(tolerance: tolerance) {
                current = equivalent
                distances.removeAll(keepingCapacity: false)
            }
        }
        source = current
        var nativeCandidate = current
        var localTolerance = tolerance
        var images: [OriginalAffineWordSurface3D] = []
        // Outer Euclidean offsets are not commuted through a nonuniform word.
        // Their general requested-order path retains the original composition.
        if distances.isEmpty {
            while case let .procedural(.originalAffineWord(image)) = nativeCandidate {
                depth = try rationalAlgebraCount(depth, 1)
                try usage.visitSilhouetteSource(depth: depth)
                localTolerance = try image.sourceCalculationTolerance(tolerance: localTolerance, using: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalAffineWordSurface3D.self, usage: &usage)
                images.append(image); nativeCandidate = image.source
            }
        }
        nativeWordImages = images; nativeTolerance = localTolerance
        if case let .bSpline(native) = nativeCandidate { nativeSource = native }
        else if case let .procedural(.ruled(ruled)) = nativeCandidate {
            try GeometryStructuralComparisonWork.charge(surface: nativeCandidate, using: &usage)
            // Reuse the existing original same-denominator tensor authority and
            // its unchanged finite control ceiling. The rows retain both original
            // rail buffers; no degree, weights, parameter or control is fitted.
            try RationalAlgebraStorage.retain(4, of: UInt32.self, usage: &usage)
            nativeSource = try SurfaceAreaRuledTensorAuthority(original: ruled,
                maximumControlPointCount: 1_048_576, tolerance: localTolerance, using: &usage)?.tensor
        } else { nativeSource = nil }
        distances.reverse()
        offsetDistances = distances
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout OriginalQueryExecution) throws {
        try emitter.emit(.beginRecord(type: "sourcePreparation"), usage: &usage)
        try emitter.field("source", usage: &usage); try emitter.write(source, usage: &usage)
        try emitter.field("nativeSource", usage: &usage)
        if let nativeSource { try emitter.write(Surface3D.bSpline(nativeSource), usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("offsetDistances", usage: &usage)
        try emitter.emit(.beginArray(count: offsetDistances.count), usage: &usage)
        for distance in offsetDistances { try emitter.write(distance, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("nativeWordImages", usage: &usage)
        try emitter.emit(.beginArray(count: nativeWordImages.count), usage: &usage)
        for image in nativeWordImages { try emitter.write(Surface3D.procedural(.originalAffineWord(image)), usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("nativeTolerance", usage: &usage); try emitter.write(nativeTolerance, usage: &usage)
        try emitter.emit(.endRecord, usage: &usage)
    }

}
