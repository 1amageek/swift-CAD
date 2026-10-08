/// A validated source snapshot retaining the family-owned original chart frame.
/// Frame columns map primitive-local XYZ to world XYZ; getters are constant-time.
/// Sphere uses the canonical identity image frame. Cylinder and torus use their
/// actual source frame, with no inferred exact unit length or orthogonality.
public protocol OriginalPrimitiveImageReading: OriginalImageFrameReading {
    var imageKind: OriginalPrimitiveImageKind { get }
    var majorRadius: Double { get }
    var minorRadius: Double { get }
}
