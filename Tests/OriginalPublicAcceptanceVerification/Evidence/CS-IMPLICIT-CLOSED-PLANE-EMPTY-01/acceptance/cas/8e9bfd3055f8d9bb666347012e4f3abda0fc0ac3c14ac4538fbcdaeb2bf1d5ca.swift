import CADCore

/// Actual authored revolution and normalized traversal stay retained together.
public struct OriginalRevolutionSnapshot<Child:Sendable>:OriginalRevolutionSourceReading {
    public let original:OriginalRevolutionSurface3D
    public let originalGenerator:OriginalSourceBinding<OriginalTraversalSpanSnapshot<Child>>
    public let originalLowerU:Double
    public let originalUpperU:Double
    public func axisOriginCoordinate(in axis:Int)->Double { axis == 0 ? original.axisOrigin.x:axis == 1 ? original.axisOrigin.y:original.axisOrigin.z }
    public func axisDirectionCoordinate(in axis:Int)->Double { axis == 0 ? original.axisDirection.x:axis == 1 ? original.axisDirection.y:original.axisDirection.z }
}
