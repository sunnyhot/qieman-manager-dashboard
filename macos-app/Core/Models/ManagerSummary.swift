import Foundation

struct ManagerSummary: Identifiable, Hashable, Codable {
    let brokerUserId: String
    let userName: String
    let userLabel: String
    let userAvatarURL: String
    let groupId: Int
    let groupName: String

    var id: String { brokerUserId }
}
