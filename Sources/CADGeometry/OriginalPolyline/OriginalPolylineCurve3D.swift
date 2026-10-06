import CADCore

/// Original adjacent-point geometry with an exact Euclidean-length clock.
public struct OriginalPolylineCurve3D: Hashable, Sendable {
    public let points: [Point3D]
    public let isClosed: Bool
    public let certificationTolerance: ModelingTolerance
    package let remainingSourceDepth: Int
    package let maximumSubdivisionDepth: Int
    package let maximumAlgebraicDepth: Int
    package var maximumSpanCount: Int { law.segments.count }
    private let law: OriginalEuclideanPolyline3DParameterLaw

    public init<B: RationalAlgebraAdmitting>(points: [Point3D], isClosed: Bool,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try tolerance.validate()
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original polyline requires independent caller capabilities.")
        }
        try RationalAlgebraStorage.retain(points.count, of: Point3D.self, usage: &usage)
        law = try OriginalEuclideanPolyline3DParameterLaw(originalPoints: points,
            inheritedDepth: 0, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        self.points = points; self.isClosed = isClosed; certificationTolerance = tolerance
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    public var domain: ParameterDomain { .closed(0, 1) }
    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original polyline changed its certification tolerance.")
        }
    }
    public static func == (a: Self, b: Self) -> Bool { a.points == b.points && a.isClosed == b.isClosed }
    public func hash(into hasher: inout Hasher) { hasher.combine(points); hasher.combine(isClosed) }

    package struct OwningJet: Sendable {
        package let originalPointIndex: Int
        package let exactLower: OriginalSingularFieldElement
        package let exactUpper: OriginalSingularFieldElement
        package let parameters: ScalarInterval
        package let jet: IntervalVectorDerivativeJet
    }

    private struct Usage: RationalAlgebraAdmitting {
        let work: () throws -> Void
        let storage: ((Int) throws -> Void)?
        let algebraDepth: Int
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original polyline work is negative.") }
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try work() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original polyline storage bytes overflow.")
            }
            try storage?(bytes.partialValue)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= algebraDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original polyline exceeds caller algebra depth.")
            }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    }

    private func selectedLaw<B: RationalAlgebraAdmitting>(maximumAlgebraicDepth requested: Int?,
        usage: inout B) throws -> OriginalEuclideanPolyline3DParameterLaw {
        guard requested.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original polyline algebra cap is outside zero through 32.")
        }
        let selected = min(requested ?? maximumAlgebraicDepth, maximumAlgebraicDepth)
        if selected < maximumAlgebraicDepth {
            return try .init(originalPoints: points, inheritedDepth: 0,
                maximumAlgebraicDepth: selected, usage: &usage)
        }
        return law
    }

    package func owningDerivativeJets(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth requested: Int? = nil) throws -> [OwningJet] {
        try validate(tolerance: tolerance)
        guard (0...3).contains(order), maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            remainingSourceDepth >= 0, parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower >= 0, parameters.upper <= 1, parameters.lower <= parameters.upper,
            requested.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original polyline requires a closed normalized owning query.")
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            let depth = min(requested ?? self.maximumAlgebraicDepth, self.maximumAlgebraicDepth)
            var usage = Usage(work: work, storage: consumeStorage, algebraDepth: depth)
            let original = try selectedLaw(maximumAlgebraicDepth: requested, usage: &usage)
            let lower = try OriginalSingularFieldElement.constant(.originalDouble(parameters.lower, usage: &usage),
                in: original.context, maximumDepth: depth, usage: &usage)
            let upper = try OriginalSingularFieldElement.constant(.originalDouble(parameters.upper, usage: &usage),
                in: original.context, maximumDepth: depth, usage: &usage)
            guard original.segments.count <= maximumSpanCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original polyline exceeds caller owning-span admission.")
            }
            try RationalAlgebraStorage.retain(original.segments.count, of: OwningJet.self, usage: &usage)
            var output: [OwningJet] = []; output.reserveCapacity(original.segments.count)
            let width = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &usage)
            for segment in original.segments {
                try usage.consumeExactWork(1)
                let lowerBefore = try lower.subtracting(segment.lowerFraction, maximumDepth: depth, usage: &usage)
                    .sign(maximumDepth: depth, usage: &usage)
                let upperAfter = try upper.subtracting(segment.upperFraction, maximumDepth: depth, usage: &usage)
                    .sign(maximumDepth: depth, usage: &usage)
                let a = lowerBefore == .negative ? segment.lowerFraction : lower
                let b = upperAfter == .positive ? segment.upperFraction : upper
                if try b.subtracting(a, maximumDepth: depth, usage: &usage)
                    .sign(maximumDepth: depth, usage: &usage) == .negative { continue }
                let first = try segment.originalXYZ(atOriginalFraction: a, maximumAlgebraicDepth: depth, usage: &usage)
                let last = try segment.originalXYZ(atOriginalFraction: b, maximumAlgebraicDepth: depth, usage: &usage)
                let derivative = try segment.originalFirstDerivative(maximumAlgebraicDepth: depth, usage: &usage)
                func axis(_ first: OriginalSingularFieldElement, _ last: OriginalSingularFieldElement,
                    _ derivative: OriginalSingularFieldElement, usage: inout Usage) throws -> IntervalDerivativeJet {
                    try RationalAlgebraStorage.retain(order + 1, of: OutwardScalarInterval.self, usage: &usage)
                    var values: [OutwardScalarInterval] = []; values.reserveCapacity(order + 1)
                    let x = try first.enclosure(maximumWidth: width, maximumDepth: depth, usage: &usage)
                    let y = try last.enclosure(maximumWidth: width, maximumDepth: depth, usage: &usage)
                    values.append(x.union(y)); try usage.consumeExactWork(1)
                    if order > 0 { values.append(try derivative.enclosure(maximumWidth: width,
                        maximumDepth: depth, usage: &usage)) }
                    if order > 1 { for _ in 2...order { values.append(.exact(0)) } }
                    return IntervalDerivativeJet(derivatives: values)
                }
                let jet = try IntervalVectorDerivativeJet(
                    x: axis(first.x, last.x, derivative.x, usage: &usage),
                    y: axis(first.y, last.y, derivative.y, usage: &usage),
                    z: axis(first.z, last.z, derivative.z, usage: &usage))
                let lo = try a.enclosure(maximumDepth: depth, usage: &usage)
                let hi = try b.enclosure(maximumDepth: depth, usage: &usage)
                let localization = try ScalarInterval(lower: max(parameters.lower, lo.lower),
                    upper: min(parameters.upper, hi.upper))
                output.append(.init(originalPointIndex: segment.originalPointIndex,
                    exactLower: a, exactUpper: b, parameters: localization, jet: jet))
            }
            guard !output.isEmpty else { throw GeometryConversionError.invalidInput("Original polyline has no selected owner.") }
            return output
        }
    }

    package func preparedFirstOrder(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> OriginalCurveFirstOrderJet {
        let owners = try owningDerivativeJets(over: parameters, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        var position = IntervalVector3DBounds(x: owners[0].jet.x.derivatives[0], y: owners[0].jet.y.derivatives[0], z: owners[0].jet.z.derivatives[0])
        var derivative = IntervalVector3DBounds(x: owners[0].jet.x.derivatives[1], y: owners[0].jet.y.derivatives[1], z: owners[0].jet.z.derivatives[1])
        for owner in owners.dropFirst() {
            for _ in 0..<6 { try consumeWork() }
            position = .init(x: position.x.union(owner.jet.x.derivatives[0]), y: position.y.union(owner.jet.y.derivatives[0]), z: position.z.union(owner.jet.z.derivatives[0]))
            derivative = .init(x: derivative.x.union(owner.jet.x.derivatives[1]), y: derivative.y.union(owner.jet.y.derivatives[1]), z: derivative.z.union(owner.jet.z.derivatives[1]))
        }
        return .init(position: position, firstDerivative: derivative)
    }

    package func hasSmoothNativeInterval(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth requested: Int? = nil) throws -> Bool {
        let owners = try owningDerivativeJets(over: parameters, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: requested)
        return try withoutActuallyEscaping(consumeWork) { work in
            let depth = min(requested ?? self.maximumAlgebraicDepth, self.maximumAlgebraicDepth)
            var usage = Usage(work: work, storage: consumeStorage, algebraDepth: depth)
            let original = try selectedLaw(maximumAlgebraicDepth: requested, usage: &usage)
            var previous: (x: OriginalSingularFieldElement, y: OriginalSingularFieldElement, z: OriginalSingularFieldElement)?
            for owner in owners {
                if parameters.lower < parameters.upper, try owner.exactUpper.subtracting(owner.exactLower, maximumDepth: depth, usage: &usage)
                    .sign(maximumDepth: depth, usage: &usage) != .positive { continue }
                var selected: OriginalEuclideanPolyline3DParameterLaw.Segment?
                for candidate in original.segments {
                    try usage.consumeExactWork(1)
                    if candidate.originalPointIndex == owner.originalPointIndex { selected = candidate; break }
                }
                guard let segment = selected else {
                    throw GeometryConversionError.invalidInput("Original polyline owner does not match its source segment.")
                }
                let current = try segment.originalFirstDerivative(maximumAlgebraicDepth: depth, usage: &usage)
                if let previous {
                    if try current.x.subtracting(previous.x, maximumDepth: depth, usage: &usage).sign(maximumDepth: depth, usage: &usage) != .zero { return false }
                    if try current.y.subtracting(previous.y, maximumDepth: depth, usage: &usage).sign(maximumDepth: depth, usage: &usage) != .zero { return false }
                    if try current.z.subtracting(previous.z, maximumDepth: depth, usage: &usage).sign(maximumDepth: depth, usage: &usage) != .zero { return false }
                }
                previous = current
            }
            return true
        }
    }

    package func derivatives(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> IntervalVectorDerivativeJet {
        if order > 1, parameters.lower < parameters.upper {
            guard try hasSmoothNativeInterval(over: parameters, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth) else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original polyline corner has no whole higher differential law.")
            }
        }
        let owners = try owningDerivativeJets(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        if parameters.lower == parameters.upper { return owners[0].jet }
        func axis(_ index: Int) throws -> IntervalDerivativeJet {
            func coordinate(_ owner: OwningJet) -> IntervalDerivativeJet {
                index == 0 ? owner.jet.x : index == 1 ? owner.jet.y : owner.jet.z
            }
            let bytes = (order + 1).multipliedReportingOverflow(by: MemoryLayout<OutwardScalarInterval>.stride)
            guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original polyline jet bytes overflow.") }
            try consumeStorage?(bytes.partialValue)
            var values = coordinate(owners[0]).derivatives
            for owner in owners.dropFirst() {
                for k in 0...order { try consumeWork(); values[k] = values[k].union(coordinate(owner).derivatives[k]) }
            }
            return .init(derivatives: values)
        }
        return try .init(x: axis(0), y: axis(1), z: axis(2))
    }

    package func intervalTaylorJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let original = try derivatives(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        func axis(_ source: IntervalDerivativeJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var output = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            var factorial = 1.0
            for k in 0...order {
                if k > 0 { try consumeWork(); factorial *= Double(k) }
                guard let value = source.derivatives[k].divided(by: .exact(factorial)) else {
                    throw GeometryConversionError.invalidInput("Original polyline Taylor factorial is singular.")
                }
                try consumeWork(); try output.set(value, k, 0)
            }
            return output
        }
        return try .init(x: axis(original.x), y: axis(original.y), z: axis(original.z))
    }

    package func positionBounds(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> IntervalVector3DBounds {
        let owners = try owningDerivativeJets(over: parameters, throughOrder: 0, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        var value = IntervalVector3DBounds(x: owners[0].jet.x.value, y: owners[0].jet.y.value, z: owners[0].jet.z.value)
        for owner in owners.dropFirst() {
            for _ in 0..<3 { try consumeWork() }
            value = .init(x: value.x.union(owner.jet.x.value), y: value.y.union(owner.jet.y.value), z: value.z.union(owner.jet.z.value))
        }
        return value
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let position = try positionBounds(over: ScalarInterval(lower: parameter, upper: parameter),
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
        let candidate = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
        guard IntervalVector3DBounds(x: position.x - .exact(candidate.x),
            y: position.y - .exact(candidate.y), z: position.z - .exact(candidate.z))
            .lengthUpperBound <= tolerance.distance else {
            throw GeometryConversionError.resourceLimitExceeded("Original polyline point requires narrower exact coordinates.")
        }
        return candidate
    }
}
