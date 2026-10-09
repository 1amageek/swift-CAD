#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
#endif

/// Original offset construction retaining its child and exact distance bits.
public protocol OriginalOffsetSourceReading:Sendable {
    associatedtype Child:Sendable
    var originalChild:OriginalSourceBinding<Child> { get }
    var originalDistance:Double { get }
}
