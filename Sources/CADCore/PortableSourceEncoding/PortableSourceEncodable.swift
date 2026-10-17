/// Explicit original-value encoding with caller-owned admission and no runtime metadata.
public protocol PortableSourceEncodable {
    func encodeSource<A: NumericWorkAdmission & ~Copyable>(
        to encoder: inout PortableSourceEncoder, using admission: inout A
    ) throws
}

public extension PortableSourceEncodable {
    /// Preserves ordinary authoring policy while using the same admitted writer body.
    func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        var admission = UnboundedAuthoringAdmission()
        try encodeSource(to: &encoder, using: &admission)
    }
}
