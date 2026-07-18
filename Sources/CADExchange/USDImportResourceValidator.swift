import CADCore
import CADUSD
import OpenUSD

struct USDImportResourceValidator {
    private enum TextState {
        case normal
        case comment
        case assetPath
        case quoted(UInt8)
        case tripleQuoted(UInt8)
    }

    let limits: ExchangeResourceLimits

    func validateInput(
        _ bytes: USDByteSlice,
        isText: Bool,
        format: ExchangeFileFormat,
        budget: ExchangeProcessingBudget
    ) throws {
        try budget.check(format: format)
        guard bytes.byteCount <= limits.maximumBytes else {
            throw resourceError(
                "\(format.displayName) input exceeds the configured byte limit."
            )
        }
        guard bytes.byteCount <= limits.maximumIterations else {
            throw resourceError(
                "\(format.displayName) input exceeds the configured parsing iteration limit."
            )
        }
        if isText {
            try validateTextNesting(bytes, format: format, budget: budget)
        }
        try budget.check(format: format)
    }

    func validateOutput(
        _ result: ImportResult,
        format: ExchangeFileFormat,
        budget: ExchangeProcessingBudget
    ) throws {
        var entityCount = result.meshes.count
        var iterationCount = 0
        for mesh in result.meshes.values {
            try budget.check(format: format)
            try add(mesh.positions.count, to: &entityCount, label: "entity")
            try add(mesh.indices.count / 3, to: &entityCount, label: "entity")
            try add(mesh.positions.count, to: &iterationCount, label: "iteration")
            try add(mesh.normals.count, to: &iterationCount, label: "iteration")
            try add(mesh.indices.count, to: &iterationCount, label: "iteration")
            try add(mesh.textureCoordinates.count, to: &iterationCount, label: "iteration")
            try add(mesh.vertexColors.count, to: &iterationCount, label: "iteration")
            guard entityCount <= limits.maximumEntities else {
                throw resourceError(
                    "\(format.displayName) output exceeds the configured entity limit."
                )
            }
            guard iterationCount <= limits.maximumIterations else {
                throw resourceError(
                    "\(format.displayName) output exceeds the configured processing iteration limit."
                )
            }
        }
        try budget.check(format: format)
    }

    private func validateTextNesting(
        _ bytes: USDByteSlice,
        format: ExchangeFileFormat,
        budget: ExchangeProcessingBudget
    ) throws {
        try bytes.withUnsafeBytes { buffer in
            var state = TextState.normal
            var depth = 0
            var index = 0
            while index < buffer.count {
                if index.isMultiple(of: 4_096) {
                    try budget.check(format: format)
                }
                let byte = buffer[index]
                switch state {
                case .normal:
                    if byte == 35 {
                        state = .comment
                    } else if byte == 64 {
                        state = .assetPath
                    } else if byte == 34 || byte == 39 {
                        if index + 2 < buffer.count,
                           buffer[index + 1] == byte,
                           buffer[index + 2] == byte {
                            state = .tripleQuoted(byte)
                            index += 2
                        } else {
                            state = .quoted(byte)
                        }
                    } else if byte == 40 || byte == 91 || byte == 123 {
                        depth += 1
                        guard depth <= limits.maximumNesting else {
                            throw resourceError(
                                "\(format.displayName) input exceeds the configured nesting limit."
                            )
                        }
                    } else if byte == 41 || byte == 93 || byte == 125 {
                        depth = max(0, depth - 1)
                    }
                case .comment:
                    if byte == 10 || byte == 13 {
                        state = .normal
                    }
                case .assetPath:
                    if byte == 64 {
                        state = .normal
                    }
                case let .quoted(quote):
                    if byte == 92 {
                        index += 1
                    } else if byte == quote {
                        state = .normal
                    }
                case let .tripleQuoted(quote):
                    if byte == quote,
                       index + 2 < buffer.count,
                       buffer[index + 1] == quote,
                       buffer[index + 2] == quote {
                        state = .normal
                        index += 2
                    }
                }
                index += 1
            }
        }
    }

    private func add(
        _ value: Int,
        to total: inout Int,
        label: String
    ) throws {
        let addition = total.addingReportingOverflow(value)
        guard !addition.overflow else {
            throw resourceError("USD \(label) accounting exceeds the platform integer range.")
        }
        total = addition.partialValue
    }

    private func resourceError(_ message: String) -> KernelError {
        KernelError(
            phase: .exchange,
            code: .resourceLimitExceeded,
            tolerance: nil,
            message: message
        )
    }
}
