/// Explicit original-value encoding; this requirement is callable without runtime metadata.
public protocol PortableSourceEncodable {
    func encodeSource(to encoder: inout PortableSourceEncoder) throws
}
