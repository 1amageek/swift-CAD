#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
#endif

/// Immutable constructor authority proves exact C0 joins and a normalized partition.
public protocol OriginalGuideSourceReading:Sendable {
    associatedtype Traversal:Sendable
    associatedtype Coefficient:Sendable
    var originalTraversalCount:Int { get }
    func originalTraversal(at index:Int)->OriginalSourceBinding<Traversal>
    func originalStation(at index:Int)->Coefficient
    func originalSegmentOrdinal(at index:Int)->Int
}
