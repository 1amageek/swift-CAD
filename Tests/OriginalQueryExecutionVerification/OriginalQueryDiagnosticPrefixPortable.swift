import CADCore
import CADGeometry

@main
struct OriginalQueryDiagnosticPrefixPortable {
    static func main() throws {
        try OriginalQueryDiagnosticPrefixChecks.prefixPreservesEveryPublishedFieldAndInnerContext()
        print("PASS prefixPreservesEveryPublishedFieldAndInnerContext")
        try OriginalQueryDiagnosticPrefixChecks.rawResourcePublicationRetainsCauseAndFillsOnlyMissingContext()
        print("PASS rawResourcePublicationRetainsCauseAndFillsOnlyMissingContext")
        try OriginalQueryDiagnosticPrefixChecks.explicitClassificationOwnerStillControlsItsAggregateDecision()
        print("PASS explicitClassificationOwnerStillControlsItsAggregateDecision")
        try OriginalQueryDiagnosticPrefixChecks.diagnosticPrefixNeverClassifiesCancellationOrInventsForeignAuthority()
        print("PASS diagnosticPrefixNeverClassifiesCancellationOrInventsForeignAuthority")
    }
}
