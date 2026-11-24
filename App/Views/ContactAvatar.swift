import ScheduledTextsCore
import SwiftUI

/// A contact's round picture, like Messages: their photo when they have
/// one, otherwise their initials in white on gray, or a person symbol when
/// the name has no letters (a bare number).
///
/// Hidden from VoiceOver, since the name beside it is read anyway.
struct ContactAvatar: View {
    var name: String
    var image: UIImage?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            // The gray gradient Messages uses behind initials.
            LinearGradient(
                colors: [
                    Color(red: 0.66, green: 0.68, blue: 0.73),
                    Color(red: 0.52, green: 0.54, blue: 0.59),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            let initials = ContactInitials.of(name)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .offset(y: size * 0.06)
            } else {
                Text(initials)
                    .font(.system(size: size * (initials.count > 1 ? 0.4 : 0.45), weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.1)
            }
        }
        .foregroundStyle(.white)
    }
}
