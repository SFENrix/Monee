//
//  OnboardingSetupView.swift
//  Monee
//
//  Second onboarding step, shown after the welcome screen's "Get Started" tap.
//  Collects a display name and a rough financial status so later screens (e.g.
//  Profile's Overview averages) have something to anchor to before any real
//  transactions exist. Same visual language as OnboardingView: Buntel sitting
//  over a soft gradient strip, with a white sheet curving up underneath him.
//

import SwiftUI

struct OnboardingSetupView: View {
    /// Called once the *entire* onboarding flow (this step + the financial-info
    /// step after it) is done, with everything the user entered across both.
    var onFinish: (
        _ name: String,
        _ status: OnboardingStatus?,
        _ totalMoney: Double?,
        _ monthlyIncome: Double?,
        _ monthlyExpense: Double?
    ) -> Void = { _, _, _, _, _ in }

    @State private var name: String = ""
    @State private var status: OnboardingStatus?
    @State private var isStatusExpanded = false
    @State private var showingFinancialSetup = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            backgroundGradient
                .frame(height: 260)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer().frame(height: 250) // clears room for the mascot overlapping the sheet

                sheetContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color.white)
                    .clipShape(ArchCurveShape())
            }
            .ignoresSafeArea(edges: .bottom)

            Image("buntel")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .padding(.top, 70)
        }
        .dismissKeyboardOnTap()
        .fullScreenCover(isPresented: $showingFinancialSetup) {
            OnboardingFinancialSetupView { totalMoney, monthlyIncome, monthlyExpense in
                onFinish(name, status, totalMoney, monthlyIncome, monthlyExpense)
            }
        }
    }

    // MARK: - Sheet content

    private var sheetContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Hi I am Buntel!")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Help me get to know you better")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 5) {
                fieldCard(label: "Name") {
                    TextField("Input name", text: $name)
                        .font(.system(size: 16))
                        .focused($nameFieldFocused)
                }
                
                Text("GANTI DISINI YAAAA")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity,minHeight: 1, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom,10 )
                    .foregroundStyle(.secondary)

//                Button {
//                    withAnimation(.easeInOut(duration: 0.2)) {
//                        isStatusExpanded.toggle()
//                    }
//                } label: {
//                    fieldCard(
//                        label: "Status",
//                        trailingSystemImage: isStatusExpanded ? "chevron.up" : "chevron.down"
//                    ) {
//                        Text(status?.rawValue ?? "Select status")
//                            .font(.system(size: 16))
//                            .foregroundStyle(status == nil ? .secondary : .primary)
//                    }
//                }
//                .buttonStyle(.plain)
//
//                if isStatusExpanded {
//                    VStack(spacing: 0) {
//                        ForEach(OnboardingStatus.allCases) { option in
//                            Button {
//                                status = option
//                                withAnimation(.easeInOut(duration: 0.2)) {
//                                    isStatusExpanded = false
//                                }
//                            } label: {
//                                Text(option.rawValue)
//                                    .font(.system(size: 16))
//                                    .foregroundStyle(.primary)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//                                    .padding(.horizontal, 18)
//                                    .padding(.vertical, 14)
//                            }
//                            .buttonStyle(.plain)
//
//                            if option != OnboardingStatus.allCases.last {
//                                Divider().padding(.leading, 18)
//                            }
//                        }
//                    }
//                    .background(
//                        RoundedRectangle(cornerRadius: 20, style: .continuous)
//                            .fill(Color(.systemGray6).opacity(0.6))
//                    )
//                    .transition(.opacity.combined(with: .move(edge: .top)))
//                }
            }
            

            Spacer(minLength: 0)
            

            Button {
                showingFinancialSetup = true
            } label: {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.38, green: 0.78, blue: 0.80),
                                        Color(red: 0.30, green: 0.68, blue: 0.72)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }

    private func fieldCard<Content: View>(
        label: String,
        trailingSystemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                content()
            }

            if let trailingSystemImage {
                Spacer()
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.6))
        )
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)

            Circle()
                .fill(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.55))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 120, y: -60)

            Circle()
                .fill(Color(red: 0.55, green: 0.80, blue: 0.70).opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -130, y: 40)
        }
    }
}

/// Symmetric "arch" — low at both edges, rising toward the center — so the
/// white sheet appears to hug the mascot's silhouette rather than cutting
/// across it with a flat or diagonal edge.
struct ArchCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edgeY: CGFloat = 60

        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: edgeY),
            control: CGPoint(x: rect.midX, y: -10)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    OnboardingSetupView()
}
