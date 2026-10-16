import CADCore

public struct OriginalBoundedSphereConeBoundaryRootReceipt: Sendable {
    public typealias Source = OriginalBoundedSphereConeSurfaceSnapshot

    public enum Outcome: Sendable {
        case unique(OriginalBoundedSphereConeBoundaryRootReceipt)
        case empty(Exclusion)
        case unresolved
    }

    /// Complete exclusion only of this one declared boundary-gauge request.
    public struct Exclusion: Sendable {
        fileprivate let proof: Proof
        fileprivate init(proof: Proof) { self.proof = proof }
        public var source: OriginalSourceBinding<Source> { proof.provider.source }
        public var boundaryCoordinate: SurfaceIntersectionParameterCoordinate { proof.boundaryCoordinate }
        public var boundaryStation: Double { proof.boundaryStation }
        public var requestedBox: SurfaceIntersectionParameterBox { proof.requestedBox }
        public var proofDepth: ExactScalarDepth { proof.preparation.depth.scalar }

        public func admitProof(limits: OriginalSourceIssuanceLimits,
            using execution: inout OriginalQueryExecution) throws {
            try proof.withRead(limits: limits, using: &execution) { execution in
                try execution.checkpoint()
            }
        }
    }

    /// A symbolic coordinate of this exact implicit root, never a scalar sample.
    public struct Coordinate: Sendable {
        public let root: OriginalBoundedSphereConeBoundaryRootReceipt
        public let axis: SurfaceIntersectionParameterCoordinate
        fileprivate init(root: OriginalBoundedSphereConeBoundaryRootReceipt,
            axis: SurfaceIntersectionParameterCoordinate) {
            self.root = root; self.axis = axis
        }
        public func enclosure(limits: OriginalSourceIssuanceLimits,
            using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
            try root.proof.withRead(limits: limits, using: &execution) { execution in
                try execution.consumeWork(1)
                guard let isolation = root.proof.isolation else { throw ExactScalarFailure.invalidEvidence }
                return isolation.interval(for: axis)
            }
        }
    }

    /// Both coordinates project the same source-bound implicit root.
    public struct UV: Sendable {
        public let u: Coordinate
        public let v: Coordinate
        public let isFirst: Bool
        public var isSphere: Bool { u.root.source.original.sphereIsFirst == isFirst }
        fileprivate init(root: OriginalBoundedSphereConeBoundaryRootReceipt, isFirst: Bool) {
            self.isFirst = isFirst
            u = Coordinate(root: root, axis: isFirst ? .firstU : .secondU)
            v = Coordinate(root: root, axis: isFirst ? .firstV : .secondV)
        }
    }

    /// Original cone Cartesian law composed with the same implicit root UV.
    public struct CartesianCoordinate: Sendable {
        public typealias Law = OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Source.Field>
        public let root: OriginalBoundedSphereConeBoundaryRootReceipt
        public let axis: Int
        public var isFirst: Bool { !root.source.original.sphereIsFirst }

        fileprivate init(root: OriginalBoundedSphereConeBoundaryRootReceipt, axis: Int) {
            self.root = root; self.axis = axis
        }

        /// The position polynomial at `axis` uses this law's defined functions
        /// applied to `parameters`; the implicit root is never a Field.Value.
        public func originalLaw(limits: OriginalSourceIssuanceLimits,
            using execution: inout OriginalQueryExecution) throws -> Law {
            try root.proof.withRead(limits: limits, using: &execution) { execution in
                try execution.consumeWork(1)
                let source = root.source.original
                let law = isFirst ? source.firstLaw : source.secondLaw
                guard law.source.original.coordinateKind == .cone, law.position.count == 3 else {
                    throw ExactScalarFailure.invalidEvidence
                }
                try execution.retainStorage(count: 1, stride: MemoryLayout<Law>.stride)
                return law
            }
        }

