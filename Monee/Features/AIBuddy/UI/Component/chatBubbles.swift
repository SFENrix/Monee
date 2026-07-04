import SwiftUI

struct ChatBubble: View {
    let message: MessageText
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            
            if message.sender == .assistant {
                
                AppIconAvatar()
                    .offset(y: -8)
                
                messageBody
                
                Spacer(minLength: 50)
                
            } else {
                
                Spacer(minLength: 50)
                
                messageBody
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    private var messageBody: some View {
        Text(message.text)
            .font(.system(size: 17))
            .foregroundColor(.primary)
            .lineSpacing(5)
            .multilineTextAlignment(message.sender == .user ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white)
                    .overlay {
                        if message.sender == .assistant {
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                        }
                    }
                    .shadow(
                        color: .black.opacity(0.05),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
            .frame(
                //maxWidth: UIScreen.main.bounds.width * 0.75,
                alignment: message.sender == .user ? .trailing : .leading
            )
    }
    
    struct AppIconAvatar: View {
        var body: some View {
            Image("Monee")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(
                    color: .black.opacity(0.12),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
    }
}
#Preview {
    ZStack {
        Color(red: 0.94, green: 0.97, blue: 1.0)
            .ignoresSafeArea()

        VStack(spacing: 20) {

            ChatBubble(
                message: MessageText(
                    sender: .assistant,
                    text: "Hi Gwen! Want to treat yourself without the guilt?"
                )
            )

            ChatBubble(
                message: MessageText(
                    sender: .user,
                    text: "Can I afford a new pair of shoes this month?"
                )
            )

            ChatBubble(
                message: MessageText(
                    sender: .assistant,
                    text: "Based on your current finances, I'd recommend waiting until your next paycheck. This will keep your emergency fund healthy and avoid unnecessary pressure on your monthly budget."
                )
            )

            ChatBubble(
                message: MessageText(
                    sender: .user,
                    text: "Thanks! I'll wait."
                )
            )
        }
        .padding(.vertical)
    }
}
