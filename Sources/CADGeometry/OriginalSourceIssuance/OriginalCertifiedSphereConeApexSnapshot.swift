import CADCore

/// Immutable coefficients produced by the original certified apex position owner.
public struct OriginalCertifiedSphereConeApexSnapshot: Sendable {
    public let original: CertifiedSphereConeIntersectionCurve
    public let field: OriginalPhysicalAngleScalarDomain
    public let apex: Point3D
    public let axis: Vector3D
    public let basisU: Vector3D
    public let basisV: Vector3D
    public let halfAngle: Double
    public let axialCenter: Double
    public let radialCosine: Double
    public let radialSine: Double
    public let quadraticA: Double
    public let quadraticC: Double
    /// These are regenerated binary64 coefficients, not mathematical sine/cosine.
    public let sine: Double
    public let cosine: Double
    public let slope: Double
    public let slantDenominator: Double
    public let inverseQuadraticCosine: Double
    public let slantScale: Double

    init(original: CertifiedSphereConeIntersectionCurve, field: OriginalPhysicalAngleScalarDomain,
        apex: Point3D, axis: Vector3D, basisU: Vector3D, basisV: Vector3D, halfAngle: Double,
        axialCenter: Double, radialCosine: Double, radialSine: Double, quadraticA: Double,
        quadraticC: Double, sine: Double, cosine: Double, slope: Double,
        slantDenominator: Double, inverseQuadraticCosine: Double, slantScale: Double) {
        self.original = original; self.field = field; self.apex = apex; self.axis = axis
        self.basisU = basisU; self.basisV = basisV; self.halfAngle = halfAngle
        self.axialCenter = axialCenter; self.radialCosine = radialCosine; self.radialSine = radialSine
        self.quadraticA = quadraticA; self.quadraticC = quadraticC
        self.sine = sine; self.cosine = cosine; self.slope = slope
        self.slantDenominator = slantDenominator; self.inverseQuadraticCosine = inverseQuadraticCosine
        self.slantScale = slantScale
    }
}
