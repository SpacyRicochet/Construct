//
//  CampaignBrowseViewState.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 11/10/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import ComposableArchitecture

struct CampaignBrowseViewState: NavigationStackSourceState, Equatable {
    let node: CampaignNode
    var mode: Mode

    var items: Async<[CampaignNode], Error, Environment>

    let showSettingsButton: Bool

    var sheet: Sheet?

    var presentedScreens: [NavigationDestination: NextScreen]

    init(node: CampaignNode, mode: Mode, items: Async<[CampaignNode], Error, Environment> = .initial, showSettingsButton: Bool, sheet: Sheet? = nil, presentedScreens: [NavigationDestination: NextScreen] = [:]) {
        self.node = node
        self.mode = mode
        self.items = items
        self.showSettingsButton = showSettingsButton
        self.sheet = sheet
        self.presentedScreens = presentedScreens
    }

    var normalizedForDeduplication: CampaignBrowseViewState {
        var res = self
        res.presentedScreens = presentedScreens.mapValues {
            switch $0 {
            case .catalogBrowse: return .catalogBrowse(CampaignBrowseViewState.nullInstance)
            case .encounter: return .encounter(EncounterDetailViewState.nullInstance)
            }
        }
        return res
    }

    enum Mode: Equatable {
        case browse
        case move([CampaignNode])
    }

    enum Sheet: Equatable, Identifiable {
        case settings
        case nodeEdit(NodeEditState)
        indirect case move(CampaignBrowseViewState)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .nodeEdit(let s): return s.id.uuidString
            case .move: return "move"
            }
        }
    }

    struct NodeEditState: Equatable, Identifiable {
        var id = UUID()
        var name: String
        var contentType: CampaignNode.Contents.ContentType? // non-nil if new non-group node
        var node: CampaignNode? // nil if new node
    }

    enum NextScreen: NavigationStackItemStateConvertible, NavigationStackItemState, Equatable {
        indirect case catalogBrowse(CampaignBrowseViewState)
        case encounter(EncounterDetailViewState)

        var navigationStackItemState: NavigationStackItemState {
            switch self {
            case .catalogBrowse(let s): return s
            case .encounter(let s): return s
            }
        }
    }
}

extension CampaignBrowseViewState {
    var navigationBarTitle: String {
        if node.id == CampaignNode.root.id {
            return NSLocalizedString("Adventure", comment: "Title of the campaign browser")
        }
        return node.title
    }

    var sortedItems: [CampaignNode]? {
        if case .move = mode {
            return items.value?.filter { $0.contents == nil }.sorted { $0.title < $1.title }
        } else {
            return items.value?.sorted { $0.title < $1.title }
        }
    }
}

extension CampaignBrowseViewState: NavigationStackItemState {
    var navigationStackItemStateId: String {
        node.id.uuidString
    }

    var navigationTitle: String { navigationBarTitle }
}

enum CampaignBrowseViewAction: NavigationStackSourceAction, Equatable {

    case items(Async<[CampaignNode], Error, Environment>.Action)
    case didTapNodeEditDone(CampaignBrowseViewState.NodeEditState, CampaignNode?, String)
    case didTapConfirmMoveButton
    case remove(CampaignNode)
    case sheet(CampaignBrowseViewState.Sheet?)
    case performMove([CampaignNode], CampaignNode)
    indirect case moveSheet(CampaignBrowseViewAction)
    case setNextScreen(CampaignBrowseViewState.NextScreen?)
    indirect case nextScreen(NextScreenAction)
    case setDetailScreen(CampaignBrowseViewState.NextScreen?)
    indirect case detailScreen(NextScreenAction)

    // Key-path support
    var items: Async<[CampaignNode], Error, Environment>.Action? {
        get {
            guard case .items(let a) = self else { return nil }
            return a
        }
        set {
            guard case .items = self, let value = newValue else { return }
            self = .items(value)
        }
    }

    var nextCampaignBrowse: CampaignBrowseViewAction? {
        guard case .nextScreen(.campaignBrowse(let a)) = self else { return nil }
        return a
    }

    var nextEncounterDetail: EncounterDetailViewState.Action? {
        guard case .nextScreen(.encounterDetail(let a)) = self else { return nil }
        return a
    }

    var detailEncounterDetail: EncounterDetailViewState.Action? {
        guard case .detailScreen(.encounterDetail(let a)) = self else { return nil }
        return a
    }

    var moveSheet: CampaignBrowseViewAction? {
        guard case .moveSheet(let a) = self else { return nil }
        return a
    }

    static func presentScreen(_ destination: NavigationDestination, _ screen: CampaignBrowseViewState.NextScreen?) -> Self {
        switch destination {
        case .nextInStack: return .setNextScreen(screen)
        case .detail: return .setDetailScreen(screen)
        }
    }

    static func presentedScreen(_ destination: NavigationDestination, _ action: NextScreenAction) -> Self {
        switch destination {
        case .nextInStack: return .nextScreen(action)
        case .detail: return .detailScreen(action)
        }
    }

    enum NextScreenAction: Equatable {
        case campaignBrowse(CampaignBrowseViewAction)
        case encounterDetail(EncounterDetailViewState.Action)
    }
}

protocol CampaignBrowseViewNextScreenAction {

}

extension CampaignBrowseViewState {
    var nextCampaignBrowseView: CampaignBrowseViewState? {
        get { nextScreen?.navigationStackItemState as? CampaignBrowseViewState }
        set {
            if let newValue = newValue {
                nextScreen = .catalogBrowse(newValue)
            }
        }
    }

    var nextEncounterDetailView: EncounterDetailViewState? {
        get { nextScreen?.navigationStackItemState as? EncounterDetailViewState}
        set {
            if let newValue = newValue {
                nextScreen = .encounter(newValue)
            }
        }
    }

