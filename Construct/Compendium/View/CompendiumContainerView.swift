//
//  CompendiumContainerView.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 02/09/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import SwiftUI
import ComposableArchitecture

struct CompendiumContainerView: View {
    @EnvironmentObject var environment: Environment
    var store: Store<AppState, AppState.Action>

    var body: some View {
        NavigationView {
            CompendiumIndexView(store: store.scope(state: { $0.compendium }, action: { .compendium($0) }))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .edgesIgnoringSafeArea(.top)
    }
}

let compendiumContainerReducer: Reducer<CompendiumIndexState, CompendiumIndexAction, Environment> = Reducer.combine(
    Reducer { state, action, env in
        if let monster = action.onSaveMonsterAsNPCButtonMonster {
            return Effect.future { callback in
                var stats = monster.stats
                stats.name = "\(stats.name) NPC"
                let character = Character(id: UUID(), realm: .homebrew, level: nil, stats: stats, player: nil)

                do {
                    // save character
                    let entry = CompendiumEntry(character)
                    try env.compendium.put(entry)

                    // workaround: programmatic navigation doesn't work (FB8784916) so we instruct the user
                    // where to find the newly created NPC
                    callback(.success(.alert(AlertState<CompendiumIndexAction>(title: "Monster saved as NPC", message: "A character named “\(stats.name)” was added to the compendium.", dismissButton: .default("OK")))))

//                    // navigate to detail view of character
//                    callback(.success(.setNextScreen(.compendiumIndex(CompendiumIndexState(
//                        title: "Characters",
//                        properties: .secondary,
//                        results: .initial(type: .character),
//                        presentedScreens: [.nextInStack: .itemDetail(CompendiumEntryDetailViewState(entry: entry))]
//                    )))))
                } catch { }
                callback(.success(nil))
            }.compactMap { $0 }.eraseToEffect()
        }
        return .none
    },
    CompendiumIndexState.reducer
)

extension CompendiumIndexAction {
    var onSaveMonsterAsNPCButtonMonster: Monster? {
        switch self {
        case .nextScreen(.compendiumEntry(CompendiumItemDetailViewAction.onSaveMonsterAsNPCButton(let m))):
            return m
        case .nextScreen(.compendiumIndex(let a)):
            return a.onSaveMonsterAsNPCButtonMonster
        default:
            return nil
        }
    }
}
