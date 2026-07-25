import Foundation

nonisolated enum ByteFormat {
    private static let dash = "–"
    private static let units = ["B", "kB", "MB", "GB", "TB", "PB"]

    static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return dash }
        return scaled(Double(bytes))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return dash }
        return scaled(bytesPerSecond) + "/s"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return dash }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func scaled(_ value: Double) -> String {
        var value = value
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) B"
        }
        // Deutsches Zahlenformat mit genau einer Nachkommastelle, ohne NumberFormatter
        // (der ist nicht threadsicher und die Aufrufer sind nonisolated).
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10),\(tenths % 10) \(units[unitIndex])"
    }
}
