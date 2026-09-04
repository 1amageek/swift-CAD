/// The resource dimension a tessellation invocation exhausted.
///
/// The dimensions are generic counts and bytes rather than CAD concepts, so a
/// consumer can report exhaustion without knowing which surface produced it.
public enum TessellationResource: String, Codable, Sendable, Hashable, CaseIterable {
    case vertexCount
    case indexCount
    case triangleCount
    case byteCount
}
