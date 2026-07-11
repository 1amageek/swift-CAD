import CADCore

package struct ValidatedCADDocumentTransition: Sendable {
    package let sourceIdentity: ValidatedCADDocumentIdentity
    package let changedFeatureIDs: Set<FeatureID>
}