    var detailEncounterDetailView: EncounterDetailViewState? {
        get { detailScreen?.navigationStackItemState as? EncounterDetailViewState}
        set {
            if let newValue = newValue {
                detailScreen = .encounter(newValue)
            }
        }
    }

    var nodeEditState: NodeEditState? {
        get {
            guard case .nodeEdit(let s)? = sheet else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                sheet = .nodeEdit(newValue)
            }
        }
    }

    var moveSheetState: CampaignBrowseViewState? {
        get {
            guard case .move(let s)? = sheet else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                sheet = .move(newValue)
            }
        }
    }

    var isMoveMode: Bool {
        if case .move = mode {
            return true
        }
        return false
    }

    var isMoveOrigin: Bool {
        guard case .move(let nodes) = mode, let node = nodes.first else { return false }
        return node.parentKeyPrefix == self.node.keyPrefixForChildren
    }

    func isBeingMoved(_ node: CampaignNode) -> Bool {
        guard case .move(let nodes) = mode else { return false }
        return nodes.contains { $0.id == node.id }
    }

    var movingNodesDescription: String? {
        guard case .move(let nodes) = mode else { return nil }
        return ListFormatter().string(for: nodes.map { "“\($0.title)”" })
    }

    static var reducer: Reducer<CampaignBrowseViewState, CampaignBrowseViewAction, Environment> {
        return Reducer.combine(
            Reducer { state, action, env in
                let node = state.node
                switch action {
                case .didTapConfirmMoveButton:
                    let s = state

                    if case .move(let nodes) = s.mode {
                        return Effect(value: .performMove(nodes, s.node))
                    }
                case .performMove: // will bubble up below
                    break
                case .moveSheet(.performMove(let items, let destination)):
                    return Effect.fireAndForget {
                        // perform move
                        for item in items {
                            try? env.campaignBrowser.move(item, to: destination)
                        }
                    }.append([.sheet(nil), .items(.startLoading)]).eraseToEffect()
                case .moveSheet:
                    break
                case .sheet(let s):
                    state.sheet = s
                case .setNextScreen(let s):
                    state.presentedScreens[.nextInStack] = s
                case .setDetailScreen(let s):
                    state.presentedScreens[.detail] = s
                case .nextScreen(.campaignBrowse(.performMove(let items, let destination))):
                    // bubble-up
                    return Effect(value: .performMove(items, destination))
                case .nextScreen, .detailScreen:
                    break
                case .didTapNodeEditDone(_, var node?, let title):
                    // edit
                    return Effect.result {
                        // rename content
                        if node.contents?.type == .encounter, let key = node.contents?.key {
                            do {
                                if var encounter: Encounter = try env.campaignBrowser.store.get(key) {
                                    encounter.name = title
                                    try env.campaignBrowser.store.put(encounter)
                                }
                            } catch { assertionFailure("Could not rename encounter") }
                        }

                        node.title = title
                        try? env.campaignBrowser.put(node)
                        return .success(.items(.startLoading))
                    }
                case .didTapNodeEditDone(let state, nil, let title):
                    // new
                    return Effect.result {
                        var contents: CampaignNode.Contents? = nil
                        if state.contentType == .encounter {
                            let encounter = Encounter(name: title, combatants: [])
                            try? env.campaignBrowser.store.put(encounter)

                            contents = CampaignNode.Contents(key: encounter.key, type: .encounter)
                        }

                        try? env.campaignBrowser.put(CampaignNode(
                            id: UUID(),
                            title: title,
                            contents: contents,
                            special: nil,
                            parentKeyPrefix: node.keyPrefixForChildren
                        ))
                        return .success(.items(.startLoading))
                    }
                case .remove(let n):
                    return Effect.fireAndForget {
                        try? env.campaignBrowser.remove(n)
                    }.append(.items(.startLoading)).eraseToEffect()
                case .items: break // handled below
                }
                return .none
            },
            Reducer.withState({ $0.node.id != $1.node.id }) { state in
                Async<[CampaignNode], Error, Environment>.reducer { env in
                    do {
                        let nodes = try env.campaignBrowser.nodes(in: state.node)
                        return Just(nodes).promoteError().eraseToAnyPublisher()
                    } catch {
                        return Fail(error: error).eraseToAnyPublisher()
                    }
                }.pullback(state: \.items, action: /CampaignBrowseViewAction.items)
            },
            Reducer.lazy(CampaignBrowseViewState.reducer).optional().pullback(state: \.nextCampaignBrowseView, action: CasePath(embed: { CampaignBrowseViewAction.nextScreen(.campaignBrowse($0)) }, extract: { $0.nextCampaignBrowse })),
            EncounterDetailViewState.reducer.optional().pullback(state: \.nextEncounterDetailView, action: CasePath(embed: { CampaignBrowseViewAction.nextScreen(.encounterDetail($0)) }, extract: { $0.nextEncounterDetail })),
            EncounterDetailViewState.reducer.optional().pullback(state: \.detailEncounterDetailView, action: CasePath(embed: { CampaignBrowseViewAction.detailScreen(.encounterDetail($0)) }, extract: { $0.detailEncounterDetail })),
            Reducer.lazy(CampaignBrowseViewState.reducer).optional().pullback(state: \.moveSheetState as WritableKeyPath<CampaignBrowseViewState, CampaignBrowseViewState?>, action: CasePath(embed: { CampaignBrowseViewAction.moveSheet($0) }, extract: { $0.moveSheet }))
        )
    }
}

extension CampaignBrowseViewState {
    static let nullInstance = CampaignBrowseViewState(node: CampaignNode.root, mode: .browse, showSettingsButton: false)
}
