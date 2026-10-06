import CADTopology

/// Original loop order and topology role after whole-law orientation admission.
package struct OriginalFaceSectionLoop: Sendable {
    package let loopID: LoopID
    package let role: LoopRole
    package let segments: [OriginalFaceSectionSegment]
}
