//
//  SectionContainer.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 22/10/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import SwiftUI

func SectionContainer<Content>(title: String, backgroundColor: Color = Color(UIColor.secondarySystemBackground), @ViewBuilder content: () -> Content) -> some View where Content: View {
    SectionContainer(title: title, accessory: EmptyView(), backgroundColor: backgroundColor, content: content)
}

func SectionContainer<Accessory, Content>(title: String, accessory: Accessory, backgroundColor: Color = Color(UIColor.secondarySystemBackground), @ViewBuilder content: () -> Content) -> some View where Accessory: View, Content: View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(title).font(.headline)
            Spacer()
            accessory
        }
        SectionContainerContent(backgroundColor, content)
    }
}

func SectionContainer<Content>(backgroundColor: Color = Color(UIColor.secondarySystemBackground), @ViewBuilder content: () -> Content) -> some View where Content: View {
    SectionContainerContent(backgroundColor, content)
}

fileprivate func SectionContainerContent<Content>(_ backgroundColor: Color = Color(UIColor.secondarySystemBackground), @ViewBuilder _ content: () -> Content) -> some View where Content: View {
    content()
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor.cornerRadius(8))
}
