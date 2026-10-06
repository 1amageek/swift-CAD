import CADGeometry

/// Native JSON framing preserves every typed original event without interpretation.
struct DrawingSilhouetteProvenanceEventValue: Encodable {
    let event: SurfaceSilhouetteProvenanceEvent
    func encode(to encoder: any Encoder) throws {
        var values = encoder.unkeyedContainer()
        switch event {
        case .beginRecord(let type): try values.encode("beginRecord"); try values.encode(type)
        case .endRecord: try values.encode("endRecord")
        case .field(let name): try values.encode("field"); try values.encode(name)
        case .beginArray(let count): try values.encode("beginArray"); try values.encode(count)
        case .endArray: try values.encode("endArray")
        case .text(let value): try values.encode("text"); try values.encode(value)
        case .boolean(let value): try values.encode("boolean"); try values.encode(value)
        case .integer(let value): try values.encode("integer"); try values.encode(value)
        case .floatingBits(let value): try values.encode("floatingBits"); try values.encode(value)
        case .unsignedWords(let value): try values.encode("unsignedWords"); try values.encode(value)
        case .surface(let value): try values.encode("surface"); try values.encode(value)
        case .null: try values.encode("null")
        }
    }
}
