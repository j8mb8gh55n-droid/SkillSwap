//
//      SkillCategoryCard.swift
//  SkillSwap
//
//  Created by mac on 07/05/1448 AH.
//

import SwiftUI

struct SkillCategoryCard: View {

    let title: String
    let colors: [Color]

    var body: some View {

        ZStack(alignment: .bottomLeading) {

            // MARK: - Background
            Color(red: 0.55, green: 0.52, blue: 0.75)

            // MARK: - First Gradient Blob
            Circle()
                .fill(colors[0])
                .frame(width: 120, height: 120)
                .blur(radius: 35)
                .opacity(0.45)
                .offset(x: 65, y: -35)

            // MARK: - Second Gradient Blob
            Circle()
                .fill(colors[1])
                .frame(width: 100, height: 100)
                .blur(radius: 35)
                .opacity(0.35)
                .offset(x: -20, y: 50)

            // MARK: - Category Title
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    SkillCategoryCard(
        title: "Technology",
        colors: [.purple, .blue]
    )
}
