import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceSubobjectReference`.
extension CADIR.SurfaceSubobjectReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .whole(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "whole", values: 1)
            try encoder.field("_0", value0)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "parameter", values: 1)
            try encoder.field("_0", value0)
        case let .span(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "span", values: 1)
            try encoder.field("_0", value0)
        case let .controlPoint(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "controlPoint", values: 1)
            try encoder.field("_0", value0)
        case let .knot(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "knot", values: 1)
            try encoder.field("_0", value0)
        case let .trim(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trim", values: 1)
            try encoder.field("_0", value0)
        case let .trimSpan(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trimSpan", values: 1)
            try encoder.field("_0", value0)
        case let .trimKnot(value0):
            try encoder.enumeration("CADIR.SurfaceSubobjectReference", caseName: "trimKnot", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
