/// Exact intrinsic source expression X=cx-R*sin(label), Y=cy+R*cos(label), Z=h.
public struct OriginalCoaxialSymbolicPosition: Sendable {
    public let source: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>
    public let positive: Bool
    public let intrinsicLabel: OriginalPhysicalAngleValue
    public let radius: OriginalPhysicalAngleValue
    public let centerX: OriginalPhysicalAngleValue
    public let centerY: OriginalPhysicalAngleValue
    public let height: OriginalPhysicalAngleValue
    public var cosine: OriginalSourceCoordinateFunction<OriginalPhysicalAngleValue> { .intrinsicCosine(axis: 0) }
    public var sine: OriginalSourceCoordinateFunction<OriginalPhysicalAngleValue> { .intrinsicSine(axis: 0) }
}
