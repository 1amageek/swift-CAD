import CADCore

/// Orders existing scalar contact receipts and retains the actual source partition.
struct OriginalPlanarCurveCutProducer {
    private struct Station {
        var coordinate: ExactMonotoneGraphEndpoint
        let eventIndex: Int?
    }

    func produce(source: BSplineCurve3D, parameters: ScalarInterval,
        events: [OriginalPlanarCurveContactEvent], firstSource: Bool,
        mergeEndpoints: [OriginalCurveRootEndpoint]? = nil,
        budget: inout NativeCurveCurveContactBudget)
        throws -> (cuts: [OriginalPlanarCurveContactCut], segments: [OriginalPlanarCurveContactSegment]) {
        var cuts: [OriginalPlanarCurveContactCut] = []
        var segments: [OriginalPlanarCurveContactSegment] = []
        for owner in source.degree..<source.controlPointCount {
            try budget.work(1)
            let lower = max(parameters.lower, source.knots[owner])
            let upper = min(parameters.upper, source.knots[owner + 1])
            guard lower < upper else { continue }
            try RationalAlgebraStorage.retain(2, of: Station.self, usage: &budget)
            let exactLower = try ExactRationalCoefficient.originalDouble(lower, usage: &budget)
            let exactUpper = try ExactRationalCoefficient.originalDouble(upper, usage: &budget)
            var stations: [Station] = [
                .init(coordinate: .authored(exactLower), eventIndex: nil),
                .init(coordinate: .authored(exactUpper), eventIndex: nil)
            ]
            let inputCount = mergeEndpoints?.count ?? events.count
            for index in 0..<inputCount {
                try budget.work(1)
                let endpoint: OriginalCurveRootEndpoint
                if let mergeEndpoints {
                    endpoint = mergeEndpoints[index]
                    switch endpoint {
                    case .authored(let value):
                        guard value >= lower, value <= upper else { continue }
                    case .algebraic(let retained):
                        guard retained.spanIndex == owner else { continue }
                    }
                } else {
                    let event = events[index]
                    guard (firstSource ? event.firstNativeSpanIndex : event.secondNativeSpanIndex) == owner else { continue }
                    endpoint = firstSource ? event.firstEndpoint : event.secondEndpoint
                }
                let coordinate: ExactMonotoneGraphEndpoint
                switch endpoint {
                case .authored(let value): coordinate = try .authored(.originalDouble(value, usage: &budget))
                case .algebraic(let retained): coordinate = retained.retainedRootEndpoint
                }
                try RationalAlgebraStorage.retain(1, of: Station.self, usage: &budget)
                stations.append(.init(coordinate: coordinate, eventIndex: index))
            }
            try sort(&stations, budget: &budget)
            if mergeEndpoints != nil {
                var first = stations[0].coordinate, last = stations[stations.count - 1].coordinate
                var expectedLower = ExactMonotoneGraphEndpoint.authored(exactLower)
                var expectedUpper = ExactMonotoneGraphEndpoint.authored(exactUpper)
                guard try compare(&first, &expectedLower, budget: &budget) == 0,
                    try compare(&last, &expectedUpper, budget: &budget) == 0 else {
                    throw GeometryConversionError.invalidInput("Merged source cut lies outside its declared original trim.")
                }
            }
            var index = 0
            let firstCut = cuts.count
            while index < stations.count {
                var coordinate = stations[index].coordinate
                var eventIndices: [Int] = []
                var next = index
                while next < stations.count {
                    var candidate = stations[next].coordinate
                    let order = try compare(&coordinate, &candidate, budget: &budget)
                    stations[next].coordinate = candidate
                    guard order == 0 else { break }
                    if let event = stations[next].eventIndex {
                        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &budget)
                        eventIndices.append(event)
                    }
                    next += 1
                }
                let endpoint: OriginalCurveRootEndpoint
                switch coordinate {
                case .authored(let rational):
                    let enclosure = try rational.outwardInterval(usage: &budget)
                    guard enclosure.lower == enclosure.upper else { throw budget.exhausted() }
                    endpoint = .authored(enclosure.lower)
                case .algebraic(let root):
                    endpoint = try .algebraic(OriginalCurveRootBoundary.retaining(source: source,
                        spanIndex: owner, coordinate: root, maximumSubdivisionDepth: budget.maximumSubdivisionDepth,
                        tolerance: budget.tolerance, usage: &budget,
                        maximumAlgebraicDepth: budget.maximumAlgebraicDepth))
                }
                try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactCut.self, usage: &budget)
                cuts.append(.init(endpoint: endpoint, nativeSpanIndex: owner, eventIndices: eventIndices))
                index = next
            }
            guard cuts.count - firstCut >= 2 else { throw budget.exhausted() }
            for lowerIndex in firstCut..<(cuts.count - 1) {
                let upperIndex = lowerIndex + 1
                let maximumSpans = max(1, budget.availableWork)
                let span = try OriginalCurveRootSpan3D(source: .bSpline(source),
                    start: cuts[lowerIndex].endpoint, end: cuts[upperIndex].endpoint, nativeSpanIndex: owner,
                    maximumParameterWidth: budget.tolerance.relative,
                    maximumSubdivisionDepth: budget.maximumSubdivisionDepth, tolerance: budget.tolerance,
                    storageByteStride: MemoryLayout<UInt32>.stride, usage: &budget,
                    maximumSpanCount: maximumSpans, remainingSourceDepth: 0,
                    maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
                try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactSegment.self, usage: &budget)
                segments.append(.init(lowerCutIndex: lowerIndex, upperCutIndex: upperIndex, originalSpan: span))
            }
        }
        return (cuts, segments)
    }

    /// Refinement changes derived isolation only and starts at each retained depth.
    private func compare(_ first: inout ExactMonotoneGraphEndpoint,
        _ second: inout ExactMonotoneGraphEndpoint, budget: inout NativeCurveCurveContactBudget) throws -> Int {
        try ExactOrderedRealEndpoints.compare(&first, &second,
            maximumDepth: budget.maximumDepth, usage: &budget)
    }

    /// Stable bounded merge ordering retains refined roots rather than re-isolating.
    private func sort(_ stations: inout [Station], budget: inout NativeCurveCurveContactBudget) throws {
        guard stations.count > 1 else { return }
        try RationalAlgebraStorage.retain(stations.count, of: Station.self, usage: &budget)
        var scratch = Array(repeating: stations[0], count: stations.count)
        var width = 1
        while width < stations.count {
            var start = 0
            while start < stations.count {
                let middle = min(stations.count, start + width)
                let end = min(stations.count, middle + width)
                var a = start, b = middle, output = start
                while a < middle || b < end {
                    try budget.work(1)
                    if a == middle { scratch[output] = stations[b]; b += 1 }
                    else if b == end { scratch[output] = stations[a]; a += 1 }
                    else {
                        var left = stations[a], right = stations[b]
                        let order = try compare(&left.coordinate, &right.coordinate, budget: &budget)
                        stations[a] = left; stations[b] = right
                        if order <= 0 { scratch[output] = left; a += 1 }
                        else { scratch[output] = right; b += 1 }
                    }
                    output += 1
                }
                start = end
            }
            swap(&stations, &scratch)
            if width > stations.count / 2 { break }
            width *= 2
        }
    }
}
