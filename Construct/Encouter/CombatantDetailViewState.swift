//
//  CombatantDetailViewState.swift
//  Construct
//
//  Created by Thomas Visser on 22/05/2020.
//  Copyright © 2020 Thomas Visser. All rights reserved.
//

import Foundation
import ComposableArchitecture
import SwiftUI
import Combine
import CasePaths

struct CombatantDetailViewState: NavigationStackSourceState, Equatable {

    var runningEncounter: RunningEncounter?
    var encounter: Encounter

    var combatant: Combatant {
        didSet {
            let c = combatant
            nextCombatantTagsViewState?.update(c)
            nextCombatantResourcesViewState?.combatant = c
        }
    }

    var popover: Popover?
    var actionSheet: ActionSheetState<CombatantDetailViewAction>?

    var presentedScreens: [NavigationDestination: NextScreen] = [:]

    var navigationStackItemStateId: String {
        combatant.id.uuidString
    }

    var navigationTitle: String { combatant.discriminatedName }
    var navigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? { .inline }

    var nextCombatantTagsViewState: CombatantTagsViewState? {
        get { nextScreen.flatMap((/NextScreen.combatantTagsView).extract) }
        set {
            if let newValue = newValue {
                nextScreen = (/NextScreen.combatantTagsView).embed(newValue)
            }
        }
    }

    var nextCombatantTagEditViewState: CombatantTagEditViewState? {
        get { nextScreen.flatMap((/NextScreen.combatantTagEditView).extract) }
        set {
            if let newValue = newValue {
                nextScreen = (/NextScreen.combatantTagEditView).embed(newValue)
            }
        }
    }

    var nextCreatureEditViewState: CreatureEditViewState? {
        get { nextScreen.flatMap((/NextScreen.creatureEditView).extract) }
        set {
            if let newValue = newValue {
                nextScreen = (/NextScreen.creatureEditView).embed(newValue)
            }
        }
    }

    var nextCombatantResourcesViewState: CombatantResourcesViewState? {
        get { nextScreen.flatMap((/NextScreen.combatantResourcesView).extract) }
        set {
            if let newValue = newValue {
                nextScreen = (/NextScreen.combatantResourcesView).embed(newValue)
            }
        }
    }

