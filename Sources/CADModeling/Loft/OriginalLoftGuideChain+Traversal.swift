import CADCore
import CADGeometry

extension OriginalLoftGuideChain {
    package func originalConnector(from start: OriginalLoftGuideContact,
        to end: OriginalLoftGuideContact, using usage: inout OriginalQueryExecution) throws -> OriginalGuideTraversalChain3D {
        guard start.segmentIndex <= end.segmentIndex,
            try orderedBounds(start, tolerance: tolerance).upper < orderedBounds(end, tolerance: tolerance).lower,
            usage.effectiveLimits.remainingSourceDepth > 1 else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection, tolerance: tolerance,
                message: "Original guide connector requires strictly ordered retained events and source descent.")
        }
        func eventEndpoint(_ contact: OriginalLoftGuideContact) throws -> OriginalCurveRootEndpoint {
            guard let endpoint = contact.nativeEndpoint else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Loft guide publication
                // needs the original scalar endpoint issuer for every guide
                // family. A numerical contact bracket midpoint is construction
                // only and cannot become an authored original endpoint.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original guide contact lacks its retained scalar endpoint source.")
            }
            return endpoint
        }
        let firstEndpoint = try eventEndpoint(start), lastEndpoint = try eventEndpoint(end)
        var traversals: [OriginalCurveRootSpan3D] = [], ordinals: [Int] = []
        var admittedCapacity = 0
        func append(source: Curve3D, first: OriginalCurveRootEndpoint, last: OriginalCurveRootEndpoint,
            owner: Int?, ordinal: Int) throws {
            if case .authored(let a) = first, case .authored(let b) = last, a == b { return }
            if traversals.count == admittedCapacity {
                let doubled = admittedCapacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original guide traversal capacity overflows.") }
                let capacity = admittedCapacity == 0 ? 1 : doubled.partialValue
                try RationalAlgebraStorage.retain(capacity, of: OriginalCurveRootSpan3D.self, usage: &usage)
                try RationalAlgebraStorage.retain(capacity, of: Int.self, usage: &usage)
                try usage.consumeWork(try checkedCopyCount(traversals.count))
                traversals.reserveCapacity(capacity); ordinals.reserveCapacity(capacity)
                admittedCapacity = capacity
            }
            traversals.append(try OriginalCurveRootSpan3D(source: source, start: first, end: last,
                nativeSpanIndex: owner, maximumParameterWidth: tolerance.relative,
                maximumSubdivisionDepth: usage.effectiveLimits.maximumSubdivisionDepth, tolerance: tolerance,
                usage: &usage,
                maximumSpanCount: usage.effectiveLimits.maximumSpans,
                remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth-1,
                maximumAlgebraicDepth: usage.effectiveLimits.maximumValueDepth))
            ordinals.append(ordinal)
        }
        func owner(_ endpoint: OriginalCurveRootEndpoint, atStart: Bool, reversed: Bool,
            spline: BSplineCurve3D) throws -> Int {
            switch endpoint {
            case .algebraic(let root):
                guard root.source == spline else { throw GeometryConversionError.invalidInput("Original guide endpoint belongs to another source.") }
                try usage.consumeWork(1)
                return root.spanIndex
            case .authored(let parameter):
                for index in spline.degree..<spline.controlPointCount {
                    try usage.consumeWork(1)
                    let a = spline.knots[index], b = spline.knots[index+1]
                    guard a < b else { continue }
                    let takesUpperSide = atStart != reversed
                    if takesUpperSide ? parameter >= a && parameter < b : parameter > a && parameter <= b { return index }
                }
                throw GeometryConversionError.invalidInput("Original guide authored endpoint has no directed positive native owner.")
            }
        }
        for ordinal in start.segmentIndex...end.segmentIndex {
            try usage.consumeWork(1)
            let original = segments[ordinal], raw = try source(at: ordinal, tolerance: tolerance)
            let first: OriginalCurveRootEndpoint = ordinal == start.segmentIndex ? firstEndpoint
                : .authored(original.isReversed ? raw.parameters.upper : raw.parameters.lower)
            let last: OriginalCurveRootEndpoint = ordinal == end.segmentIndex ? lastEndpoint
                : .authored(original.isReversed ? raw.parameters.lower : raw.parameters.upper)
            if case .authored(let a) = first, case .authored(let b) = last, a == b { continue }
            if case .bSpline(let spline) = raw.curve {
                let firstOwner = try owner(first, atStart: true, reversed: original.isReversed, spline: spline)
                let lastOwner = try owner(last, atStart: false, reversed: original.isReversed, spline: spline)
                let direction = original.isReversed ? -1 : 1
                guard original.isReversed ? firstOwner >= lastOwner : firstOwner <= lastOwner else {
                    throw GeometryConversionError.invalidInput("Original guide native owner order contradicts its directed source.")
                }
                var index = firstOwner
                while true {
                    try usage.consumeWork(1)
                    if spline.knots[index] < spline.knots[index+1] {
                        let a: OriginalCurveRootEndpoint = index == firstOwner ? first
                            : .authored(spline.knots[index + (original.isReversed ? 1 : 0)])
                        let b: OriginalCurveRootEndpoint = index == lastOwner ? last
                            : .authored(spline.knots[index + (original.isReversed ? 0 : 1)])
                        try append(source: raw.curve, first: a, last: b, owner: index, ordinal: ordinal)
                    }
                    if index == lastOwner { break }
                    index += direction
                }
            } else { try append(source: raw.curve, first: first, last: last, owner: nil, ordinal: ordinal) }
        }
        guard !traversals.isEmpty, UInt64(traversals.count) <= 9_007_199_254_740_992 else {
            throw GeometryConversionError.invalidInput("Original guide aggregate requires a representable positive source partition count.")
        }
        let stationCount = traversals.count.addingReportingOverflow(1)
        guard !stationCount.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original guide station count overflows.") }
        try RationalAlgebraStorage.retain(stationCount.partialValue, of: ExactRationalCoefficient.self, usage: &usage)
        var stations: [ExactRationalCoefficient] = []; stations.reserveCapacity(stationCount.partialValue)
        let count = try ExactRationalCoefficient.originalDouble(Double(traversals.count), usage: &usage)
        for index in 0...traversals.count {
            let numerator = try ExactRationalCoefficient.originalDouble(Double(index), usage: &usage)
            stations.append(try numerator.divided(by: count, usage: &usage))
        }
        return try OriginalGuideTraversalChain3D(traversals: traversals, stations: stations,
            sourceSegmentOrdinals: ordinals, remainingSourceDepth: usage.effectiveLimits.remainingSourceDepth,
            tolerance: tolerance, using: &usage)
    }

    private func checkedCopyCount(_ count: Int) throws -> Int {
        let copies = count.multipliedReportingOverflow(by: 2)
        guard !copies.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original guide source copy count overflows.") }
        return copies.partialValue
    }
}
