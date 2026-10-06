#if !hasFeature(Embedded)
import CADCore
import CADGeometry

/// Strict frame decoding shared only by this source owner.
package enum IndependentShapeFrameDecoding {
    private enum FrameKeys: String, CodingKey { case basisX, basisY, basisZ, translation }
    private enum VectorKeys: String, CodingKey { case x, y, z }
    static func decodeVector(from decoder: Decoder) throws -> Vector3D {
        let vector = try decoder.container(keyedBy: VectorKeys.self)
        try vector.validateOnlyExpectedKeys([.x, .y, .z], in: decoder)
        return try Vector3D(from: decoder)
    }
    static func decode(from decoder: Decoder) throws -> AffineTransform3D {
        let c = try decoder.container(keyedBy: FrameKeys.self)
        try c.validateOnlyExpectedKeys([.basisX, .basisY, .basisZ, .translation], in: decoder)
        for key in [FrameKeys.basisX, .basisY, .basisZ, .translation] {
            let d = try c.superDecoder(forKey: key)
            let vector = try d.container(keyedBy: VectorKeys.self)
            try vector.validateOnlyExpectedKeys([.x, .y, .z], in: d)
        }
        return try AffineTransform3D(from: decoder)
    }
}

#endif
