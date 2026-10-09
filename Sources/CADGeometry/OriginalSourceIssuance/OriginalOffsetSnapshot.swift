import CADCore

/// Retains actual construction; numerical query tolerance remains caller-owned.
public struct OriginalOffsetSnapshot<Child:Sendable>:OriginalOffsetSourceReading {
    public let original:OffsetSurface3D
    public let originalChild:OriginalSourceBinding<Child>
    public var originalDistance:Double { original.distance }
    init(original:OffsetSurface3D,originalChild:OriginalSourceBinding<Child>) {
        self.original=original;self.originalChild=originalChild
    }
}
