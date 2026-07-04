

import SwiftUI

struct PufferfishMascot: View {
    /// Diameter of the mascot. Defaults to match the chat screen's hero size.
    var size: CGFloat = 180

    var body: some View {
        ZStack {
            // Soft "puddle" shadow under the mascot
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 1.5, height: size * 0.22)
                .offset(y: size * 0.52)
                .blur(radius: 2)

            // Body
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "F8DFA0"), Color(hex: "F3B9C0")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Spikes — simple placeholder ring of small triangles
                    SpikeRing(count: 20)
                        .stroke(Color(hex: "F3B9C0"), lineWidth: 2)
                )
                .frame(width: size, height: size)

            // Face
            VStack(spacing: size * 0.06) {
                HStack(spacing: size * 0.16) {
                    Capsule().fill(Color.black).frame(width: size * 0.09, height: size * 0.035)
                    Capsule().fill(Color.black).frame(width: size * 0.09, height: size * 0.035)
                }
                Capsule()
                    .fill(Color(hex: "6B3F73"))
                    .frame(width: size * 0.32, height: size * 0.11)
            }
            .offset(y: -size * 0.02)

            // Cheeks
            HStack {
                Circle().fill(Color.pink.opacity(0.35)).frame(width: size * 0.11)
                Spacer()
                Circle().fill(Color.pink.opacity(0.35)).frame(width: size * 0.11)
            }
            .frame(width: size * 0.86)
        }
        .accessibilityLabel("Buntel mascot")
        .accessibilityHidden(false)
    }
}

/// Tiny decorative ring used to hint at pufferfish spikes without needing real art yet.
private struct SpikeRing: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        let spikeLength: CGFloat = radius * 0.08

        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
            let start = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            let end = CGPoint(
                x: center.x + (radius + spikeLength) * cos(angle),
                y: center.y + (radius + spikeLength) * sin(angle)
            )
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }
}

extension Color {
    /// Convenience hex initializer for placeholder palette colors.
    /// Internal (not private) so it can be shared across AIBuddy files —
    /// if the app already has a hex initializer elsewhere, delete this one.
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

#Preview {
    PufferfishMascot()
}
