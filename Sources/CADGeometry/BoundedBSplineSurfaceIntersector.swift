import Foundation
import CADCore

struct BoundedBSplineSurfaceIntersector {
    private struct DomainBounds: Sendable {
        let firstU: (lower: Double, upper: Double)
        let firstV: (lower: Double, upper: Double)
        let secondU: (lower: Double, upper: Double)
        let secondV: (lower: Double, upper: Double)

        var spans: [Double] {
            [
                firstU.upper - firstU.lower,
                firstV.upper - firstV.lower,
                secondU.upper - secondU.lower,
                secondV.upper - secondV.lower,
            ]
        }

        var lowerBounds: [Double] {
            [firstU.lower, firstV.lower, secondU.lower, secondV.lower]
        }

        func actual(_ normalized: [Double]) -> [Double] {
            [
                interpolate(firstU, normalized[0]),
                interpolate(firstV, normalized[1]),
                interpolate(secondU, normalized[2]),
                interpolate(secondV, normalized[3]),
            ]
        }

        func normalized(_ actual: [Double]) -> [Double] {
            [
                fraction(firstU, actual[0]),
                fraction(firstV, actual[1]),
                fraction(secondU, actual[2]),
                fraction(secondV, actual[3]),
            ]
        }

        private func interpolate(_ bounds: (lower: Double, upper: Double), _ fraction: Double) -> Double {
            bounds.lower + (bounds.upper - bounds.lower) * fraction
        }

        private func fraction(_ bounds: (lower: Double, upper: Double), _ value: Double) -> Double {
            (value - bounds.lower) / (bounds.upper - bounds.lower)
        }
    }

    private struct PairSample: Sendable {
        let normalized: [Double]
        let actual: [Double]
        let firstPoint: Point3D
        let secondPoint: Point3D
        let point: Point3D
        let residual: Double
    }

    private struct PatchPair: Sendable {
        let first: RationalBezierSurfacePatch3D
        let second: RationalBezierSurfacePatch3D
        let difference: RationalBezierSurfaceSurfaceDifferencePatch
    }

    private struct UnresolvedPatchPair: Sendable {
        let pair: PatchPair
        let reason: String
    }

    private struct CertifiedRegularGraphCell: Sendable {
        let bounds: [(lower: Double, upper: Double)]
        let freeParameterIndex: Int
        let probes: [PairSample]
    }

    private enum GraphCellCertificationAttempt {
        case certified(CertifiedRegularGraphCell)
        case unresolved(CertifiedRegularGraphCell, KernelError)
    }

    private struct CertifiedBoundaryRootCell: Sendable {
        let pair: PatchPair
        let fixedParameterIndex: Int
        let side: RationalBezierSurfaceSurfaceDifferencePatch.BoundarySide
    }

    private struct BoundaryRootPairing: Sendable {
        let freeParameterIndex: Int
        let components: [[PairSample]]
    }

    private enum BoundarySeedProof {
        case complete
        case incomplete(String)
    }

    private struct SplineDerivatives: Sendable {
        let point: Vector3D
        let firstParameter: Point2D
        let secondParameter: Point2D
    }

    private struct TangencyPreflight {
        var isolatedContacts: [PairSample]
        var contactComponents: [[PairSample]]
        var branchingComponents: [[PairSample]]
    }

