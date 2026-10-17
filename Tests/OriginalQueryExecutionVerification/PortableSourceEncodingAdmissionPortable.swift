// Compile with the same Core admission checks used by the Native test wrapper.
@main
struct PortableSourceEncodingAdmissionPortable {
    static func main() throws {
        try PortableSourceEncodingAdmissionChecks.canonicalBytesAndLocalMeasurementRemainOriginal()
        print("PASS canonicalBytesAndLocalMeasurementRemainOriginal")
        try PortableSourceEncodingAdmissionChecks.childKeysShareOneAdmissionAndExactResourceBoundaries()
        print("PASS childKeysShareOneAdmissionAndExactResourceBoundaries")
        try PortableSourceEncodingAdmissionChecks.originalGuardsCollisionAndCancellationRemainExplicit()
        print("PASS originalGuardsCollisionAndCancellationRemainExplicit")
    }
}