    var addLimitedResourceState: CombatantTrackerEditViewState? {
        get {
            guard case .addLimitedResource(let s) = popover else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                popover = .addLimitedResource(newValue)
            }
        }
    }

    var healthDialogState: HealthDialogState? {
        get {
            guard case .healthAction(let s) = popover else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                popover = .healthAction(newValue)
            }
        }
    }

    var rollCheckDialogState: NumberEntryViewState? {
        get {
            guard case .rollCheck(let s) = popover else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                popover = .rollCheck(newValue)
            }
        }
    }

    var diceActionPopoverState: DiceActionViewState? {
        get {
            guard case .diceAction(let s) = popover else { return nil }
            return s
        }
        set {
            if let newValue = newValue {
                popover = .diceAction(newValue)
            }
        }
    }


    var normalizedForDeduplication: Self {
        var res = self
        res.presentedScreens = presentedScreens.mapValues {
            switch $0 {
            case .combatantTagsView: return .combatantTagsView(CombatantTagsViewState.nullInstance)
            case .combatantTagEditView: return .combatantTagEditView(CombatantTagEditViewState.nullInstance)
            case .creatureEditView: return .creatureEditView(CreatureEditViewState.nullInstance)
            case .combatantResourcesView: return .combatantResourcesView(CombatantResourcesViewState.nullInstance)
            case .runningEncounterLogView: return .runningEncounterLogView(RunningEncounterLogViewState.nullInstance)
            }
        }
        res.popover = popover.map {
            switch $0 {
            case .healthAction: return .healthAction(HealthDialogState.nullInstance)
            case .initiative: return .initiative(Combatant.nullInstance)
            case .rollCheck: return .rollCheck(NumberEntryViewState.nullInstance)
            case .diceAction: return .diceAction(DiceActionViewState.nullInstance)
            case .tagDetails: return .tagDetails(CombatantTag.nullInstance)
            case .addLimitedResource: return .addLimitedResource(CombatantTrackerEditViewState.nullInstance)
            }
        }
        return res
    }

    static let reducer: Reducer<Self, CombatantDetailViewAction, Environment> = Reducer.combine(
        CombatantTagEditViewState.reducer.optional().pullback(state: \.nextCombatantTagEditViewState, action: /CombatantDetailViewAction.nextScreen..CombatantDetailViewAction.NextScreenAction.combatantTagEditView),
        NumberEntryViewState.reducer.optional().pullback(state: \.rollCheckDialogState, action: /CombatantDetailViewAction.rollCheckDialog),
        DiceActionViewState.reducer.optional().pullback(state: \.diceActionPopoverState, action: /CombatantDetailViewAction.diceActionPopover),
        Reducer { state, action, env in
            switch action {
            case .combatant: break // should be handled by parent
            case .popover(let p):
                state.popover = p
            case .actionSheet(let a):
                state.actionSheet = a
            case .addLimitedResource(.onDoneTap):
                guard case .addLimitedResource(let s) = state.popover else { return .none }
                return Effect.fireAndForget {
                    env.dismissKeyboard()
                }.append([.popover(nil), .combatant(.addResource(s.resource))]).eraseToEffect()
            case .addLimitedResource: break // handled below
            case .healthDialog: break // handled below
            case .rollCheckDialog: break // handled above
            case .diceActionPopover: break // handled above
            case .saveToCompendium:
                guard let def = state.combatant.definition as? AdHocCombatantDefinition, let stats = def.stats else { return .none }
                let monster = Monster(realm: .homebrew, stats: stats, challengeRating: Fraction(integer: 0))
                try? env.compendium.put(CompendiumEntry(monster))
                return Effect(value: .combatant(.setDefinition(Combatant.CodableCombatDefinition(definition: CompendiumCombatantDefinition(item: monster, persistent: false)))))
            case .unlinkFromCompendium:
                let currentDefinition = state.combatant.definition

                let original = (currentDefinition as? CompendiumCombatantDefinition).map { CompendiumItemReference(itemTitle: $0.name, itemKey: $0.item.key) }
                let def = AdHocCombatantDefinition(id: UUID(), stats: currentDefinition.stats, player: currentDefinition.player, level: currentDefinition.level, original: original)
                return Effect(value: .combatant(.setDefinition(Combatant.CodableCombatDefinition(definition: def))))
            case .setNextScreen(let s):
                state.presentedScreens[.nextInStack] = s
            case .setDetailScreen(let s):
                state.presentedScreens[.detail] = s
            case .nextScreen(.combatantTagsView(.combatant(let c, let a))):
                guard c.id == state.combatant.id else { return .none }
                // bubble-up action
                return Effect(value: .combatant(a))
            case .nextScreen(.combatantResourcesView(.combatant(let a))):
                // bubble-up action
                return Effect(value: .combatant(a))
            case .nextScreen(.combatantTagEditView(.onDoneTap)):
                let tag = state.nextCombatantTagEditViewState?.tag
                state.nextScreen = nil

                if let tag = tag {
                    return Effect(value: .combatant(.addTag(tag)))
                }
            case .nextScreen(.creatureEditView(.onDoneTap(let state))):
                guard let def = state.adHocCombatant else { return .none }
                return [.setNextScreen(nil), .combatant(.setDefinition(Combatant.CodableCombatDefinition(definition: def)))].publisher.eraseToEffect()
            case .nextScreen, .detailScreen: break// handled by reducers below
            }
            return .none
        },
        CombatantTagsViewState.reducer.optional().pullback(state: \.nextCombatantTagsViewState, action: /CombatantDetailViewAction.nextScreen..CombatantDetailViewAction.NextScreenAction.combatantTagsView),
        CombatantResourcesViewState.reducer.optional().pullback(state: \.nextCombatantResourcesViewState, action: /CombatantDetailViewAction.nextScreen..CombatantDetailViewAction.NextScreenAction.combatantResourcesView),
        CreatureEditViewState.reducer.optional().pullback(state: \.nextCreatureEditViewState, action: /CombatantDetailViewAction.nextScreen..CombatantDetailViewAction.NextScreenAction.creatureEditView),
        CombatantTrackerEditViewState.reducer.optional().pullback(state: \.addLimitedResourceState, action: /CombatantDetailViewAction.addLimitedResource),
        HealthDialogState.reducer.optional().pullback(state: \.healthDialogState, action: /CombatantDetailViewAction.healthDialog)
    )

    enum NextScreen: NavigationStackItemStateConvertible, NavigationStackItemState, Equatable {
        case combatantTagsView(CombatantTagsViewState)
        case combatantTagEditView(CombatantTagEditViewState)
        case creatureEditView(CreatureEditViewState)
        case combatantResourcesView(CombatantResourcesViewState)
        case runningEncounterLogView(RunningEncounterLogViewState)

        var navigationStackItemState: NavigationStackItemState {
            switch self {
            case .combatantResourcesView(let s): return s
            case .combatantTagsView(let s): return s
            case .combatantTagEditView(let s): return s
            case .creatureEditView(let s): return s
            case .runningEncounterLogView(let s): return s
            }
        }
    }

    enum Popover: Equatable {
        case healthAction(HealthDialogState)
        case initiative(Combatant)
        case rollCheck(NumberEntryViewState)
        case diceAction(DiceActionViewState)
        case tagDetails(CombatantTag)
        case addLimitedResource(CombatantTrackerEditViewState)
    }

}

enum CombatantDetailViewAction: NavigationStackSourceAction, Equatable {
    case combatant(CombatantAction)
    case popover(CombatantDetailViewState.Popover?)
    case actionSheet(ActionSheetState<CombatantDetailViewAction>?)
    case addLimitedResource(CombatantTrackerEditViewAction)
    case healthDialog(HealthDialogAction)
    case rollCheckDialog(NumberEntryViewAction)
    case diceActionPopover(DiceActionViewAction)
    case saveToCompendium
    case unlinkFromCompendium

    case setNextScreen(CombatantDetailViewState.NextScreen?)
    case nextScreen(NextScreenAction)
    case setDetailScreen(CombatantDetailViewState.NextScreen?)
    case detailScreen(NextScreenAction)

    static func presentScreen(_ destination: NavigationDestination, _ screen: CombatantDetailViewState.NextScreen?) -> Self {
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
        case combatantTagsView(CombatantTagsViewAction)
        case combatantTagEditView(CombatantTagEditViewAction)
        case creatureEditView(CreatureEditViewAction)
        case combatantResourcesView(CombatantResourcesViewAction)
        case runningEncounterLogView
    }

}

extension CombatantDetailViewState {
    static let nullInstance = CombatantDetailViewState(encounter: Encounter.nullInstance, combatant: Combatant.nullInstance)
}
