import Foundation
import CADCore
import CADIR
import CADUSD

#if CAD_ENABLE_USDC_READER
import CADUSDC
#endif

#if CAD_ENABLE_USDZ_READER
import CADUSDZ
#endif

public enum USDImportBackend: Sendable, Equatable {
    case automatic
    case systemUSD
    case pureSwift
}

public struct USDExchange: Sendable {
    private let textReader: USDAReader
    private let importBackend: USDImportBackend
    private let systemImportToolchain: any USDImportToolchain

    public init(
        textReader: USDAReader = USDAReader(),
        importBackend: USDImportBackend = .automatic,
        systemImportToolchain: any USDImportToolchain = SystemUSDConversionToolchain()
    ) {
        self.textReader = textReader
        self.importBackend = importBackend
        self.systemImportToolchain = systemImportToolchain
    }

    public func `import`(_ source: any ByteSource, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        try source.withNoCopyData { data in
            do {
                let scene = try readScene(data, as: format)
                return try importedModel(from: scene, format: format)
            } catch let error as ImportError {
                throw error
            } catch let error as USDImportError {
                throw mapUSDImportError(error)
            } catch {
                throw ImportError.invalidData(error.localizedDescription)
            }
        }
    }

    private func readScene(_ data: Data, as format: ExchangeFileFormat) throws -> USDScene {
        guard format == .usd || format == .usda || format == .usdc || format == .usdz else {
            throw ImportError.unsupportedFormat(format.displayName)
        }
        if shouldUseSystemImport {
            return try readWithSystemUSD(data, fileExtension: format.rawValue)
        }
        switch format {
        case .usd:
            if data.starts(with: USDCSignature.bytes) {
                return try readPureUSDC(data)
            }
            return try textReader.read(from: data)
        case .usda:
            return try textReader.read(from: data)
        case .usdc:
            return try readPureUSDC(data)
        case .usdz:
            return try readPureUSDZ(data)
        default:
            throw ImportError.unsupportedFormat(format.displayName)
        }
    }

    private var shouldUseSystemImport: Bool {
        switch importBackend {
        case .automatic:
            #if os(macOS)
            true
            #else
            false
            #endif
        case .systemUSD:
            true
        case .pureSwift:
            false
        }
    }

