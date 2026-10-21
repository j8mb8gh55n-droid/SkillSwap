//
//  SplashView.swift
//  SkillSwap
//
//  Branded splash shown during the real app-startup window (session restore)
//  so the native launch screen doesn't flash by. It visually MATCHES the native
//  LaunchScreen.storyboard (sage app-icon background + the two-arrow symbol +
//  "SkillSwap"), so there's no jump between the two. Fixed colors so it looks
//  identical in light and dark; no spinners, timers, or percentages here.
//

import SwiftUI

struct SplashView: View {

    // The app-icon background color (soft sage), matching the launch screen.
    private let sage = Color(red: 213/255, green: 233/255, blue: 224/255)
    private let charcoal = Color(red: 0.141, green: 0.141, blue: 0.141)

    var body: some View {
        ZStack {
            sage.ignoresSafeArea()
            // Dimensions/position MATCH LaunchScreen.storyboard exactly (symbol
            // 100×83, title 34pt, spacing 22, centered) so the native launch
            // screen hands off to this view with no size jump or layout shift.
            VStack(spacing: 22) {
                Image("LaunchSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 83)   // explicit = no first-frame resize
                Text("SkillSwap")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(charcoal)
            }
        }
    }
}

#Preview {
    SplashView()
}
