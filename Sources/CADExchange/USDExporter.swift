import Foundation
import CADCore
import CADIR
import OpenUSD
import OpenUSDC
import OpenUSDZ

public struct USDExporter: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func write(
        meshes: [BodyID: Mesh],
        encoding: USDEncoding,
        unit: LengthUnit = .meter,
        to sink: any ByteSink
    ) throws {
        do {
            let stage = try USDMeshStageBuilder().stage(
                meshes: meshes,
                unit: unit,
                tolerance: tolerance
            )
            let data: Data
            switch encoding {
            case .usd, .usda:
                data = try USDAAttributeSyntaxNormalizer().normalize(
                    stage.exportUSDAData()
                )
            case .usdc:
                data = try stage.exportUSDC()
            case .usdz:
                data = try stage.exportUSDZ(format: .usdc)
            }
            try sink.write(data)
        } catch let error as ExportError {
            throw error
        } catch let error as USDError {
            throw ExportError.invalidMesh("OpenUSD authoring failed: \(error)")
        } catch {
            throw ExportError.fileWriteFailure(error.localizedDescription)
        }
    }
}
