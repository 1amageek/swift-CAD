/// The source is the canonical intrinsic sphere primitive, not a fitted sphere
/// or a physical-radian parameter image. Its authored law is
/// C + r (cos(phi(v)) cos(phi(u)), cos(phi(v)) sin(phi(u)), sin(phi(v)))
/// with phi(label) = mathematicalPi * label / binary64Pi. Providers validate
/// finite center, positive finite radius, retained source depth and this exact
/// coordinate meaning. Accessors are constant-time and immutable.
public protocol OriginalIntrinsicSphereSourceReading: Sendable {
    func centerCoordinate(in axis: Int) -> Double
    var radius: Double { get }
}
