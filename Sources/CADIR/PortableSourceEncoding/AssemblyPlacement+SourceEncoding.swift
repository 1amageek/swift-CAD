import CADCore
import CADGeometry

/// Encodes the original direct assembly placement family and authored columns.
extension AssemblyPlacement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .rigid(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "rigid", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .affine(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "affine", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .step(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "step", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .word(let value):
            try encoder.enumeration("CADIR.AssemblyPlacement", caseName: "word", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}
