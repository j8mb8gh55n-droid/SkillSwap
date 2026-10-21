//
//  OnboardingView.swift
//  SkillSwap
//
//  Created by mac on 07/05/1448 AH.
//

import SwiftUI

struct OnboardingView: View {

    // MARK: - State

    @State private var currentPage = 0
    @State private var showSignUp = false
    @State private var showLogin = false

    private let cream = Color(red: 0.98, green: 0.97, blue: 0.95)

    var body: some View {

        ZStack {

            AtmosphericBackground()

            VStack(spacing: 0) {

                // MARK: - Top Navigation

                HStack {

                    Text("SKILLSWAP")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(3)

                    Spacer()

                    if currentPage < 2 {

                        Button("Skip") {
                            withAnimation(.smooth) {
                                currentPage = 2
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                // MARK: - Animated Onboarding Pages

                TabView(selection: $currentPage) {

                    WelcomePage()
                        .tag(0)

                    SkillExchangePage()
                        .tag(1)

                    FindPeoplePage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // MARK: - Page Indicators

                HStack(spacing: 8) {

                    ForEach(0..<3, id: \.self) { index in

                        Capsule()
                            .fill(
                                currentPage == index
                                ? Theme.charcoal
                                : Theme.charcoal.opacity(0.2)
                            )
                            .frame(
                                width: currentPage == index ? 28 : 8,
                                height: 8
                            )
                    }
                }
                .animation(.smooth, value: currentPage)
                .padding(.bottom, 28)

                // MARK: - Continue / Get Started Button

                Button {

                    if currentPage < 2 {

                        withAnimation(.smooth) {
                            currentPage += 1
                        }

                    } else {

                        // Open Sign Up
                        showSignUp = true
                    }

                } label: {

                    HStack {

                        Text(
                            currentPage == 2
                            ? "Get Started"
                            : "Continue"
                        )

                        Spacer()

                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(Theme.primaryAction)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 22)
                    )
                }
                .padding(.horizontal, 28)

                // MARK: - Login Button

                HStack(spacing: 4) {

                    Text("Already have an account?")
                        .foregroundStyle(Theme.mutedStone)

                    Button("Log In") {
                        showLogin = true
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.charcoal)
                }
                .font(.system(size: 14))
                .padding(.top, 18)
                .padding(.bottom, 22)
            }
        }

        // MARK: - Present Sign Up Screen

        .fullScreenCover(isPresented: $showSignUp) {

            NavigationStack {
                SignUpView()
            }
        }
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginView()
            }
        }
    }
}

// MARK: - Page 1: Welcome

struct WelcomePage: View {

    @State private var animate = false

    var body: some View {

        GeometryReader { geometry in

            VStack(spacing: 24) {

                Spacer()

                ZStack {

                    Text("Skill\nSwap")
                        .font(
                            .system(
                                size: 58,
                                weight: .black,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(Theme.charcoal)
                        .multilineTextAlignment(.center)
                        .tracking(-3)

                    FloatingSkill(
                        symbol: "camera.fill",
                        color: .pink,
                        x: -115,
                        y: -105,
                        animate: animate
                    )

                    FloatingSkill(
                        symbol: "laptopcomputer",
                        color: .blue,
                        x: 115,
                        y: -70,
                        animate: animate
                    )

                    FloatingSkill(
                        symbol: "paintbrush.pointed.fill",
                        color: .orange,
                        x: -105,
                        y: 110,
                        animate: animate
                    )

                    FloatingSkill(
                        symbol: "book.closed.fill",
                        color: .green,
                        x: 110,
                        y: 105,
                        animate: animate
                    )
                }
                .frame(height: geometry.size.height * 0.55)

                Spacer()

                VStack(spacing: 12) {

                    Text("Good things are\nbetter shared.")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundStyle(Theme.charcoal)
                        .multilineTextAlignment(.center)
                        .tracking(-1)

                    Text("Your skills. Their skills.\nEndless possibilities.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.mutedStone)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Floating Skill Component

struct FloatingSkill: View {

    let symbol: String
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let animate: Bool

    var body: some View {

        Image(systemName: symbol)
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 72, height: 72)
            .background(color.opacity(0.15))
            .clipShape(
                RoundedRectangle(cornerRadius: 22)
            )
            .rotationEffect(
                .degrees(animate ? 8 : -8)
            )
            .offset(
                x: x,
                y: y + (animate ? -9 : 9)
            )
            .animation(
                .easeInOut(duration: 2.4)
                    .repeatForever(autoreverses: true),
                value: animate
            )
    }
}

// MARK: - Page 2: Skill Exchange

struct SkillExchangePage: View {

    @State private var swapped = false

    var body: some View {

        GeometryReader { geometry in

            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Headline

                VStack(alignment: .leading, spacing: 4) {

                    Text("YOU KNOW")
                        .font(.system(size: 40, weight: .black))

                    Text("something")
                        .font(
                            .system(
                                size: 40,
                                design: .serif
                            )
                        )
                        .italic()

                    Text("THEY DON'T.")
                        .font(.system(size: 40, weight: .black))
                }
                .padding(.top, 30)

                Spacer(minLength: 16)

                // MARK: - Animated Skill Cards

                ZStack {

                    SkillSwapCard(
                        title: "I CAN TEACH",
                        skill: "Swift Coding",
                        symbol: "chevron.left.forwardslash.chevron.right",
                        color: Color(
                            red: 0.86,
                            green: 0.82,
                            blue: 1
                        )
                    )
                    .offset(
                        x: swapped ? 35 : -35,
                        y: swapped ? 55 : -55
                    )
                    .rotationEffect(
                        .degrees(swapped ? 8 : -8)
                    )

                    SkillSwapCard(
                        title: "I WANT TO LEARN",
                        skill: "Photography",
                        symbol: "camera.fill",
                        color: Color(
                            red: 0.85,
                            green: 0.92,
                            blue: 0.72
                        )
                    )
                    .offset(
                        x: swapped ? -35 : 35,
                        y: swapped ? -55 : 55
                    )
                    .rotationEffect(
                        .degrees(swapped ? -8 : 8)
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 310)

                Spacer(minLength: 16)

                // MARK: - Description

                Text("Trade what you know.\nDiscover what you love.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 30)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .onAppear {

            withAnimation(
                .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
            ) {
                swapped = true
            }
        }
    }
}

// MARK: - Skill Swap Card

struct SkillSwapCard: View {

    let title: String
    let skill: String
    let symbol: String
    let color: Color

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            Image(systemName: symbol)
                .font(.system(size: 28))

            Spacer()

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)

            Text(skill)
                .font(.system(size: 22, weight: .bold))
        }
        .padding(22)
        .frame(
            width: 225,
            height: 190,
            alignment: .leading
        )
        .background(color)
        .clipShape(
            RoundedRectangle(cornerRadius: 26)
        )
        .shadow(
            color: .black.opacity(0.08),
            radius: 16,
            y: 8
        )
    }
}

// MARK: - Page 3: Find Your People

struct FindPeoplePage: View {

    @State private var appeared = false

    var body: some View {

        VStack(spacing: 24) {

            Spacer()

            Text("Find your\nkind of curious.")
                .font(.system(size: 43, weight: .black))
                .multilineTextAlignment(.center)
                .tracking(-2)

            Spacer()

            ZStack {

                PersonSkillCard(
                    name: "Sara",
                    skill: "Swift Coding",
                    color: Color(
                        red: 0.86,
                        green: 0.82,
                        blue: 1
                    )
                )
                .offset(x: -65, y: -95)
                .rotationEffect(.degrees(-12))

                PersonSkillCard(
                    name: "Lina",
                    skill: "Photography",
                    color: Color(
                        red: 1,
                        green: 0.85,
                        blue: 0.79
                    )
                )
                .offset(x: 75, y: 15)
                .rotationEffect(.degrees(10))

                PersonSkillCard(
                    name: "Noor",
                    skill: "Graphic Design",
                    color: Color(
                        red: 0.85,
                        green: 0.92,
                        blue: 0.72
                    )
                )
                .offset(x: -50, y: 125)
                .rotationEffect(.degrees(-5))
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .frame(height: 340)

            Spacer()

            Text("Connect with students who love\nlearning as much as you do.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .onAppear {

            withAnimation(.spring(duration: 0.9)) {
                appeared = true
            }
        }
    }
}

// MARK: - Person Skill Card

struct PersonSkillCard: View {

    let name: String
    let skill: String
    let color: Color

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))

            Spacer()

            Text(name)
                .font(.system(size: 23, weight: .bold))

            Text(skill)
                .font(.system(size: 13))
        }
        .padding(20)
        .frame(
            width: 185,
            height: 155,
            alignment: .leading
        )
        .background(color)
        .clipShape(
            RoundedRectangle(cornerRadius: 24)
        )
        .shadow(
            color: .black.opacity(0.08),
            radius: 12,
            y: 6
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AuthManager())
}
