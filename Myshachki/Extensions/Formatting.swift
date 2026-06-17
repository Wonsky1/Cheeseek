import Foundation

extension Double {
    var formattedDistance: String {
        if self >= 1000 {
            String(format: "%.1f km", self / 1000)
        } else {
            "\(Int(self)) m"
        }
    }
}

extension TimeInterval {
    var formattedClock: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedPace: String {
        guard isFinite, self > 0 else { return "Not enough data" }
        let totalSeconds = Int(self.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d / km", minutes, seconds)
    }
}