    private func readWithSystemUSD(_ data: Data, fileExtension: String) throws -> USDScene {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SwiftCAD-usd-import-\(UUID().uuidString)",
            isDirectory: true
        )
        let inputURL = directoryURL.appendingPathComponent("scene").appendingPathExtension(fileExtension)
        var importedScene: USDScene?
        var primaryError: Error?

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: inputURL)
            let sink = DataByteSink()
            try systemImportToolchain.writeUSDA(fromUSD: inputURL, to: sink)
            importedScene = try textReader.read(from: sink.bytes)
        } catch {
            primaryError = error
        }

        if fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.removeItem(at: directoryURL)
            } catch {
                if primaryError == nil {
                    primaryError = ImportError.fileReadFailure(
                        "Failed to remove temporary USD import directory: \(error.localizedDescription)"
                    )
                }
            }
        }

        if let importedScene {
            return importedScene
        }
        if let primaryError {
            throw primaryError
        }
        throw ImportError.invalidData("System USD import produced no scene.")
    }

    private func readPureUSDC(_ data: Data) throws -> USDScene {
        #if CAD_ENABLE_USDC_READER
        return try USDCReader().read(from: data)
        #else
        throw ImportError.unsupportedFormat(ExchangeFileFormat.usdc.displayName)
        #endif
    }

    private func readPureUSDZ(_ data: Data) throws -> USDScene {
        #if CAD_ENABLE_USDZ_READER
        return try USDZReader().read(from: data)
        #else
        throw ImportError.unsupportedFormat(ExchangeFileFormat.usdz.displayName)
        #endif
    }

    private func importedModel(from scene: USDScene, format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        let unit = try lengthUnit(forMetersPerUnit: scene.metersPerUnit)
        var meshes: [BodyID: Mesh] = [:]
        for usdMesh in scene.meshes {
            let mesh = try mesh(from: usdMesh, metersPerUnit: scene.metersPerUnit, upAxis: scene.upAxis)
            try validateImportedMesh(mesh, formatName: format.displayName)
            meshes[BodyID()] = mesh
        }
        guard !meshes.isEmpty else {
            throw ImportError.invalidData("USD scene contains no importable meshes.")
        }
        return ImportedExchangeModel(format: format, meshes: meshes, units: UnitSystem(length: unit, angle: .radian))
    }

    private func mesh(from usdMesh: USDMesh, metersPerUnit: Double, upAxis: USDUpAxis) throws -> Mesh {
        guard !usdMesh.points.isEmpty else {
            throw ImportError.invalidData("USD Mesh contains no points.")
        }
        let expectedIndexCount = try expectedFaceVertexIndexCount(usdMesh.faceVertexCounts)
        guard expectedIndexCount == usdMesh.faceVertexIndices.count else {
            throw ImportError.invalidData("USD Mesh faceVertexIndices count does not match faceVertexCounts.")
        }
        let positions = try usdMesh.points.map { point in
            let convertedPoint = convertToZUp(point, from: upAxis)
            let x = convertedPoint.x * metersPerUnit
            let y = convertedPoint.y * metersPerUnit
            let z = convertedPoint.z * metersPerUnit
            guard x.isFinite, y.isFinite, z.isFinite else {
                throw ImportError.invalidData("USD Mesh point contains a non-finite internal coordinate.")
            }
            return Point3D(x: x, y: y, z: z)
        }
        let indices = try triangulatedFaceVertexIndices(
            counts: usdMesh.faceVertexCounts,
            indices: usdMesh.faceVertexIndices,
            positionCount: positions.count,
            orientation: usdMesh.orientation ?? .rightHanded
        )
        let normals = try normals(from: usdMesh, positionCount: positions.count, upAxis: upAxis)
        return Mesh(positions: positions, normals: normals, indices: indices)
    }

    private func normals(from usdMesh: USDMesh, positionCount: Int, upAxis: USDUpAxis) throws -> [Vector3D] {
        guard !usdMesh.normals.isEmpty else {
            return []
        }
        let interpolation = usdMesh.normalsInterpolation ?? "vertex"
        guard interpolation == "vertex" else {
            throw ImportError.invalidData(
                "Unsupported USD feature: Only vertex-interpolated USD Mesh normals are supported."
            )
        }
        guard usdMesh.normals.count == positionCount else {
            throw ImportError.invalidData("USD Mesh vertex normal count does not match point count.")
        }
        return try usdMesh.normals.enumerated().map { index, normal in
            let convertedNormal = convertToZUp(normal, from: upAxis)
            let vector = Vector3D(x: convertedNormal.x, y: convertedNormal.y, z: convertedNormal.z)
            do {
                return try vector.normalized(tolerance: ModelingTolerance.standard.distance)
            } catch {
                throw ImportError.invalidData("USD Mesh normal \(index) is not a finite non-zero vector.")
            }
        }
    }

    private func convertToZUp(_ point: USDPoint3D, from upAxis: USDUpAxis) -> USDPoint3D {
        switch upAxis {
        case .x:
            return USDPoint3D(x: point.y, y: point.z, z: point.x)
        case .y:
            return USDPoint3D(x: point.x, y: -point.z, z: point.y)
        case .z:
            return point
        }
    }

    private func expectedFaceVertexIndexCount(_ counts: [Int]) throws -> Int {
        guard !counts.isEmpty else {
            throw ImportError.invalidData("USD Mesh contains no faces.")
        }
        var total = 0
        for count in counts {
            guard count >= 3 else {
                throw ImportError.invalidData("USD Mesh faces must contain at least three vertices.")
            }
            guard total <= Int.max - count else {
                throw ImportError.invalidData("USD Mesh faceVertexCounts exceed platform range.")
            }
            total += count
        }
        return total
    }

    private func triangulatedFaceVertexIndices(
        counts: [Int],
        indices: [Int],
        positionCount: Int,
        orientation: USDOrientation
    ) throws -> [UInt32] {
        var output: [UInt32] = []
        let triangleCount = counts.reduce(0) { $0 + max($1 - 2, 0) }
        output.reserveCapacity(triangleCount * 3)
        var cursor = 0
        for count in counts {
            let first = try meshIndex(indices[cursor], positionCount: positionCount)
            for offset in 1..<(count - 1) {
                let current = try meshIndex(indices[cursor + offset], positionCount: positionCount)
                let next = try meshIndex(indices[cursor + offset + 1], positionCount: positionCount)
                output.append(first)
                switch orientation {
                case .rightHanded:
                    output.append(current)
                    output.append(next)
                case .leftHanded:
                    output.append(next)
                    output.append(current)
                }
            }
            cursor += count
        }
        return output
    }

    private func meshIndex(_ index: Int, positionCount: Int) throws -> UInt32 {
        guard index >= 0, index < positionCount else {
            throw ImportError.invalidData("USD Mesh face index is out of range.")
        }
        guard let value = UInt32(exactly: index) else {
            throw ImportError.invalidData("USD Mesh face index does not fit UInt32.")
        }
        return value
    }

    private func lengthUnit(forMetersPerUnit metersPerUnit: Double) throws -> LengthUnit {
        guard metersPerUnit.isFinite, metersPerUnit > 0 else {
            throw ImportError.invalidData("USD metersPerUnit must be a positive finite value.")
        }
        let tolerance = max(1.0e-12, metersPerUnit * 1.0e-9)
        guard let unit = LengthUnit.allCases.first(where: { abs($0.metersPerUnit - metersPerUnit) <= tolerance }) else {
            throw ImportError.invalidData("USD metersPerUnit does not map to a supported length unit.")
        }
        return unit
    }

    private func mapUSDImportError(_ error: USDImportError) -> ImportError {
        switch error {
        case let .invalidData(message):
            return .invalidData(message)
        case let .missingRequiredField(field):
            return .missingRequiredEntity(field)
        case let .unsupportedFeature(message):
            return .invalidData("Unsupported USD feature: \(message)")
        case let .notImplemented(message):
            return .invalidData(message)
        }
    }
}

private enum USDCSignature {
    static let bytes = Data("PXR-USDC".utf8)
}
