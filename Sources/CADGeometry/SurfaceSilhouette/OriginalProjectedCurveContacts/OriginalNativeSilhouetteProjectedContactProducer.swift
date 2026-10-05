import CADCore

/// Exact native tensor screen incidence and original real edge-fiber lifting.
public struct OriginalNativeSilhouetteProjectedContactProducer: SurfaceSilhouetteProjectedContactProducing {
    public init() {}

    public func partition(edge: BSplineCurve3D, spanIndex: Int, over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve, frame: OrthographicProjectionFrame,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteProjectedPartition {
        try partition(edge: .bSpline(edge), spanIndex: spanIndex, over: range,
            silhouette: silhouette, frame: frame, usage: &usage)
    }

    public func partition(edge: Curve3D, spanIndex: Int, over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve, frame: OrthographicProjectionFrame,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteProjectedPartition {
        let pair = try OriginalProjectedNativePolynomialPair(edge: edge, spanIndex: spanIndex,
            over: range, silhouette: silhouette, frame: frame, usage: &usage)
        var equations: [ExactBivariatePolynomial] = []
        try RationalAlgebraStorage.retain(5, of: ExactBivariatePolynomial.self, usage: &usage)
        equations.reserveCapacity(5); equations.append(pair.zeroLaw)
        if let eliminated = pair.eliminated {
            equations.append(eliminated)
        } else {
            if let horizontal = pair.horizontal.coefficients.first { equations.append(horizontal) }
            if let vertical = pair.vertical.coefficients.first { equations.append(vertical) }
        }
        let domain = try Self.isolationDomain(silhouette.original.chart,
            equations: &equations, usage: &usage)
        let roots: [ExactBivariateSystemRoot]
        do {
            roots = try ExactBivariateSystemSolver.isolatedRoots(of: equations, over: domain,
                maximumDepth: usage.maximumDepth, usage: &usage)
        } catch let classification as ExactBivariateSystemClassification {
            switch classification {
            case .positiveDimensionalOriginalIdeal:
                // FIXME(INCOMPLETE_IMPLEMENTATION): This actual native D1
                // path must decompose original positive-dimensional screen incidence
                // and lift its real common edge sections before declaring coverage.
                // Finite-ideal classification is not a substitute for overlap output.
                let locus = try OriginalProjectedNativeLocus(original: pair, domain: domain, usage: &usage)
                throw OriginalProjectedNativeSectionFailure(originalLocus: locus)
            }
        }
        var contacts: [SurfaceSilhouetteProjectedContact] = []
        var cuts: [SurfaceSilhouetteTrimEndpoint] = []
        let context = try OriginalSingularFieldContext(usage: &usage)
        for index in 0..<2 {
            let endpoint = index == 0 ? range.lower : range.upper
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
            cuts.append(.init(try .constant(.originalDouble(endpoint, usage: &usage), in: context,
                maximumDepth: usage.maximumDepth, usage: &usage), depth: 0))
        }
        var wholeRange = false
        for root in roots {
            let fiber = try OriginalProjectedNativeFiber(original: pair, at: root, usage: &usage)
            if fiber.parameters.isEmpty { continue }
            let branchParameters = try silhouette.original.projectedOriginalParameters(at: root,
                in: fiber.context, usage: &usage)
            for parameter in branchParameters {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                let branch = SurfaceSilhouetteTrimEndpoint(parameter, depth: parameter.context.depth)
                if try branch.compare(to: silhouette.lower, usage: &usage) < 0 { continue }
                if try branch.compare(to: silhouette.upper, usage: &usage) > 0 { continue }
                for edgeParameter in fiber.parameters {
                    switch edgeParameter {
                    case .wholeNativeRange:
                        wholeRange = true
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedContact.self, usage: &usage)
                        contacts.append(.init(edgeParameter: nil, silhouetteParameter: branch,
                            edgeMultiplicity: 0, wholeRange: true, originalUV: root, originalFiber: fiber,
                            depthDifference: nil))
                    case .isolated(_, let value, let multiplicity):
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                        let station = SurfaceSilhouetteTrimEndpoint(value, depth: value.context.depth)
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedContact.self, usage: &usage)
                        let depth = try OriginalProjectedNativeDepth.difference(original: pair,
                            at: value, uvContext: fiber.context, usage: &usage)
                        contacts.append(.init(edgeParameter: station, silhouetteParameter: branch,
                            edgeMultiplicity: multiplicity, wholeRange: false, originalUV: root, originalFiber: fiber,
                            depthDifference: depth))
                        try Self.insert(station, into: &cuts, usage: &usage)
                    }
                }
            }
        }
        var sectors: [SurfaceSilhouetteProjectedPartition.Sector] = []
        if !wholeRange {
            for index in 1..<cuts.count {
                let lower = cuts[index - 1], upper = cuts[index]
                let witness = try lower.interiorWitness(before: upper, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedPartition.Sector.self, usage: &usage)
                sectors.append(.init(lower: lower, upper: upper, originalInteriorWitness: witness))
            }
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProjectedPartition.self, usage: &usage)
        return .init(edge: edge, spanIndex: spanIndex, original: pair, contacts: contacts,
            cuts: cuts, sectors: sectors, wholeRange: wholeRange)
    }

    private static func insert(_ station: SurfaceSilhouetteTrimEndpoint,
        into cuts: inout [SurfaceSilhouetteTrimEndpoint], usage: inout SurfaceSilhouetteUsage) throws {
        var index = 0
        while index < cuts.count {
            try usage.consumeWork()
            let comparison = try station.compare(to: cuts[index], usage: &usage)
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
        equations: inout [ExactBivariatePolynomial], usage: inout SurfaceSilhouetteUsage)
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
