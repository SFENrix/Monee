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
    
    private var bubbleColor: Color {
        message.sender == .user
            ? Color(red: 0.97, green: 0.87, blue: 0.72)   // peach/tan
            : Color(red: 0.85, green: 0.92, blue: 0.85)   // mint green
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
                    .fill(bubbleColor)
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
            Image("buntel")
                .renderingMode(.original)
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
    VStack(spacing: 0) {
        ChatBubble(message: MessageText(
            sender: .assistant,
            text: "Hey! I noticed you've spent a bit more on food this month — want me to break it down by week?"
        ))

        ChatBubble(message: MessageText(
            sender: .user,
            text: "Yeah, show me the weekly breakdown please"
        ))

        ChatBubble(message: MessageText(
            sender: .assistant,
            text: "Sure thing 👍"
        ))
    }
    .padding(.vertical, 12)
    .background(Color(.systemGroupedBackground))
}
