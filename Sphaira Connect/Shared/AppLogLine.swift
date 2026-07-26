import Foundation

struct AppLogLine: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
}
