import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetBridgeFeature`.
extension CADIR.SheetBridgeFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SheetBridgeFeature", fields: 12, using: &admission)
        try encoder.field("angularAllowance", angularAllowance, using: &admission)
        try encoder.field("curvatureAllowance", curvatureAllowance, using: &admission)
        try encoder.text("edges", using: &admission)
        if let edges {
            try encoder.tag(0x20, using: &admission)
            try encoder.record("CADIR.SheetBridgeFeature.EdgePair", fields: 2, using: &admission)
            try encoder.field("first", edges.first, using: &admission)
            try encoder.field("second", edges.second, using: &admission)
        } else {
            try encoder.tag(0x00, using: &admission)
        }
        try encoder.field("extent", extent, using: &admission)
        try encoder.field("first", first, using: &admission)
        try encoder.field("reversesFirstSense", reversesFirstSense, using: &admission)
        try encoder.field("reversesSecondSense", reversesSecondSense, using: &admission)
        try encoder.field("second", second, using: &admission)
        try encoder.field("shape", shape, using: &admission)
        try encoder.field("tension", tension, using: &admission)
        try encoder.field("trimWalls", trimWalls, using: &admission)
        try encoder.field("width", width, using: &admission)
    }
}
