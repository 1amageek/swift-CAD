import CADCore

/// Generated connector retaining original section endpoint expressions.
public struct OriginalEndpointConnectorCurve3D: Hashable, Sendable {
    public let construction: BSplineCurve3D
    public let startBoundary: OriginalCurveRootSpan3D
    public let startAtEnd: Bool
    public let endBoundary: OriginalCurveRootSpan3D
    public let endAtEnd: Bool
    public let correctionBasis: OriginalEndpointCorrectionBasis
    private let preparedConstruction: OriginalCurveRootSpan3D
    private let originalStart: IntervalVector3DBounds
    private let originalEnd: IntervalVector3DBounds
    private let constructionStart: IntervalVector3DBounds
    private let constructionEnd: IntervalVector3DBounds
    private let preparedMaximumSpanCount: Int

    public init<B: RationalAlgebraAdmitting>(construction: BSplineCurve3D,
        startBoundary: OriginalCurveRootSpan3D, startAtEnd: Bool,
        endBoundary: OriginalCurveRootSpan3D, endAtEnd: Bool,
        correctionBasis: OriginalEndpointCorrectionBasis,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        guard construction.domain == .closed(0, 1), !construction.isPeriodic,
            startBoundary.certificationTolerance == tolerance,
            endBoundary.certificationTolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Original endpoint connectors require one normalized construction and original tolerance.")
        }
        try RationalAlgebraStorage.retain(1, of: OriginalCurveRootSpan3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: IntervalVector3DBounds.self, usage: &usage)
        let prepared = try OriginalCurveRootSpan3D(source: .bSpline(construction),
            start: .authored(0), end: .authored(1), maximumParameterWidth: tolerance.relative,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance,
            storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
            maximumSpanCount: maximumSpanCount, remainingSourceDepth: 0)
        func position(_ source: OriginalCurveRootSpan3D, atEnd: Bool) throws -> IntervalVector3DBounds {
            let station = atEnd ? 1.0 : 0.0
            let jet = try source.intervalTaylorJet(over: .init(lower: station, upper: station),
                throughOrder: 0, tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride,
                usage: &usage, maximumSpanCount: maximumSpanCount, remainingSourceDepth: source.remainingSourceDepth)
            return try .init(x: jet.x.coefficient(0, 0), y: jet.y.coefficient(0, 0), z: jet.z.coefficient(0, 0))
        }
        originalStart = try position(startBoundary, atEnd: startAtEnd)
        originalEnd = try position(endBoundary, atEnd: endAtEnd)
        constructionStart = try position(prepared, atEnd: false)
        constructionEnd = try position(prepared, atEnd: true)
        self.construction = construction
        self.startBoundary = startBoundary; self.startAtEnd = startAtEnd
        self.endBoundary = endBoundary; self.endAtEnd = endAtEnd
        self.correctionBasis = correctionBasis; preparedConstruction = prepared
        preparedMaximumSpanCount = maximumSpanCount
    }

    public var domain: ParameterDomain { .closed(0, 1) }
    public var certificationTolerance: ModelingTolerance { startBoundary.certificationTolerance }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original endpoint connector queries require their preparation tolerance.")
        }
    }

    package var constructionTraversal: OriginalCurveRootSpan3D { preparedConstruction }
    package var maximumSpanCount: Int { preparedMaximumSpanCount }
    package var maximumSubdivisionDepth: Int { preparedConstruction.maximumSubdivisionDepth }

    package func originalEndpoint(at parameter: Double) -> (boundary: OriginalCurveRootSpan3D, atEnd: Bool)? {
        if parameter == 0 { return (startBoundary, startAtEnd) }
        if parameter == 1 { return (endBoundary, endAtEnd) }
        return nil
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.construction == b.construction && a.startBoundary == b.startBoundary && a.startAtEnd == b.startAtEnd
            && a.endBoundary == b.endBoundary && a.endAtEnd == b.endAtEnd && a.correctionBasis == b.correctionBasis
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(construction); hasher.combine(startBoundary); hasher.combine(startAtEnd)
        hasher.combine(endBoundary); hasher.combine(endAtEnd); hasher.combine(correctionBasis)
    }

    package func intervalTaylorJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try validate(tolerance: tolerance)
        guard order >= 0, parameters.lower >= 0, parameters.upper <= 1,
            maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original connector query requires its closed normalized domain and nonnegative caps.")
        }
        let original = try preparedConstruction.intervalTaylorJet(over: parameters, throughOrder: order,
            tolerance: tolerance, consumeWork: consumeWork, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: 0, consumeStorage: consumeStorage)
        let h1 = try correctionJet(over: parameters, throughOrder: order,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        func coordinate(_ q: SurfaceAreaIntervalTaylorScalarJet,
            start: OutwardScalarInterval, end: OutwardScalarInterval,
            candidateStart: OutwardScalarInterval, candidateEnd: OutwardScalarInterval)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            for _ in 0..<3 { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
            let firstCorrection = start - candidateStart
            let lastCorrection = end - candidateEnd
            let first = try SurfaceAreaIntervalTaylorScalarJet.constant(firstCorrection, order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            var result = try q.adding(first, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(h1.scaled(by: lastCorrection - firstCorrection,
                    consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
            // The source endpoint expression, not interval cancellation, owns value incidence.
            if parameters.lower == parameters.upper, parameters.lower == 0 {
                try consumeWork(); try result.set(start, 0, 0)
            } else if parameters.lower == parameters.upper, parameters.lower == 1 {
                try consumeWork(); try result.set(end, 0, 0)
            }
            return result
        }
        return try .init(x: coordinate(original.x, start: originalStart.x, end: originalEnd.x,
                candidateStart: constructionStart.x, candidateEnd: constructionEnd.x),
            y: coordinate(original.y, start: originalStart.y, end: originalEnd.y,
                candidateStart: constructionStart.y, candidateEnd: constructionEnd.y),
            z: coordinate(original.z, start: originalStart.z, end: originalEnd.z,
                candidateStart: constructionStart.z, candidateEnd: constructionEnd.z))
    }

    private func correctionJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorScalarJet {
        try OriginalEndpointCorrectionTaylor.jet(basis: correctionBasis, over: parameters,
            throughOrder: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    package func preparedFirstOrder(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> OriginalCurveFirstOrderJet {
        try validate(tolerance: tolerance)
        guard parameters.lower >= 0, parameters.upper <= 1, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original connector first-order query requires its normalized source domain.")
        }
        let original = try preparedConstruction.preparedFirstOrder(over: parameters,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: 0,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        let h1 = try correctionJet(over: parameters, throughOrder: 1,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let h = try h1.coefficient(0, 0), dh = try h1.coefficient(1, 0)
        func axis(_ position: OutwardScalarInterval, _ derivative: OutwardScalarInterval,
            _ start: OutwardScalarInterval, _ end: OutwardScalarInterval,
            _ candidateStart: OutwardScalarInterval, _ candidateEnd: OutwardScalarInterval)
            throws -> (OutwardScalarInterval, OutwardScalarInterval) {
            for _ in 0..<8 { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
            let first = start - candidateStart, delta = end - candidateEnd - first
            var value = position + first + delta * h
            if parameters.lower == parameters.upper, parameters.lower == 0 { value = start }
            else if parameters.lower == parameters.upper, parameters.lower == 1 { value = end }
            return (value, derivative + delta * dh)
        }
        let x = try axis(original.position.x, original.firstDerivative.x, originalStart.x,
            originalEnd.x, constructionStart.x, constructionEnd.x)
        let y = try axis(original.position.y, original.firstDerivative.y, originalStart.y,
            originalEnd.y, constructionStart.y, constructionEnd.y)
        let z = try axis(original.position.z, original.firstDerivative.z, originalStart.z,
            originalEnd.z, constructionStart.z, constructionEnd.z)
        return .init(position: .init(x: x.0, y: y.0, z: z.0),
            firstDerivative: .init(x: x.1, y: y.1, z: z.1))
    }

    package func correctedOwningSpans(from original: PreparedCurveDifferentialEncloser.ClosedNativeJet,
        tolerance: ModelingTolerance, maximumSpanCount: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> [PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan] {
        try validate(tolerance: tolerance)
        try GeometryStructuralComparisonWork.charge(curve: .bSpline(construction), using: { count in
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
        })
        try GeometryStructuralComparisonWork.charge(curve: original.source, using: { count in
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
        })
        guard original.source == .bSpline(construction), original.tolerance == tolerance,
            !original.spans.isEmpty, original.parameters.lower >= 0, original.parameters.upper <= 1,
            original.spans.count <= maximumSpanCount, original.spans.count <= preparedMaximumSpanCount else {
            throw GeometryConversionError.invalidInput("Original connector owning jets require their exact retained construction receipt.")
        }
        try OriginalCoefficientAllocation.reserve(count: original.spans.count,
            of: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan.self, consumeStorage: consumeStorage)
        var result: [PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan] = []
        result.reserveCapacity(original.spans.count)
        for owner in original.spans {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            guard owner.parameters.lower >= original.parameters.lower,
                owner.parameters.upper <= original.parameters.upper else {
                throw GeometryConversionError.invalidInput("Original connector owner leaves its retained query parameters.")
            }
            let h = try correctionJet(over: owner.parameters, throughOrder: 3,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let value = try h.coefficient(0, 0), first = try h.coefficient(1, 0)
            let second = try h.coefficient(2, 0) * .exact(2), third = try h.coefficient(3, 0) * .exact(6)
            func axis(_ q: SurfaceIntervalJet, _ start: OutwardScalarInterval,
                _ end: OutwardScalarInterval, _ candidateStart: OutwardScalarInterval,
                _ candidateEnd: OutwardScalarInterval) throws -> SurfaceIntervalJet {
                for _ in 0..<12 { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
                let offset = start - candidateStart, gain = end - candidateEnd - offset
                var position = q.value + offset + gain * value
                if owner.parameters.lower == owner.parameters.upper, owner.parameters.lower == 0 { position = start }
                else if owner.parameters.lower == owner.parameters.upper, owner.parameters.lower == 1 { position = end }
                let zero = OutwardScalarInterval.exact(0)
                return .init(value: position, derivativeU: q.derivativeU + gain * first, derivativeV: zero,
                    secondDerivativeUU: q.secondDerivativeUU + gain * second,
                    secondDerivativeUV: zero, secondDerivativeVV: zero,
                    thirdDerivativeUUU: q.thirdDerivativeUUU + gain * third,
                    thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
            }
            let jet = try SurfaceIntervalVectorJet(
                x: axis(owner.jet.x, originalStart.x, originalEnd.x, constructionStart.x, constructionEnd.x),
                y: axis(owner.jet.y, originalStart.y, originalEnd.y, constructionStart.y, constructionEnd.y),
                z: axis(owner.jet.z, originalStart.z, originalEnd.z, constructionStart.z, constructionEnd.z))
            result.append(.init(nativeIndex: owner.nativeIndex, nativeDomain: owner.nativeDomain,
                parameters: owner.parameters, jet: jet, originalPeriodicCycle: owner.originalPeriodicCycle,
                originalSurfaceSpan: owner.originalSurfaceSpan,
                originalSurfaceParameters: owner.originalSurfaceParameters,
                originalIsoTraversal: owner.originalIsoTraversal))
        }
        return result
    }

    package func derivatives(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> IntervalVectorDerivativeJet {
        let original = try intervalTaylorJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let count = order.addingReportingOverflow(1)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original connector derivative dimensions overflow.") }
        func axis(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            try OriginalCoefficientAllocation.reserve(count: count.partialValue,
                of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
            var values: [OutwardScalarInterval] = []; values.reserveCapacity(count.partialValue)
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
                if k > 0 { factorial = factorial * .exact(Double(k)) }
                values.append(try q.coefficient(k, 0) * factorial)
            }
            return .init(derivatives: values)
        }
        return try .init(x: axis(original.x), y: axis(original.y), z: axis(original.z))
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let jet = try intervalTaylorJet(over: .init(lower: parameter, upper: parameter), throughOrder: 0,
            tolerance: tolerance, maximumSpanCount: preparedMaximumSpanCount, maximumSubdivisionDepth: preparedConstruction.maximumSubdivisionDepth,
            remainingSourceDepth: 0, consumeWork: {})
        let x = try jet.x.coefficient(0, 0), y = try jet.y.coefficient(0, 0), z = try jet.z.coefficient(0, 0)
        let point = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
        let error = IntervalVector3DBounds(x: x - .exact(point.x), y: y - .exact(point.y), z: z - .exact(point.z))
        guard error.lengthUpperBound <= tolerance.distance else { throw GeometryConversionError.toleranceRejected }
        return point
    }
}
