//
//  DetailRow.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI

struct DetailRow<Content: View>: View {
    let iconName: String
    let title: String
    let contentBody: Content
    
    init(iconName: String, title: String, @ViewBuilder content: () -> Content) {
        self.iconName = iconName
        self.title = title
        self.contentBody = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(Color.themePrimary)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.themeTextPrimary)
            }
            HStack {
                Spacer().frame(width: 24 + 10)
                contentBody
                    .padding(.top, 2)
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}

extension DetailRow where Content == Text {
    init(iconName: String, title: String, content: String, contentColor: Color = Color.themeTextSecondary) {
        self.iconName = iconName
        self.title = title
        self.contentBody = Text(content).font(.body).foregroundStyle(contentColor)
    }

    init(iconName: String, title: String, content: Date, style: Text.DateStyle, contentColor: Color = Color.themeTextSecondary) {
        self.iconName = iconName
        self.title = title
        self.contentBody = Text(content, style: style).font(.body).foregroundStyle(contentColor)
    }
}
