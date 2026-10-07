#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyLimits: Sendable {
 public let maximumGeneratedCells: Int
 public let maximumRootsPerStack: Int
 public let maximumClosures: Int
 public let maximumAttachmentPieces: Int
 public let maximumComponents: Int
 public init(maximumGeneratedCells: Int, maximumRootsPerStack: Int, maximumClosures: Int,
  maximumAttachmentPieces: Int, maximumComponents: Int) throws(ExactRealTopologyFailure) {
  guard maximumGeneratedCells >= 0, maximumRootsPerStack >= 0, maximumClosures >= 0,
   maximumAttachmentPieces >= 0, maximumComponents >= 0 else { throw .invalidDefinition }
  self.maximumGeneratedCells = maximumGeneratedCells; self.maximumRootsPerStack = maximumRootsPerStack
  self.maximumClosures = maximumClosures; self.maximumAttachmentPieces = maximumAttachmentPieces
  self.maximumComponents = maximumComponents
 }
}
