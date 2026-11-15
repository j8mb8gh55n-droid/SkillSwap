import SwiftUI

struct DiscoveryStudentAvatar: View {
    let student: DiscoveredStudent

    var body: some View {
        AsyncImage(url: student.avatarURL.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                AvatarBadge(initials: student.initials, size: 42)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
