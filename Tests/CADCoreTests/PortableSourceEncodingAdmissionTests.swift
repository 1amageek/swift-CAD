import Testing

@Suite("Canonical source encoding caller admission", .timeLimit(.minutes(1)))
struct PortableSourceEncodingAdmissionTests {
    @Test func canonicalBytesAndLocalMeasurementRemainOriginal() throws {
        try PortableSourceEncodingAdmissionChecks.canonicalBytesAndLocalMeasurementRemainOriginal()
    }
    @Test func childKeysShareOneAdmissionAndExactResourceBoundaries() throws {
        try PortableSourceEncodingAdmissionChecks.childKeysShareOneAdmissionAndExactResourceBoundaries()
    }
    @Test func originalGuardsCollisionAndCancellationRemainExplicit() throws {
        try PortableSourceEncodingAdmissionChecks.originalGuardsCollisionAndCancellationRemainExplicit()
    }
}
