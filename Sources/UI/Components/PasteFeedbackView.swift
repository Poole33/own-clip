import SwiftUI

struct PasteFeedbackView: View {
    let message: AppMessage

    var body: some View {
        Text(message.text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
    }
}
