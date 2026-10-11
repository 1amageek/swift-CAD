import CADCore

/// Whole-phase exclusion for the fixed original unit-Z apex law and actual plane Z=2.
public struct DefaultOriginalCertifiedSphereConeApexPlaneSeparationIssuer:
    OriginalCertifiedSphereConeApexPlaneSeparationIssuing {
    public init() {}

    public func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<OriginalCertifiedSphereConeApexSnapshot>,
        plane: borrowing OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, OriginalPhysicalAngleScalarDomain>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalCertifiedSphereConeApexPlaneSeparationReceipt {
        do {
            let retainedSource = copy source, retainedPlane = copy plane
            return try OriginalSourceProofAdmission.withBorrow(&admission) { usage in
                try usage.checkpoint(); try usage.consumeWork(1)
                try retainedSource.require(limits); try retainedPlane.source.require(limits)
                let s = retainedSource.original, f = s.field
                // FIXME(INCOMPLETE_IMPLEMENTATION): Other certified configurations or target
                // planes lack this whole-support separation theorem. Public pair issuance
                // must reject them until their actual source laws and bounds are certified.
                guard OriginalCertifiedSphereConeApexSnapshotProvider.supports(
                    .certifiedIntersection(.sphereCone(s.original))),
                    OriginalCertifiedSphereConeApexSnapshotProvider.supportsPlane(retainedPlane.source.original.original),
                    s.apex == Point3D(x: 1, y: 0, z: 0), s.axis == .unitZ,
                    s.basisU.z == 0, s.basisV.z == 0,
                    s.axialCenter == 0, s.quadraticC == 0 else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                guard f.originalRadians.bitPattern == s.halfAngle.bitPattern else {
                    throw OriginalSourceIssuanceFailure.unsupportedCoefficientField
                }
                let zero = try f.integer(0, using: &usage), one = try f.integer(1, using: &usage)
                let two = try f.integer(2, using: &usage)
                // A same-angle field with a different owner is not this plane's field.
                let planeZero = try retainedPlane.field.integer(0, using: &usage)
                _ = try f.importing(planeZero, using: &usage)
                guard retainedPlane.origin.count == 3, retainedPlane.normal.count == 3,
                    retainedPlane.u.count == 3, retainedPlane.v.count == 3 else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                for axis in 0..<3 {
                    try usage.consumeWork(1)
                    let expectedOrigin = axis == 2 ? two : zero
                    let expectedNormal = axis == 2 ? one : zero
                    guard try f.compare(retainedPlane.origin[axis], expectedOrigin, using: &usage) == .equal,
                          try f.compare(retainedPlane.normal[axis], expectedNormal, using: &usage) == .equal else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                    _ = try f.sign(of: retainedPlane.u[axis], using: &usage)
                    _ = try f.sign(of: retainedPlane.v[axis], using: &usage)
                }

                // Retain exact imports of the actual owner-produced coefficients and labels.
                // Order: angle/lower/upper; apex/axis/U/V XYZ; a/rc/rs/A/C; sin/cos/tan/D/1D/2D.
                try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 26, of: Double.self))
                let raw = [s.halfAngle, s.original.lowerAngle, s.original.upperAngle,
                    s.apex.x, s.apex.y, s.apex.z, s.axis.x, s.axis.y, s.axis.z,
                    s.basisU.x, s.basisU.y, s.basisU.z, s.basisV.x, s.basisV.y, s.basisV.z,
                    s.axialCenter, s.radialCosine, s.radialSine, s.quadraticA, s.quadraticC,
                    s.sine, s.cosine, s.slope, s.slantDenominator, s.inverseQuadraticCosine, s.slantScale]
                try usage.retainStorage(bytes: exactScalarPayloadBytes(count: raw.count,
                    of: OriginalPhysicalAngleScalarDomain.Value.self))
                var binary: [OriginalPhysicalAngleScalarDomain.Value] = []; binary.reserveCapacity(raw.count)
                for value in raw {
                    try usage.consumeWork(1)
                    binary.append(try f.binary64(exactly: value, using: &usage))
                }
                let physicalSine = try f.sine(using: &usage), physicalCosine = try f.cosine(using: &usage)
                guard try f.sign(of: physicalCosine, using: &usage) == .positive else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                let physicalSlope = try f.dividing(physicalSine, by: physicalCosine, using: &usage)
                let physicalA = try f.adding(one, f.multiplying(physicalSlope, physicalSlope, using: &usage), using: &usage)

                func fraction(_ numerator: Int, _ denominator: Int) throws -> OriginalPhysicalAngleScalarDomain.Value {
                    try f.dividing(f.integer(numerator, using: &usage), by: f.integer(denominator, using: &usage), using: &usage)
                }
                func inside(_ value: OriginalPhysicalAngleScalarDomain.Value,
                    _ lower: OriginalPhysicalAngleScalarDomain.Value,
                    _ upper: OriginalPhysicalAngleScalarDomain.Value) throws {
                    try usage.consumeWork(1)
                    guard try f.compare(value, lower, using: &usage) == .greater,
                          try f.compare(value, upper, using: &usage) == .less else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                }
                let sineLower = try fraction(7, 16), sineUpper = try fraction(15, 32)
                let cosineLower = try fraction(7, 8), cosineUpper = try fraction(29, 32)
                let slopeLower = try fraction(31, 64), slopeUpper = try fraction(33, 64)
                let aLower = try fraction(79, 64), aUpper = try fraction(81, 64)
                // The stored binary coefficients and mathematical angle functions are
                // independently checked. Their numerical closeness is never equality.
                try inside(binary[20], sineLower, sineUpper); try inside(physicalSine, sineLower, sineUpper)
                try inside(binary[21], cosineLower, cosineUpper); try inside(physicalCosine, cosineLower, cosineUpper)
                try inside(binary[22], slopeLower, slopeUpper); try inside(physicalSlope, slopeLower, slopeUpper)
                try inside(binary[18], aLower, aUpper); try inside(physicalA, aLower, aUpper)
                let radialCosineUpper = try fraction(1, 64), radialSineUpper = try fraction(65, 64)
                try inside(binary[16], f.negated(radialCosineUpper, using: &usage), radialCosineUpper)
                try inside(binary[17], f.negated(radialSineUpper, using: &usage), radialSineUpper)
                guard try f.sign(of: binary[15], using: &usage) == .zero,
                      try f.sign(of: binary[19], using: &usage) == .zero else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                let denominatorLower = try f.multiplying(aLower, cosineLower, using: &usage)
                let denominatorUpper = try f.multiplying(aUpper, cosineUpper, using: &usage)
                let physicalDenominator = try f.multiplying(physicalA, physicalCosine, using: &usage)
                guard try f.sign(of: denominatorLower, using: &usage) == .positive else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                try inside(binary[23], denominatorLower, denominatorUpper)
                try inside(physicalDenominator, denominatorLower, denominatorUpper)
                let inverseUpper = try f.dividing(one, by: denominatorLower, using: &usage)
                let scaleUpper = try f.dividing(two, by: denominatorLower, using: &usage)
                // Preserve actual rounded inverse/scale coefficients as separate inputs;
                // do not assert that a binary division equals mathematical division.
                try inside(binary[24], zero, inverseUpper); try inside(binary[25], zero, scaleUpper)
                let physicalInverse = try f.dividing(one, by: physicalDenominator, using: &usage)
                let physicalScale = try f.multiplying(two, physicalInverse, using: &usage)
                try inside(physicalInverse, zero, inverseUpper); try inside(physicalScale, zero, scaleUpper)

                // For every real phase, |C|,|S|<=1. The original unit-Z generator
                // has Z=cos(alpha), including both closed apex endpoints. Bound the
                // numerator and denominator independently; never cancel cosine.
                let radialUpper = try f.adding(radialCosineUpper, radialSineUpper, using: &usage)
                let halfLinearUpper = try f.multiplying(slopeUpper, radialUpper, using: &usage)
                let heightUpper = try f.multiplying(cosineUpper,
                    f.multiplying(scaleUpper, halfLinearUpper, using: &usage), using: &usage)
                let strictHeightLimit = try fraction(15, 16)
                guard try f.compare(heightUpper, strictHeightLimit, using: &usage) == .less else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                let lower = try f.subtracting(f.negated(heightUpper, using: &usage), two, using: &usage)
                let upper = try f.subtracting(heightUpper, two, using: &usage)
                let clearance = try f.subtracting(two, heightUpper, using: &usage)
                guard try f.sign(of: upper, using: &usage) == .negative,
                      try f.sign(of: clearance, using: &usage) == .positive else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: OriginalPhysicalAngleScalarDomain.Value.self))
                let physical = [physicalSine, physicalCosine, physicalSlope, physicalA]
                try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 19, of: OriginalPhysicalAngleScalarDomain.Value.self))
                let envelope = [sineLower, sineUpper, cosineLower, cosineUpper, slopeLower, slopeUpper,
                    aLower, aUpper, radialCosineUpper, radialSineUpper, denominatorLower, denominatorUpper,
                    inverseUpper, scaleUpper, physicalDenominator, physicalInverse, physicalScale,
                    halfLinearUpper, strictHeightLimit]
                try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                    of: OriginalCertifiedSphereConeApexPlaneSeparationReceipt.self))
                let result = OriginalCertifiedSphereConeApexPlaneSeparationReceipt(source: retainedSource,
                    plane: retainedPlane, field: f, support: .init(lower: zero, upper: one),
                    signedDistanceLower: lower, signedDistanceUpper: upper, heightUpperBound: heightUpper,
                    clearance: clearance, binaryCoefficients: binary, physicalCoefficients: physical,
                    commonEnvelope: envelope, proofDepth: try usage.depth)
                try usage.checkpoint(); return result
            }
        } catch { throw .init(preserving: error) }
    }
}
