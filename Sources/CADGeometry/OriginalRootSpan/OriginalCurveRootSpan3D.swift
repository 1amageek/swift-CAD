import CADCore

/// Original normalized traversal with exact authored or algebraic endpoint authority.
public struct OriginalCurveRootSpan3D: Hashable, Sendable {
    public let source: Curve3D
    public let nativeSpanIndex: Int?
    public let start: OriginalCurveRootEndpoint
    public let end: OriginalCurveRootEndpoint
    public let certificationTolerance: ModelingTolerance
    private let preparedStart: ScalarInterval
    private let preparedEnd: ScalarInterval
    private let preparedSlope: OutwardScalarInterval
    private let preparedNativeSpan: RationalBezierCurveJetEncloser.NativeSpan?
    private let preparedWholeTraversal: PreparedCurveDifferentialEncloser?
    private let preparedMaximumSpanCount: Int
    private let preparedRemainingSourceDepth: Int
    private let preparedMaximumSubdivisionDepth: Int
    private let preparedMaximumAlgebraicDepth: Int
    package var maximumSpanCount: Int { preparedMaximumSpanCount }
    package var maximumSubdivisionDepth: Int { preparedMaximumSubdivisionDepth }
    package var maximumAlgebraicDepth: Int { preparedMaximumAlgebraicDepth }
    package var remainingSourceDepth: Int { preparedRemainingSourceDepth }

    private struct ScopedAdmission: RationalAlgebraAdmitting {
        let work: (Int) throws -> Void
        let storage: (Int) throws -> Void
        let cell: (Int) throws -> Void
        let coefficientCell: (Int) throws -> Void
        mutating func consumeExactWork(_ count: Int) throws { try work(count) }
        mutating func retainExactStorage(_ count: Int) throws { try storage(count) }
        mutating func visitExactCell(depth: Int) throws { try cell(depth) }
        mutating func visitCoefficientCell(depth: Int) throws { try coefficientCell(depth) }
    }

    /// Admits actual preparation bytes through the composing storage slot unit.
    public init<B: RationalAlgebraAdmitting>(source: Curve3D,
        start: OriginalCurveRootEndpoint, end: OriginalCurveRootEndpoint, nativeSpanIndex: Int? = nil,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, storageByteStride: Int, usage: inout B,
        maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max,
        maximumAlgebraicDepth: Int? = nil) throws {
        guard storageByteStride > 0 else {
            throw GeometryConversionError.invalidInput("Original preparation storage slot stride must be positive.")
        }
        var caller = usage
        defer { usage = caller }
        func work(_ count: Int) throws { try caller.consumeExactWork(count) }
        func retained(_ count: Int) throws { try caller.retainExactStorage(count) }
        func cell(_ depth: Int) throws { try caller.visitExactCell(depth: depth) }
        func coefficientCell(_ depth: Int) throws { try caller.visitCoefficientCell(depth: depth) }
        func bytes(_ count: Int) throws {
            let rounded = count.addingReportingOverflow(storageByteStride - 1)
            guard count >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original preparation byte conversion overflows.")
            }
            try caller.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        self = try withoutActuallyEscaping(work) { work in
            try withoutActuallyEscaping(retained) { storage in
                try withoutActuallyEscaping(cell) { cell in
                    try withoutActuallyEscaping(bytes) { bytes in
                        return try withoutActuallyEscaping(coefficientCell) { coefficientCell in
                        var admission = ScopedAdmission(work: work, storage: storage, cell: cell, coefficientCell: coefficientCell)
                        return try Self(source: source, start: start, end: end, nativeSpanIndex: nativeSpanIndex,
                            maximumParameterWidth: maximumParameterWidth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            tolerance: tolerance, usage: &admission, maximumSpanCount: maximumSpanCount,
                            remainingSourceDepth: remainingSourceDepth, consumeStorage: bytes, maximumAlgebraicDepth: maximumAlgebraicDepth)
                        }
                    }
                }
            }
        }
    }

    public init<B: RationalAlgebraAdmitting>(source: Curve3D,
        start: OriginalCurveRootEndpoint, end: OriginalCurveRootEndpoint, nativeSpanIndex: Int? = nil,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B,
        maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
        try self.init(source: source, start: start, end: end, nativeSpanIndex: nativeSpanIndex,
            maximumParameterWidth: maximumParameterWidth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth, retainedNativePreparation: nil)
    }

