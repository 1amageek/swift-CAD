import CADCore
import CADGeometry

/// Encodes the original direct assembly placement family and authored columns.
extension AssemblyPlacement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .rigid(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "rigid", values: 1)
            try encoder.field("_0", value)
        case .affine(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "affine", values: 1)
            try encoder.field("_0", value)
        case .step(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "step", values: 1)
            try encoder.field("_0", value)
        case .word(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "word", values: 1)
            try encoder.field("_0", value)
        }
    }
}
