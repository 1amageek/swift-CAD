import Foundation
import CADCore

public struct CADDocumentSourceFingerprint: Codable, Hashable, Sendable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public extension CADDocument {
    func sourceFingerprint(tolerance: ModelingTolerance = .standard) throws -> CADDocumentSourceFingerprint {
        try validate(tolerance: tolerance)
        let payload = try CADDocumentSourceFingerprintPayload(document: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return CADDocumentSourceFingerprint(
            algorithm: "sha256-cad-source-v1",
            value: SHA256Digest.hexDigest(for: data)
        )
    }
}

private struct CADDocumentSourceFingerprintPayload: Encodable {
    var id: String
    var schemaVersion: SchemaVersion
    var units: UnitSystem
    var parameters: ParameterTableFingerprint
    var designGraph: DesignGraphFingerprint
    var selectionDimensions: [SelectionDimension]

    init(document: CADDocument) throws {
        id = document.id.description
        schemaVersion = document.schemaVersion
        units = document.units
        parameters = ParameterTableFingerprint(table: document.parameters)
        designGraph = try DesignGraphFingerprint(graph: document.designGraph)
        selectionDimensions = try document.selectionDimensions.sortedByStableEncoding()
    }
}

private struct ParameterTableFingerprint: Encodable {
    var revision: DocumentRevision
    var parameters: [ParameterFingerprint]

    init(table: ParameterTable) {
        revision = table.revision
        parameters = table.parameters
            .sorted { $0.key.description < $1.key.description }
            .map { ParameterFingerprint(id: $0.key, parameter: $0.value) }
    }
}

private struct ParameterFingerprint: Encodable {
    var tableID: String
    var id: String
    var name: String
    var expression: CADExpression
    var kind: QuantityKind

    init(id tableID: ParameterID, parameter: Parameter) {
        self.tableID = tableID.description
        id = parameter.id.description
        name = parameter.name
        expression = parameter.expression
        kind = parameter.kind
    }
}

private struct DesignGraphFingerprint: Encodable {
    var revision: DocumentRevision
    var order: [String]
    var dependencies: [DependencyFingerprint]
    var nodes: [FeatureNodeFingerprint]

    init(graph: DesignGraph) throws {
        revision = graph.revision
        order = graph.order.map(\.description)
        dependencies = graph.dependencies
            .map(DependencyFingerprint.init)
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source < rhs.source
                }
                return lhs.target < rhs.target
            }
        nodes = try graph.nodes
            .sorted { $0.key.description < $1.key.description }
            .map { try FeatureNodeFingerprint(tableID: $0.key, node: $0.value) }
    }
}

private struct DependencyFingerprint: Encodable {
    var source: String
    var target: String

    init(_ dependency: DependencyEdge) {
        source = dependency.source.description
        target = dependency.target.description
    }
}

private struct FeatureNodeFingerprint: Encodable {
    var tableID: String
    var id: String
    var name: String?
    var operation: FeatureOperationFingerprint
    var inputs: [FeatureInput]
    var outputs: [FeatureOutput]
    var isSuppressed: Bool

    init(tableID: FeatureID, node: FeatureNode) throws {
        self.tableID = tableID.description
        id = node.id.description
        name = node.name
        operation = try FeatureOperationFingerprint(operation: node.operation)
        inputs = node.inputs
        outputs = node.outputs
        isSuppressed = node.isSuppressed
    }
}

private struct FeatureOperationFingerprint: Encodable {
    var kind: String
    var sketch: SketchFingerprint?
    var extrude: ExtrudeFeature?
    var revolve: RevolveFeature?
    var sweep: SweepFeature?
    var boolean: BooleanFeature?
    var polySpline: PolySplineFeature?
    var bSplineSurface: BSplineSurfaceFeature?
    var faceLoopOffset: FaceLoopOffsetFeature?
    var edgeOffset: EdgeOffsetFeature?
    var faceKnife: FaceKnifeFeature?
    var bridgeCurve: BridgeCurveFeature?
    var curveEdit: CurveEditFeature?
    var curveOffset: CurveOffsetFeature?
    var curveTrim: CurveTrimFeature?