        public func parameters(limits: OriginalSourceIssuanceLimits,
            using execution: inout OriginalQueryExecution) throws -> UV {
            try root.uv(isFirst: isFirst, limits: limits, using: &execution)
        }
    }

    /// One admitted symbolic position and all four original UV projections.
    public struct Position: Sendable {
        public let x: CartesianCoordinate
        public let y: CartesianCoordinate
        public let z: CartesianCoordinate
        public let firstUV: UV
        public let secondUV: UV

        fileprivate init(root: OriginalBoundedSphereConeBoundaryRootReceipt) {
            x = CartesianCoordinate(root: root, axis: 0)
            y = CartesianCoordinate(root: root, axis: 1)
            z = CartesianCoordinate(root: root, axis: 2)
            firstUV = UV(root: root, isFirst: true)
            secondUV = UV(root: root, isFirst: false)
        }
    }

    fileprivate struct ContractionStep: Sendable {
        enum Origin: Sendable { case originalSourceNecessaryBounds, gauge }
        let origin: Origin
        let input: SurfaceIntersectionParameterBox
        let retained: SurfaceIntersectionParameterBox
        let proofDepth: ExactScalarDepth
        let coefficientDepth: Int
    }

    /// Immutable authority shared by the root and all coordinate projections.
    fileprivate final class Proof: Sendable {
        let provider: OriginalBoundedSphereConeBoundaryJetProvider
        let boundaryCoordinate: SurfaceIntersectionParameterCoordinate
        let boundaryStation: Double
        let exactBoundaryStation: ExactRationalCoefficient
        let requestedBox: SurfaceIntersectionParameterBox
        let isolation: SurfaceIntersectionParameterBox?
        let coefficientDepth: Int
        let ancestry: [ContractionStep]
        let candidate: OriginalBoundedSphereConeFiniteArcCertifier.CellProof?
        let preparation: OriginalGeometryPreparationReceipt

        init(provider: OriginalBoundedSphereConeBoundaryJetProvider,
            boundaryCoordinate: SurfaceIntersectionParameterCoordinate, boundaryStation: Double,
            exactBoundaryStation: ExactRationalCoefficient, requestedBox: SurfaceIntersectionParameterBox,
            isolation: SurfaceIntersectionParameterBox?, coefficientDepth: Int,
            ancestry: [ContractionStep], candidate: OriginalBoundedSphereConeFiniteArcCertifier.CellProof?, preparation: OriginalGeometryPreparationReceipt) {
            self.provider = provider; self.boundaryCoordinate = boundaryCoordinate
            self.boundaryStation = boundaryStation; self.exactBoundaryStation = exactBoundaryStation
            self.requestedBox = requestedBox; self.isolation = isolation
            self.coefficientDepth = coefficientDepth; self.ancestry = ancestry
            self.candidate = candidate
            self.preparation = preparation
        }

        func withRead<Result>(limits: OriginalSourceIssuanceLimits,
            using execution: inout OriginalQueryExecution,
            _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
            // Check caller ceilings before contribution reattachment can allocate;
            // the inner admissions still enforce effective contribution ceilings.
            try execution.checkpoint()
            let source = provider.source
            try source.require(limits)
            let retained = preparation.depth
            try execution.admitSourceDepth(max(source.sourceDepth, retained.sourceDepth))
            let sourceProof = source.original.proofDepth
            var value = max(retained.scalar.value, max(provider.proofDepth.value, sourceProof.value))
            var coefficient = max(retained.scalar.coefficient,
                max(coefficientDepth, max(provider.proofDepth.coefficient, sourceProof.coefficient)))
            if let candidate {
                value = max(value, candidate.proofDepth.value)
                coefficient = max(coefficient, candidate.proofDepth.coefficient)
            }
            try execution.admitDepth(value: value, coefficient: coefficient)
            try execution.admitGeometricDepth(retained.geometricDepth)
            try execution.admitTransportDepth(retained.transportDepth)
            return try preparation.withContributionScopes(using: &execution) { execution in
                try execution.checkpoint()
                let source = provider.source
                try source.require(limits)
                try execution.admitSourceDepth(source.sourceDepth)
                try preparation.admit(tolerance: preparation.tolerance, using: &execution)
                if let candidate { try candidate.admitProof(limits: limits, using: &execution) }
                try execution.admitDepth(value: provider.proofDepth.value,
                    coefficient: max(provider.proofDepth.coefficient, coefficientDepth))
                try source.original.firstLaw.admitProof(limits: limits, using: &execution)
                try source.original.secondLaw.admitProof(limits: limits, using: &execution)
                let result = try body(&execution)
                try execution.checkpoint()
                return result
            }
        }
    }

