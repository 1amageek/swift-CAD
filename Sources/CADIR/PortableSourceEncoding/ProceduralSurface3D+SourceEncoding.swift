import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ProceduralSurface3D`.
extension CADGeometry.ProceduralSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .originalDrafted(let value):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalDrafted", values: 1)
            try encoder.field("_0", value)
        case .originalPlaneDerivative(let value):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalPlaneDerivative", values: 1)
            try encoder.field("_0", value)
        case .originalAngularTransport(let value):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalAngularTransport", values: 1)
            try encoder.field("_0", value)
        case .originalAffineWord(let value):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalAffineWord", values: 1)
            try encoder.field("_0", value)
        case let .offset(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "offset", values: 1)
            try encoder.field("_0", value0)
        case let .ruled(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "ruled", values: 1)
            try encoder.field("_0", value0)
        case let .rollingBall(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "rollingBall", values: 1)
            try encoder.field("_0", value0)
        case let .originalImage(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalImage", values: 1)
            try encoder.field("_0", value0)
        case let .originalBoundaryCorrected(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalBoundaryCorrected", values: 1)
            try encoder.field("_0", value0)
        case let .originalCoons(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalCoons", values: 1)
            try encoder.field("_0", value0)
        case let .originalRevolution(value0):
            try encoder.enumeration("CADGeometry.ProceduralSurface3D", caseName: "originalRevolution", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
