import CADCore

/// Exact native tensor screen incidence and original real edge-fiber lifting.
public struct OriginalNativeSilhouetteProjectedContactProducer: SurfaceSilhouetteProjectedContactProducing {
    public init() {}

    public func partition(edge: BSplineCurve3D, spanIndex: Int, over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve, frame: OrthographicProjectionFrame,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteProjectedPartition {
        return try silhouette.original.queryContext.withExecution(using: &execution) { execution in
        try partition(edge: .bSpline(edge), spanIndex: spanIndex, over: range,
            silhouette: silhouette, frame: frame, using: &execution)
    
        }
    }

    public func partition(edge: Curve3D, spanIndex: Int, over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve, frame: OrthographicProjectionFrame,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteProjectedPartition {
        return try silhouette.original.queryContext.withExecution(using: &execution) { execution in
        let pair = try OriginalProjectedNativePolynomialPair(edge: edge, spanIndex: spanIndex,
            over: range, silhouette: silhouette, frame: frame, usage: &execution)
        return try Self.partitionAfterPair(pair, over: range,
            silhouette: silhouette, using: &execution)
    
        }
    }

    @inline(never)
    private static func partitionAfterPair(_ pair: OriginalProjectedNativePolynomialPair,
        over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteProjectedPartition {
        var equations: [ExactBivariatePolynomial] = []
        try RationalAlgebraStorage.retain(5, of: ExactBivariatePolynomial.self, usage: &execution)
        equations.reserveCapacity(5); equations.append(pair.zeroLaw)
        if let eliminated = pair.eliminated {
            equations.append(eliminated)
        } else {
            if let horizontal = pair.horizontal.coefficients.first { equations.append(horizontal) }
            if let vertical = pair.vertical.coefficients.first { equations.append(vertical) }
        }
        let domain = try Self.isolationDomain(silhouette.original.chart,
            equations: &equations, usage: &execution)
        let roots: [ExactBivariateSystemRoot]
        do {
            roots = try ExactBivariateSystemSolver.isolatedRoots(of: equations, over: domain,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        } catch let classification as ExactBivariateSystemClassification {
            switch classification {
            case .positiveDimensionalOriginalIdeal:
                // FIXME(INCOMPLETE_IMPLEMENTATION): This actual native D1
                // path must decompose original positive-dimensional screen incidence
                // and lift its real common edge sections before declaring coverage.
                // Finite-ideal classification is not a substitute for overlap output.
                let locus = try OriginalProjectedNativeLocus(original: pair, domain: domain, usage: &execution)
                throw OriginalProjectedNativeSectionFailure(originalLocus: locus)
            }
        }
        var contacts: [SurfaceSilhouetteProjectedContact] = []
        var cuts: [SurfaceSilhouetteTrimEndpoint] = []
        let context = try OriginalSingularFieldContext(usage: &execution)
        for index in 0..<2 {
            let endpoint = index == 0 ? range.lower : range.upper
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
            cuts.append(try .init(.constant(.originalDouble(endpoint, usage: &execution), in: context,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution), depth: 0, using: &execution))
        }
        var wholeRange = false
        for root in roots {
            let fiber = try OriginalProjectedNativeFiber(original: pair, at: root, usage: &execution)
            if fiber.parameters.isEmpty { continue }
            let branchParameters = try silhouette.original.projectedOriginalParameters(at: root,
                in: fiber.context, usage: &execution)
            for parameter in branchParameters {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
                let branch = try SurfaceSilhouetteTrimEndpoint(parameter, depth: parameter.context.depth, using: &execution)
                if try branch.compare(to: silhouette.lower, using: &execution) < 0 { continue }
                if try branch.compare(to: silhouette.upper, using: &execution) > 0 { continue }
                for edgeParameter in fiber.parameters {
                    switch edgeParameter {
                    case .wholeNativeRange:
                        wholeRange = true
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedContact.self, usage: &execution)
                        contacts.append(.init(edgeParameter: nil, silhouetteParameter: branch,
                            edgeMultiplicity: 0, wholeRange: true, originalUV: root, originalFiber: fiber,
                            depthDifference: nil))
                    case .isolated(_, let value, let multiplicity):
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
                        let station = try SurfaceSilhouetteTrimEndpoint(value, depth: value.context.depth, using: &execution)
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedContact.self, usage: &execution)
                        let depth = try OriginalProjectedNativeDepth.difference(original: pair,
                            at: value, uvContext: fiber.context, usage: &execution)
                        contacts.append(.init(edgeParameter: station, silhouetteParameter: branch,
                            edgeMultiplicity: multiplicity, wholeRange: false, originalUV: root, originalFiber: fiber,
                            depthDifference: depth))
                        try Self.insert(station, into: &cuts, usage: &execution)
                    }
                }
            }
        }
        var sectors: [SurfaceSilhouetteProjectedPartition.Sector] = []
        if !wholeRange {
            for index in 1..<cuts.count {
                let lower = cuts[index - 1], upper = cuts[index]
                let witness = try lower.interiorWitness(before: upper, using: &execution)
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedPartition.Sector.self, usage: &execution)
                sectors.append(.init(lower: lower, upper: upper, originalInteriorWitness: witness))
            }
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedPartition.self, usage: &execution)
        return .init(original: pair, contacts: contacts,
            cuts: cuts, sectors: sectors, wholeRange: wholeRange)
    }

    private static func insert(_ station: SurfaceSilhouetteTrimEndpoint,
        into cuts: inout [SurfaceSilhouetteTrimEndpoint], usage: inout OriginalQueryExecution) throws {
        var index = 0
        while index < cuts.count {
            try usage.consumeWork(1)
            let comparison = try station.compare(to: cuts[index], using: &usage)
            if comparison == 0 { return }
            if comparison < 0 { break }
            index += 1
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
        // Array insertion moves actual retained source slots; every moved slot is work.
        try usage.consumeWork(cuts.count - index)
        cuts.insert(station, at: index)
    }

    private static func isolationDomain(_ original: SurfaceParameterBox,
        equations: inout [ExactBivariatePolynomial], usage: inout OriginalQueryExecution)
        throws -> SurfaceParameterBox {
        func axis(_ range: ScalarInterval, alongU: Bool) throws -> ScalarInterval {
            if range.width > 0 { return range }
            guard range.lower.isFinite, range.lower.nextDown.isFinite, range.upper.nextUp.isFinite else {
                throw rationalAlgebraFailure("Original coordinate singleton has no finite isolation neighborhood.")
            }
            let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            equations.append(try coordinate.subtracting(.constant(.originalDouble(range.lower, usage: &usage),
                usage: &usage), usage: &usage))
            return try .init(lower: range.lower.nextDown, upper: range.upper.nextUp)
        }
        let u = try axis(original.u, alongU: true), v = try axis(original.v, alongU: false)
        return try .init(u: u, v: v)
    }
}