    init(operation: FeatureOperation) throws {
        switch operation {
        case let .sketch(sketch):
            kind = "sketch"
            self.sketch = try SketchFingerprint(sketch: sketch)
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .extrude(extrude):
            kind = "extrude"
            sketch = nil
            self.extrude = extrude
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .revolve(revolve):
            kind = "revolve"
            sketch = nil
            extrude = nil
            self.revolve = revolve
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .sweep(sweep):
            kind = "sweep"
            sketch = nil
            extrude = nil
            revolve = nil
            self.sweep = sweep
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .boolean(boolean):
            kind = "boolean"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            self.boolean = boolean
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .polySpline(polySpline):
            kind = "polySpline"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            self.polySpline = polySpline
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .bSplineSurface(bSplineSurface):
            kind = "bSplineSurface"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            self.bSplineSurface = bSplineSurface
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .faceLoopOffset(faceLoopOffset):
            kind = "faceLoopOffset"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            self.faceLoopOffset = faceLoopOffset
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .edgeOffset(edgeOffset):
            kind = "edgeOffset"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            self.edgeOffset = edgeOffset
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .faceKnife(faceKnife):
            kind = "faceKnife"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            self.faceKnife = faceKnife
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .bridgeCurve(bridgeCurve):
            kind = "bridgeCurve"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            self.bridgeCurve = bridgeCurve
            curveEdit = nil
            curveOffset = nil
            curveTrim = nil
        case let .curveEdit(curveEdit):
            kind = "curveEdit"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            self.curveEdit = curveEdit
            curveOffset = nil
            curveTrim = nil
        case let .curveOffset(curveOffset):
            kind = "curveOffset"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            self.curveOffset = curveOffset
            curveTrim = nil
        case let .curveTrim(curveTrim):
            kind = "curveTrim"
            sketch = nil
            extrude = nil
            revolve = nil
            sweep = nil
            boolean = nil
            polySpline = nil
            bSplineSurface = nil
            faceLoopOffset = nil
            edgeOffset = nil
            faceKnife = nil
            bridgeCurve = nil
            curveEdit = nil
            curveOffset = nil
            self.curveTrim = curveTrim
        }
    }
}

private struct SketchFingerprint: Encodable {
    var id: String
    var plane: SketchPlane
    var entities: [SketchEntityFingerprint]
    var constraints: [SketchConstraint]
    var dimensions: [SketchDimension]

    init(sketch: Sketch) throws {
        id = sketch.id.description
        plane = sketch.plane
        entities = sketch.entities
            .sorted { $0.key.description < $1.key.description }
            .map { SketchEntityFingerprint(id: $0.key, entity: $0.value) }
        constraints = try sketch.constraints.sortedByStableEncoding()
        dimensions = try sketch.dimensions.sortedByStableEncoding()
    }
}

private struct SketchEntityFingerprint: Encodable {
    var id: String
    var entity: SketchEntity

    init(id: SketchEntityID, entity: SketchEntity) {
        self.id = id.description
        self.entity = entity
    }
}

private extension Array where Element: Encodable {
    func sortedByStableEncoding() throws -> [Element] {
        try map { element in
            (try stableJSONString(for: element), element)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }
}

private func stableJSONString<T: Encodable>(for value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw SchemaError.invalidMetadata("Canonical source fingerprint payload is not UTF-8.")
    }
    return string
}

private enum SHA256Digest {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hexDigest(for data: Data) -> String {
        digest(for: data).map { String(format: "%08x", $0) }.joined()
    }

    private static func digest(for data: Data) -> [UInt32] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: bitLength.bigEndianBytes)

        var hash = initialHash
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = Array(repeating: UInt32(0), count: 64)
            for index in 0..<16 {
                let byteIndex = chunkStart + index * 4
                words[index] = UInt32(message[byteIndex]) << 24
                    | UInt32(message[byteIndex + 1]) << 16
                    | UInt32(message[byteIndex + 2]) << 8
                    | UInt32(message[byteIndex + 3])
            }
            for index in 16..<64 {
                words[index] = smallSigma1(words[index - 2])
                    &+ words[index - 7]
                    &+ smallSigma0(words[index - 15])
                    &+ words[index - 16]
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let temp1 = h
                    &+ bigSigma1(e)
                    &+ choose(e, f, g)
                    &+ roundConstants[index]
                    &+ words[index]
                let temp2 = bigSigma0(a) &+ majority(a, b, c)
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }
        return hash
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static func choose(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (~x & z)
    }

    private static func majority(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) ^ (x & z) ^ (y & z)
    }

    private static func bigSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 2) ^ rotateRight(value, by: 13) ^ rotateRight(value, by: 22)
    }

    private static func bigSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 6) ^ rotateRight(value, by: 11) ^ rotateRight(value, by: 25)
    }

    private static func smallSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 7) ^ rotateRight(value, by: 18) ^ (value >> 3)
    }

    private static func smallSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 17) ^ rotateRight(value, by: 19) ^ (value >> 10)
    }
}

private extension UInt64 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 56) & 0xff),
            UInt8((self >> 48) & 0xff),
            UInt8((self >> 40) & 0xff),
            UInt8((self >> 32) & 0xff),
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
    }
}
