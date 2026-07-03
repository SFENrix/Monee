import Foundation
 
struct MessageText: Identifiable, Equatable {
    enum Sender {
        case user
        case assistant
    }
 
    let id = UUID()
    let sender: Sender
    let text: String
    let timestamp: Date = .init()
}
 