    func intersections(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        if first == second {
            return [.coincident(try SurfaceSurfaceCoincidence(
                residual: 0.0,
                tolerance: tolerance
            ))]
        }
        let domains = try domainBounds(first: first, second: second, tolerance: tolerance)
        let quadraticTangencyCertificate = try QuadraticHeightFieldTangencyCertificate
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            )
        if let quadraticTangencyCertificate {
            return try certifiedQuadraticTangencyIntersections(
                quadraticTangencyCertificate,
                first: first,
                second: second,
                tolerance: tolerance
            )
        }
        if let quarticTangencyCertificate = try QuarticHeightFieldTangencyCertificate
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            ) {
            let witness = quarticTangencyCertificate.witness
            return [.point(try SurfaceSurfaceIntersectionPoint(
                point: witness.point,
                firstSurfaceParameter: witness.firstParameter,
                secondSurfaceParameter: witness.secondParameter,
                residual: max(
                    witness.firstParameter.residual,
                    witness.secondParameter.residual
                ),
                tolerance: tolerance
            ))]
        }
        if let exactGraphs = try ExactIsoparametricPlanarIntersectionGraph.certified(
            first: first,
            second: second,
            tolerance: tolerance
        ) {
            return [try exactIsoparametricPlanarIntersection(
                exactGraphs,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                domains: domains,
                options: options,
                tolerance: tolerance
            )]
        }
        if let exactGraph = try ExactAffineBilinearIntersectionGraph.certified(
            first: first,
            second: second,
            tolerance: tolerance
        ) {
            return [try exactAffineBilinearIntersection(
                exactGraph,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                domains: domains,
                options: options,
                tolerance: tolerance
            )]
        }
        let decomposer = BSplineSurfaceBezierDecomposer()
        let firstPatches = try decomposer.surfacePatches(surface: first, tolerance: tolerance)
        let secondPatches = try decomposer.surfacePatches(surface: second, tolerance: tolerance)
        var seeds: [PairSample] = []
        var certifiedRegularGraphCells: [CertifiedRegularGraphCell] = []
        var unresolvedPairs: [UnresolvedPatchPair] = []
        var remainingSubdivisionCells = options.maximumSubdivisionCells
        var remainingRootAttempts = options.maximumRootAttempts
        var remainingBoundarySubdivisionCells = options.maximumBoundarySubdivisionCells
        var encounteredRankDeficientLeaf = false
        for firstPatch in firstPatches {
            for secondPatch in secondPatches {
                try collectSeeds(
                    pair: PatchPair(
                        first: firstPatch,
                        second: secondPatch,
                        difference: try RationalBezierSurfaceSurfaceDifferencePatch(
                            first: firstPatch,
                            second: secondPatch,
                            tolerance: tolerance
                        )
                    ),
                    depth: 0,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingSubdivisionCells: &remainingSubdivisionCells,
                    remainingRootAttempts: &remainingRootAttempts,
                    remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells,
                    encounteredRankDeficientLeaf: &encounteredRankDeficientLeaf,
                    seeds: &seeds,
                    certifiedRegularGraphCells: &certifiedRegularGraphCells,
                    unresolvedPairs: &unresolvedPairs
                )
            }
        }
        seeds.sort { lexicographicallyPrecedes($0.normalized, $1.normalized) }
        guard seeds.isEmpty == false else {
            if unresolvedPairs.isEmpty { return [] }
            throw resourceLimit(
                tolerance: tolerance,
                message: unresolvedPairs[0].reason
            )
        }

        var remainingPointCount = min(max(options.maximumSeedCount * 64, 4_096), 65_536)
        let tangencies = try preflightTangencies(
            seeds: seeds,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        var transverseComponents: [[PairSample]] = []
        for seed in seeds {
            if try isRepresented(seed, by: transverseComponents, tolerance: tolerance)
                || isRepresented(seed, by: tangencies.isolatedContacts, tolerance: tolerance)
                || (try isRepresented(seed, by: tangencies.contactComponents, tolerance: tolerance))
                || (try isRepresented(seed, by: tangencies.branchingComponents, tolerance: tolerance)) {
                continue
            }
            let component = try marchedComponent(
                from: seed,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            if component.count >= 2 {
                transverseComponents.append(component)
            }
        }
        for graphCell in certifiedRegularGraphCells {
            let represented = isRepresented(
                graphCell,
                by: transverseComponents
                    + tangencies.contactComponents
                    + tangencies.branchingComponents,
                tolerance: tolerance
            )
            if represented { continue }
            let component = try marchedComponent(
                from: graphCell.probes[1],
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            if component.count >= 2 {
                transverseComponents.append(component)
            }
        }
        transverseComponents = consolidatedComponents(
            transverseComponents,
            tolerance: tolerance
        )
        let allComponents = transverseComponents
            + tangencies.contactComponents
            + tangencies.branchingComponents
        if encounteredRankDeficientLeaf {
            throw resourceLimit(
                tolerance: tolerance,
                message: "A rank-deficient surface intersection leaf lacks a complete tangency-locus certificate."
            )
        }
        for unresolved in unresolvedPairs {
            guard isParameterCovered(
                unresolved.pair,
                by: allComponents,
                isolatedContacts: tangencies.isolatedContacts,
                domains: domains
            ) else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: unresolved.reason
                )
            }
        }
        for component in transverseComponents where component.count >= 2 {
            let isCovered = component.allSatisfy { sample in
                certifiedRegularGraphCells.contains { graphCell in
                    zip(sample.normalized, graphCell.bounds).allSatisfy {
                        value, bounds in
                        value >= bounds.lower - 1.0e-8
                            && value <= bounds.upper + 1.0e-8
                    }
                }
            }
            if isCovered == false {
                certifiedRegularGraphCells.removeAll { graphCell in
                    isRepresented(
                        graphCell,
                        by: [component],
                        tolerance: tolerance
                    )
                }
                certifiedRegularGraphCells.append(
                    contentsOf: try supplementalCertifiedGraphCells(
                        for: component,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingRootAttempts: &remainingRootAttempts,
                        remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
                    )
                )
            }
        }
        for graphCell in certifiedRegularGraphCells {
            guard isRepresented(
                graphCell,
                by: allComponents,
                tolerance: tolerance
            ) else {
                let graphBounds = graphCell.bounds.flatMap {
                    [$0.lower, $0.upper]
                }
                let graphProbes = graphCell.probes.map(\.normalized)
                let componentDiagnostics = allComponents.map { component in
                    let bounds = (0..<4).map { index in
                        let values = component.map { $0.normalized[index] }
                        return [values.min() ?? .infinity, values.max() ?? -.infinity]
                    }
                    let representedProbes = graphCell.probes.map {
                        componentRepresents(
                            probe: $0,
                            in: graphCell,
                            component: component,
                            tolerance: tolerance
                        )
                    }
                    return "bounds=\(bounds), probes=\(representedProbes)"
                }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A certified regular intersection graph was not completely represented by one traced component. Graph bounds: \(graphBounds). Graph probes: \(graphProbes). Components: \(componentDiagnostics)."
                )
            }
        }
        let contactComponents = consolidatedComponents(
            tangencies.contactComponents,
            tolerance: tolerance
        )
        let branchingComponents = consolidatedComponents(
            tangencies.branchingComponents,
            tolerance: tolerance
        )
        let transverseCurves = try transverseComponents.map {
            try intersectionCurve(
                samples: $0,
                kind: .transverse,
                certifiedGraphCells: certifiedRegularGraphCells,
                domains: domains,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
        }
        let contactCurves = try contactComponents.map {
            try intersectionCurve(
                samples: $0,
                kind: .tangent,
                certifiedGraphCells: [],
                domains: domains,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
        }
        let branchingCurves = try branchingComponents.map {
            try intersectionCurve(
                samples: $0,
                kind: .mixed,
                certifiedGraphCells: [],
                domains: domains,
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
        }
        let points = try tangencies.isolatedContacts.map {
            try intersectionPoint(
                sample: $0,
                first: first,
                second: second,
                tolerance: tolerance
            )
        }
        return transverseCurves + contactCurves + branchingCurves + points
    }

    private func exactIsoparametricPlanarIntersection(
        _ exactGraphs: ExactIsoparametricPlanarIntersectionGraph,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        var samples: [PairSample] = []
        var graphCells: [CertifiedRegularGraphCell] = []
        for cell in exactGraphs.cells {
            let sampleCount = 16
            let segmentSamples = try (0...sampleCount).map { index in
                let parameters = try exactGraphs.normalizedParameterPair(
                    in: cell,
                    at: Double(index) / Double(sampleCount),
                    tolerance: tolerance
                )
                return try pairSample(
                    normalized: parameters.values,
                    first: first,
                    second: second,
                    domains: domains,
                    tolerance: tolerance
                )
            }
            samples.append(contentsOf: samples.isEmpty
                ? segmentSamples
                : Array(segmentSamples.dropFirst()))
            let probes = try [0.0, 0.5, 1.0].map { fraction in
                let parameters = try exactGraphs.normalizedParameterPair(
                    in: cell,
                    at: fraction,
                    tolerance: tolerance
                )
                return try pairSample(
                    normalized: parameters.values,
                    first: first,
                    second: second,
                    domains: domains,
                    tolerance: tolerance
                )
            }
            graphCells.append(CertifiedRegularGraphCell(
                bounds: cell.normalizedBounds,
                freeParameterIndex: cell.freeParameter.rawValue,
                probes: probes
            ))
        }
        return try intersectionCurve(
            samples: samples,
            kind: .transverse,
            certifiedGraphCells: graphCells,
            domains: domains,
            first: first,
            second: second,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            preservesSampleOrientation: true,
            tolerance: tolerance
        )
    }

    private func exactAffineBilinearIntersection(
        _ exactGraph: ExactAffineBilinearIntersectionGraph,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let fractions = (0...16).map { Double($0) / 16.0 }
        let samples = try fractions.map { fraction in
            let parameters = try exactGraph.normalizedParameterPair(
                at: fraction,
                tolerance: tolerance
            )
            return try pairSample(
                normalized: parameters.values,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
        }
        let graphProbes = try [0.0, 0.5, 1.0].map { fraction in
            let parameters = try exactGraph.normalizedParameterPair(
                at: fraction,
                tolerance: tolerance
            )
            return try pairSample(
                normalized: parameters.values,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
        }
        let graphCell = CertifiedRegularGraphCell(
            bounds: Array(
                repeating: (lower: 0.0, upper: 1.0),
                count: 4
            ),
            freeParameterIndex: exactGraph.freeParameter.rawValue,
            probes: graphProbes
        )
        return try intersectionCurve(
            samples: samples,
            kind: .transverse,
            certifiedGraphCells: [graphCell],
            domains: domains,
            first: first,
            second: second,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func supplementalCertifiedGraphCells(
        for component: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [CertifiedRegularGraphCell] {
        let candidates = (0..<4).filter { index in
            let values = component.map { $0.normalized[index] }
            guard let lower = values.min(), let upper = values.max(),
                  upper - lower > tolerance.relative else {
                return false
            }
            let nondecreasing = zip(values, values.dropFirst()).allSatisfy {
                $0.1 >= $0.0 - tolerance.relative
            }
            let nonincreasing = zip(values, values.dropFirst()).allSatisfy {
                $0.1 <= $0.0 + tolerance.relative
            }
            return nondecreasing || nonincreasing
        }.sorted { firstIndex, secondIndex in
            let firstValues = component.map { $0.normalized[firstIndex] }
            let secondValues = component.map { $0.normalized[secondIndex] }
            let firstSpan = (firstValues.max() ?? 0.0) - (firstValues.min() ?? 0.0)
            let secondSpan = (secondValues.max() ?? 0.0) - (secondValues.min() ?? 0.0)
            if firstSpan != secondSpan { return firstSpan > secondSpan }
            return firstIndex < secondIndex
        }
        var failures: [String] = []
        for freeParameterIndex in candidates {
            let endpoints = [component[0], component[component.count - 1]].sorted {
                $0.normalized[freeParameterIndex]
                    < $1.normalized[freeParameterIndex]
            }
            do {
                return try supplementalCertifiedGraphCells(
                    lowerRoot: endpoints[0],
                    upperRoot: endpoints[1],
                    component: component,
                    freeParameterIndex: freeParameterIndex,
                    depth: 0,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingRootAttempts: &remainingRootAttempts,
                    remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
                )
            } catch let error as KernelError {
                failures.append(
                    "Free parameter \(freeParameterIndex): \(error.message)"
                )
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "Traced component samples could not supplement complete graph coverage: "
                + failures.joined(separator: " | ")
        )
    }

    private func supplementalCertifiedGraphCells(
        lowerRoot: PairSample,
        upperRoot: PairSample,
        component: [PairSample],
        freeParameterIndex: Int,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [CertifiedRegularGraphCell] {
        guard remainingBoundarySubdivisionCells > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Supplemental graph certification exhausted its subdivision-cell limit."
            )
        }
        remainingBoundarySubdivisionCells -= 1
        let lowerFree = lowerRoot.normalized[freeParameterIndex]
        let upperFree = upperRoot.normalized[freeParameterIndex]
        guard upperFree - lowerFree > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Supplemental graph endpoints do not span a free-parameter interval."
            )
        }
        let segmentSamples = component.filter {
            let value = $0.normalized[freeParameterIndex]
            return value >= lowerFree - tolerance.relative
                && value <= upperFree + tolerance.relative
        }
        var bounds = (0..<4).map { index -> (lower: Double, upper: Double) in
            if index == freeParameterIndex {
                return (lowerFree, upperFree)
            }
            let values = segmentSamples.map { $0.normalized[index] }
                + [lowerRoot.normalized[index], upperRoot.normalized[index]]
            let anchorLower = values.min() ?? 0.0
            let anchorUpper = values.max() ?? 1.0
            let margin = max(
                max((anchorUpper - anchorLower) * 1.0e-2, 1.0e-3),
                tolerance.relative * 16.0
            )
            return (
                max(0.0, (anchorLower - margin).nextDown),
                min(1.0, (anchorUpper + margin).nextUp)
            )
        }
        let midpointFree = midpoint(lowerFree, upperFree)
        var midpointSeed = zip(
            lowerRoot.normalized,
            upperRoot.normalized
        ).map { midpoint($0.0, $0.1) }
        midpointSeed[freeParameterIndex] = midpointFree
        try consumeRootAttempt(
            remainingRootAttempts: &remainingRootAttempts,
            tolerance: tolerance
        )
        guard let midpointProbe = try gaugeIntersectionSample(
            seed: midpointSeed,
            fixedParameterIndex: freeParameterIndex,
            constraints: bounds,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Supplemental graph midpoint refinement failed."
            )
        }
        bounds[freeParameterIndex] = (lowerFree, upperFree)
        let graphCell = CertifiedRegularGraphCell(
            bounds: bounds,
            freeParameterIndex: freeParameterIndex,
            probes: [lowerRoot, midpointProbe, upperRoot]
        )
        switch try certifiedContractedGraphCell(
            graphCell,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) {
        case let .certified(certified):
            return [certified]
        case let .unresolved(_, error):
            guard depth < options.maximumBoundarySubdivisionDepth else {
                throw error
            }
            let lowerCells = try supplementalCertifiedGraphCells(
                lowerRoot: lowerRoot,
                upperRoot: midpointProbe,
                component: component,
                freeParameterIndex: freeParameterIndex,
                depth: depth + 1,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingRootAttempts: &remainingRootAttempts,
                remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
            )
            let upperCells = try supplementalCertifiedGraphCells(
                lowerRoot: midpointProbe,
                upperRoot: upperRoot,
                component: component,
                freeParameterIndex: freeParameterIndex,
                depth: depth + 1,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingRootAttempts: &remainingRootAttempts,
                remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
            )
            return lowerCells + upperCells
        }
    }

    private func certifiedQuadraticTangencyIntersections(
        _ certificate: QuadraticHeightFieldTangencyCertificate,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        switch certificate.kind {
        case let .isolated(witness):
            return [.point(try SurfaceSurfaceIntersectionPoint(
                point: witness.point,
                firstSurfaceParameter: witness.firstParameter,
                secondSurfaceParameter: witness.secondParameter,
                residual: max(
                    witness.firstParameter.residual,
                    witness.secondParameter.residual
                ),
                tolerance: tolerance
            ))]
        case .contact, .branching:
            let componentCount = try CertifiedQuadraticTangencyIntersectionCurve
                .componentCount(
                    firstSurface: first,
                    secondSurface: second,
                    tolerance: tolerance
                )
            return try (0..<componentCount).map { componentIndex in
                let truth = try CertifiedQuadraticTangencyIntersectionCurve(
                    firstSurface: first,
                    secondSurface: second,
                    componentIndex: componentIndex,
                    tolerance: tolerance
                )
                return .curve(try SurfaceSurfaceIntersectionCurve(
                    truth: .quadraticTangency(truth),
                    derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                        curve: truth.curve,
                        firstSurfaceParameterCurve: truth.firstSurfaceParameterCurve,
                        secondSurfaceParameterCurve: truth.secondSurfaceParameterCurve,
                        maximumResidualUpperBound: truth.maximumResidualUpperBound,
                        tolerance: tolerance
                    ),
                    kind: truth.kind,
                    firstSurfaceAnchor: truth.firstSurfaceAnchor,
                    secondSurfaceAnchor: truth.secondSurfaceAnchor,
                    tolerance: tolerance
                ))
            }
        }
    }

    private func preflightTangencies(
        seeds: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> TangencyPreflight {
        let orderedSeeds = try seeds.map { seed in
            let firstNormal = try first.normal(
                u: seed.actual[0],
                v: seed.actual[1],
                tolerance: tolerance
            )
            let secondNormal = try second.normal(
                u: seed.actual[2],
                v: seed.actual[3],
                tolerance: tolerance
            )
            return (seed: seed, normalResidual: firstNormal.cross(secondNormal).length)
        }.sorted { firstCandidate, secondCandidate in
            if firstCandidate.normalResidual != secondCandidate.normalResidual {
                return firstCandidate.normalResidual < secondCandidate.normalResidual
            }
            return lexicographicallyPrecedes(
                firstCandidate.seed.normalized,
                secondCandidate.seed.normalized
            )
        }
        var isolatedContacts: [PairSample] = []
        var contactComponents: [[PairSample]] = []
        var branchingComponents: [[PairSample]] = []
        for candidate in orderedSeeds
            where candidate.normalResidual <= BSplineSurfaceTangencyRefiner.maximumInitialAngularResidual {
            guard isRepresented(
                candidate.seed,
                by: isolatedContacts,
                tolerance: tolerance
            ) == false,
            isGeometricallyRepresented(
                candidate.seed,
                by: contactComponents,
                tolerance: tolerance
            ) == false,
            isGeometricallyRepresented(
                candidate.seed,
                by: branchingComponents,
                tolerance: tolerance
            ) == false,
            let contact = try BSplineSurfaceTangencyRefiner().refinedContact(
                near: candidate.seed.normalized,
                first: first,
                second: second,
                domainLowerBounds: domains.lowerBounds,
                domainSpans: domains.spans,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            ) else {
                continue
            }
            switch contact.classification {
            case .isolated:
                let sample = PairSample(
                    normalized: contact.normalizedParameters,
                    actual: contact.actualParameters,
                    firstPoint: contact.firstPoint,
                    secondPoint: contact.secondPoint,
                    point: interpolated(
                        contact.firstPoint,
                        contact.secondPoint,
                        fraction: 0.5
                    ),
                    residual: (contact.firstPoint - contact.secondPoint).length
                )
                if isRepresented(
                    sample,
                    by: isolatedContacts,
                    tolerance: tolerance
                ) == false {
                    isolatedContacts.append(sample)
                }
            case .contactCurve:
                let traced = try BSplineSurfaceContactCurveTracer().component(
                    from: contact,
                    first: first,
                    second: second,
                    domainLowerBounds: domains.lowerBounds,
                    domainSpans: domains.spans,
                    options: options,
                    tolerance: tolerance,
                    remainingPointCount: &remainingPointCount
                ).map {
                    PairSample(
                        normalized: $0.normalizedParameters,
                        actual: $0.actualParameters,
                        firstPoint: $0.firstPoint,
                        secondPoint: $0.secondPoint,
                        point: $0.point,
                        residual: $0.residual
                    )
                }
                if traced.count >= 2 {
                    contactComponents.append(traced)
                }
            case .branching:
                branchingComponents.append(contentsOf: try branchedComponents(
                    at: contact,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingPointCount: &remainingPointCount
                ))
            case .degenerate:
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: contact.normalResidual,
                    tolerance: tolerance,
                    message: "Bounded B-spline surfaces have a second-order-degenerate tangency."
                )
            }
        }
        return TangencyPreflight(
            isolatedContacts: isolatedContacts,
            contactComponents: contactComponents,
            branchingComponents: branchingComponents
        )
    }

    private func branchedComponents(
        at contact: BSplineSurfaceTangencyRefiner.Contact,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [[PairSample]] {
        guard contact.classification == .branching,
              contact.branchTangents.count == 2 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "Branching B-spline contact requires two certified Hessian-cone directions."
            )
        }
        let center = PairSample(
            normalized: contact.normalizedParameters,
            actual: contact.actualParameters,
            firstPoint: contact.firstPoint,
            secondPoint: contact.secondPoint,
            point: interpolated(contact.firstPoint, contact.secondPoint, fraction: 0.5),
            residual: (contact.firstPoint - contact.secondPoint).length
        )
        var result: [[PairSample]] = []
        for tangent in contact.branchTangents {
            let forward = try branchHalf(
                from: center,
                direction: tangent,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            let reverse = try branchHalf(
                from: center,
                direction: tangent.map { -$0 },
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
            let combined = Array(reverse.reversed()) + [center] + forward
            result.append(try refined(
                combined,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            ))
        }
        return result
    }

    private func branchHalf(
        from center: PairSample,
        direction: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        let baseStep = max(
            1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
            1.0 / 256.0
        )
        let boundaryStep = scaleToUnitBoundary(
            from: center.normalized,
            direction: direction,
            requestedStep: baseStep
        )
        guard boundaryStep > 1.0e-12 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A branching B-spline intersection direction terminates at its singular boundary point."
            )
        }
        let predictor = zip(center.normalized, direction).map {
            $0.0 + $0.1 * boundaryStep
        }
        guard let seed = try pseudoArclengthCorrection(
            predictor: predictor,
            tangent: direction,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A branching B-spline intersection could not enter its regular branch."
            )
        }
        var regularTangent = try intersectionTangent(
            sample: seed,
            first: first,
            second: second,
            domains: domains,
            maximumIterations: options.maximumIterations,
            tolerance: tolerance
        )
        if dot(regularTangent, direction) < 0.0 {
            regularTangent = regularTangent.map { -$0 }
        }
        return try march(
            from: seed,
            initialTangent: regularTangent,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
    }

    private func collectSeeds(
        pair: PatchPair,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingSubdivisionCells: inout Int,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int,
        encounteredRankDeficientLeaf: inout Bool,
        seeds: inout [PairSample],
        certifiedRegularGraphCells: inout [CertifiedRegularGraphCell],
        unresolvedPairs: inout [UnresolvedPatchPair]
    ) throws {
        guard remainingSubdivisionCells > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Bounded surface intersection exceeded its subdivision-cell limit."
            )
        }
        remainingSubdivisionCells -= 1
        guard pair.difference.excludesZero(tolerance: tolerance) == false else {
            return
        }
        let shouldAttemptEarlyGraph = depth.isMultiple(of: 2)
        let earlyGaugeCertificate = shouldAttemptEarlyGraph
            ? pair.difference.gaugeRootCertificate()
            : nil
        if case .cellEmpty? = earlyGaugeCertificate {
            return
        }
        if case let .fullGraph(freeParameterIndex)? = earlyGaugeCertificate {
            let graphCell = try certifiedRegularGraphCell(
                pair: pair,
                freeParameterIndex: freeParameterIndex,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingRootAttempts: &remainingRootAttempts
            )
            certifiedRegularGraphCells.append(graphCell)
            let midpointProbe = graphCell.probes[1]
            try appendDistinctSeed(
                midpointProbe,
                to: &seeds,
                maximumSeedCount: options.maximumSeedCount,
                tolerance: tolerance
            )
            return
        }
        if depth < options.maximumSubdivisionDepth {
            if depth.isMultiple(of: 2) {
                let surfaceChildren = try pair.first.subdivided()
                let differenceChildren = pair.difference.subdividedFirstSurface()
                guard surfaceChildren.count == differenceChildren.count else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "First surface and homogeneous difference subdivision disagree."
                    )
                }
                for index in surfaceChildren.indices {
                    try collectSeeds(
                        pair: PatchPair(
                            first: surfaceChildren[index],
                            second: pair.second,
                            difference: differenceChildren[index]
                        ),
                        depth: depth + 1,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingSubdivisionCells: &remainingSubdivisionCells,
                        remainingRootAttempts: &remainingRootAttempts,
                        remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells,
                        encounteredRankDeficientLeaf: &encounteredRankDeficientLeaf,
                        seeds: &seeds,
                        certifiedRegularGraphCells: &certifiedRegularGraphCells,
                        unresolvedPairs: &unresolvedPairs
                    )
                }
            } else {
                let surfaceChildren = try pair.second.subdivided()
                let differenceChildren = pair.difference.subdividedSecondSurface()
                guard surfaceChildren.count == differenceChildren.count else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Second surface and homogeneous difference subdivision disagree."
                    )
                }
                for index in surfaceChildren.indices {
                    try collectSeeds(
                        pair: PatchPair(
                            first: pair.first,
                            second: surfaceChildren[index],
                            difference: differenceChildren[index]
                        ),
                        depth: depth + 1,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingSubdivisionCells: &remainingSubdivisionCells,
                        remainingRootAttempts: &remainingRootAttempts,
                        remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells,
                        encounteredRankDeficientLeaf: &encounteredRankDeficientLeaf,
                        seeds: &seeds,
                        certifiedRegularGraphCells: &certifiedRegularGraphCells,
                        unresolvedPairs: &unresolvedPairs
                    )
                }
            }
            return
        }
        let gaugeCertificate = earlyGaugeCertificate
            ?? pair.difference.gaugeRootCertificate()
        if gaugeCertificate == .rankUnresolved {
            encounteredRankDeficientLeaf = true
        }
        let actualSeed = [
            midpoint(pair.first.uLower, pair.first.uUpper),
            midpoint(pair.first.vLower, pair.first.vUpper),
            midpoint(pair.second.uLower, pair.second.uUpper),
            midpoint(pair.second.vLower, pair.second.vUpper),
        ]
        let normalizedSeed = domains.normalized(actualSeed)
        let constraints = normalizedPatchBounds(pair, domains: domains)
        var incompleteBoundaryReason = "The boundary proof was not attempted."
        if gaugeCertificate != .rankUnresolved {
            do {
                switch try collectCertifiedRegularBoundarySeeds(
                    pair: pair,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingRootAttempts: &remainingRootAttempts,
                    remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells,
                    seeds: &seeds,
                    certifiedRegularGraphCells: &certifiedRegularGraphCells
                ) {
                case .complete:
                    return
                case let .incomplete(reason):
                    incompleteBoundaryReason = reason
                }
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .intersectionFailure {
                incompleteBoundaryReason = error.message
            }
        }
        if gaugeCertificate != .rankUnresolved {
            unresolvedPairs.append(
                UnresolvedPatchPair(
                    pair: pair,
                    reason: "A regular surface intersection cell exhausted its complete boundary-root proof. \(incompleteBoundaryReason)"
                )
            )
            return
        }
        var candidateSeeds = [normalizedSeed] + (0..<16).map { mask in
            constraints.indices.map { index in
                mask & (1 << index) == 0
                    ? constraints[index].lower
                    : constraints[index].upper
            }
        }
        var convergedSeedCount = 0
        var requiresCenterFallback = false
        switch gaugeCertificate {
        case .fullGraph:
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A complete regular graph reached the uncertified leaf fallback."
            )
        case let .uniqueMidpointRoot(freeParameterIndex):
            candidateSeeds.removeFirst()
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            guard let sample = try gaugeIntersectionSample(
                seed: normalizedSeed,
                fixedParameterIndex: freeParameterIndex,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Interval Krawczyk certified a unique midpoint-gauge root that numerical refinement did not resolve."
                )
            }
            convergedSeedCount = 1
            try appendDistinctSeed(
                sample,
                to: &seeds,
                maximumSeedCount: options.maximumSeedCount,
                tolerance: tolerance
            )
        case let .unresolved(freeParameterIndex):
            candidateSeeds.removeFirst()
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            if let sample = try gaugeIntersectionSample(
                seed: normalizedSeed,
                fixedParameterIndex: freeParameterIndex,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) {
                convergedSeedCount = 1
                try appendDistinctSeed(
                    sample,
                    to: &seeds,
                    maximumSeedCount: options.maximumSeedCount,
                    tolerance: tolerance
                )
            } else {
                requiresCenterFallback = true
            }
        case .cellEmpty:
            return
        case .midpointSliceEmpty, .rankUnresolved:
            break
        }
        for candidate in candidateSeeds {
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            guard let sample = try closestIntersectionSample(
                seed: candidate,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                continue
            }
            convergedSeedCount += 1
            try appendDistinctSeed(
                sample,
                to: &seeds,
                maximumSeedCount: options.maximumSeedCount,
                tolerance: tolerance
            )
        }
        if convergedSeedCount == 0, requiresCenterFallback {
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            if let sample = try closestIntersectionSample(
                seed: normalizedSeed,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) {
                convergedSeedCount = 1
                try appendDistinctSeed(
                    sample,
                    to: &seeds,
                    maximumSeedCount: options.maximumSeedCount,
                    tolerance: tolerance
                )
            }
        }
        guard convergedSeedCount > 0 else {
            unresolvedPairs.append(
                UnresolvedPatchPair(
                    pair: pair,
                    reason: unresolvedControlHulls(tolerance: tolerance).message
                )
            )
            return
        }
    }

    private func appendDistinctSeed(
        _ sample: PairSample,
        to seeds: inout [PairSample],
        maximumSeedCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        guard seeds.contains(where: {
            normalizedDistance($0.normalized, sample.normalized) <= 1.0e-8
        }) == false else {
            return
        }
        guard seeds.count < maximumSeedCount else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Bounded surface intersection exceeded its distinct-seed limit."
            )
        }
        seeds.append(sample)
    }

    private func collectCertifiedRegularBoundarySeeds(
        pair: PatchPair,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int,
        seeds: inout [PairSample],
        certifiedRegularGraphCells: inout [CertifiedRegularGraphCell]
    ) throws -> BoundarySeedProof {
        guard let boundaryRoots = try certifiedRegularBoundaryRoots(
            pair: pair,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingRootAttempts: &remainingRootAttempts,
            remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
        ) else {
            return .incomplete("At least one boundary face remained interval-unresolved.")
        }
        guard boundaryRoots.isEmpty == false else { return .complete }
        guard case let .regular(preferredFreeParameterIndex) = pair.difference
            .rankThreeCertificate() else {
            return .incomplete(
                "Certified boundary roots belong to a cell without a uniform rank-three certificate."
            )
        }
        let patchBounds = normalizedPatchBounds(pair, domains: domains)
        let pairing: BoundaryRootPairing
        if boundaryRoots.count == 2 {
            pairing = BoundaryRootPairing(
                freeParameterIndex: preferredFreeParameterIndex,
                components: [boundaryRoots]
            )
        } else if let multiplePairing = pairedBoundaryRootComponents(
            boundaryRoots,
            preferredFreeParameterIndex: preferredFreeParameterIndex,
            bounds: patchBounds,
            tolerance: tolerance
        ) {
            pairing = multiplePairing
        } else {
            return .incomplete(
                "The cell has \(boundaryRoots.count) boundary roots that cannot be paired across one parameter coordinate."
            )
        }

        var componentGraphCells: [[CertifiedRegularGraphCell]] = []
        for component in pairing.components {
            let adaptiveCandidates = adaptiveFreeParameterCandidates(
                boundaryRoots: component,
                preferredFreeParameterIndex: pairing.freeParameterIndex,
                bounds: patchBounds,
                tolerance: tolerance
            )
            let freeParameterCandidates = [pairing.freeParameterIndex]
                + adaptiveCandidates.filter { $0 != pairing.freeParameterIndex }
            let inheritedBounds = pairing.components.count == 1
                ? nil
                : localizedComponentBounds(
                    component,
                    freeParameterIndex: pairing.freeParameterIndex,
                    patchBounds: patchBounds,
                    tolerance: tolerance
                )
            var graphCells: [CertifiedRegularGraphCell]?
            var graphFailureMessages: [String] = []
            for freeParameterIndex in freeParameterCandidates {
                do {
                    graphCells = try buildCertifiedRegularGraphCells(
                        fromBoundaryRoots: component,
                        pair: pair,
                        freeParameterIndex: freeParameterIndex,
                        depth: 0,
                        inheritedBounds: inheritedBounds,
                        first: first,
                        second: second,
                        domains: domains,
                        options: options,
                        tolerance: tolerance,
                        remainingRootAttempts: &remainingRootAttempts,
                        remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
                    )
                    break
                } catch let error as KernelError {
                    graphFailureMessages.append(
                        "Free parameter \(freeParameterIndex): \(error.message)"
                    )
                }
            }
            guard let graphCells else {
                return .incomplete(
                    "No parameter coordinate certified a full graph: "
                        + graphFailureMessages.joined(separator: " | ")
                )
            }
            componentGraphCells.append(graphCells)
        }
        certifiedRegularGraphCells.append(
            contentsOf: componentGraphCells.flatMap { $0 }
        )
        for graphCells in componentGraphCells {
            guard let graphCell = graphCells.first else { continue }
            try appendDistinctSeed(
                graphCell.probes[1],
                to: &seeds,
                maximumSeedCount: options.maximumSeedCount,
                tolerance: tolerance
            )
        }
        return .complete
    }

    private func pairedBoundaryRootComponents(
        _ boundaryRoots: [PairSample],
        preferredFreeParameterIndex: Int,
        bounds: [(lower: Double, upper: Double)],
        tolerance: ModelingTolerance
    ) -> BoundaryRootPairing? {
        guard boundaryRoots.count > 2,
              boundaryRoots.count.isMultiple(of: 2) else {
            return nil
        }
        var best: (pairing: BoundaryRootPairing, score: Double)?
        for freeParameterIndex in bounds.indices {
            let interval = bounds[freeParameterIndex]
            let scale = max(interval.upper - interval.lower, 1.0)
            let threshold = max(
                tolerance.relative * scale * 16.0,
                Double.ulpOfOne * scale * 1_024.0
            )
            let lowerRoots = boundaryRoots.filter {
                abs($0.normalized[freeParameterIndex] - interval.lower) <= threshold
            }
            let upperRoots = boundaryRoots.filter {
                abs($0.normalized[freeParameterIndex] - interval.upper) <= threshold
            }
            guard lowerRoots.count == upperRoots.count,
                  lowerRoots.count * 2 == boundaryRoots.count else {
                continue
            }
            let dependentIndexes = bounds.indices.filter {
                $0 != freeParameterIndex
            }
            let orderedLower = lowerRoots.sorted { firstRoot, secondRoot in
                lexicographicallyPrecedes(
                    dependentIndexes.map { index in firstRoot.normalized[index] },
                    dependentIndexes.map { index in secondRoot.normalized[index] }
                )
            }
            let orderedUpper = upperRoots.sorted { firstRoot, secondRoot in
                lexicographicallyPrecedes(
                    dependentIndexes.map { index in firstRoot.normalized[index] },
                    dependentIndexes.map { index in secondRoot.normalized[index] }
                )
            }
            let components = zip(orderedLower, orderedUpper).map { [$0.0, $0.1] }
            let score = components.reduce(0.0) { partial, component in
                partial + dependentIndexes.reduce(0.0) { distance, index in
                    let delta = component[0].normalized[index]
                        - component[1].normalized[index]
                    return distance + delta * delta
                }
            }
            if best == nil
                || score < best!.score
                || (score == best!.score
                    && freeParameterIndex == preferredFreeParameterIndex) {
                best = (
                    BoundaryRootPairing(
                        freeParameterIndex: freeParameterIndex,
                        components: components
                    ),
                    score
                )
            }
        }
        return best?.pairing
    }

    private func localizedComponentBounds(
        _ boundaryRoots: [PairSample],
        freeParameterIndex: Int,
        patchBounds: [(lower: Double, upper: Double)],
        tolerance: ModelingTolerance
    ) -> [(lower: Double, upper: Double)] {
        patchBounds.indices.map { index in
            let values = boundaryRoots.map { $0.normalized[index] }
            guard index != freeParameterIndex,
                  let anchorLower = values.min(),
                  let anchorUpper = values.max() else {
                return patchBounds[index]
            }
            let full = patchBounds[index]
            let margin = max(
                (full.upper - full.lower) * 1.0e-3,
                tolerance.relative * 16.0
            )
            return (
                max(full.lower, (anchorLower - margin).nextDown),
                min(full.upper, (anchorUpper + margin).nextUp)
            )
        }
    }

    private func buildCertifiedRegularGraphCells(
        fromBoundaryRoots boundaryRoots: [PairSample],
        pair: PatchPair,
        freeParameterIndex: Int,
        depth: Int,
        inheritedBounds: [(lower: Double, upper: Double)]?,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [CertifiedRegularGraphCell] {
        guard remainingBoundarySubdivisionCells > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Regular graph interval subdivision exhausted its cell limit."
            )
        }
        remainingBoundarySubdivisionCells -= 1
        guard boundaryRoots.count == 2,
              boundaryRoots.allSatisfy({
                  $0.normalized.indices.contains(freeParameterIndex)
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Boundary graph roots have an invalid free-parameter contract."
            )
        }
        let orderedRoots = boundaryRoots.sorted {
            $0.normalized[freeParameterIndex] < $1.normalized[freeParameterIndex]
        }
        let lowerFree = orderedRoots[0].normalized[freeParameterIndex]
        let upperFree = orderedRoots[1].normalized[freeParameterIndex]
        guard upperFree - lowerFree > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: upperFree - lowerFree,
                tolerance: tolerance,
                message: "Boundary graph roots do not span a resolvable free-parameter interval."
            )
        }
        var constraints = inheritedBounds
            ?? normalizedPatchBounds(pair, domains: domains)
        constraints[freeParameterIndex] = (lowerFree, upperFree)
        var midpointSeed = zip(
            orderedRoots[0].normalized,
            orderedRoots[1].normalized
        ).map { midpoint($0.0, $0.1) }
        midpointSeed[freeParameterIndex] = midpoint(lowerFree, upperFree)
        let interpolatedProbe = try pairSample(
            normalized: midpointSeed,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        let midpointProbe: PairSample
        if interpolatedProbe.residual <= tolerance.distance {
            midpointProbe = interpolatedProbe
        } else {
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            guard let refinedProbe = try gaugeIntersectionSample(
                seed: midpointSeed,
                fixedParameterIndex: freeParameterIndex,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Boundary graph roots do not reproduce a midpoint root under the selected gauge."
                )
            }
            midpointProbe = refinedProbe
        }
        let graphCell = CertifiedRegularGraphCell(
            bounds: constraints,
            freeParameterIndex: freeParameterIndex,
            probes: [orderedRoots[0], midpointProbe, orderedRoots[1]]
        )
        switch try certifiedContractedGraphCell(
            graphCell,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) {
        case let .certified(certified):
            return [certified]
        case let .unresolved(contracted, error):
            guard depth < options.maximumBoundarySubdivisionDepth,
                  remainingRootAttempts > 0 else {
                throw error
            }
            let lowerCells = try buildCertifiedRegularGraphCellsSelectingFreeParameter(
                fromBoundaryRoots: [orderedRoots[0], midpointProbe],
                pair: pair,
                preferredFreeParameterIndex: freeParameterIndex,
                depth: depth + 1,
                inheritedBounds: contracted.bounds,
                expansionBounds: normalizedBezierSpanBounds(
                    pair: pair,
                    first: first,
                    second: second,
                    domains: domains
                ),
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingRootAttempts: &remainingRootAttempts,
                remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
            )
            let upperCells = try buildCertifiedRegularGraphCellsSelectingFreeParameter(
                fromBoundaryRoots: [midpointProbe, orderedRoots[1]],
                pair: pair,
                preferredFreeParameterIndex: freeParameterIndex,
                depth: depth + 1,
                inheritedBounds: contracted.bounds,
                expansionBounds: normalizedBezierSpanBounds(
                    pair: pair,
                    first: first,
                    second: second,
                    domains: domains
                ),
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingRootAttempts: &remainingRootAttempts,
                remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
            )
            return lowerCells + upperCells
        }
    }

    private func buildCertifiedRegularGraphCellsSelectingFreeParameter(
        fromBoundaryRoots boundaryRoots: [PairSample],
        pair: PatchPair,
        preferredFreeParameterIndex: Int,
        depth: Int,
        inheritedBounds: [(lower: Double, upper: Double)],
        expansionBounds: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [CertifiedRegularGraphCell] {
        let candidates = adaptiveFreeParameterCandidates(
            boundaryRoots: boundaryRoots,
            preferredFreeParameterIndex: preferredFreeParameterIndex,
            bounds: inheritedBounds,
            tolerance: tolerance
        )
        var failures: [String] = []
        for candidate in candidates {
            let candidateBounds = boundsWithAnchorMargins(
                inheritedBounds,
                expansionBounds: expansionBounds,
                boundaryRoots: boundaryRoots,
                freeParameterIndex: candidate,
                tolerance: tolerance
            )
            do {
                return try buildCertifiedRegularGraphCells(
                    fromBoundaryRoots: boundaryRoots,
                    pair: pair,
                    freeParameterIndex: candidate,
                    depth: depth,
                    inheritedBounds: candidateBounds,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance,
                    remainingRootAttempts: &remainingRootAttempts,
                    remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
                )
            } catch let error as KernelError {
                failures.append(
                    "Free parameter \(candidate): \(error.message)"
                )
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "No adaptive free parameter certified a child graph cell: "
                + failures.joined(separator: " | ")
        )
    }

    private func boundsWithAnchorMargins(
        _ bounds: [(lower: Double, upper: Double)],
        expansionBounds: [(lower: Double, upper: Double)],
        boundaryRoots: [PairSample],
        freeParameterIndex: Int,
        tolerance: ModelingTolerance
    ) -> [(lower: Double, upper: Double)] {
        var result = bounds
        for index in result.indices where index != freeParameterIndex {
            let maximum = expansionBounds[index]
            let maximumWidth = maximum.upper - maximum.lower
            let margin = max(
                maximumWidth * 1.0e-3,
                tolerance.relative * 16.0
            )
            var lower = result[index].lower
            var upper = result[index].upper
            for root in boundaryRoots {
                let value = root.normalized[index]
                lower = max(
                    maximum.lower,
                    min(lower, value - margin).nextDown
                )
                upper = min(
                    maximum.upper,
                    max(upper, value + margin).nextUp
                )
            }
            result[index] = (lower, upper)
        }
        return result
    }

    private func normalizedBezierSpanBounds(
        pair: PatchPair,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds
    ) -> [(lower: Double, upper: Double)] {
        let patchBounds: [(lower: Double, upper: Double)] = [
            (pair.first.uLower, pair.first.uUpper),
            (pair.first.vLower, pair.first.vUpper),
            (pair.second.uLower, pair.second.uUpper),
            (pair.second.vLower, pair.second.vUpper),
        ]
        let knotVectors = [
            first.uKnots,
            first.vKnots,
            second.uKnots,
            second.vKnots,
        ]
        return patchBounds.indices.map { index in
            let target = midpoint(
                patchBounds[index].lower,
                patchBounds[index].upper
            )
            let actual = zip(
                knotVectors[index],
                knotVectors[index].dropFirst()
            ).compactMap { lower, upper in
                upper > lower ? (lower: lower, upper: upper) : nil
            }.first { span in
                target >= span.lower && target <= span.upper
            } ?? patchBounds[index]
            return (
                (actual.lower - domains.lowerBounds[index]) / domains.spans[index],
                (actual.upper - domains.lowerBounds[index]) / domains.spans[index]
            )
        }
    }

    private func adaptiveFreeParameterCandidates(
        boundaryRoots: [PairSample],
        preferredFreeParameterIndex: Int,
        bounds: [(lower: Double, upper: Double)],
        tolerance: ModelingTolerance
    ) -> [Int] {
        bounds.indices.filter { index in
            let values = boundaryRoots.map { $0.normalized[index] }
            guard let lower = values.min(), let upper = values.max() else {
                return false
            }
            return upper - lower > tolerance.relative
        }.sorted { first, second in
            let firstScore = dependentBoundaryContactCount(
                freeParameterIndex: first,
                boundaryRoots: boundaryRoots,
                bounds: bounds,
                tolerance: tolerance
            )
            let secondScore = dependentBoundaryContactCount(
                freeParameterIndex: second,
                boundaryRoots: boundaryRoots,
                bounds: bounds,
                tolerance: tolerance
            )
            if firstScore != secondScore {
                return firstScore < secondScore
            }
            let firstSpan = normalizedAnchorSpan(
                parameterIndex: first,
                boundaryRoots: boundaryRoots,
                bounds: bounds
            )
            let secondSpan = normalizedAnchorSpan(
                parameterIndex: second,
                boundaryRoots: boundaryRoots,
                bounds: bounds
            )
            if firstSpan != secondSpan {
                return firstSpan > secondSpan
            }
            if first == preferredFreeParameterIndex { return true }
            if second == preferredFreeParameterIndex { return false }
            return first < second
        }
    }

    private func normalizedAnchorSpan(
        parameterIndex: Int,
        boundaryRoots: [PairSample],
        bounds: [(lower: Double, upper: Double)]
    ) -> Double {
        let values = boundaryRoots.map { $0.normalized[parameterIndex] }
        guard let lower = values.min(),
              let upper = values.max(),
              bounds[parameterIndex].upper > bounds[parameterIndex].lower else {
            return 0.0
        }
        return (upper - lower)
            / (bounds[parameterIndex].upper - bounds[parameterIndex].lower)
    }

    private func dependentBoundaryContactCount(
        freeParameterIndex: Int,
        boundaryRoots: [PairSample],
        bounds: [(lower: Double, upper: Double)],
        tolerance: ModelingTolerance
    ) -> Int {
        bounds.indices.filter { $0 != freeParameterIndex }.reduce(0) {
            count, index in
            count + boundaryRoots.reduce(0) { rootCount, root in
                let value = root.normalized[index]
                let scale = max(bounds[index].upper - bounds[index].lower, 1.0)
                let threshold = max(
                    tolerance.relative * scale * 16.0,
                    Double.ulpOfOne * scale * 1_024.0
                )
                let touchesBoundary = abs(value - bounds[index].lower) <= threshold
                    || abs(value - bounds[index].upper) <= threshold
                return rootCount + (touchesBoundary ? 1 : 0)
            }
        }
    }

    private func certifiedContractedGraphCell(
        _ graphCell: CertifiedRegularGraphCell,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> GraphCellCertificationAttempt {
        var candidate = graphCell
        var lastError: KernelError?
        let maximumContractionIterations = min(
            options.maximumBoundarySubdivisionDepth,
            2
        )
        for iteration in 0...maximumContractionIterations {
            do {
                _ = try publicGraphCell(
                    candidate,
                    direction: .forward,
                    first: first,
                    second: second,
                    domains: domains,
                    tolerance: tolerance
                )
                return .certified(candidate)
            } catch let error as KernelError where error.code == .intersectionFailure {
                lastError = error
            }
            guard iteration < maximumContractionIterations,
                  let contractedBounds = try contractedGraphBounds(
                      candidate,
                      first: first,
                      second: second,
                      domains: domains,
                      tolerance: tolerance
                  ) else {
                break
            }
            candidate = CertifiedRegularGraphCell(
                bounds: contractedBounds,
                freeParameterIndex: candidate.freeParameterIndex,
                probes: candidate.probes
            )
        }
        let error = lastError ?? KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "A regular graph cell could not be contracted to a full-graph certificate."
        )
        return .unresolved(candidate, error)
    }

    private func contractedGraphBounds(
        _ graphCell: CertifiedRegularGraphCell,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> [(lower: Double, upper: Double)]? {
        let actualLower = domains.actual(graphCell.bounds.map(\.lower))
        let actualUpper = domains.actual(graphCell.bounds.map(\.upper))
        let trimmedFirst = try first.trimmed(
            uFrom: actualLower[0],
            uTo: actualUpper[0],
            vFrom: actualLower[1],
            vTo: actualUpper[1],
            tolerance: tolerance
        )
        let trimmedSecond = try second.trimmed(
            uFrom: actualLower[2],
            uTo: actualUpper[2],
            vFrom: actualLower[3],
            vTo: actualUpper[3],
            tolerance: tolerance
        )
        let decomposer = BSplineSurfaceBezierDecomposer()
        let firstPatches = try decomposer.surfacePatches(
            surface: trimmedFirst,
            tolerance: tolerance
        )
        let secondPatches = try decomposer.surfacePatches(
            surface: trimmedSecond,
            tolerance: tolerance
        )
        guard firstPatches.count == 1, secondPatches.count == 1 else {
            return nil
        }
        let difference = try RationalBezierSurfaceSurfaceDifferencePatch(
            first: firstPatches[0],
            second: secondPatches[0],
            tolerance: tolerance
        )
        guard let localContraction = difference.parameterizedKrawczykContraction(
            freeParameterIndex: graphCell.freeParameterIndex
        ) else {
            return nil
        }
        var result = graphCell.bounds
        var totalReduction = 0.0
        for index in result.indices where index != graphCell.freeParameterIndex {
            let original = graphCell.bounds[index]
            let width = original.upper - original.lower
            var lower = max(
                original.lower,
                (original.lower + width * localContraction[index].lower).nextDown
            )
            var upper = min(
                original.upper,
                (original.lower + width * localContraction[index].upper).nextUp
            )
            let anchorMargin = max(
                width * 1.0e-3,
                tolerance.relative * 16.0
            )
            for probe in graphCell.probes {
                lower = max(
                    original.lower,
                    min(lower, probe.normalized[index] - anchorMargin).nextDown
                )
                upper = min(
                    original.upper,
                    max(upper, probe.normalized[index] + anchorMargin).nextUp
                )
            }
            guard upper - lower > tolerance.relative else { return nil }
            totalReduction += width - (upper - lower)
            result[index] = (lower, upper)
        }
        guard totalReduction > tolerance.relative else { return nil }
        return result
    }

    private func certifiedRegularBoundaryRoots(
        pair: PatchPair,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [PairSample]? {
        var rootCells: [CertifiedBoundaryRootCell] = []
        for fixedParameterIndex in 0..<4 {
            for side in RationalBezierSurfaceSurfaceDifferencePatch.BoundarySide.allCases {
                guard let faceRoots = try certifiedBoundaryRootCells(
                    pair: pair,
                    fixedParameterIndex: fixedParameterIndex,
                    side: side,
                    depth: 0,
                    options: options,
                    tolerance: tolerance,
                    remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
                ) else {
                    throw resourceLimit(
                        tolerance: tolerance,
                        message: "Boundary root certification remained unresolved for parameter \(fixedParameterIndex) on the \(side) side within patch bounds \([pair.first.uLower, pair.first.uUpper, pair.first.vLower, pair.first.vUpper, pair.second.uLower, pair.second.uUpper, pair.second.vLower, pair.second.vUpper]). \(pair.difference.boundaryRootProofDiagnostic(fixedParameterIndex: fixedParameterIndex, side: side, tolerance: tolerance))"
                    )
                }
                rootCells.append(contentsOf: faceRoots)
            }
        }
        guard rootCells.isEmpty == false else { return [] }

        var roots: [PairSample] = []
        roots.reserveCapacity(rootCells.count)
        for rootCell in rootCells {
            let constraints = normalizedPatchBounds(rootCell.pair, domains: domains)
            var seed = constraints.map { midpoint($0.lower, $0.upper) }
            seed[rootCell.fixedParameterIndex] = rootCell.side == .lower
                ? constraints[rootCell.fixedParameterIndex].lower
                : constraints[rootCell.fixedParameterIndex].upper
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            guard let root = try gaugeIntersectionSample(
                seed: seed,
                fixedParameterIndex: rootCell.fixedParameterIndex,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Interval Krawczyk certified a unique boundary root that numerical refinement did not resolve."
                )
            }
            let parameterMergeTolerance = max(
                1.0e-8,
                sqrt(tolerance.relative)
            )
            if roots.contains(where: {
                normalizedDistance($0.normalized, root.normalized)
                    <= parameterMergeTolerance
                    && ($0.point - root.point).length <= tolerance.distance
            }) == false {
                roots.append(root)
            }
        }
        return roots
    }

    private func certifiedBoundaryRootCells(
        pair: PatchPair,
        fixedParameterIndex: Int,
        side: RationalBezierSurfaceSurfaceDifferencePatch.BoundarySide,
        depth: Int,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingBoundarySubdivisionCells: inout Int
    ) throws -> [CertifiedBoundaryRootCell]? {
        guard remainingBoundarySubdivisionCells > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Boundary root certification exhausted its subdivision-cell limit."
            )
        }
        remainingBoundarySubdivisionCells -= 1
        switch pair.difference.boundaryRootCertificate(
            fixedParameterIndex: fixedParameterIndex,
            side: side,
            tolerance: tolerance
        ) {
        case .empty:
            return []
        case .unique:
            return [CertifiedBoundaryRootCell(
                pair: pair,
                fixedParameterIndex: fixedParameterIndex,
                side: side
            )]
        case .unresolved:
            guard depth < options.maximumBoundarySubdivisionDepth else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: "Boundary root certification remained unresolved for parameter \(fixedParameterIndex) on the \(side) side at depth \(depth) within patch bounds \([pair.first.uLower, pair.first.uUpper, pair.first.vLower, pair.first.vUpper, pair.second.uLower, pair.second.uUpper, pair.second.vLower, pair.second.vUpper]). \(pair.difference.boundaryRootProofDiagnostic(fixedParameterIndex: fixedParameterIndex, side: side, tolerance: tolerance))"
                )
            }
        }

        guard let subdivisionParameterIndex = pair.difference
              .preferredBoundarySubdivisionParameter(
                fixedParameterIndex: fixedParameterIndex,
                side: side
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Boundary root certification found no finite subdivision direction."
            )
        }
        let children = try subdividedBoundaryFace(
            pair: pair,
            parameterIndex: subdivisionParameterIndex,
            tolerance: tolerance
        )
        var roots: [CertifiedBoundaryRootCell] = []
        for child in children {
            guard let childRoots = try certifiedBoundaryRootCells(
                pair: child,
                fixedParameterIndex: fixedParameterIndex,
                side: side,
                depth: depth + 1,
                options: options,
                tolerance: tolerance,
                remainingBoundarySubdivisionCells: &remainingBoundarySubdivisionCells
            ) else {
                return nil
            }
            roots.append(contentsOf: childRoots)
        }
        return roots
    }

    private func subdividedBoundaryFace(
        pair: PatchPair,
        parameterIndex: Int,
        tolerance: ModelingTolerance
    ) throws -> [PatchPair] {
        let surfaceChildren: [RationalBezierSurfacePatch3D]
        if parameterIndex < 2 {
            surfaceChildren = try pair.first.subdivided(
                parameterIndex: parameterIndex
            )
        } else {
            surfaceChildren = try pair.second.subdivided(
                parameterIndex: parameterIndex - 2
            )
        }
        let differenceChildren = pair.difference.subdivided(
            parameterIndex: parameterIndex
        )
        guard surfaceChildren.count == 2,
              surfaceChildren.count == differenceChildren.count else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Boundary-face surface and homogeneous difference subdivision disagree."
            )
        }
        return surfaceChildren.indices.map { index in
            PatchPair(
                first: parameterIndex < 2 ? surfaceChildren[index] : pair.first,
                second: parameterIndex < 2 ? pair.second : surfaceChildren[index],
                difference: differenceChildren[index]
            )
        }
    }

    private func certifiedRegularGraphCell(
        pair: PatchPair,
        freeParameterIndex: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingRootAttempts: inout Int
    ) throws -> CertifiedRegularGraphCell {
        let constraints = normalizedPatchBounds(pair, domains: domains)
        guard constraints.indices.contains(freeParameterIndex) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular graph certificate selected an invalid free parameter."
            )
        }
        let freeBounds = constraints[freeParameterIndex]
        let freeValues = [
            freeBounds.lower,
            midpoint(freeBounds.lower, freeBounds.upper),
            freeBounds.upper,
        ]
        let center = constraints.map { midpoint($0.lower, $0.upper) }
        var probes: [PairSample] = []
        probes.reserveCapacity(freeValues.count)
        for freeValue in freeValues {
            try consumeRootAttempt(
                remainingRootAttempts: &remainingRootAttempts,
                tolerance: tolerance
            )
            var seed = center
            seed[freeParameterIndex] = freeValue
            guard let probe = try gaugeIntersectionSample(
                seed: seed,
                fixedParameterIndex: freeParameterIndex,
                constraints: constraints,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Interval Krawczyk certified a complete regular graph that numerical refinement did not resolve."
                )
            }
            probes.append(probe)
        }
        return CertifiedRegularGraphCell(
            bounds: constraints,
            freeParameterIndex: freeParameterIndex,
            probes: probes
        )
    }

    private func consumeRootAttempt(
        remainingRootAttempts: inout Int,
        tolerance: ModelingTolerance
    ) throws {
        guard remainingRootAttempts > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "Bounded surface intersection exceeded its numerical root-attempt limit."
            )
        }
        remainingRootAttempts -= 1
    }

    private func closestIntersectionSample(
        seed: [Double],
        constraints: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> PairSample? {
        var parameters = seed
        for _ in 0..<options.maximumIterations {
            let sample = try pairSample(
                normalized: parameters,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let columns = try jacobianColumns(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
            var rightHandSide = Array(repeating: 0.0, count: 4)
            let difference = sample.firstPoint - sample.secondPoint
            for row in 0..<4 {
                rightHandSide[row] = -columns[row].dot(difference)
                for column in 0..<4 {
                    matrix[row][column] = columns[row].dot(columns[column])
                }
            }
            let maximumDiagonal = (0..<4).map { matrix[$0][$0] }.max() ?? 1.0
            let damping = max(maximumDiagonal * 1.0e-10, 1.0e-14)
            for index in 0..<4 {
                matrix[index][index] += damping
            }
            guard let delta = SmallLinearSystem4.solve(
                matrix: matrix,
                rightHandSide: rightHandSide
            ) else {
                return nil
            }
            for index in 0..<4 {
                parameters[index] = min(
                    max(parameters[index] + delta[index], constraints[index].lower),
                    constraints[index].upper
                )
            }
            if delta.map(abs).max() ?? 0.0 <= 1.0e-13 {
                break
            }
        }
        let final = try pairSample(
            normalized: parameters,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        return final.residual <= tolerance.distance ? final : nil
    }

    private func gaugeIntersectionSample(
        seed: [Double],
        fixedParameterIndex: Int,
        constraints: [(lower: Double, upper: Double)],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> PairSample? {
        guard seed.count == 4,
              constraints.count == 4,
              seed.indices.contains(fixedParameterIndex) else {
            return nil
        }
        let dependentIndices = seed.indices.filter { $0 != fixedParameterIndex }
        let fixedValue = min(
            max(seed[fixedParameterIndex], constraints[fixedParameterIndex].lower),
            constraints[fixedParameterIndex].upper
        )
        var parameters = seed.indices.map { index in
            min(max(seed[index], constraints[index].lower), constraints[index].upper)
        }
        parameters[fixedParameterIndex] = fixedValue

        for _ in 0..<options.maximumIterations {
            let sample = try pairSample(
                normalized: parameters,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            if sample.residual <= tolerance.distance {
                return sample
            }
            let columns = try jacobianColumns(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let difference = sample.firstPoint - sample.secondPoint
            let rightHandSide = Vector3D(
                x: -difference.x,
                y: -difference.y,
                z: -difference.z
            )
            guard let delta = solveThreeColumnSystem(
                columns: dependentIndices.map { columns[$0] },
                rightHandSide: rightHandSide,
                tolerance: tolerance
            ) else {
                return nil
            }

            var acceptedParameters: [Double]?
            var acceptedSample: PairSample?
            var step = 1.0
            for _ in 0..<8 {
                var candidate = parameters
                for localIndex in dependentIndices.indices {
                    let parameterIndex = dependentIndices[localIndex]
                    candidate[parameterIndex] = min(
                        max(
                            candidate[parameterIndex] + delta[localIndex] * step,
                            constraints[parameterIndex].lower
                        ),
                        constraints[parameterIndex].upper
                    )
                }
                candidate[fixedParameterIndex] = fixedValue
                let candidateSample = try pairSample(
                    normalized: candidate,
                    first: first,
                    second: second,
                    domains: domains,
                    tolerance: tolerance
                )
                if candidateSample.residual < sample.residual
                    || candidateSample.residual <= tolerance.distance {
                    acceptedParameters = candidate
                    acceptedSample = candidateSample
                    break
                }
                step *= 0.5
            }
            guard let acceptedParameters, let acceptedSample else { return nil }
            let movement = zip(parameters, acceptedParameters)
                .map { abs($0.1 - $0.0) }
                .max() ?? 0.0
            parameters = acceptedParameters
            if acceptedSample.residual <= tolerance.distance {
                return acceptedSample
            }
            if movement <= 1.0e-13 {
                break
            }
        }
        let final = try pairSample(
            normalized: parameters,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        return final.residual <= tolerance.distance ? final : nil
    }

    private func solveThreeColumnSystem(
        columns: [Vector3D],
        rightHandSide: Vector3D,
        tolerance: ModelingTolerance
    ) -> [Double]? {
        guard columns.count == 3 else { return nil }
        let systemDeterminant = determinant(columns[0], columns[1], columns[2])
        let scale = columns.map(\.length).reduce(1.0, *)
        let determinantFloor = max(tolerance.relative, Double.ulpOfOne * 64.0) * scale
        guard systemDeterminant.isFinite,
              scale.isFinite,
              scale > 0.0,
              abs(systemDeterminant) > determinantFloor else {
            return nil
        }
        let solution = [
            determinant(rightHandSide, columns[1], columns[2]) / systemDeterminant,
            determinant(columns[0], rightHandSide, columns[2]) / systemDeterminant,
            determinant(columns[0], columns[1], rightHandSide) / systemDeterminant,
        ]
        return solution.allSatisfy(\.isFinite) ? solution : nil
    }

    private func marchedComponent(
        from seed: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        let tangent = try intersectionTangent(
            sample: seed,
            first: first,
            second: second,
            domains: domains,
            maximumIterations: options.maximumIterations,
            tolerance: tolerance
        )
        let forward = try march(
            from: seed,
            initialTangent: tangent,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        let reverse = try march(
            from: seed,
            initialTangent: tangent.map { -$0 },
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        let combined = Array(reverse.dropFirst().reversed()) + forward
        return try refined(
            combined,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
    }

    private func march(
        from seed: PairSample,
        initialTangent: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        var result = [seed]
        var current = seed
        var tangent = initialTangent
        let baseStep = max(
            1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
            1.0 / 256.0
        )
        while true {
            guard result.count < 16_384 else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: "Surface intersection marching exceeded its component length limit."
                )
            }
            guard remainingPointCount > 0 else {
                throw resourceLimit(tolerance: tolerance, message: "Surface intersection marching exceeded its point limit.")
            }
            var step = baseStep
            var corrected: PairSample?
            var reachesBoundary = false
            for _ in 0..<8 {
                let boundaryScale = scaleToUnitBoundary(
                    from: current.normalized,
                    direction: tangent,
                    requestedStep: step
                )
                reachesBoundary = boundaryScale < step
                let predictor = zip(current.normalized, tangent).map {
                    $0.0 + $0.1 * boundaryScale
                }
                corrected = try pseudoArclengthCorrection(
                    predictor: predictor,
                    tangent: tangent,
                    first: first,
                    second: second,
                    domains: domains,
                    options: options,
                    tolerance: tolerance
                )
                if reachesBoundary, let correctedSample = corrected {
                    let boundaryParameterIndex = predictor.indices.min {
                        min(abs(predictor[$0]), abs(1.0 - predictor[$0]))
                            < min(abs(predictor[$1]), abs(1.0 - predictor[$1]))
                    }
                    if let boundaryParameterIndex {
                        let boundaryValue = predictor[boundaryParameterIndex] <= 0.5
                            ? 0.0
                            : 1.0
                        var boundarySeed = correctedSample.normalized
                        boundarySeed[boundaryParameterIndex] = boundaryValue
                        corrected = try gaugeIntersectionSample(
                            seed: boundarySeed,
                            fixedParameterIndex: boundaryParameterIndex,
                            constraints: Array(
                                repeating: (lower: 0.0, upper: 1.0),
                                count: 4
                            ),
                            first: first,
                            second: second,
                            domains: domains,
                            options: options,
                            tolerance: tolerance
                        )
                    }
                }
                if corrected != nil { break }
                step *= 0.5
            }
            guard let next = corrected else {
                if isOnUnitBoundary(current.normalized) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Pseudo-arclength correction failed at the marching seed."
                )
            }
            if (next.point - current.point).length <= tolerance.distance * 0.1 {
                if isOnUnitBoundary(next.normalized) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: (next.point - current.point).length,
                    tolerance: tolerance,
                    message: "Surface intersection marching stagnated before reaching a component boundary."
                )
            }
            remainingPointCount -= 1
            result.append(next)
            if result.count > 12,
               (next.point - seed.point).length <= tolerance.distance * 2.0 {
                result[result.count - 1] = seed
                break
            }
            if reachesBoundary || isOnUnitBoundary(next.normalized) {
                break
            }
            var nextTangent = try intersectionTangent(
                sample: next,
                first: first,
                second: second,
                domains: domains,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            )
            if dot(nextTangent, tangent) < 0.0 {
                nextTangent = nextTangent.map { -$0 }
            }
            tangent = nextTangent
            current = next
        }
        return result
    }

    private func pseudoArclengthCorrection(
        predictor: [Double],
        tangent: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> PairSample? {
        var parameters = predictor.map { min(max($0, 0.0), 1.0) }
        for _ in 0..<options.maximumIterations {
            let sample = try pairSample(
                normalized: parameters,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let gauge = dot(zip(parameters, predictor).map { $0.0 - $0.1 }, tangent)
            if sample.residual <= tolerance.distance * 0.1,
               abs(gauge) <= 1.0e-10 {
                return sample
            }
            let columns = try jacobianColumns(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
            let difference = sample.firstPoint - sample.secondPoint
            let matrix = [
                columns.map(\.x),
                columns.map(\.y),
                columns.map(\.z),
                tangent,
            ]
            let rhs = [-difference.x, -difference.y, -difference.z, -gauge]
            guard let delta = SmallLinearSystem4.solve(matrix: matrix, rightHandSide: rhs) else {
                return nil
            }
            for index in 0..<4 {
                parameters[index] = min(max(parameters[index] + delta[index], 0.0), 1.0)
            }
        }
        let final = try pairSample(
            normalized: parameters,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        return final.residual <= tolerance.distance ? final : nil
    }

    private func refined(
        _ samples: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [PairSample] {
        guard samples.count >= 2 else { return samples }
        var result = [samples[0]]
        for index in 1..<samples.count {
            try refineSegment(
                firstSample: samples[index - 1],
                secondSample: samples[index],
                depth: 0,
                first: first,
                second: second,
                domains: domains,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount,
                result: &result
            )
        }
        return result
    }

    private func refineSegment(
        firstSample: PairSample,
        secondSample: PairSample,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int,
        result: inout [PairSample]
    ) throws {
        let residual = try linearSegmentResidual(
            firstSample: firstSample,
            secondSample: secondSample,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        if residual <= tolerance.distance * 0.5 {
            result.append(secondSample)
            return
        }
        let difference = zip(secondSample.normalized, firstSample.normalized).map { $0.0 - $0.1 }
        guard let tangent = normalized(difference) else {
            return
        }
        let predictor = zip(firstSample.normalized, secondSample.normalized).map {
            ($0.0 + $0.1) * 0.5
        }
        guard let middle = try pseudoArclengthCorrection(
            predictor: predictor,
            tangent: tangent,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Surface intersection midpoint correction failed."
            )
        }
        guard depth < 18,
              remainingPointCount > 0 else {
            throw resourceLimit(tolerance: tolerance, message: "Surface intersection residual refinement exceeded its limit.")
        }
        remainingPointCount -= 1
        try refineSegment(
            firstSample: firstSample,
            secondSample: middle,
            depth: depth + 1,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
        try refineSegment(
            firstSample: middle,
            secondSample: secondSample,
            depth: depth + 1,
            first: first,
            second: second,
            domains: domains,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
    }

    private func linearSegmentResidual(
        firstSample: PairSample,
        secondSample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximum = 0.0
        for fraction in [0.25, 0.5, 0.75] {
            let normalizedParameters = zip(
                firstSample.normalized,
                secondSample.normalized
            ).map {
                $0.0 + ($0.1 - $0.0) * fraction
            }
            let actual = domains.actual(normalizedParameters)
            let curvePoint = interpolated(
                firstSample.point,
                secondSample.point,
                fraction: fraction
            )
            let firstPoint = try first.point(
                u: actual[0],
                v: actual[1],
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                u: actual[2],
                v: actual[3],
                tolerance: tolerance
            )
            maximum = max(
                maximum,
                (curvePoint - firstPoint).length,
                (curvePoint - secondPoint).length
            )
        }
        return maximum
    }

    private func intersectionCurve(
        samples: [PairSample],
        kind: CurveSurfaceIntersectionKind,
        certifiedGraphCells: [CertifiedRegularGraphCell],
        domains: DomainBounds,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        preservesSampleOrientation: Bool = false,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let orientedSamples = preservesSampleOrientation
            ? samples
            : canonicallyOriented(samples, tolerance: tolerance)
        guard kind == .transverse else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A tangential B-spline surface-intersection component is singular without a complete exact-locus certificate."
            )
        }
        let implicitCurve = try certifiedImplicitCurve(
            for: orientedSamples,
            from: certifiedGraphCells,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        var splineSamples: [BoundedSurfaceIntersectionSplineBuilder.Sample] = []
        splineSamples.reserveCapacity(orientedSamples.count)
        let splineDomains = try domainBounds(
            first: first,
            second: second,
            tolerance: tolerance
        )
        for index in orientedSamples.indices {
            let derivatives: SplineDerivatives?
            switch kind {
            case .transverse:
                derivatives = try regularSplineDerivatives(
                    at: index,
                    samples: orientedSamples,
                    first: first,
                    second: second,
                    domains: splineDomains,
                    options: options,
                    tolerance: tolerance
                )
            case .tangent, .mixed:
                derivatives = nil
            }
            let sample = orientedSamples[index]
            splineSamples.append(
                BoundedSurfaceIntersectionSplineBuilder.Sample(
                    point: sample.point,
                    firstParameter: Point2D(x: sample.actual[0], y: sample.actual[1]),
                    secondParameter: Point2D(x: sample.actual[2], y: sample.actual[3]),
                    residual: sample.residual,
                    pointDerivative: derivatives?.point,
                    firstParameterDerivative: derivatives?.firstParameter,
                    secondParameterDerivative: derivatives?.secondParameter
                )
            )
        }
        let spline = try BoundedSurfaceIntersectionSplineBuilder().build(
            samples: splineSamples,
            first: first,
            second: second,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let anchorSample = orientedSamples[0]
        let firstAnchorResidual = (anchorSample.point - anchorSample.firstPoint).length
        let secondAnchorResidual = (anchorSample.point - anchorSample.secondPoint).length
        guard firstAnchorResidual <= tolerance.distance,
              secondAnchorResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(firstAnchorResidual, secondAnchorResidual),
                tolerance: tolerance,
                message: "A verified surface intersection sample failed anchor residual verification."
            )
        }
        let firstAnchor = try SurfaceParameterProjection(
            u: anchorSample.actual[0],
            v: anchorSample.actual[1],
            point: anchorSample.firstPoint,
            residual: firstAnchorResidual
        )
        let secondAnchor = try SurfaceParameterProjection(
            u: anchorSample.actual[2],
            v: anchorSample.actual[3],
            point: anchorSample.secondPoint,
            residual: secondAnchorResidual
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .implicit(implicitCurve),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: spline.curve,
                firstSurfaceParameterCurve: spline.firstPcurve,
                secondSurfaceParameterCurve: spline.secondPcurve,
                maximumResidualUpperBound: spline.maximumResidual,
                tolerance: tolerance
            ),
            kind: kind,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            tolerance: tolerance
        ))
    }

    private func certifiedImplicitCurve(
        for component: [PairSample],
        from graphCells: [CertifiedRegularGraphCell],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionCurve {
        guard component.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified implicit intersection requires a traced component."
            )
        }
        let assignedCells = graphCells.compactMap { graphCell -> (
            cell: CertifiedRegularGraphCell,
            midpointLocation: Double,
            lowerLocation: Double,
            upperLocation: Double
        )? in
            guard isRepresented(
                graphCell,
                by: [component],
                tolerance: tolerance
            ),
            let lowerLocation = componentLocation(
                of: graphCell.probes[0],
                in: component
            ),
            let midpointLocation = componentLocation(
                of: graphCell.probes[1],
                in: component
            ),
            let upperLocation = componentLocation(
                of: graphCell.probes[2],
                in: component
            ) else {
                return nil
            }
            return (
                graphCell,
                midpointLocation,
                lowerLocation,
                upperLocation
            )
        }.sorted { firstCell, secondCell in
            firstCell.midpointLocation < secondCell.midpointLocation
        }
        guard assignedCells.isEmpty == false,
              component.allSatisfy({ sample in
                  assignedCells.contains { assigned in
                      zip(sample.normalized, assigned.cell.bounds).allSatisfy { value, bounds in
                          value >= bounds.lower - 1.0e-8
                              && value <= bounds.upper + 1.0e-8
                      }
                  }
              }) else {
            let maximumCoverageGap = component.map { sample in
                assignedCells.map { assigned in
                    zip(sample.normalized, assigned.cell.bounds).reduce(0.0) {
                        gap, valueAndBounds in
                        let (value, bounds) = valueAndBounds
                        return max(
                            gap,
                            bounds.lower - value,
                            value - bounds.upper,
                            0.0
                        )
                    }
                }.min() ?? .infinity
            }.max() ?? .infinity
            let componentBounds = (0..<4).map { index in
                let values = component.map { $0.normalized[index] }
                return [values.min() ?? .infinity, values.max() ?? -.infinity]
            }
            let certifiedBounds = assignedCells.map { assigned in
                assigned.cell.bounds.flatMap { [$0.lower, $0.upper] }
            }
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumCoverageGap,
                tolerance: tolerance,
                message: "A traced surface-intersection component is not completely covered by full-graph Krawczyk cells. Maximum normalized coverage gap: \(maximumCoverageGap). Component bounds: \(componentBounds). Certified bounds: \(certifiedBounds)."
            )
        }
        let cells = try assignedCells.map { assigned in
            try publicGraphCell(
                assigned.cell,
                direction: assigned.lowerLocation <= assigned.upperLocation
                    ? .forward
                    : .reversed,
                first: first,
                second: second,
                domains: domains,
                tolerance: tolerance
            )
        }
        let firstSample = component[0]
        let lastSample = component[component.count - 1]
        let isClosed = (firstSample.point - lastSample.point).length
            <= tolerance.distance
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: cells,
            isClosed: isClosed,
            tolerance: tolerance
        )
    }

    private func publicGraphCell(
        _ graphCell: CertifiedRegularGraphCell,
        direction: CertifiedImplicitIntersectionDirection,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        guard graphCell.bounds.count == 4,
              graphCell.probes.count == 3,
              let freeParameter = SurfaceIntersectionParameterCoordinate(
                  rawValue: graphCell.freeParameterIndex
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified graph cell has an invalid parameter contract."
            )
        }
        let lower = domains.actual(graphCell.bounds.map(\.lower))
        let upper = domains.actual(graphCell.bounds.map(\.upper))
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: lower[0], upper: upper[0]),
                firstV: try ScalarInterval(lower: lower[1], upper: upper[1]),
                secondU: try ScalarInterval(lower: lower[2], upper: upper[2]),
                secondV: try ScalarInterval(lower: lower[3], upper: upper[3])
            ),
            freeParameter: freeParameter,
            direction: direction,
            lowerAnchor: try SurfaceIntersectionParameterPair(
                values: graphCell.probes[0].actual
            ),
            midpointAnchor: try SurfaceIntersectionParameterPair(
                values: graphCell.probes[1].actual
            ),
            upperAnchor: try SurfaceIntersectionParameterPair(
                values: graphCell.probes[2].actual
            ),
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
    }

    private func componentLocation(
        of probe: PairSample,
        in component: [PairSample]
    ) -> Double? {
        guard component.count >= 2 else { return nil }
        var bestLocation: Double?
        var bestDistanceSquared = Double.infinity
        for index in 1..<component.count {
            let start = component[index - 1].normalized
            let end = component[index].normalized
            let direction = zip(end, start).map { $0.0 - $0.1 }
            let offset = zip(probe.normalized, start).map { $0.0 - $0.1 }
            let denominator = direction.reduce(0.0) { $0 + $1 * $1 }
            let fraction: Double
            if denominator > Double.ulpOfOne {
                let numerator = zip(offset, direction).reduce(0.0) {
                    $0 + $1.0 * $1.1
                }
                fraction = min(max(numerator / denominator, 0.0), 1.0)
            } else {
                fraction = 0.0
            }
            let candidate = zip(start, direction).map { $0.0 + $0.1 * fraction }
            let distanceSquared = zip(probe.normalized, candidate).reduce(0.0) {
                let difference = $1.0 - $1.1
                return $0 + difference * difference
            }
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestLocation = Double(index - 1) + fraction
            }
        }
        return bestLocation
    }

    private func regularSplineDerivatives(
        at index: Int,
        samples: [PairSample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SplineDerivatives {
        let lowerIndex = max(index - 1, 0)
        let upperIndex = min(index + 1, samples.count - 1)
        guard lowerIndex != upperIndex,
              let referenceDirection = normalized(
                  zip(
                      samples[upperIndex].normalized,
                      samples[lowerIndex].normalized
                  ).map { $0.0 - $0.1 }
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A regular intersection spline requires a nonzero parameter direction."
            )
        }
        var tangent = try intersectionTangent(
            sample: samples[index],
            first: first,
            second: second,
            domains: domains,
            maximumIterations: options.maximumIterations,
            tolerance: tolerance
        )
        if dot(tangent, referenceDirection) < 0.0 {
            tangent = tangent.map { -$0 }
        }
        let actualTangent = tangent.indices.map {
            tangent[$0] * domains.spans[$0]
        }
        let firstDifferential = try first.differentialGeometry(
            atU: samples[index].actual[0],
            v: samples[index].actual[1],
            tolerance: tolerance
        )
        let secondDifferential = try second.differentialGeometry(
            atU: samples[index].actual[2],
            v: samples[index].actual[3],
            tolerance: tolerance
        )
        let firstVelocity = firstDifferential.tangentU * actualTangent[0]
            + firstDifferential.tangentV * actualTangent[1]
        let secondVelocity = secondDifferential.tangentU * actualTangent[2]
            + secondDifferential.tangentV * actualTangent[3]
        let velocity = (firstVelocity + secondVelocity) * 0.5
        let speed = velocity.length
        let velocityMismatch = (firstVelocity - secondVelocity).length
        guard speed.isFinite,
              speed > tolerance.distance,
              velocityMismatch <= max(
                  tolerance.distance,
                  speed * tolerance.relative * 16.0
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: velocityMismatch,
                tolerance: tolerance,
                message: "Surface intersection tangent derivatives disagree."
            )
        }
        let inverseSpeed = 1.0 / speed
        return SplineDerivatives(
            point: velocity * inverseSpeed,
            firstParameter: Point2D(
                x: actualTangent[0] * inverseSpeed,
                y: actualTangent[1] * inverseSpeed
            ),
            secondParameter: Point2D(
                x: actualTangent[2] * inverseSpeed,
                y: actualTangent[3] * inverseSpeed
            )
        )
    }

    private func canonicallyOriented(
        _ samples: [PairSample],
        tolerance: ModelingTolerance
    ) -> [PairSample] {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else {
            return samples
        }
        let isClosed = (first.point - last.point).length <= tolerance.distance
        if isClosed == false {
            return pointPrecedes(last.point, first.point, tolerance: tolerance)
                ? Array(samples.reversed())
                : samples
        }

        var ring = Array(samples.dropLast())
        guard ring.count >= 2 else { return samples }
        var anchorIndex = 0
        for index in ring.indices.dropFirst()
            where pointPrecedes(
                ring[index].point,
                ring[anchorIndex].point,
                tolerance: tolerance
            ) {
            anchorIndex = index
        }
        let count = ring.count
        let forward = (0..<count).map { offset in
            ring[(anchorIndex + offset) % count]
        }
        let reverse = (0..<count).map { offset in
            ring[(anchorIndex - offset + count) % count]
        }
        ring = pointPrecedes(
            reverse[1].point,
            forward[1].point,
            tolerance: tolerance
        ) ? reverse : forward
        ring.append(ring[0])
        return ring
    }

    private func pointPrecedes(
        _ first: Point3D,
        _ second: Point3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let firstCoordinates = [first.x, first.y, first.z]
        let secondCoordinates = [second.x, second.y, second.z]
        for index in firstCoordinates.indices {
            let difference = firstCoordinates[index] - secondCoordinates[index]
            if abs(difference) > tolerance.distance {
                return difference < 0.0
            }
        }
        for index in firstCoordinates.indices
            where firstCoordinates[index] != secondCoordinates[index] {
            return firstCoordinates[index] < secondCoordinates[index]
        }
        return false
    }

    private func intersectionPoint(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let firstGeometry = try first.differentialGeometry(
            atU: sample.actual[0],
            v: sample.actual[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: sample.actual[2],
            v: sample.actual[3],
            tolerance: tolerance
        )
        let normalResidual = firstGeometry.normal.cross(secondGeometry.normal).length
        guard sample.residual <= tolerance.distance,
              normalResidual <= tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(sample.residual, normalResidual),
                tolerance: tolerance,
                message: "Bounded B-spline tangency failed point and normal verification."
            )
        }
        let firstProjectionResidual = (sample.point - sample.firstPoint).length
        let secondProjectionResidual = (sample.point - sample.secondPoint).length
        let firstProjection = try SurfaceParameterProjection(
            u: sample.actual[0],
            v: sample.actual[1],
            point: sample.firstPoint,
            residual: firstProjectionResidual
        )
        let secondProjection = try SurfaceParameterProjection(
            u: sample.actual[2],
            v: sample.actual[3],
            point: sample.secondPoint,
            residual: secondProjectionResidual
        )
        return .point(try SurfaceSurfaceIntersectionPoint(
            point: sample.point,
            firstSurfaceParameter: firstProjection,
            secondSurfaceParameter: secondProjection,
            residual: max(
                sample.residual,
                max(firstProjectionResidual, secondProjectionResidual)
            ),
            tolerance: tolerance
        ))
    }

    private func pairSample(
        normalized: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> PairSample {
        let actual = domains.actual(normalized)
        let firstPoint = try first.point(u: actual[0], v: actual[1], tolerance: tolerance)
        let secondPoint = try second.point(u: actual[2], v: actual[3], tolerance: tolerance)
        return PairSample(
            normalized: normalized,
            actual: actual,
            firstPoint: firstPoint,
            secondPoint: secondPoint,
            point: interpolated(firstPoint, secondPoint, fraction: 0.5),
            residual: (firstPoint - secondPoint).length
        )
    }

    private func jacobianColumns(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        tolerance: ModelingTolerance
    ) throws -> [Vector3D] {
        let firstGeometry = try first.differentialGeometry(
            atU: sample.actual[0],
            v: sample.actual[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: sample.actual[2],
            v: sample.actual[3],
            tolerance: tolerance
        )
        let spans = domains.spans
        return [
            firstGeometry.tangentU * spans[0],
            firstGeometry.tangentV * spans[1],
            secondGeometry.tangentU * -spans[2],
            secondGeometry.tangentV * -spans[3],
        ]
    }

    private func intersectionTangent(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let firstGeometry = try first.differentialGeometry(
            atU: sample.actual[0],
            v: sample.actual[1],
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: sample.actual[2],
            v: sample.actual[3],
            tolerance: tolerance
        )
        let normalSeparation = firstGeometry.normal.cross(secondGeometry.normal).length
        guard normalSeparation > tolerance.angle else {
            throw try tangencyDiagnostic(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
        }
        let columns = try jacobianColumns(
            sample: sample,
            first: first,
            second: second,
            domains: domains,
            tolerance: tolerance
        )
        let cofactors = [
            -determinant(columns[1], columns[2], columns[3]),
            determinant(columns[0], columns[2], columns[3]),
            -determinant(columns[0], columns[1], columns[3]),
            determinant(columns[0], columns[1], columns[2]),
        ]
        guard let tangent = normalized(cofactors) else {
            throw try tangencyDiagnostic(
                sample: sample,
                first: first,
                second: second,
                domains: domains,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
        }
        return tangent
    }

    private func tangencyDiagnostic(
        sample: PairSample,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domains: DomainBounds,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> KernelError {
        let contact = try BSplineSurfaceTangencyRefiner().refinedContact(
            near: sample.normalized,
            first: first,
            second: second,
            domainLowerBounds: domains.lowerBounds,
            domainSpans: domains.spans,
            maximumIterations: maximumIterations,
            tolerance: tolerance
        )
        switch contact?.classification {
        case .branching:
            return KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: contact?.normalResidual,
                tolerance: tolerance,
                message: "Regular B-spline marching reached a branching point outside preflight branch extraction."
            )
        case .degenerate:
            return KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: contact?.normalResidual,
                tolerance: tolerance,
                message: "Bounded B-spline surface marching reached a degenerate contact locus."
            )
        case .contactCurve:
            return KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: contact?.normalResidual,
                tolerance: tolerance,
                message: "A transverse B-spline intersection component reached a tangent contact curve."
            )
        case .isolated:
            return KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: contact?.normalResidual,
                tolerance: tolerance,
                message: "A regular B-spline intersection component reached an isolated tangency."
            )
        case nil:
            return KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: sample.residual,
                tolerance: tolerance,
                message: "Bounded B-spline surface marching reached an unresolved rank-deficient contact."
            )
        }
    }

    private func domainBounds(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> DomainBounds {
        DomainBounds(
            firstU: try closedBounds(first.uDomain, tolerance: tolerance),
            firstV: try closedBounds(first.vDomain, tolerance: tolerance),
            secondU: try closedBounds(second.uDomain, tolerance: tolerance),
            secondV: try closedBounds(second.vDomain, tolerance: tolerance)
        )
    }

    private func normalizedPatchBounds(
        _ pair: PatchPair,
        domains: DomainBounds
    ) -> [(lower: Double, upper: Double)] {
        let lower = domains.normalized([
            pair.first.uLower,
            pair.first.vLower,
            pair.second.uLower,
            pair.second.vLower,
        ])
        let upper = domains.normalized([
            pair.first.uUpper,
            pair.first.vUpper,
            pair.second.uUpper,
            pair.second.vUpper,
        ])
        return lower.indices.map { (lower[$0], upper[$0]) }
    }

    private func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(lower, upper) = domain,
              upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded surface marching requires closed parameter domains."
            )
        }
        return (lower, upper)
    }

    private func isRepresented(
        _ seed: PairSample,
        by components: [[PairSample]],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for component in components {
            for index in 1..<component.count {
                let start = component[index - 1]
                let end = component[index]
                if pointSegmentDistance(seed.point, start.point, end.point)
                    <= tolerance.distance * 2.0,
                   parameterPointSegmentDistance(
                       seed.normalized,
                       start.normalized,
                       end.normalized
                   ) <= 1.0e-3 {
                    return true
                }
            }
        }
        return false
    }

    private func isGeometricallyRepresented(
        _ seed: PairSample,
        by components: [[PairSample]],
        tolerance: ModelingTolerance
    ) -> Bool {
        components.contains { component in
            (1..<component.count).contains { index in
                pointSegmentDistance(
                    seed.point,
                    component[index - 1].point,
                    component[index].point
                ) <= tolerance.distance * 2.0
            }
        }
    }

    private func isRepresented(
        _ seed: PairSample,
        by isolatedContacts: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        isolatedContacts.contains {
            (seed.point - $0.point).length <= tolerance.distance * 2.0
        }
    }

    private func isRepresented(
        _ graphCell: CertifiedRegularGraphCell,
        by components: [[PairSample]],
        tolerance: ModelingTolerance
    ) -> Bool {
        components.contains { component in
            graphCell.probes.allSatisfy { probe in
                componentRepresents(
                    probe: probe,
                    in: graphCell,
                    component: component,
                    tolerance: tolerance
                )
            }
        }
    }

    private func componentRepresents(
        probe: PairSample,
        in graphCell: CertifiedRegularGraphCell,
        component: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        guard component.count >= 2 else { return false }
        if component.contains(where: {
            normalizedDistance(probe.normalized, $0.normalized) <= 1.0e-8
                && (probe.point - $0.point).length <= tolerance.distance * 2.0
        }) {
            return true
        }
        let freeParameterIndex = graphCell.freeParameterIndex
        let target = probe.normalized[freeParameterIndex]
        for index in 1..<component.count {
            let start = component[index - 1]
            let end = component[index]
            let startFree = start.normalized[freeParameterIndex]
            let endFree = end.normalized[freeParameterIndex]
            let freeDelta = endFree - startFree
            guard abs(freeDelta) > Double.ulpOfOne else { continue }
            let fraction = (target - startFree) / freeDelta
            guard fraction >= -1.0e-12, fraction <= 1.0 + 1.0e-12 else {
                continue
            }
            let boundedFraction = min(max(fraction, 0.0), 1.0)
            let candidateParameters = interpolated(
                start.normalized,
                end.normalized,
                fraction: boundedFraction
            )
            guard zip(candidateParameters, graphCell.bounds).allSatisfy({ value, bounds in
                value >= bounds.lower - 1.0e-8
                    && value <= bounds.upper + 1.0e-8
            }) else {
                continue
            }
            let parameterSegmentLength = normalizedDistance(
                start.normalized,
                end.normalized
            )
            guard normalizedDistance(candidateParameters, probe.normalized)
                <= max(parameterSegmentLength * 0.25, 1.0e-8) else {
                continue
            }
            let candidatePoint = interpolated(
                start.point,
                end.point,
                fraction: boundedFraction
            )
            let pointSegmentLength = (end.point - start.point).length
            if (candidatePoint - probe.point).length
                <= max(pointSegmentLength * 0.25, tolerance.distance * 2.0) {
                return true
            }
        }
        return false
    }

    private func consolidatedComponents(
        _ source: [[PairSample]],
        tolerance: ModelingTolerance
    ) -> [[PairSample]] {
        var merged = source
        var didMerge = true
        while didMerge {
            didMerge = false
            outer: for firstIndex in merged.indices {
                guard firstIndex + 1 < merged.count else { continue }
                for secondIndex in (firstIndex + 1)..<merged.count {
                    guard let joined = continuouslyJoined(
                        merged[firstIndex],
                        merged[secondIndex],
                        tolerance: tolerance
                    ) else {
                        continue
                    }
                    merged[firstIndex] = joined
                    merged.remove(at: secondIndex)
                    didMerge = true
                    break outer
                }
            }
        }

        var unique: [[PairSample]] = []
        for component in merged {
            if unique.contains(where: {
                representsSameLocus(component, $0, tolerance: tolerance)
            }) == false {
                unique.append(component)
            }
        }
        return unique
    }

    private func continuouslyJoined(
        _ first: [PairSample],
        _ second: [PairSample],
        tolerance: ModelingTolerance
    ) -> [PairSample]? {
        guard first.count >= 2, second.count >= 2 else { return nil }
        let firstVariants = [first, Array(first.reversed())]
        let secondVariants = [second, Array(second.reversed())]
        for left in firstVariants {
            for right in secondVariants {
                guard let leftEnd = left.last,
                      let rightStart = right.first,
                      (leftEnd.point - rightStart.point).length <= tolerance.distance * 4.0,
                      normalizedDistance(leftEnd.normalized, rightStart.normalized) <= 1.0e-6,
                      let incoming = unitDirection(
                          from: left[left.count - 2].point,
                          to: leftEnd.point,
                          tolerance: tolerance
                      ),
                      let outgoing = unitDirection(
                          from: rightStart.point,
                          to: right[1].point,
                          tolerance: tolerance
                      ),
                      incoming.dot(outgoing) >= 0.95 else {
                    continue
                }
                return left + Array(right.dropFirst())
            }
        }
        return nil
    }

    private func unitDirection(
        from start: Point3D,
        to end: Point3D,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        let direction = end - start
        let length = direction.length
        guard length > tolerance.distance * 0.1 else { return nil }
        return direction / length
    }

    private func representsSameLocus(
        _ first: [PairSample],
        _ second: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        samples(first, lieOn: second, tolerance: tolerance)
            && samples(second, lieOn: first, tolerance: tolerance)
    }

    private func samples(
        _ samples: [PairSample],
        lieOn component: [PairSample],
        tolerance: ModelingTolerance
    ) -> Bool {
        guard component.count >= 2 else { return false }
        return samples.allSatisfy { sample in
            (1..<component.count).contains { index in
                pointSegmentDistance(
                    sample.point,
                    component[index - 1].point,
                    component[index].point
                ) <= tolerance.distance * 8.0
                    && parameterPointSegmentDistance(
                        sample.normalized,
                        component[index - 1].normalized,
                        component[index].normalized
                    ) <= 1.0e-3
            }
        }
    }

    private func isParameterCovered(
        _ pair: PatchPair,
        by components: [[PairSample]],
        isolatedContacts: [PairSample],
        domains: DomainBounds
    ) -> Bool {
        let bounds = normalizedPatchBounds(pair, domains: domains)
        if isolatedContacts.contains(where: {
            parameters($0.normalized, areInside: bounds)
        }) {
            return true
        }
        return components.contains { component in
            component.contains { sample in
                parameters(sample.normalized, areInside: bounds)
            }
        }
    }

    private func parameters(
        _ values: [Double],
        areInside bounds: [(lower: Double, upper: Double)]
    ) -> Bool {
        values.count == bounds.count
            && zip(values, bounds).allSatisfy { value, bound in
                value >= bound.lower - 1.0e-10
                    && value <= bound.upper + 1.0e-10
            }
    }

    private func pointSegmentDistance(_ point: Point3D, _ start: Point3D, _ end: Point3D) -> Double {
        let direction = end - start
        let squaredLength = direction.dot(direction)
        guard squaredLength > Double.ulpOfOne else { return (point - start).length }
        let fraction = min(max((point - start).dot(direction) / squaredLength, 0.0), 1.0)
        return (point - (start + direction * fraction)).length
    }

    private func parameterPointSegmentDistance(
        _ point: [Double],
        _ start: [Double],
        _ end: [Double]
    ) -> Double {
        let direction = zip(end, start).map { $0.0 - $0.1 }
        let fromStart = zip(point, start).map { $0.0 - $0.1 }
        let squaredLength = dot(direction, direction)
        guard squaredLength > Double.ulpOfOne else {
            return normalizedDistance(point, start)
        }
        let fraction = min(max(dot(fromStart, direction) / squaredLength, 0.0), 1.0)
        return normalizedDistance(
            point,
            zip(start, direction).map { $0.0 + $0.1 * fraction }
        )
    }

    private func scaleToUnitBoundary(
        from parameters: [Double],
        direction: [Double],
        requestedStep: Double
    ) -> Double {
        var result = requestedStep
        for index in 0..<4 {
            if direction[index] > 0.0 {
                result = min(result, (1.0 - parameters[index]) / direction[index])
            } else if direction[index] < 0.0 {
                result = min(result, -parameters[index] / direction[index])
            }
        }
        return max(result, 0.0)
    }

    private func isOnUnitBoundary(_ values: [Double]) -> Bool {
        values.contains { $0 <= 1.0e-10 || $0 >= 1.0 - 1.0e-10 }
    }

    private func determinant(_ first: Vector3D, _ second: Vector3D, _ third: Vector3D) -> Double {
        first.dot(second.cross(third))
    }

    private func normalized(_ values: [Double]) -> [Double]? {
        let length = sqrt(values.reduce(0.0) { $0 + $1 * $1 })
        guard length.isFinite, length > 1.0e-12 else { return nil }
        return values.map { $0 / length }
    }

    private func dot(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private func normalizedDistance(_ first: [Double], _ second: [Double]) -> Double {
        sqrt(zip(first, second).reduce(0.0) { partial, pair in
            let difference = pair.0 - pair.1
            return partial + difference * difference
        })
    }

    private func lexicographicallyPrecedes(_ first: [Double], _ second: [Double]) -> Bool {
        for index in first.indices where first[index] != second[index] {
            return first[index] < second[index]
        }
        return false
    }

    private func interpolated(_ first: Point3D, _ second: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            z: first.z + (second.z - first.z) * fraction
        )
    }

    private func interpolated(
        _ first: [Double],
        _ second: [Double],
        fraction: Double
    ) -> [Double] {
        zip(first, second).map { start, end in
            start + (end - start) * fraction
        }
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func resourceLimit(tolerance: ModelingTolerance, message: String) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private func unresolvedControlHulls(tolerance: ModelingTolerance) -> KernelError {
        resourceLimit(
            tolerance: tolerance,
            message: "Overlapping Bezier control hulls remain unresolved at the bounded surface subdivision limit."
        )
    }
}
