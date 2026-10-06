import CADCore

package struct ValidatedCADDocumentIdentity: Hashable, Sendable {
    private let rawValue: PortableIdentity128

    package init() {
        rawValue = PortableIdentity128()
    }
}
