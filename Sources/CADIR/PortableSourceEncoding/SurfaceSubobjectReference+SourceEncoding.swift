import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceSubobjectReference`.
extension CADIR.SurfaceSubobjectReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .whole(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "whole", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "parameter", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .span(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "span", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .controlPoint(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "controlPoint", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .knot(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "knot", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .trim(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trim", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .trimSpan(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trimSpan", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .trimKnot(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trimKnot", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
