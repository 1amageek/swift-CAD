import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetBridgeFeature`.
extension CADIR.SheetBridgeFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SheetBridgeFeature", fields: 12)
        try encoder.field("angularAllowance", angularAllowance)
        try encoder.field("curvatureAllowance", curvatureAllowance)
        try encoder.text("edges")
        if let edges {
            try encoder.tag(0x20)
            try encoder.record("CADIR.SheetBridgeFeature.EdgePair", fields: 2)
            try encoder.field("first", edges.first)
            try encoder.field("second", edges.second)
        } else {
            try encoder.tag(0x00)
        }
        try encoder.field("extent", extent)
        try encoder.field("first", first)
        try encoder.field("reversesFirstSense", reversesFirstSense)
        try encoder.field("reversesSecondSense", reversesSecondSense)
        try encoder.field("second", second)
        try encoder.field("shape", shape)
        try encoder.field("tension", tension)
        try encoder.field("trimWalls", trimWalls)
        try encoder.field("width", width)
    }
}