    private enum Classification { case unique, empty, unresolved }
    private struct Prepared {
        let classification: Classification
        let isolation: SurfaceIntersectionParameterBox?
        let exactBoundaryStation: ExactRationalCoefficient
        let coefficientDepth: Int
        let ancestry: [ContractionStep]
    }
    private let proof: Proof
    private init(proof: Proof) { self.proof = proof }

    public var source: OriginalSourceBinding<Source> { proof.provider.source }
    public var boundaryCoordinate: SurfaceIntersectionParameterCoordinate { proof.boundaryCoordinate }
    public var boundaryStation: Double { proof.boundaryStation }
    public var exactBoundaryStation: ExactRationalCoefficient { proof.exactBoundaryStation }
    public var requestedBox: SurfaceIntersectionParameterBox { proof.requestedBox }
    public var coefficientDepth: Int { proof.coefficientDepth }
    public var contractionCount: Int { proof.ancestry.count }
    public var candidateBranch: Int? { proof.candidate?.branch }
    public var proofDepth: ExactScalarDepth { proof.preparation.depth.scalar }

    /// Source issuer only: each leaf borrows the cover's one continuing Session.
    static func issue(provider: OriginalBoundedSphereConeBoundaryJetProvider,
        session: inout OriginalBoundedSphereConeBoundaryJetProvider.Session,
        candidate: OriginalBoundedSphereConeFiniteArcCertifier.CellProof? = nil,
        parameterBox: SurfaceIntersectionParameterBox,
        boundaryCoordinate: SurfaceIntersectionParameterCoordinate, boundaryStation: Double,
        coefficientRefinementDepth: Int, tolerance: ModelingTolerance,
        limits: OriginalSourceIssuanceLimits, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Outcome {
        try execution.checkpoint()
        try tolerance.validate()
        guard boundaryStation.isFinite, coefficientRefinementDepth > 0,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, maximumAlgebraicDepth >= 0 else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        let source = provider.source
        guard session.provider.source.owner === source.owner else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        guard coefficientRefinementDepth >= session.coefficientDepth else {
            throw ExactScalarFailure.invalidEvidence
        }
        try source.require(limits)
        try execution.admitSourceDepth(source.sourceDepth)
        try validate(parameterBox, boundaryCoordinate: boundaryCoordinate,
            boundaryStation: boundaryStation, using: &execution)
        let effective = execution.effectiveLimits
        let spanLimit = min(maximumSpanCount, effective.maximumSpans)
        guard spanLimit > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Boundary gauge exhausted the caller span limit.")
        }
        let sourceLimits = try OriginalSourceIssuanceLimits(
            remainingSourceDepth: min(limits.remainingSourceDepth, effective.remainingSourceDepth))
        let geometricLimit = min(maximumSubdivisionDepth, effective.maximumSubdivisionDepth)
        let scalarLimit = try ExactScalarDepth(value: min(maximumAlgebraicDepth, effective.maximumValueDepth),
            coefficient: min(maximumAlgebraicDepth, effective.maximumCoefficientDepth))
        let prepared = try execution.withPreparationScope { execution in
            try execution.withProofScope(maximum: scalarLimit) { execution in
                try execution.admitSourceDepth(source.sourceDepth)
                let station = try ExactRationalScalarDomain().binary64(exactly: boundaryStation, using: &execution)
                var currentBox = parameterBox
                var ancestry: [ContractionStep] = []
                var ancestryCapacity = 0
                if let candidate {
                    let retained = try candidateBox(candidate, provider: provider,
                        requested: parameterBox, boundaryCoordinate: boundaryCoordinate,
                        boundaryStation: boundaryStation, limits: sourceLimits, using: &execution)
                    if retained != currentBox {
                        try admitAncestryDepth(1, maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
                        try execution.retainStorage(count: 1, stride: MemoryLayout<ContractionStep>.stride)
                        ancestry.reserveCapacity(1); ancestryCapacity = 1
                        ancestry.append(ContractionStep(origin: .originalSourceNecessaryBounds, input: currentBox,
                            retained: retained, proofDepth: try execution.depth,
                            coefficientDepth: candidate.proofDepth.coefficient))
                        currentBox = retained
                    }
                }
                while true {
                    try execution.checkpoint()
                    try execution.admitSourceDepth(source.sourceDepth)
                    try admitAncestryDepth(ancestry.count,
                        maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
                    try execution.visitCertificationCell(depth: ancestry.count)
                    let result = try ParametricSurfaceIntersectionGraphProver.originalPairGaugeParameterBounds(
                        firstSurface: source.original.original.first,
                        secondSurface: source.original.original.second,
                        parameterBox: currentBox, freeParameter: boundaryCoordinate,
                        atNormalizedFraction: 0.5, tolerance: tolerance,
                        maximumSpanCount: spanLimit,
                        maximumSubdivisionDepth: geometricLimit,
                        remainingSourceDepth: sourceLimits.remainingSourceDepth,
                        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution
                    ) { isFirst, parameters, execution in
                        try execution.admitSourceDepth(source.sourceDepth)
                        let jet = try session.intervalJet(isFirst: isFirst, overClosedBox: parameters,
                            refinementDepth: coefficientRefinementDepth, limits: sourceLimits, using: &execution)
                        guard jet.source.owner === source.owner,
                            session.provider.source.owner === source.owner,
                            jet.isFirst == isFirst,
                            sameBox(jet.parameters, parameters),
                            jet.coefficientDepth == session.coefficientDepth,
                            jet.coefficientDepth >= coefficientRefinementDepth,
                            jet.proofDepth == (try execution.depth) else {
                            throw OriginalSourceIssuanceFailure.foreignBinding
                        }
                        try execution.admitDepth(value: jet.proofDepth.value,
                            coefficient: jet.proofDepth.coefficient)
                        try execution.admitDepth(value: 0, coefficient: jet.coefficientDepth)
                        try execution.checkpoint()
                        return jet.value
                    }
                    switch result.certificate {
                    case .uniqueRoot:
                        guard let bounds = result.parameterBounds,
                            result.necessaryParameterBounds == nil else { throw ExactScalarFailure.invalidEvidence }
                        let isolation = try checkedBox(bounds, containedIn: currentBox,
                            boundaryCoordinate: boundaryCoordinate, boundaryStation: boundaryStation,
                            using: &execution)
                        return Prepared(classification: .unique, isolation: isolation,
                            exactBoundaryStation: station, coefficientDepth: session.coefficientDepth,
                            ancestry: ancestry)
                    case .empty:
                        guard result.parameterBounds == nil, result.necessaryParameterBounds == nil else {
                            throw ExactScalarFailure.invalidEvidence
                        }
                        // Every preceding necessary box contains all original roots.
                        // Empty of this equivalent box therefore excludes the original request.
                        return Prepared(classification: .empty, isolation: nil,
                            exactBoundaryStation: station, coefficientDepth: session.coefficientDepth,
                            ancestry: ancestry)
                    case .unresolved:
                        guard result.parameterBounds == nil else { throw ExactScalarFailure.invalidEvidence }
                        guard let bounds = result.necessaryParameterBounds else {
                            return Prepared(classification: .unresolved, isolation: nil,
                                exactBoundaryStation: station, coefficientDepth: session.coefficientDepth,
                                ancestry: ancestry)
                        }
                        let retained = try checkedBox(bounds, containedIn: currentBox,
                            boundaryCoordinate: boundaryCoordinate, boundaryStation: boundaryStation,
                            using: &execution)
                        var progressed = false
                        for index in 0..<4 {
                            try execution.consumeWork(1)
                            guard let axis = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
                                throw ExactScalarFailure.invalidEvidence
                            }
                            let old = currentBox.interval(for: axis), next = retained.interval(for: axis)
                            progressed = progressed || next.lower > old.lower || next.upper < old.upper
                        }
                        guard progressed else {
                            return Prepared(classification: .unresolved, isolation: nil,
                                exactBoundaryStation: station, coefficientDepth: session.coefficientDepth,
                                ancestry: ancestry)
                        }
                        if ancestry.count == ancestryCapacity {
                            let doubled = ancestryCapacity.multipliedReportingOverflow(by: 2)
                            guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
                            let capacity = max(1, doubled.partialValue)
                            try execution.retainStorage(count: capacity, stride: MemoryLayout<ContractionStep>.stride)
                            ancestry.reserveCapacity(capacity); ancestryCapacity = capacity
                        }
                        ancestry.append(ContractionStep(origin: .gauge, input: currentBox, retained: retained,
                            proofDepth: try execution.depth, coefficientDepth: session.coefficientDepth))
                        currentBox = retained
                    }
                }
            }
        }
        if case .unresolved = prepared.result.classification {
            try execution.checkpoint()
            return .unresolved
        }
        let preparation = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: prepared.depth, using: &execution)
        try execution.retainStorage(bytes:
            MemoryLayout<OriginalBoundedSphereConeBoundaryJetProvider>.stride
            + MemoryLayout<SurfaceIntersectionParameterCoordinate>.stride + MemoryLayout<Double>.stride
            + MemoryLayout<ExactRationalCoefficient>.stride + MemoryLayout<SurfaceIntersectionParameterBox>.stride
            + MemoryLayout<SurfaceIntersectionParameterBox?>.stride + MemoryLayout<Int>.stride
            + MemoryLayout<[ContractionStep]>.stride
            + MemoryLayout<OriginalBoundedSphereConeFiniteArcCertifier.CellProof?>.stride
            + MemoryLayout<OriginalGeometryPreparationReceipt>.stride + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let proof = Proof(provider: provider, boundaryCoordinate: boundaryCoordinate,
            boundaryStation: boundaryStation, exactBoundaryStation: prepared.result.exactBoundaryStation,
            requestedBox: parameterBox, isolation: prepared.result.isolation,
            coefficientDepth: prepared.result.coefficientDepth, ancestry: prepared.result.ancestry,
            candidate: candidate, preparation: preparation)
        switch prepared.result.classification {
        case .unique:
            try execution.retainStorage(count: 1, stride: MemoryLayout<Outcome>.stride)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Self>.stride)
            let root = Self(proof: proof)
            try execution.checkpoint()
            return .unique(root)
        case .empty:
            try execution.retainStorage(count: 1, stride: MemoryLayout<Outcome>.stride)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Exclusion>.stride)
            let exclusion = Exclusion(proof: proof)
            try execution.checkpoint()
            return .empty(exclusion)
        case .unresolved:
            throw ExactScalarFailure.invalidEvidence
        }
    }

    public func admitProof(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws {
        try proof.withRead(limits: limits, using: &execution) { execution in
            try execution.checkpoint()
        }
    }
    public func owns(_ coordinate: Coordinate) -> Bool { proof === coordinate.root.proof }
    public func owns(_ coordinate: CartesianCoordinate) -> Bool { proof === coordinate.root.proof }

    public func position(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws -> Position {
        try proof.withRead(limits: limits, using: &execution) { execution in
            try execution.retainStorage(count: 1, stride: MemoryLayout<Position>.stride)
            return Position(root: self)
        }
    }


    public func coordinate(_ axis: SurfaceIntersectionParameterCoordinate,
        limits: OriginalSourceIssuanceLimits, using execution: inout OriginalQueryExecution) throws -> Coordinate {
        try proof.withRead(limits: limits, using: &execution) { execution in
            try execution.retainStorage(count: 1, stride: MemoryLayout<Coordinate>.stride)
            return Coordinate(root: self, axis: axis)
        }
    }
    public func firstUV(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws -> UV {
        try uv(isFirst: true, limits: limits, using: &execution)
    }
    public func secondUV(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws -> UV {
        try uv(isFirst: false, limits: limits, using: &execution)
    }
    private func uv(isFirst: Bool, limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws -> UV {
        try proof.withRead(limits: limits, using: &execution) { execution in
            try execution.retainStorage(count: 1, stride: MemoryLayout<UV>.stride)
            return UV(root: self, isFirst: isFirst)
        }
    }

    private static func admitAncestryDepth(_ depth: Int, maximumSubdivisionDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        if maximumSubdivisionDepth < execution.effectiveLimits.maximumSubdivisionDepth,
            depth > maximumSubdivisionDepth {
            throw OriginalQueryFailure.published(
                GeometryConversionError.resourceLimitExceeded("Boundary root contraction exhausted geometric ancestry."),
                context: execution.context.recording(resource: .init(axis: .geometricDepth,
                    used: .known(execution.geometricDepth), limit: .known(maximumSubdivisionDepth),
                    requested: .known(depth))), tolerance: nil)
        }
        try execution.admitGeometricDepth(depth)
    }

    private static func candidateBox(_ candidate: OriginalBoundedSphereConeFiniteArcCertifier.CellProof,
        provider: OriginalBoundedSphereConeBoundaryJetProvider,
        requested: SurfaceIntersectionParameterBox,
        boundaryCoordinate: SurfaceIntersectionParameterCoordinate, boundaryStation: Double,
        limits: OriginalSourceIssuanceLimits, using execution: inout OriginalQueryExecution) throws
        -> SurfaceIntersectionParameterBox {
        try execution.checkpoint()
        try execution.admitSourceDepth(provider.source.sourceDepth)
        guard candidate.source.owner === provider.source.owner,
            case .boundaryCandidate(guardReason: .sphereAzimuthUpper) = candidate.kind,
            candidate.branch == 0 || candidate.branch == 1 else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        let sphereIsFirst = provider.source.original.sphereIsFirst
        guard boundaryCoordinate == (sphereIsFirst ? .firstU : .secondU) else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let sphere = sphereIsFirst ? candidate.firstBox : candidate.secondBox
        let cone = sphereIsFirst ? candidate.secondBox : candidate.firstBox
        let requestedSphereV = requested.interval(for: sphereIsFirst ? .firstV : .secondV)
        let requestedConeU = requested.interval(for: sphereIsFirst ? .secondU : .firstU)
        let requestedConeV = requested.interval(for: sphereIsFirst ? .secondV : .firstV)
        try execution.consumeWork(4)
        guard sphere.u.lower < sphere.u.upper,
            sphere.u.upper.bitPattern == boundaryStation.bitPattern,
            sameInterval(sphere.v, requestedSphereV), sameInterval(cone.u, requestedConeU),
            sameInterval(cone.v, requestedConeV),
            candidate.coneU.lowerBound.bitPattern == cone.u.lower.bitPattern,
            candidate.coneU.upperBound.bitPattern == cone.u.upper.bitPattern else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        try candidate.admitProof(limits: limits, using: &execution)
        let necessary = try candidate.candidateSlantBounds(limits: limits, using: &execution)
        guard necessary.lower.isFinite, necessary.upper.isFinite, necessary.lower <= necessary.upper else {
            throw ExactScalarFailure.invalidEvidence
        }
        let lower = max(requestedConeV.lower, necessary.lower)
        let upper = min(requestedConeV.upper, necessary.upper)
        guard lower <= upper else { throw ExactScalarFailure.invalidEvidence }
        let slant = try ScalarInterval(lower: lower, upper: upper)
        let necessaryV = try candidate.candidateSphereVBounds(limits: limits, using: &execution)
        guard necessaryV.lower.isFinite, necessaryV.upper.isFinite, necessaryV.lower <= necessaryV.upper else {
            throw ExactScalarFailure.invalidEvidence
        }
        let lowerV = max(requestedSphereV.lower, necessaryV.lower)
        let upperV = min(requestedSphereV.upper, necessaryV.upper)
        guard lowerV <= upperV else { throw ExactScalarFailure.invalidEvidence }
        let latitude = try ScalarInterval(lower: lowerV, upper: upperV)
        try execution.retainStorage(count: 1, stride: MemoryLayout<SurfaceIntersectionParameterBox>.stride)
        return sphereIsFirst
            ? .init(firstU: requested.firstU, firstV: latitude,
                secondU: requested.secondU, secondV: slant)
            : .init(firstU: requested.firstU, firstV: slant,
                secondU: requested.secondU, secondV: latitude)
    }

    private static func sameInterval(_ first: ScalarInterval, _ second: ScalarInterval) -> Bool {
        first.lower.bitPattern == second.lower.bitPattern && first.upper.bitPattern == second.upper.bitPattern
    }

    private static func checkedBox(_ bounds: [ScalarInterval],
        containedIn requested: SurfaceIntersectionParameterBox,
        boundaryCoordinate: SurfaceIntersectionParameterCoordinate, boundaryStation: Double,
        using execution: inout OriginalQueryExecution) throws -> SurfaceIntersectionParameterBox {
        guard bounds.count == 4 else { throw ExactScalarFailure.invalidEvidence }
        for index in 0..<4 {
            try execution.consumeWork(1)
            guard let axis = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
                throw ExactScalarFailure.invalidEvidence
            }
            let value = bounds[index], outer = requested.interval(for: axis)
            guard value.lower.isFinite, value.upper.isFinite, value.lower <= value.upper,
                value.lower >= outer.lower, value.upper <= outer.upper else {
                throw ExactScalarFailure.invalidEvidence
            }
            if axis == boundaryCoordinate {
                guard value.lower.bitPattern == boundaryStation.bitPattern,
                    value.upper.bitPattern == boundaryStation.bitPattern else {
                    throw ExactScalarFailure.invalidEvidence
                }
            }
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<SurfaceIntersectionParameterBox>.stride)
        return .init(firstU: bounds[0], firstV: bounds[1], secondU: bounds[2], secondV: bounds[3])
    }

    private static func validate(_ box: SurfaceIntersectionParameterBox,
        boundaryCoordinate: SurfaceIntersectionParameterCoordinate, boundaryStation: Double,
        using execution: inout OriginalQueryExecution) throws {
        for index in 0..<4 {
            try execution.consumeWork(1)
            guard let axis = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
                throw ExactScalarFailure.invalidEvidence
            }
            let interval = box.interval(for: axis)
            guard interval.lower.isFinite, interval.upper.isFinite, interval.lower <= interval.upper else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
        }
        let boundary = box.interval(for: boundaryCoordinate)
        guard boundary.lower.bitPattern == boundaryStation.bitPattern,
            boundary.upper.bitPattern == boundaryStation.bitPattern else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
    }
    private static func sameBox(_ first: SurfaceParameterBox, _ second: SurfaceParameterBox) -> Bool {
        first.u.lower.bitPattern == second.u.lower.bitPattern
            && first.u.upper.bitPattern == second.u.upper.bitPattern
            && first.v.lower.bitPattern == second.v.lower.bitPattern
            && first.v.upper.bitPattern == second.v.upper.bitPattern
    }
}
