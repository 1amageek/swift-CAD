#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Owner-bearing local selection, not whole requested-domain coverage evidence.
public struct OriginalSourceChart<Source: Sendable, Selection: Sendable>: Sendable {
    public let binding: OriginalSourceBinding<Source>
    public let selection: Selection
    init(binding: OriginalSourceBinding<Source>, selection: Selection) {
        self.binding = binding
        self.selection = selection
    }
}
