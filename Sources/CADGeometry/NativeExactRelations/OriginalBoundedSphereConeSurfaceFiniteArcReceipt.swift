import CADCore


/// Complete original finite arc selected by the caller's raw UV boxes.
public struct OriginalBoundedSphereConeSurfaceFiniteArcReceipt: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
    public let firstBox: SurfaceParameterBox
    public let secondBox: SurfaceParameterBox
    public let coneU: ClosedRange<Double>
    public let coneCycle: ExactRationalCoefficient
    public let sphereCycle: ExactRationalCoefficient
    public let principalConeLower: ExactRationalCoefficient
    public let principalConeUpper: ExactRationalCoefficient
    public let principalSphereLower: ExactRationalCoefficient
    public let principalSphereUpper: ExactRationalCoefficient
    public let branch: Int
    public let proofDepth: ExactScalarDepth
    private let preparation: OriginalGeometryPreparationReceipt
    public var imageDimension: Int { coneU.lowerBound == coneU.upperBound ? 0 : 1 }

    private init(source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox, coneU: ClosedRange<Double>,
        coneCycle:ExactRationalCoefficient,sphereCycle:ExactRationalCoefficient,
        principalConeLower:ExactRationalCoefficient,principalConeUpper:ExactRationalCoefficient,
        principalSphereLower:ExactRationalCoefficient,principalSphereUpper:ExactRationalCoefficient,
        branch: Int, proofDepth: ExactScalarDepth, preparation: OriginalGeometryPreparationReceipt) {
        self.source=source; self.firstBox=firstBox; self.secondBox=secondBox
        self.coneU=coneU; self.branch=branch; self.proofDepth=proofDepth; self.preparation=preparation
        self.coneCycle=coneCycle; self.sphereCycle=sphereCycle
        self.principalConeLower=principalConeLower; self.principalConeUpper=principalConeUpper
        self.principalSphereLower=principalSphereLower; self.principalSphereUpper=principalSphereUpper
    }

    /// Assemble the already checked selected cell without repeating its solve.
    static func assemble(
        selected proof: OriginalBoundedSphereConeFiniteArcCertifier.CellProof,
        preparation: OriginalGeometryPreparationReceipt,
        limits: OriginalSourceIssuanceLimits, using a: inout OriginalQueryExecution) throws -> Self {
        try a.withProofScope { a in
            try a.checkpoint(); try a.consumeWork(1)
            try preparation.admit(tolerance: preparation.tolerance, using: &a)
            try proof.admitProof(limits: limits, using: &a)
            guard proof.kind == .selected else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(source: proof.source, firstBox: proof.firstBox, secondBox: proof.secondBox,
                coneU: proof.coneU, coneCycle: proof.coneCycle, sphereCycle: proof.sphereCycle,
                principalConeLower: proof.principalConeLower, principalConeUpper: proof.principalConeUpper,
                principalSphereLower: proof.principalSphereLower, principalSphereUpper: proof.principalSphereUpper,
                branch: proof.branch, proofDepth: try a.depth, preparation: preparation)
            try a.checkpoint(); return result
        }
    }

    /// Checked union of adjacent selected cells; the caller retains array ownership.
    static func assemble(
        selected proofs: borrowing [OriginalBoundedSphereConeFiniteArcCertifier.CellProof],
        preparation: OriginalGeometryPreparationReceipt,
        limits: OriginalSourceIssuanceLimits, using a: inout OriginalQueryExecution) throws -> Self {
        try a.withProofScope { a in
            try a.checkpoint(); try a.consumeWork(1)
            try preparation.admit(tolerance: preparation.tolerance, using: &a)
            guard let first = proofs.first, let last = proofs.last else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            let sphereIsFirst = first.source.original.sphereIsFirst
            let sphere = sphereIsFirst ? first.firstBox : first.secondBox
            let firstCone = sphereIsFirst ? first.secondBox : first.firstBox
            let q = ExactRationalScalarDomain()
            var previousUpper = first.coneU.lowerBound
            var index = 0
            while index < proofs.count {
                let proof = proofs[index]
                try a.checkpoint(); try a.consumeWork(1)
                try proof.admitProof(limits: limits, using: &a)
                let proofSphere = sphereIsFirst ? proof.firstBox : proof.secondBox
                let proofCone = sphereIsFirst ? proof.secondBox : proof.firstBox
                guard proof.kind == .selected, proof.source.owner === first.source.owner,
                    proof.branch == first.branch, proofSphere == sphere, proofCone.v == firstCone.v,
                    proof.coneU.lowerBound == previousUpper,
                    proofs.count == 1 || proof.coneU.lowerBound < proof.coneU.upperBound,
                    try q.compare(proof.coneCycle, first.coneCycle, using: &a) == .equal,
                    try q.compare(proof.sphereCycle, first.sphereCycle, using: &a) == .equal else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                previousUpper = proof.coneU.upperBound
                index += 1
            }
            let cone = SurfaceParameterBox(u: try ScalarInterval(lower: first.coneU.lowerBound,
                upper: last.coneU.upperBound), v: firstCone.v)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(source: first.source,
                firstBox: sphereIsFirst ? sphere : cone, secondBox: sphereIsFirst ? cone : sphere,
                coneU: first.coneU.lowerBound...last.coneU.upperBound,
                coneCycle: first.coneCycle, sphereCycle: first.sphereCycle,
                principalConeLower: first.principalConeLower, principalConeUpper: last.principalConeUpper,
                principalSphereLower: first.principalSphereLower, principalSphereUpper: first.principalSphereUpper,
                branch: first.branch, proofDepth: try a.depth, preparation: preparation)
            try a.checkpoint(); return result
        }
    }

    public func admitProof(using a: inout OriginalQueryExecution) throws {
        try withRead(using: &a) { a in try a.checkpoint() }
    }

    public func contains(_ rawU: Field.Value, using a: inout OriginalQueryExecution) throws -> Bool {
        try withRead(using: &a) { a in
            let f=source.original.field, u=try f.importing(rawU,using:&a)
            return try f.compare(u,f.binary64(exactly:coneU.lowerBound,using:&a),using:&a) != .less
                && f.compare(u,f.binary64(exactly:coneU.upperBound,using:&a),using:&a) != .greater
        }
    }

    public func accepts(coneCycle requestedCone: ExactRationalCoefficient,
        sphereCycle requestedSphere: ExactRationalCoefficient,
        using a: inout OriginalQueryExecution) throws -> Bool {
        try withRead(using: &a) { a in
            guard requestedCone.canonicalDenominatorWords == [1],
                requestedSphere.canonicalDenominatorWords == [1] else { return false }
            let q=ExactRationalScalarDomain()
            return try q.compare(requestedCone,coneCycle,using:&a) == .equal
                && q.compare(requestedSphere,sphereCycle,using:&a) == .equal
        }
    }

    public func position(coneU rawU: Field.Value,
        using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceFiniteArcPosition {
        try withRead(using: &a) { a in
            try a.withProofScope { a in
                try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
                guard try contains(rawU,using:&a) else { throw OriginalSourceIssuanceFailure.invalidSource }
                let s=source.original,f=s.field,u=try f.importing(rawU,using:&a)
                let coneOffset=try f.multiplying(OriginalSourceRationalImport.value(coneCycle,field:f,using:&a),s.labelPeriod,using:&a)
                let sphereOffset=try f.multiplying(OriginalSourceRationalImport.value(sphereCycle,field:f,using:&a),s.labelPeriod,using:&a)
                let principalU=try f.subtracting(u,coneOffset,using:&a)
                let ax=try f.binary64(exactly:s.apex.x,using:&a),ay=try f.binary64(exactly:s.apex.y,using:&a)
                let az=try f.binary64(exactly:s.apex.z,using:&a)
                let ox=try f.binary64(exactly:s.sphereCenter.x,using:&a),oy=try f.binary64(exactly:s.sphereCenter.y,using:&a)
                let oz=try f.binary64(exactly:s.sphereCenter.z,using:&a),radius=try f.binary64(exactly:s.sphereRadius,using:&a)
                let dx=try f.subtracting(ax,ox,using:&a),dz=try f.subtracting(oz,az,using:&a)
                let constant=try f.subtracting(f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dz,dz,using:&a),using:&a),
                    f.multiplying(radius,radius,using:&a),using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcSlant.self))
                let root=OriginalBoundedSphereConeSurfaceFiniteArcSlant(middleOffset:try f.multiplying(dz,s.cosine,using:&a),
                    sineCoefficient:try f.multiplying(dx,s.sine,using:&a),constant:constant,
                    coneU:u,principalConeU:principalU,labelPeriod:s.labelPeriod,branch:branch)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalBoundedSphereConeSurfaceFiniteArcCoordinate.self))
                let x=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:0,apex:ax,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
                let y=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:1,apex:ay,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
                let z=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:2,apex:az,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcSphereUV.self))
                let uv=OriginalBoundedSphereConeSurfaceFiniteArcSphereUV(x:x,y:y,z:z,centerX:ox,centerY:oy,centerZ:oz,radius:radius,
                    labelPeriod:s.labelPeriod,azimuthOffset:sphereOffset,sphereCycle:sphereCycle)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcPosition.self))
                let result=OriginalBoundedSphereConeSurfaceFiniteArcPosition(source:source,coneU:u,principalConeU:principalU,
                    coneCycle:coneCycle,sphereCycle:sphereCycle,branch:branch,
                    slant:root,x:x,y:y,z:z,sphereInverse:uv,proofDepth:try a.depth)
                try a.checkpoint(); return result
            }
        }
    }

    private func withRead<Result>(using a: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        // Check caller ceilings before contribution reattachment can allocate;
        // the inner admissions still enforce effective contribution ceilings.
        try a.checkpoint()
        let retained = preparation.depth
        try a.admitSourceDepth(max(source.sourceDepth, retained.sourceDepth))
        let sourceProof = source.original.proofDepth
        try a.admitDepth(value: max(retained.scalar.value, max(proofDepth.value, sourceProof.value)),
            coefficient: max(retained.scalar.coefficient, max(proofDepth.coefficient, sourceProof.coefficient)))
        try a.admitGeometricDepth(retained.geometricDepth)
        try a.admitTransportDepth(retained.transportDepth)
        return try preparation.withContributionScopes(using: &a) { a in
            try a.checkpoint()
            try a.admitSourceDepth(source.sourceDepth)
            try preparation.admit(tolerance: preparation.tolerance, using: &a)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            let result = try body(&a)
            try a.checkpoint()
            return result
        }
    }
}
