//
//  ReferenceView.swift
//  Construct
//
//  Created by Thomas Visser on 24/10/2020.
//  Copyright © 2020 Thomas Visser. All rights reserved.
//

import Foundation
import SwiftUI
import ComposableArchitecture

struct ReferenceView: View {

    let store: Store<ReferenceViewState, ReferenceViewAction>

    var body: some View {
        WithViewStore(store, removeDuplicates: { $0.normalizedForDeduplication == $1.normalizedForDeduplication }) { viewStore in
            TabbedDocumentView<ReferenceItemView>(
                items: tabItems(viewStore),
                selection: viewStore.binding(get: { $0.selectedItemId }, send: { .selectItem($0) }),
                _onDelete: {
                    viewStore.send(.removeTab($0))
                }
            )
            .environment(\.appNavigation, .tab)
            .toolbar {
                ToolbarItem(placement: ToolbarItemPlacement.primaryAction) {
                    Button(action: {
                        withAnimation {
                            viewStore.send(.onNewTabTapped)
                        }
                    }) {
                        Label("New Tab", systemImage: "plus")
                    }
                }
            }
            .navigationBarTitle(viewStore.state.navigationTitle, displayMode: .inline)
        }
    }

    func tabItems(_ viewStore: ViewStore<ReferenceViewState, ReferenceViewAction>) -> [TabbedDocumentView<ReferenceItemView>.ContentItem] {
        viewStore.items.map { item in
            TabbedDocumentView<ReferenceItemView>.ContentItem(
                id: item.id,
                label: Label(item.title, systemImage: "doc"),
                view: {
                    return ReferenceItemView(store: store.scope(state: { $0.items[id: item.id]?.state ?? .nullInstance }, action: { .item(item.id, $0) }))
                }
            )
        }
    }
}
