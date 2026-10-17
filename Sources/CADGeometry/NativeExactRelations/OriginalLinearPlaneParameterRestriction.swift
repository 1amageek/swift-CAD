import CADCore

/// Retains the original whole request and its source-proved necessary preimage.
struct OriginalLinearPlaneParameterRestriction: Sendable {
    typealias Member = OriginalDomainBoundParametricGraph<OriginalLinearCurveSnapshot,
        OriginalExactScalarDomain, OriginalLinearPlaneRelations.Law>
    let original: Member
    let selected: Member
    let plane: OriginalSourceBinding<OriginalPlaneSnapshot>
    let originalPlane: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>
    let selectedPlane: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>
    let endpoint: OriginalCurveEndpointReceipt<OriginalLinearCurveSnapshot,
        OriginalLinearChartSelection, OriginalExactScalarDomain>?
    let equation: ExactPolynomial<OriginalExactScalarDomain>
    let kind: OriginalAffinePlaneParameterRestriction.Kind
    let depth: ExactScalarDepth

    private init(original: Member, selected: Member, plane: OriginalSourceBinding<OriginalPlaneSnapshot>,
        originalPlane: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>,
        selectedPlane: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>,
        endpoint: OriginalCurveEndpointReceipt<OriginalLinearCurveSnapshot,
            OriginalLinearChartSelection, OriginalExactScalarDomain>?,
        equation: ExactPolynomial<OriginalExactScalarDomain>, kind: OriginalAffinePlaneParameterRestriction.Kind,
        depth: ExactScalarDepth) {
        self.original = original; self.selected = selected; self.plane = plane
        self.originalPlane = originalPlane; self.selectedPlane = selectedPlane; self.endpoint = endpoint
        self.equation = equation; self.kind = kind; self.depth = depth
    }

    static func prepare(_ binding: Member, plane: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws -> Self {
        try a.withProofScope { a in
            let restriction = try OriginalAffinePlaneParameterRestriction().select(binding,
                plane: plane, limits: limits, using: &a)
            guard binding.request.sharesFrame(with: restriction.selected.request) else {
                throw OriginalDomainIdentityFailure.foreignOwner
            }
            var selectedPlane = plane
            var endpoint: OriginalCurveEndpointReceipt<OriginalLinearCurveSnapshot,
                OriginalLinearChartSelection, OriginalExactScalarDomain>?
            if case .singleton(let parameter) = restriction.kind, !restriction.selected.request.isEmpty {
                let issued = try DefaultOriginalCurveEndpointIssuer<OriginalLinearCurveSnapshot,
                    OriginalLinearChartSelection, OriginalExactScalarDomain>().issue(
                        source: binding.graph.source, curve: binding.graph.evidence,
                        localParameter: parameter, originalParameter: parameter,
                        limits: limits.source, using: &a)
                let basis = plane.original.law
                let uv = try basis.parameters(of: issued.position, limits: limits, using: &a)
                guard uv.count == 2 else { throw NativeExactRelationFailure.invalidDomain }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2,
                    of: [ExactParameterInterval<OriginalExactScalar>].self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2,
                    of: ExactParameterInterval<OriginalExactScalar>.self))
                var axes: [[ExactParameterInterval<OriginalExactScalar>]] = []; axes.reserveCapacity(2)
                for coordinate in uv {
                    try a.consumeWork(1)
                    axes.append([try .checked(field: basis.field,
                        lower: .finite(coordinate), upper: .finite(coordinate),
                        includesLower: true, includesUpper: true, depth: coordinate.depth, using: &a)])
                }
                let originalRequest = plane.original.request
                let singleton = try originalRequest.frame.selection(intervals: axes, limits: limits, using: &a)
                let request = try originalRequest.intersection(singleton, limits: limits, using: &a)
                guard request.sharesFrame(with: originalRequest) else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                let cover = try DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot, OriginalExactScalarDomain>()
                    .issue(request: request, basis: basis, limits: limits, using: &a)
                selectedPlane = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>()
                    .compile(cover: cover, field: plane.field, limits: limits, using: &a)
                endpoint = issued
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(original: binding, selected: restriction.selected, plane: plane.original.source,
                originalPlane: plane, selectedPlane: selectedPlane, endpoint: endpoint,
                equation: restriction.equation, kind: restriction.kind, depth: try a.depth)
            try a.checkpoint(); return result
        }
    }

    func admitProof(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws {
        try a.checkpoint(); try plane.require(limits.source)
        try a.admitSourceDepth(plane.sourceDepth)
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
        guard original.request.sharesFrame(with: selected.request) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        guard originalPlane.original.request.sharesFrame(with: selectedPlane.original.request) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        try originalPlane.admitProof(limits: limits, using: &a)
        try selectedPlane.admitProof(limits: limits, using: &a)
        if let endpoint {
            try a.admitDepth(value: endpoint.depth.value, coefficient: endpoint.depth.coefficient)
            try endpoint.curve.admitProof(using: &a)
        }
        try original.admitProof(limits: limits, using: &a)
        try selected.admitProof(limits: limits, using: &a)
        _ = try original.graph.polynomials.importing(equation, using: &a)
        try a.checkpoint()
    }
}
