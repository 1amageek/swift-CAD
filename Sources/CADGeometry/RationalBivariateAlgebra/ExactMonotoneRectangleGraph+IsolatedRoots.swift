import CADCore

extension ExactMonotoneRectangleGraph {
    /// Original closed-rectangle-only roots, retaining the existing projection station.
    package func isolatedRoots<B: RationalAlgebraAdmitting>(maximumDepth: Int,
        usage: inout B) throws -> [ExactBivariateSystemRoot] {
        let source = freeAlongU ? original : try original.exchangedAxes(usage: &usage)
        let transverse = freeAlongU ? sourceDomain.v : sourceDomain.u
        let lower = try ExactRationalCoefficient.originalDouble(transverse.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(transverse.upper, usage: &usage)
        let low = try source.restricted(alongU: false, station: lower, usage: &usage)
        let high = try source.restricted(alongU: false, station: upper, usage: &usage)
        var result: [ExactBivariateSystemRoot] = []
        for index in isolatedStationIndices {
            guard index >= 0, index < stations.count, stations[index].containsRoot else {
                throw rationalAlgebraFailure("Original isolated graph station index has no retained source incidence.")
            }
            let endpoint = stations[index].endpoint
            let coordinate: ExactRationalCoefficient
            let edge: ExactBivariatePolynomial
            if case .zero = try endpoint.sign(of: low, maximumDepth: maximumDepth, usage: &usage) {
                coordinate = lower; edge = low
            } else if case .zero = try endpoint.sign(of: high, maximumDepth: maximumDepth, usage: &usage) {
                coordinate = upper; edge = high
            } else {
                throw rationalAlgebraFailure("An original isolated regular graph station is not on a source transverse edge.")
            }
            let freeRoot: ExactAlgebraicRealRoot
            switch endpoint {
            case .algebraic(let root): freeRoot = root
            case .authored(let station):
                let law = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                    .subtracting(.constant(station, usage: &usage), usage: &usage)
                freeRoot = try ExactAlgebraicRealRoot(polynomial: law,
                    isolation: ExactUnivariateRootIsolator.Root(lower: station, upper: station,
                        isRationalStation: true, isolationDepth: endpoint.depth,
                        excludesLowerEndpoint: false, excludesUpperEndpoint: false), usage: &usage)
            }
            let originalFixedLaw = try ExactBivariatePolynomial.coordinate(alongU: !freeAlongU, usage: &usage)
                .subtracting(.constant(coordinate, usage: &usage), usage: &usage)
            let projectionRoot: ExactAlgebraicRealRoot
            let fiber: ExactAlgebraicFiberPolynomial
            let fiberRoot: ExactAlgebraicFiberRootIsolator.Root
            let projectionMultiplicity: Int, fiberMultiplicity: Int
            if freeAlongU {
                projectionRoot = freeRoot
                let fixedLaw = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
                    .subtracting(.constant(coordinate, usage: &usage), usage: &usage)
                fiber = try ExactAlgebraicFiberPolynomial(source: fixedLaw, at: freeRoot,
                    maximumDepth: maximumDepth, usage: &usage)
                fiberRoot = .init(lower: coordinate, upper: coordinate, excludesLower: false,
                    excludesUpper: false, isolationDepth: freeRoot.isolation.isolationDepth)
                projectionMultiplicity = try endpointMultiplicity(edge, root: freeRoot,
                    maximumDepth: maximumDepth, usage: &usage)
                fiberMultiplicity = 1
            } else {
                let fixedLaw = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                    .subtracting(.constant(coordinate, usage: &usage), usage: &usage)
                projectionRoot = try ExactAlgebraicRealRoot(polynomial: fixedLaw,
                    isolation: ExactUnivariateRootIsolator.Root(lower: coordinate, upper: coordinate,
                        isRationalStation: true, isolationDepth: freeRoot.isolation.isolationDepth,
                        excludesLowerEndpoint: false, excludesUpperEndpoint: false), usage: &usage)
                fiber = try ExactAlgebraicFiberPolynomial(source: freeRoot.polynomial.exchangedAxes(usage: &usage),
                    at: projectionRoot, maximumDepth: maximumDepth, usage: &usage)
                fiberRoot = .init(lower: freeRoot.isolation.lower, upper: freeRoot.isolation.upper,
                    excludesLower: freeRoot.isolation.excludesLowerEndpoint,
                    excludesUpper: freeRoot.isolation.excludesUpperEndpoint,
                    isolationDepth: freeRoot.isolation.isolationDepth)
                projectionMultiplicity = 1
                fiberMultiplicity = try endpointMultiplicity(edge, root: freeRoot,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            try usage.retainExactStorage(3)
            result.append(ExactBivariateSystemRoot(equations: [original, originalFixedLaw],
                projectionRoot: projectionRoot, fiber: fiber, fiberRoot: fiberRoot,
                sourceDomain: sourceDomain, projectionMultiplicity: projectionMultiplicity,
                fiberMultiplicity: fiberMultiplicity))
        }
        return result
    }
    private func endpointMultiplicity<B: RationalAlgebraAdmitting>(_ edge: ExactBivariatePolynomial,
        root: ExactAlgebraicRealRoot, maximumDepth: Int, usage: inout B) throws -> Int {
        guard !edge.isZero else {
            throw rationalAlgebraFailure("A complete boundary graph cannot be an isolated projection station.")
        }
        var derivative = edge, result = 0
        while !derivative.isZero {
            guard case .zero = try root.sign(of: derivative, maximumDepth: maximumDepth, usage: &usage) else { break }
            result = try rationalAlgebraCount(result, 1)
            derivative = try derivative.differentiated(alongU: true, usage: &usage)
        }
        guard result > 0 else { throw rationalAlgebraFailure("Original isolated station has no exact edge multiplicity.") }
        return result
    }
}
