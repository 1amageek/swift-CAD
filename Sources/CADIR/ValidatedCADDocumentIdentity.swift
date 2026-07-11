import Foundation

package struct ValidatedCADDocumentIdentity: Hashable, Sendable {
    private let rawValue: UUID

    package init() {
        rawValue = UUID()
    }
}
