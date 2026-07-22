import Foundation

struct CompensatedSum: Sendable {
    private var sum: Double
    private var compensation: Double

    init(_ value: Double = 0.0) {
        sum = value
        compensation = 0.0
    }

    var value: Double {
        sum + compensation
    }

    mutating func add(_ value: Double) {
        let updated = sum + value
        if abs(sum) >= abs(value) {
            compensation += (sum - updated) + value
        } else {
            compensation += (value - updated) + sum
        }
        sum = updated
    }
}
