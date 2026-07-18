import Foundation
import CADCore
import CADIR

public struct ThreeMFExchange: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard isThreeMFSupportedLengthUnit(unit) else {
            throw ExportError.invalidMesh("3MF does not support \(unit.rawValue) length units.")
        }
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let modelMeasurement = try measureBytes {
            try writeModelXML(meshes: meshes, unit: unit, to: $0)
        }
        try StoredZipArchive.write(streamedEntries: [
            streamedDataEntry(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            streamedDataEntry(path: "_rels/.rels", data: Data(relationshipsXML.utf8)),
            StoredZipArchive.StreamedEntry(
                path: "3D/3dmodel.model",
                byteCount: modelMeasurement.byteCount,
                crc: modelMeasurement.crc,
                write: { sink in
                    try writeModelXML(meshes: meshes, unit: unit, to: sink)
                }
            )
        ], to: sink)
    }

    public func `import`(_ bytes: BorrowedBytes, fallbackUnit: LengthUnit = .millimeter) throws -> ImportedExchangeModel {
        try `import`(bytes as any ByteSource, fallbackUnit: fallbackUnit)
    }

    public func `import`(_ source: any ByteSource, fallbackUnit: LengthUnit = .millimeter) throws -> ImportedExchangeModel {
        do {
            return try StoredZipArchive.withBorrowedEntries(from: source) { entries in
                try importPackageEntries(entries, fallbackUnit: fallbackUnit)
            }
        } catch let error as ZipArchiveError {
            throw ImportError.invalidData("Invalid 3MF package: \(error).")
        } catch {
            throw error
        }
    }

    private func importPackageEntries(
        _ entries: [String: Data],
        fallbackUnit: LengthUnit
    ) throws -> ImportedExchangeModel {
        try validateThreeMFPackageEntries(entries)
        guard let contentTypesData = entries["[Content_Types].xml"],
              let relationshipsData = entries["_rels/.rels"] else {
            throw ImportError.missingRequiredEntity("3MF package metadata")
        }
        try ThreeMFPackageXMLValidator.validate(
            contentTypes: contentTypesData,
            relationships: relationshipsData
        )
        guard let modelData = entries["3D/3dmodel.model"] else {
            throw ImportError.missingRequiredEntity("3D/3dmodel.model")
        }
        guard String(data: modelData, encoding: .utf8) != nil else {
            throw ImportError.invalidData("3MF model XML is not UTF-8.")
        }
        let model = try ThreeMFModelXMLReader.read(modelData, fallbackUnit: fallbackUnit)
        let unit = model.unit

        var meshes: [BodyID: Mesh] = [:]
        for mesh in model.meshes {
            try validateImportedMesh(mesh, formatName: "3MF", tolerance: tolerance)
            meshes[BodyID()] = mesh
        }
        guard !meshes.isEmpty else {
            throw ImportError.invalidData("3MF build contains no mesh objects.")
        }
        return ImportedExchangeModel(format: .threeMF, meshes: meshes, units: UnitSystem(length: unit, angle: .radian))
    }

    private func writeModelXML(meshes: [BodyID: Mesh], unit: LengthUnit, to sink: any ByteSink) throws {
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        var objectID = 1
        let unitName = try threeMFUnitName(for: unit)
        try sink.writeUTF8("""
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="\(unitName)" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        """)
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
            try sink.writeUTF8("""

            <object id="\(objectID)" type="model">
              <mesh>
                <vertices>
            """)
            for point in mesh.positions {
                let x = try checkedExportUnitValue(
                    unit.fromInternal(point.x),
                    formatName: "3MF",
                    component: "vertex.x"
                )
                let y = try checkedExportUnitValue(
                    unit.fromInternal(point.y),
                    formatName: "3MF",
                    component: "vertex.y"
                )
                let z = try checkedExportUnitValue(
                    unit.fromInternal(point.z),
                    formatName: "3MF",
                    component: "vertex.z"
                )
                try sink.writeUTF8("\n<vertex x=\"\(x)\" y=\"\(y)\" z=\"\(z)\"/>")
            }
            try sink.writeUTF8("""

                </vertices>
                <triangles>
            """)
            var index = 0
            while index < mesh.indices.count {
                try sink.writeUTF8("\n<triangle v1=\"\(mesh.indices[index])\" v2=\"\(mesh.indices[index + 1])\" v3=\"\(mesh.indices[index + 2])\"/>")
                index += 3
            }
            try sink.writeUTF8("""

                </triangles>
              </mesh>
            </object>
            """)
            objectID += 1
        }
        try sink.writeUTF8("""

          </resources>
          <build>
        """)
        for objectID in 1...sortedMeshes.count {
            try sink.writeUTF8("\n<item objectid=\"\(objectID)\"/>")
        }
        try sink.writeUTF8("""

          </build>
        </model>
        """)
    }

    private var contentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """
    }

    private var relationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """
    }
}

private struct ByteMeasurement {
    var byteCount: Int
    var crc: UInt32
}

private final class MeasuringByteSink: ByteSink {
    private var checksum = CRC32()
    private(set) var byteCount = 0

    var measurement: ByteMeasurement {
        ByteMeasurement(byteCount: byteCount, crc: checksum.finalize())
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        byteCount += bytes.count
        checksum.update(bytes)
    }
}

private func measureBytes(_ operation: (any ByteSink) throws -> Void) throws -> ByteMeasurement {
    let sink = MeasuringByteSink()
    try operation(sink)
    return sink.measurement
}

private func streamedDataEntry(path: String, data: Data) -> StoredZipArchive.StreamedEntry {
    StoredZipArchive.StreamedEntry(
        path: path,
        byteCount: data.count,
        crc: CRC32.checksum(data),
        write: { sink in
            try sink.write(data)
        }
    )
}

private func threeMFUnitName(for unit: LengthUnit) throws -> String {
    switch unit {
    case .micrometer:
        "micron"
    case .meter:
        "meter"
    case .millimeter:
        "millimeter"
    case .centimeter:
        "centimeter"
    case .inch:
        "inch"
    case .foot:
        "foot"
    case .kilometer:
        throw ExportError.invalidMesh("3MF does not support kilometer length units.")
    }
}

private let supportedThreeMFPackageEntries: Set<String> = [
    "[Content_Types].xml",
    "_rels/.rels",
    "3D/3dmodel.model"
]

private func validateThreeMFPackageEntries(_ entries: [String: Data]) throws {
    let entryPaths = Set(entries.keys)
    let missingEntries = supportedThreeMFPackageEntries.subtracting(entryPaths)
    guard missingEntries.isEmpty else {
        let entry = missingEntries.sorted().first ?? "unknown"
        throw ImportError.missingRequiredEntity(entry)
    }
    let unsupportedEntries = entryPaths.subtracting(supportedThreeMFPackageEntries)
    guard unsupportedEntries.isEmpty else {
        let entry = unsupportedEntries.sorted().first ?? "unknown"
        throw ImportError.invalidData("Unsupported 3MF package entry \(entry).")
    }
}