    /// The issuer must bind both endpoint receipts to this preparation's same
    /// immutable admitted native source owner before calling this package port.
    package init<B: RationalAlgebraAdmitting>(retainingPreparedNativeSource prepared: PreparedCurveDifferentialEncloser,
        start: OriginalCurveRootEndpoint, end: OriginalCurveRootEndpoint,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B, maximumSpanCount: Int,
        remainingSourceDepth: Int, consumeStorage: ((Int) throws -> Void)?,
        maximumAlgebraicDepth: Int) throws {
        guard case .bSpline = prepared.curve, prepared.certificationTolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Retained native traversal requires the same admitted B-spline tolerance.")
        }
        try self.init(source: prepared.curve, start: start, end: end, nativeSpanIndex: nil,
            maximumParameterWidth: maximumParameterWidth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth, retainedNativePreparation: prepared)
    }

    private init<B: RationalAlgebraAdmitting>(source: Curve3D,
        start: OriginalCurveRootEndpoint, end: OriginalCurveRootEndpoint, nativeSpanIndex: Int?,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B, maximumSpanCount: Int,
        remainingSourceDepth: Int, consumeStorage: ((Int) throws -> Void)?,
        maximumAlgebraicDepth: Int?, retainedNativePreparation: PreparedCurveDifferentialEncloser?) throws {
        guard maximumSpanCount > 0, remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original root preparation requires caller span and source-depth capabilities.")
        }
        let localizationDepth = maximumAlgebraicDepth ?? maximumSubdivisionDepth
        try usage.consumeExactWork(1)
        if retainedNativePreparation == nil {
            try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try usage.consumeExactWork(1) }, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func validate(_ endpoint: OriginalCurveRootEndpoint) throws {
            if case .algebraic(let root) = endpoint {
                guard root.certificationTolerance == tolerance,
                      retainedNativePreparation != nil || source == .bSpline(root.source) else {
                    throw GeometryConversionError.invalidInput("Original algebraic endpoint belongs to another source curve or tolerance.")
                }
            }
        }
        try validate(start); try validate(end)
        if let nativeSpanIndex {
            guard case .bSpline(let spline) = source, nativeSpanIndex >= spline.degree,
                  nativeSpanIndex < spline.controlPoints.count,
                  spline.knots[nativeSpanIndex] < spline.knots[nativeSpanIndex + 1] else {
                throw GeometryConversionError.invalidInput("Original traversal requires a positive owning native span.")
            }
            for endpoint in [start, end] {
                switch endpoint {
                case .authored(let parameter):
                    guard parameter >= spline.knots[nativeSpanIndex], parameter <= spline.knots[nativeSpanIndex + 1] else {
                        throw GeometryConversionError.invalidInput("Authored traversal endpoint exceeds its original owning span.")
                    }
                case .algebraic(let root):
                    guard root.spanIndex == nativeSpanIndex else {
                        throw GeometryConversionError.invalidInput("Algebraic endpoint belongs to another original owning span.")
                    }
                }
            }
        }
        let nativePreparation: RationalBezierCurveJetEncloser.NativeSpan?
        if let nativeSpanIndex, case .bSpline(let spline) = source {
            let count = (spline.degree + 1).multipliedReportingOverflow(by:4)
            guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original root coefficient storage overflows.") }
            if consumeStorage == nil { try usage.retainExactStorage(count.partialValue) }
            nativePreparation = try RationalBezierCurveJetEncloser().originalNativeSpans(of:spline,
                tolerance:tolerance,owningSpanIndex:nativeSpanIndex,consumeWork:{ try usage.consumeExactWork(1) }, consumeStorage: consumeStorage).first
        } else { nativePreparation = nil }
        func local(_ value:ExactRationalCoefficient) throws -> ExactRationalCoefficient {
            guard let index = nativeSpanIndex,case .bSpline(let spline) = source else { return value }
            let origin = try ExactRationalCoefficient.originalDouble(spline.knots[index],usage:&usage)
            let upper = try ExactRationalCoefficient.originalDouble(spline.knots[index+1],usage:&usage)
            let width = try upper.subtracting(origin,usage:&usage)
            return try value.subtracting(origin,usage:&usage).divided(by:width,usage:&usage)
        }
        func localBounds(_ lower:ExactRationalCoefficient,_ upper:ExactRationalCoefficient) throws -> ScalarInterval {
            let a = try local(lower).outwardInterval(usage:&usage)
            let b = try local(upper).outwardInterval(usage:&usage)
            return try .init(lower:max(0,a.lower),upper:min(1,b.upper))
        }
        func preparedEndpoint(_ endpoint:OriginalCurveRootEndpoint) throws -> (bounds:ScalarInterval,
            exact:(lower:ExactRationalCoefficient,upper:ExactRationalCoefficient,excludesLower:Bool,excludesUpper:Bool)) {
            var width = maximumParameterWidth
            while true {
                try usage.consumeExactWork(1); try Task.checkCancellation()
                let exact = try endpoint.refinedIsolation(maximumWidth:width,
                    maximumSubdivisionDepth:localizationDepth,usage:&usage)
                let lo = try exact.lower.outwardInterval(usage:&usage), hi = try exact.upper.outwardInterval(usage:&usage)
                let bounds = try ScalarInterval(lower:lo.lower,upper:hi.upper)
                guard case .algebraic = endpoint, let span = nativePreparation else { return (bounds,exact) }
                let query = try localBounds(exact.lower,exact.upper)
                let jet = try OriginalNativeCurveHigherTaylor.enclosure(of:span,
                    over:.init(lower:span.lower,upper:span.upper),order:0,tolerance:tolerance,
                    normalizedRange:.init(lower:query.lower,upper:query.upper),
                    derivativesInNormalizedParameter:true,consumeWork:{ try usage.consumeExactWork(1) }, consumeStorage: consumeStorage)
                let x = try jet.x.coefficient(0,0),y = try jet.y.coefficient(0,0),z = try jet.z.coefficient(0,0)
                let error = IntervalVector3DBounds(x:x - .exact(x.midpoint),y:y - .exact(y.midpoint),z:z - .exact(z.midpoint)).lengthUpperBound
                if error.isFinite,error <= tolerance.distance/8 { return (bounds,exact) }
                let tighter = width/2
                guard tighter.isFinite,tighter > 0,tighter < width,
                      !(exact.lower == exact.upper) else {
                    throw GeometryConversionError.resourceLimitExceeded("Original endpoint position precision cannot resolve the caller tolerance.")
                }
                width = tighter
            }
        }
        let first = try preparedEndpoint(start),last = try preparedEndpoint(end)
        let a = first.bounds,b = last.bounds,exactA = first.exact,exactB = last.exact
        let forwardGap = try exactB.lower.subtracting(exactA.upper, usage: &usage)
        let reverseGap = try exactA.lower.subtracting(exactB.upper, usage: &usage)
        let forward = forwardGap.isPositive || forwardGap.isZero && (exactA.excludesUpper || exactB.excludesLower)
        let reverse = reverseGap.isPositive || reverseGap.isZero && (exactB.excludesUpper || exactA.excludesLower)
        guard forward || reverse,
              try source.parameterDomain.containsSpan(from: min(a.lower, b.lower),
                to: max(a.upper, b.upper), tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Original root traversal needs distinct ordered source endpoint authority.")
        }
        self.source = source; self.nativeSpanIndex = nativeSpanIndex; self.start = start; self.end = end
        certificationTolerance = tolerance
        if nativePreparation != nil {
            preparedStart = try localBounds(exactA.lower,exactA.upper)
            preparedEnd = try localBounds(exactB.lower,exactB.upper)
            let localAL = try local(exactA.lower), localAU = try local(exactA.upper)
            let localBL = try local(exactB.lower), localBU = try local(exactB.upper)
            let lower = try localBL.subtracting(localAU,usage:&usage).outwardInterval(usage:&usage)
            let upper = try localBU.subtracting(localAL,usage:&usage).outwardInterval(usage:&usage)
            preparedSlope = .init(lower:lower.lower,upper:upper.upper)
        } else {
            preparedStart = a; preparedEnd = b
            let lower = try exactB.lower.subtracting(exactA.upper,usage:&usage).outwardInterval(usage:&usage)
            let upper = try exactB.upper.subtracting(exactA.lower,usage:&usage).outwardInterval(usage:&usage)
            preparedSlope = .init(lower:lower.lower,upper:upper.upper)
        }
        preparedNativeSpan = nativePreparation
        preparedMaximumSpanCount = maximumSpanCount
        preparedRemainingSourceDepth = remainingSourceDepth
        preparedMaximumSubdivisionDepth = maximumSubdivisionDepth
        preparedMaximumAlgebraicDepth = localizationDepth
        if let retainedNativePreparation {
            preparedWholeTraversal = retainedNativePreparation
        } else {
            preparedWholeTraversal = nativePreparation == nil
                ? try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth) : nil
        }
    }

    /// Exact stored source identity, with complete original payload admission.
    package func hasSameOriginalTraversal(as other: Self,
        consumeWork: (Int) throws -> Void) throws -> Bool {
        try GeometryStructuralComparisonWork.charge(traversal: self, using: consumeWork)
        try GeometryStructuralComparisonWork.charge(traversal: other, using: consumeWork)
        try Task.checkCancellation()
        return source == other.source && nativeSpanIndex == other.nativeSpanIndex
            && start == other.start && end == other.end
            && certificationTolerance == other.certificationTolerance
    }

    /// Proves original positional closure without a numerical endpoint distance.
    package func provesClosedEndpoints<B: RationalAlgebraAdmitting>(
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        storageByteStride: Int = MemoryLayout<UInt32>.stride, usage: inout B,
        maximumAlgebraicDepth: Int? = nil) throws -> Bool {
        try OriginalCurveTraversalEndpointRelation().proves(first: self, firstAtEnd: false,
            second: self, secondAtEnd: true, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, storageByteStride: storageByteStride,
            usage: &usage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    public var hasOriginalClosedAuthoredEndpoints: Bool {
        guard case .authored(let first) = start,case .authored(let last) = end else { return false }
        func equal(_ curve:Curve3D,_ first:Double,_ last:Double)->Bool {
            switch curve {
            case .parameterImage(let image) where image.parameterGain == .binary(-1) && image.offset == 0:
                return equal(image.source,-first,-last)
            case .bSpline(let spline):
                let lower = spline.knots[spline.degree],upper = spline.knots[spline.controlPoints.count]
                guard first == lower && last == upper || first == upper && last == lower,
                      spline.knots.prefix(spline.degree+1).allSatisfy({ $0 == lower }),
                      spline.knots.suffix(spline.degree+1).allSatisfy({ $0 == upper }) else { return false }
                return spline.controlPoints.first == spline.controlPoints.last
            default: return false
            }
        }
        return equal(source,first,last)
    }

    public var parameterDomain: ParameterDomain { .closed(0, 1) }
    public func reversed() -> Self {
        Self(source: source, start: end, end: start, nativeSpanIndex: nativeSpanIndex, certificationTolerance: certificationTolerance, preparedStart: preparedEnd, preparedEnd: preparedStart, preparedSlope: -preparedSlope, preparedNativeSpan: preparedNativeSpan, preparedWholeTraversal: preparedWholeTraversal, preparedMaximumSubdivisionDepth: preparedMaximumSubdivisionDepth, preparedMaximumSpanCount: preparedMaximumSpanCount, preparedRemainingSourceDepth: preparedRemainingSourceDepth, preparedMaximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
    }
    private init(source: Curve3D, start: OriginalCurveRootEndpoint,
        end: OriginalCurveRootEndpoint, nativeSpanIndex: Int?, certificationTolerance: ModelingTolerance,
        preparedStart: ScalarInterval, preparedEnd: ScalarInterval, preparedSlope: OutwardScalarInterval,
        preparedNativeSpan: RationalBezierCurveJetEncloser.NativeSpan?,
        preparedWholeTraversal: PreparedCurveDifferentialEncloser?, preparedMaximumSubdivisionDepth: Int,
        preparedMaximumSpanCount: Int, preparedRemainingSourceDepth: Int, preparedMaximumAlgebraicDepth: Int) {
        self.source = source; self.nativeSpanIndex = nativeSpanIndex; self.start = start; self.end = end
        self.certificationTolerance = certificationTolerance
        self.preparedStart = preparedStart; self.preparedEnd = preparedEnd
        self.preparedSlope = preparedSlope; self.preparedNativeSpan = preparedNativeSpan
        self.preparedWholeTraversal = preparedWholeTraversal
        self.preparedMaximumSubdivisionDepth = preparedMaximumSubdivisionDepth
        self.preparedMaximumAlgebraicDepth = preparedMaximumAlgebraicDepth
        self.preparedMaximumSpanCount = preparedMaximumSpanCount
        self.preparedRemainingSourceDepth = preparedRemainingSourceDepth
    }


    public static func == (a: Self, b: Self) -> Bool {
        a.source == b.source && a.nativeSpanIndex == b.nativeSpanIndex && a.start == b.start
            && a.end == b.end && a.certificationTolerance == b.certificationTolerance
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(source); hasher.combine(nativeSpanIndex); hasher.combine(start)
        hasher.combine(end); hasher.combine(certificationTolerance)
    }

    /// Fixed evaluation of the retained original owning law, including closed ends.
    package func preparedIntervalJet(over range: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumSpanCount: Int = Int.max, maximumSubdivisionDepth: Int = Int.max,
        remainingSourceDepth: Int = Int.max, maximumAlgebraicDepth: Int? = nil) throws -> SurfaceIntervalVectorJet {
        if let maximumAlgebraicDepth {
            let admitted = try admittingQueryAlgebra(maximumAlgebraicDepth,
                tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage)
            return try admitted.preparedIntervalJet(over: range, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth)
        }
        guard tolerance == certificationTolerance, range.lower >= 0, range.upper <= 1,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original root jet requires its preparation tolerance and normalized domain.")
        }
        let s = OutwardScalarInterval(lower: range.lower, upper: range.upper)
        let a = OutwardScalarInterval(lower: preparedStart.lower, upper: preparedStart.upper)
        let b = OutwardScalarInterval(lower: preparedEnd.lower, upper: preparedEnd.upper)
        let cover = OutwardScalarInterval(lower: min(a.lower,b.lower), upper: max(a.upper,b.upper))
        guard let mapped = (a * (.exact(1)-s) + b*s).intersection(with: cover) else {
            throw GeometryConversionError.invalidInput("Original root chart has an empty source image.")
        }
        let original: SurfaceIntervalVectorJet
        if let span = preparedNativeSpan {
            guard let contained = mapped.intersection(with: .init(lower:0,upper:1)) else {
                throw GeometryConversionError.invalidInput("Original root image exceeds its retained owning side.")
            }
            let t = try OriginalNativeCurveHigherTaylor.enclosure(of:span,
                over:.init(lower:span.lower,upper:span.upper), order:3,
                tolerance:tolerance,normalizedRange:contained,
                derivativesInNormalizedParameter:true,consumeWork:consumeWork,consumeStorage:consumeStorage)
            func scalar(_ value: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceIntervalJet {
                let zero = OutwardScalarInterval.exact(0)
                return try .init(value:value.coefficient(0,0),derivativeU:value.coefficient(1,0),derivativeV:zero,
                    secondDerivativeUU:value.coefficient(2,0) * .exact(2),secondDerivativeUV:zero,secondDerivativeVV:zero,
                    thirdDerivativeUUU:value.coefficient(3,0) * .exact(6),thirdDerivativeUUV:zero,thirdDerivativeUVV:zero,thirdDerivativeVVV:zero)
            }
            original = try .init(x:scalar(t.x),y:scalar(t.y),z:scalar(t.z))
        } else {
            guard let traversal = preparedWholeTraversal else {
                throw GeometryConversionError.invalidInput("Original root chart has no retained source preparation.")
            }
            original = try traversal.closedNativeJets(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth), consumeWork: consumeWork,
                consumeStorage: consumeStorage).jet
        }

        func scale(_ value:SurfaceIntervalJet)->SurfaceIntervalJet {
            let z = OutwardScalarInterval.exact(0), d = preparedSlope
            return .init(value:value.value,derivativeU:value.derivativeU*d,derivativeV:z,
                secondDerivativeUU:value.secondDerivativeUU*d*d,secondDerivativeUV:z,secondDerivativeVV:z,
                thirdDerivativeUUU:value.thirdDerivativeUUU*d*d*d,thirdDerivativeUUV:z,thirdDerivativeUVV:z,thirdDerivativeVVV:z)
        }
        return .init(x:scale(original.x),y:scale(original.y),z:scale(original.z))
    }

    private struct QueryAlgebraAdmission: RationalAlgebraAdmitting {
        let maximumAlgebraicDepth: Int
        let consumeWork: () throws -> Void
        let consumeStorage: ((Int) throws -> Void)?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original query work count is invalid.") }
            for _ in 0..<count { try consumeWork() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original query algebra byte count overflows.")
            }
            try consumeStorage?(bytes.partialValue)
            try consumeExactWork(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumAlgebraicDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original query exceeds caller scalar algebra depth.")
            }
            try consumeWork()
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    }

    /// Reuses the native owner while re-issuing its endpoint localization capability.
    package func admittingQueryAlgebra(_ requested: Int, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> Self {
        guard (0...32).contains(requested), tolerance == certificationTolerance,
            maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original traversal query requires its retained tolerance and independent algebra policy.")
        }
        let depth = min(requested, preparedMaximumAlgebraicDepth)
        try source.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
            consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: depth)
        if start == .authored(0), end == .authored(1) {
            switch source {
            case .originalGuideTraversalChain, .originalGuideEndpointConnector:
            return Self(source: source, start: start, end: end, nativeSpanIndex: nativeSpanIndex,
                certificationTolerance: certificationTolerance, preparedStart: preparedStart, preparedEnd: preparedEnd,
                preparedSlope: preparedSlope, preparedNativeSpan: preparedNativeSpan,
                preparedWholeTraversal: preparedWholeTraversal, preparedMaximumSubdivisionDepth: preparedMaximumSubdivisionDepth,
                preparedMaximumSpanCount: preparedMaximumSpanCount, preparedRemainingSourceDepth: preparedRemainingSourceDepth,
                preparedMaximumAlgebraicDepth: depth)
            default: break
            }
        }
        guard let span = preparedNativeSpan, let index = nativeSpanIndex,
            case .bSpline(let spline) = source else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Later caller algebra selection
            // cannot rebind cached nonnative nested preparations. This RootSpan
            // drawing query requires that original capability transport before
            // a broader prepared owner can serve a stricter caller.
            if depth < preparedMaximumAlgebraicDepth {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: "Original nonnative traversal cannot rebind a stricter scalar query capability.")
            }
            return self
        }
        return try withoutActuallyEscaping(consumeWork) { consumeWork in
        var usage = QueryAlgebraAdmission(maximumAlgebraicDepth: depth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        let origin = try ExactRationalCoefficient.originalDouble(spline.knots[index], usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(spline.knots[index + 1], usage: &usage)
        let nativeWidth = try upper.subtracting(origin, usage: &usage)
        func local(_ value: ExactRationalCoefficient, usage: inout QueryAlgebraAdmission) throws -> ExactRationalCoefficient {
            try value.subtracting(origin, usage: &usage).divided(by: nativeWidth, usage: &usage)
        }
        func endpoint(_ original: OriginalCurveRootEndpoint,
            usage: inout QueryAlgebraAdmission) throws -> (ExactRationalCoefficient, ExactRationalCoefficient, ScalarInterval) {
            var width = max(Double.leastNonzeroMagnitude,
                spline.knots[index + 1] * 0.5 - spline.knots[index] * 0.5)
            while true {
                try usage.consumeExactWork(1)
                let exact = try original.refinedIsolation(maximumWidth: width,
                    maximumSubdivisionDepth: depth, usage: &usage)
                let low = try local(exact.lower, usage: &usage)
                let high = try local(exact.upper, usage: &usage)
                let a = try low.outwardInterval(usage: &usage)
                let b = try high.outwardInterval(usage: &usage)
                let bounds = try ScalarInterval(lower: max(0, a.lower), upper: min(1, b.upper))
                if case .authored = original { return (low, high, bounds) }
                let jet = try OriginalNativeCurveHigherTaylor.enclosure(of: span,
                    over: .init(lower: span.lower, upper: span.upper), order: 0, tolerance: tolerance,
                    normalizedRange: .init(lower: bounds.lower, upper: bounds.upper),
                    derivativesInNormalizedParameter: true, consumeWork: consumeWork, consumeStorage: consumeStorage)
                let x = try jet.x.coefficient(0, 0), y = try jet.y.coefficient(0, 0), z = try jet.z.coefficient(0, 0)
                let radius = IntervalVector3DBounds(x: x - .exact(x.midpoint),
                    y: y - .exact(y.midpoint), z: z - .exact(z.midpoint)).lengthUpperBound
                if radius <= tolerance.distance / 8 { return (low, high, bounds) }
                let next = width * 0.5
                guard next.isFinite, next > 0, next < width, exact.lower != exact.upper else {
                    throw GeometryConversionError.resourceLimitExceeded("Original query endpoint cannot meet retained position precision.")
                }
                width = next
            }
        }
        let first = try endpoint(start, usage: &usage), last = try endpoint(end, usage: &usage)
        let lowSlope = try last.0.subtracting(first.1, usage: &usage).outwardInterval(usage: &usage)
        let highSlope = try last.1.subtracting(first.0, usage: &usage).outwardInterval(usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(source: source, start: start, end: end, nativeSpanIndex: nativeSpanIndex,
            certificationTolerance: certificationTolerance, preparedStart: first.2, preparedEnd: last.2,
            preparedSlope: .init(lower: lowSlope.lower, upper: highSlope.upper),
            preparedNativeSpan: span, preparedWholeTraversal: preparedWholeTraversal,
            preparedMaximumSubdivisionDepth: preparedMaximumSubdivisionDepth,
            preparedMaximumSpanCount: preparedMaximumSpanCount,
            preparedRemainingSourceDepth: preparedRemainingSourceDepth,
            preparedMaximumAlgebraicDepth: depth)
        }
    }

    package func hasSmoothNativeInterval(over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> Bool {
        guard tolerance == certificationTolerance, range.lower.isFinite, range.upper.isFinite,
            range.lower >= 0, range.upper <= 1, range.lower < range.upper,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original root smoothness requires its retained positive interval and capabilities.")
        }
        if let maximumAlgebraicDepth {
            let admitted = try admittingQueryAlgebra(maximumAlgebraicDepth, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            return try admitted.hasSmoothNativeInterval(over: range, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        try consumeWork()
        if preparedNativeSpan != nil { return true }
        if start == .authored(0), end == .authored(1), case .originalGuideTraversalChain(let chain) = source {
            return try chain.hasSmoothNativeInterval(over: range, tolerance: tolerance,
                maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
        }
        if start == .authored(0), end == .authored(1), case .originalGuideEndpointConnector(let guide) = source {
            return try guide.hasSmoothNativeInterval(over: range, tolerance: tolerance,
                maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
        }
        if case .originalConstructionChart(let image) = source {
            guard start == .authored(0), end == .authored(1) else { return false }
            return try image.hasSmoothNativeInterval(over: range, tolerance: tolerance,
                maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        guard let requiresOwner = try OriginalCurveConstructionChartImage.smoothFamilyRequiresNativeOwner(source,
            remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth), consumeWork: consumeWork) else { return false }
        if !requiresOwner { return true }
        guard let traversal = preparedWholeTraversal else {
            throw GeometryConversionError.invalidInput("Original root smoothness lost its source preparation.")
        }
        let a = OutwardScalarInterval(lower: preparedStart.lower, upper: preparedStart.upper)
        let b = OutwardScalarInterval(lower: preparedEnd.lower, upper: preparedEnd.upper)
        let fraction = OutwardScalarInterval(lower: range.lower, upper: range.upper)
        let cover = OutwardScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        guard let mapped = (a * (.exact(1) - fraction) + b * fraction).intersection(with: cover) else {
            throw GeometryConversionError.invalidInput("Original root smoothness lost the original interval image.")
        }
        let receipt = try traversal.closedNativeJets(over: .init(lower: mapped.lower, upper: mapped.upper),
            tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
            remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        return try OriginalCurveConstructionChartImage.hasOnePositiveOwner(receipt, consumeWork: consumeWork)
    }

    /// Retains native owning sides for an exactly normalized construction source.
    package func constructionNativeJets(over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> PreparedCurveDifferentialEncloser.ClosedNativeJet {
        guard tolerance == certificationTolerance, case .bSpline(let original) = source,
              original.domain == .closed(0, 1), start == .authored(0), end == .authored(1),
              let traversal = preparedWholeTraversal else {
            throw GeometryConversionError.invalidInput("Construction owning jets require the retained identity native traversal.")
        }
        return try traversal.closedNativeJets(over: range, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
            remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    /// Admits actual first-order query bytes in the composing storage slot unit.
    package func preparedFirstOrder<B: RationalAlgebraAdmitting>(over range: ScalarInterval,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, storageByteStride: Int, usage: inout B) throws -> OriginalCurveFirstOrderJet {
        guard storageByteStride > 0 else {
            throw GeometryConversionError.invalidInput("Original first-order storage slot stride must be positive.")
        }
        func storage(_ bytes: Int) throws {
            let rounded = bytes.addingReportingOverflow(storageByteStride - 1)
            guard bytes >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original first-order byte conversion overflows.")
            }
            try usage.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        return try withoutActuallyEscaping(storage) { storage in
            try preparedFirstOrder(over: range, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: storage)
        }
    }

    /// Reuses original preparation; continuity admission belongs to the caller.
    package func preparedFirstOrder(over range: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> OriginalCurveFirstOrderJet {
        guard tolerance == certificationTolerance, range.lower.isFinite, range.upper.isFinite,
              range.lower >= 0, range.upper <= 1, range.lower <= range.upper,
              maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Prepared first-order traversal needs its source domain and composing ceilings.")
        }
        try consumeWork()
        let a = OutwardScalarInterval(lower: preparedStart.lower, upper: preparedStart.upper)
        let b = OutwardScalarInterval(lower: preparedEnd.lower, upper: preparedEnd.upper)
        let fraction = OutwardScalarInterval(lower: range.lower, upper: range.upper)
        let cover = OutwardScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        guard let mapped = (a * (.exact(1) - fraction) + b * fraction).intersection(with: cover) else {
            throw GeometryConversionError.invalidInput("Prepared first-order traversal lost its original image.")
        }
        let position: IntervalVector3DBounds, derivative: IntervalVector3DBounds
        if let native = preparedNativeSpan {
            guard let local = mapped.intersection(with: .init(lower: 0, upper: 1)) else {
                throw GeometryConversionError.invalidInput("Prepared first-order traversal leaves its owning local span.")
            }
            let jet = try OriginalNativeCurveHigherTaylor.enclosure(of: native,
                over: .init(lower: native.lower, upper: native.upper), order: 1,
                tolerance: tolerance, normalizedRange: local,
                derivativesInNormalizedParameter: true, consumeWork: consumeWork, consumeStorage: consumeStorage)
            position = try .init(x: jet.x.coefficient(0, 0), y: jet.y.coefficient(0, 0), z: jet.z.coefficient(0, 0))
            derivative = try .init(x: jet.x.coefficient(1, 0), y: jet.y.coefficient(1, 0), z: jet.z.coefficient(1, 0))
        } else if case .originalPolyline(let original) = source {
            let value = try original.preparedFirstOrder(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
            position = value.position; derivative = value.firstDerivative
        } else if case .originalGuideTraversalChain(let chain) = source {
            let value = try chain.preparedFirstOrder(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
            position = value.position; derivative = value.firstDerivative
        } else if case .originalGuideEndpointConnector(let chain) = source {
            let value = try chain.preparedFirstOrder(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
            position = value.position; derivative = value.firstDerivative
        } else if case .originalConstructionChart(let image) = source {
            let value = try image.preparedFirstOrder(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            position = value.position; derivative = value.firstDerivative
        } else {
            guard let traversal = preparedWholeTraversal else {
                throw GeometryConversionError.invalidInput("Prepared first-order traversal has no original token.")
            }
            let receipt = try traversal.closedNativeJets(over: .init(lower: mapped.lower, upper: mapped.upper),
                tolerance: tolerance, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth), consumeWork: consumeWork, consumeStorage: consumeStorage)
            guard let first = receipt.spans.first else {
                throw GeometryConversionError.invalidInput("Prepared first-order traversal has no original owning cover.")
            }
            var value = first.jet
            for span in receipt.spans.dropFirst() {
                try consumeWork()
                value = value.union(span.jet)
            }
            position = .init(x: value.x.value, y: value.y.value, z: value.z.value)
            derivative = .init(x: value.x.derivativeU, y: value.y.derivativeU, z: value.z.derivativeU)
        }
        let scaled = derivative * preparedSlope
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              scaled.x.isFinite, scaled.y.isFinite, scaled.z.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Prepared first-order traversal bounds are nonfinite.")
        }
        return .init(position: position, firstDerivative: scaled)
    }

    package func preparedDerivatives(over range:ScalarInterval,tolerance:ModelingTolerance,
        consumeWork:()throws->Void) throws -> IntervalVectorDerivativeJet {
        let q = try preparedIntervalJet(over:range,tolerance:tolerance,consumeWork:consumeWork)
        func coordinate(_ value:SurfaceIntervalJet)->IntervalDerivativeJet {
            .init(derivatives:[value.value,value.derivativeU,value.secondDerivativeUU,value.thirdDerivativeUUU])
        }
        return .init(x:coordinate(q.x),y:coordinate(q.y),z:coordinate(q.z))
    }

    /// Converts actual native query bytes using the composing owner's storage slot stride.
    package func intervalTaylorJet<B: RationalAlgebraAdmitting>(over range: ScalarInterval,
        throughOrder order: Int, tolerance: ModelingTolerance, storageByteStride: Int, usage: inout B,
        maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max)
        throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard storageByteStride > 0 else { throw GeometryConversionError.invalidInput("Original query storage slot stride must be positive.") }
        func storage(_ bytes: Int) throws {
            guard bytes >= 0 else { throw GeometryConversionError.invalidInput("Original query bytes must be nonnegative.") }
            let words = bytes.addingReportingOverflow(storageByteStride - 1)
            guard !words.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original native query storage word conversion overflows.") }
            try usage.retainExactStorage(words.partialValue / storageByteStride)
        }
        return try withoutActuallyEscaping(storage) { admittedStorage in
            try intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                consumeWork: { try usage.consumeExactWork(1) }, maximumSpanCount: maximumSpanCount,
                remainingSourceDepth: remainingSourceDepth, consumeStorage: admittedStorage)
        }
    }

    /// Requested-order original owning Taylor law without renewed root preparation.
    package func intervalTaylorJet(over range: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumSubdivisionDepth: Int = Int.max) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard tolerance == certificationTolerance, order >= 0, range.lower >= 0, range.upper <= 1, maximumSpanCount > 0, remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original root Taylor query requires its closed prepared source chart.")
        }
        let a = OutwardScalarInterval(lower:preparedStart.lower,upper:preparedStart.upper)
        let b = OutwardScalarInterval(lower:preparedEnd.lower,upper:preparedEnd.upper)
        let fraction = OutwardScalarInterval(lower:range.lower,upper:range.upper)
        let cover = OutwardScalarInterval(lower:min(a.lower,b.lower),upper:max(a.upper,b.upper))
        guard let mapped = (a*(.exact(1)-fraction)+b*fraction).intersection(with:cover) else {
            throw GeometryConversionError.invalidInput("Original root Taylor query has no closed owning interval.")
        }
        let result: SurfaceAreaIntervalTaylorVectorJet
        if let span = preparedNativeSpan {
            guard let native = mapped.intersection(with: .init(lower: 0, upper: 1)) else {
                throw GeometryConversionError.invalidInput("Original root Taylor query leaves its native local chart.")
            }
            result = try OriginalNativeCurveHigherTaylor.enclosure(of:span,
                over:.init(lower:span.lower,upper:span.upper),order:order,tolerance:tolerance,
                normalizedRange:native,derivativesInNormalizedParameter:true,consumeWork:consumeWork, consumeStorage: consumeStorage)
        } else {
            guard preparedWholeTraversal != nil else {
                throw GeometryConversionError.invalidInput("Original root Taylor query lacks its original traversal preparation.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Whole nonnative root traversals
            // forward original provider byte admission. Periodic/implicit/lift
            // provider families retain explicit refusal until all temporary
            // allocations and source joins are admitted; a chart adds no authority.
            result = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: source,
                over: .init(lower: mapped.lower, upper: mapped.upper), tolerance: tolerance,
                throughOrder: order, maximumSpanCount: min(maximumSpanCount, preparedMaximumSpanCount),
                maximumSubdivisionDepth: min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth),
                remainingSourceDepth: min(remainingSourceDepth, preparedRemainingSourceDepth),
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: preparedMaximumAlgebraicDepth)
        }
        func scaled(_ q:SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var target = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,consumeWork:consumeWork, consumeStorage: consumeStorage)
            var factor = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try consumeWork(); try target.set(q.coefficient(k,0)*factor,k,0); factor = factor*preparedSlope
            }
            return target
        }
        return try .init(x:scaled(result.x),y:scaled(result.y),z:scaled(result.z))
    }

    /// Full original native image and its constant exact endpoint-difference enclosure.
    package func nativeParameterBounds<B: RationalAlgebraAdmitting>(over range: ScalarInterval,
        maximumParameterWidth: Double, maximumSubdivisionDepth: Int,
        usage: inout B) throws -> (parameters: ScalarInterval, derivative: OutwardScalarInterval) {
        guard range.lower >= 0, range.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original root traversal range must belong to [0,1].")
        }
        let exactA = try start.refinedIsolation(maximumWidth: maximumParameterWidth,
            maximumSubdivisionDepth: preparedMaximumAlgebraicDepth, usage: &usage)
        let exactB = try end.refinedIsolation(maximumWidth: maximumParameterWidth,
            maximumSubdivisionDepth: preparedMaximumAlgebraicDepth, usage: &usage)
        let al = try exactA.lower.outwardInterval(usage: &usage), au = try exactA.upper.outwardInterval(usage: &usage)
        let bl = try exactB.lower.outwardInterval(usage: &usage), bu = try exactB.upper.outwardInterval(usage: &usage)
        let a = try ScalarInterval(lower: al.lower, upper: au.upper)
        let b = try ScalarInterval(lower: bl.lower, upper: bu.upper)
        let first = OutwardScalarInterval(lower: a.lower, upper: a.upper)
        let last = OutwardScalarInterval(lower: b.lower, upper: b.upper)
        let exactLower = try exactB.lower.subtracting(exactA.upper, usage: &usage)
        let exactUpper = try exactB.upper.subtracting(exactA.lower, usage: &usage)
        let lowerSlope = try exactLower.outwardInterval(usage: &usage)
        let upperSlope = try exactUpper.outwardInterval(usage: &usage)
        let slope = OutwardScalarInterval(lower: lowerSlope.lower, upper: upperSlope.upper)
        let s = OutwardScalarInterval(lower: range.lower, upper: range.upper)
        let mapped = first * (.exact(1) - s) + last * s
        let originalCover = OutwardScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        guard let contained = mapped.intersection(with: originalCover) else {
            throw GeometryConversionError.invalidInput("Original root traversal native image is empty.")
        }
        return try (.init(lower: contained.lower, upper: contained.upper), slope)
    }

    /// Original closed derivatives, with no substituted numeric root station.
    package func derivatives<B: RationalAlgebraAdmitting>(over range: ScalarInterval,
        throughOrder: Int, maximumParameterWidth: Double, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        usage: inout B) throws -> IntervalVectorDerivativeJet {
        let native = try nativeParameterBounds(over: range, maximumParameterWidth: maximumParameterWidth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
        let original: IntervalVectorDerivativeJet
        if let nativeSpanIndex, case .bSpline(let spline) = source {
            let spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: spline,
                tolerance: certificationTolerance, owningSpanIndex: nativeSpanIndex,
                consumeWork: { try usage.consumeExactWork(1) })
            guard let span = spans.first,
                  let query = OutwardScalarInterval(lower: native.parameters.lower, upper: native.parameters.upper)
                    .intersection(with: .init(lower: span.lower, upper: span.upper)) else {
                throw GeometryConversionError.invalidInput("Original root chart has no owning native coefficient span.")
            }
            let coefficients = try OriginalNativeCurveHigherTaylor.enclosure(of: span,
                over: ScalarInterval(lower: query.lower, upper: query.upper), order: max(4, throughOrder),
                tolerance: certificationTolerance, consumeWork: { try usage.consumeExactWork(1) })
            func coordinate(_ field: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
                var values: [OutwardScalarInterval] = []
                for order in 0...throughOrder {
                    var value = try field.coefficient(order, 0)
                    if order > 1 { for integer in 2...order {
                        try usage.consumeExactWork(1); value = value * .exact(Double(integer))
                    } }
                    try usage.retainExactStorage(1); values.append(value)
                }
                return .init(derivatives: values)
            }
            original = try .init(x: coordinate(coefficients.x), y: coordinate(coefficients.y), z: coordinate(coefficients.z))
        } else {
            original = try NativeCurveDerivativeEncloser.originalDerivatives(of: source,
                over: native.parameters, tolerance: certificationTolerance, throughOrder: throughOrder,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: { try usage.consumeExactWork(1) })
        }
        func scaled(_ field: IntervalDerivativeJet) throws -> IntervalDerivativeJet {
            var factor = OutwardScalarInterval.exact(1), values: [OutwardScalarInterval] = []
            for k in 0...throughOrder {
                try usage.consumeExactWork(1); try usage.retainExactStorage(1)
                let value = field.derivatives[k] * factor
                guard value.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original root traversal derivative bounds are nonfinite.")
                }
                values.append(value); factor = factor * native.derivative
            }
            return IntervalDerivativeJet(derivatives: values)
        }
        return try .init(x: scaled(original.x), y: scaled(original.y), z: scaled(original.z))
    }

    package func endpointProvesAxis(atEnd: Bool, origin: Point3D, direction: Vector3D,
        consumeWork: () throws -> Void) throws -> Bool {
        let endpoint = atEnd ? end : start
        switch endpoint {
        case .algebraic(let root): return root.provesAxis(origin: origin, direction: direction)
        case .authored(let parameter):
            guard case .bSpline(let spline) = source,
                  parameter == spline.knots[spline.degree] || parameter == spline.knots[spline.controlPoints.count] else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): General authored interior
                // point-axis incidence needs exact original homogeneous value
                // evaluation, not a rounded source point. Revolution callers
                // must retain an algebraic incidence receipt for such stations.
                return false
            }
            let lower = parameter == spline.knots[spline.degree]
            let multiplicity = spline.knots.reduce(0) { $0 + ($1 == parameter ? 1 : 0) }
            guard multiplicity == spline.degree + 1,
                  let point = lower ? spline.controlPoints.first : spline.controlPoints.last else { return false }
            return try OriginalPointLineIncidence().contains(point: point, origin: origin,
                direction: direction, consumeWork: consumeWork)
        }
    }
}

#if !hasFeature(Embedded)
extension OriginalCurveRootSpan3D: Codable {
    private enum CodingKeys: String, CodingKey { case source, start, end, nativeSpanIndex, certificationTolerance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.source, .start, .end, .nativeSpanIndex, .certificationTolerance], in: decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            let source = try c.decode(Curve3D.self, forKey: .source)
            let tolerance = try c.decode(ModelingTolerance.self, forKey: .certificationTolerance)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            let geometryDepth = try OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepth(from: decoder)
            let algebraDepth = try OriginalAffineWordDecodingContext.maximumAlgebraicDepth(from: decoder)
            let sourceDepth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder) - decoder.codingPath.count
            let width = source.parameterDomain.parameterResolution(tolerance: tolerance)
            try self.init(source: source, start: c.decode(OriginalCurveRootEndpoint.self, forKey: .start),
                end: c.decode(OriginalCurveRootEndpoint.self, forKey: .end),
                nativeSpanIndex: c.decodeIfPresent(Int.self, forKey: .nativeSpanIndex),
                maximumParameterWidth: width, maximumSubdivisionDepth: geometryDepth,
                tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: algebraDepth)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source); try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end); try c.encode(nativeSpanIndex, forKey: .nativeSpanIndex)
        try c.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
#endif
