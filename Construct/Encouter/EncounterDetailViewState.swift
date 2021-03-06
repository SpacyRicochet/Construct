//
//  EncounterDetailViewState.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 14/10/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import Combine
import CasePaths
import SwiftUI
import ComposableArchitecture

struct EncounterDetailViewState: Equatable {
    var building: Encounter {
        didSet {
            let b = building
            addCombatantState?.encounter = b
            if let cds = combatantDetailState, let c = b.combatant(for: cds.combatant.id) {
                combatantDetailState?.combatant = c
            }
        }
    }
    var running: RunningEncounter? {
        didSet {
            if let running = running {
                addCombatantState?.encounter = running.current
                if let cds = combatantDetailState {
                    combatantDetailState?.runningEncounter = running
                    if let c = running.current.combatant(for: cds.combatant.id) {
                        combatantDetailState?.combatant = c
                    }
                }
                // refresh combatants in selectedCombatantTagsState
                if let scts = selectedCombatantTagsState {
                    selectedCombatantTagsState?.combatants = scts.combatants.compactMap { running.current.combatant(for: $0.id) }
                }
            }
        }
    }

    typealias ResumableRunningEncounters = Async<[KeyValueStore.Record], Error, Environment>
    var resumableRunningEncounters: ResumableRunningEncounters = .initial

    var actionSheet: ActionSheetState<Action>?
    var sheet: Sheet?
    var popover: Popover?

    var editMode = false
    var selection = Set<UUID>()

    var encounter: Encounter {
        get { running?.current ?? building }
        set {
            if running != nil {
                running?.current = newValue
            } else {
                building = newValue
            }
        }
    }

    var addCombatantState: AddCombatantState? {
        get {
            if case .add(let sheet)? = sheet {
                return sheet.state
            }
            return nil
        }
        set {
            if case .add(let sheet)? = sheet, let state = newValue {
                self.sheet = .add(AddCombatantSheet(id: sheet.id, state: state))
            }
        }
    }

    var combatantDetailState: CombatantDetailViewState? {
        get {
            guard case .combatant(let state)? = sheet else { return nil }
            return state
        }
        set {
            if let state = newValue {
                self.sheet = .combatant(state)
            } else {
                self.sheet = nil
            }
        }
    }

    var runningEncounterLogState: RunningEncounterLogViewState? {
        guard case .runningEncounterLog(let state)? = sheet else { return nil }
        return state
    }

    var selectedCombatantTagsState: CombatantTagsViewState? {
        get {
            guard case .selectedCombatantTags(let state) = sheet else { return nil }
            return state
        }

        set {
            if let state = newValue {
                self.sheet = .selectedCombatantTags(state)
            }
        }
    }

    var normalizedForDeduplication: Self {
        var res = self
        res.sheet = sheet.map {
            switch $0 {
            case .add: return .add(AddCombatantSheet.nullInstance)
            case .combatant: return .combatant(CombatantDetailViewState.nullInstance)
            case .runningEncounterLog: return .runningEncounterLog(RunningEncounterLogViewState.nullInstance)
            case .selectedCombatantTags: return .selectedCombatantTags(CombatantTagsViewState.nullInstance)
            case .settings: return .settings
            }
        }

        res.popover = popover.map {
            switch $0 {
            case .encounterInitiative: return .encounterInitiative
            case .combatantInitiative: return .combatantInitiative(Combatant.nullInstance)
            case .health: return .health(.single(Combatant.nullInstance))
            }
        }
        return res
    }

    enum Sheet: Equatable {
        case add(AddCombatantSheet)
        case combatant(CombatantDetailViewState)
        case runningEncounterLog(RunningEncounterLogViewState)
        case selectedCombatantTags(CombatantTagsViewState)
        case settings
    }

    enum Popover: Equatable {
        case encounterInitiative
        case combatantInitiative(Combatant)
        case health(CombatantActionTarget)
    }

    enum CombatantActionTarget: Equatable {
        case single(Combatant)
        case selection
    }
}

extension EncounterDetailViewState {
    enum Action: Equatable {
        case onAppear
        case encounter(Encounter.Action) // forwarded to the effective encounter
        case buildingEncounter(Encounter.Action)
        case runningEncounter(RunningEncounter.Action)
        case onRunEncounterTap
        case onResumeRunningEncounterTap(String) // key of the running encounter
        case run(RunningEncounter?)
        case stop
        case actionSheet(ActionSheetState<Action>?)
        case sheet(Sheet?)
        case popover(Popover?)
        case addCombatant(AddCombatantState.Action)
        case combatantDetail(CombatantDetailViewAction)
        case resumableRunningEncounters(ResumableRunningEncounters.Action)
        case removeResumableRunningEncounter(String) // key of the running encounter
        case resetEncounter(Bool) // false = clear monsters, true = clear all
        case editMode(Bool)
        case selection(Set<UUID>)

        case selectionEncounterAction(SelectionEncounterAction)
        case selectionCombatantAction(CombatantAction)

        case selectedCombatantTags(CombatantTagsViewAction)

        enum SelectionEncounterAction: Hashable {
            case duplicate
            case remove
        }
    }

    static var reducer: Reducer<EncounterDetailViewState, Action, Environment> {
        return Reducer.combine(
            Reducer { state, action, env in
                switch action {
                case .onAppear:
                    var actions: [Action] = [.buildingEncounter(.refreshCompendiumItems)]
                    if state.resumableRunningEncounters.result == nil {
                        actions.insert(.resumableRunningEncounters(.startLoading), at: 0)
                    }

                    return actions.publisher.eraseToEffect()
                case .onRunEncounterTap:
                    if let resumables = state.resumableRunningEncounters.value, resumables.count > 0 {
                        return Effect(value: .actionSheet(.runEncounter(resumables)))
                    } else {
                        return Effect(value: .run(nil))
                    }
                case .onResumeRunningEncounterTap(let resumableKey):
                    return Effect.future { callback in
                        do {
                            if let runningEncounter: RunningEncounter = try env.database.keyValueStore.get(resumableKey) {
                                callback(.success(.run(runningEncounter)))
                            } else {
                                assertionFailure("Could not resume run: \(resumableKey) not found")
                                callback(.success(nil))
                            }
                        } catch {
                            assertionFailure("Could not resume run: \(error)")
                            callback(.success(nil))
                        }
                    }.compactMap { $0 }.eraseToEffect()
                case .run(let runningEncounter):
                    let base = apply(state.building) {
                        $0.ensureStableDiscriminators = true
                    }
                    let re = runningEncounter
                        ?? RunningEncounter(id: env.generateUUID(), base: base, current: base, turn: state.building.initiativeOrder.first.map { RunningEncounter.Turn(round: 1, combatantId: $0.id) })
                    state.running = re
                    // let's not use this until it's a setting
                    // state.building.runningEncounterKey = re.key
                case .stop:
                    state.running = nil
                    state.encounter.runningEncounterKey = nil
                    return Effect(value: .resumableRunningEncounters(.startLoading))
                case .encounter(let a): // forward to the effective encounter
                    if state.running != nil {
                        return Effect(value: .runningEncounter(.current(a)))
                    } else {
                        return Effect(value: .buildingEncounter(a))
                    }
                case .buildingEncounter: break
                case .runningEncounter: break
                case .resumableRunningEncounters: break // handled below
                case .removeResumableRunningEncounter(let key):
                    return Effect.future { callback in
                        _ = try? env.database.keyValueStore.remove(key)
                        callback(.success(.resumableRunningEncounters(.startLoading)))
                    }
                case .actionSheet(let s):
                    state.actionSheet = s
                case .sheet(let s):
                    state.sheet = s
                case .addCombatant(AddCombatantState.Action.onSelect(let combatants, let dismiss)):
                    return combatants.map { c in
                        .encounter(.add(c))
                    }.publisher.append(
                        // Async is needed if this action also dismissed a
                        dismiss
                            ? Just(Action.sheet(nil)).delay(for: 0, scheduler: DispatchQueue.main).eraseToAnyPublisher()
                            : Empty().eraseToAnyPublisher()
                    ).eraseToEffect()
                case .addCombatant: break // handled by AddCombatantState.reducer
                case .combatantDetail(.combatant(let a)):
                    if let combatantDetailState = state.combatantDetailState {
                        return Effect(value: .encounter(.combatant(combatantDetailState.combatant.id, a)))
                    }
                case .combatantDetail: break // handled by CombatantDetailViewState.reducer
                case .popover(let p):
                    state.popover = p
                case .resetEncounter(let clearAll):
                    state.building.runningEncounterKey = nil
                    if clearAll {
                        state.building.combatants = []
                    } else {
                        state.building.combatants.removeAll { $0.party == nil && $0.definition.player == nil }
                    }

                    let runningEncounterPrefix = RunningEncounter.keyPrefix(for: state.building)
                    return Effect.future { callback in
                        // remove all runs
                        _ = try? env.database.keyValueStore.removeAll(runningEncounterPrefix)
                        callback(.success(.resumableRunningEncounters(.startLoading)))
                    }
                case .editMode(let b):
                    state.editMode = b
                    if !b {
                        state.selection.removeAll()
                    }
                case .selection(let s):
                    state.selection = s
                case .selectionCombatantAction(let action):
                    return state.selection.map {
                        .encounter(.combatant($0, action))
                    }.publisher.eraseToEffect()
                case .selectionEncounterAction(let action):
                    let encounter = state.encounter
                    return state.selection.compactMap {
                        guard let combatant = encounter.combatant(for: $0) else { return nil }
                        switch action {
                        case .duplicate:
                            return .encounter(.duplicate(combatant))
                        case .remove:
                            return .encounter(.remove(combatant))
                        }
                    }.publisher.eraseToEffect()
                case .selectedCombatantTags(.combatant(let c, let a)):
                    return Effect(value: .encounter(.combatant(c.id, a)))
                case .selectedCombatantTags: break // handled below
                }
                return .none
            },
            Encounter.reducer.pullback(state: \.building, action: /Action.buildingEncounter),
            RunningEncounter.reducer.optional().pullback(state: \.running, action: /Action.runningEncounter),
            Reducer.withState({ $0.building.id }) { state in
                ResumableRunningEncounters.reducer { env in
                    do {
                        let nodes = try env.database.keyValueStore.fetchAllRaw(RunningEncounter.keyPrefix(for: state.building))
                        return Just(nodes).promoteError().eraseToAnyPublisher()
                    } catch {
                        return Fail(error: error).eraseToAnyPublisher()
                    }
                }.pullback(state: \.resumableRunningEncounters, action: /Action.resumableRunningEncounters)
            },
            AddCombatantState.reducer.optional().pullback(state: \.addCombatantState, action: /Action.addCombatant),
            CombatantDetailViewState.reducer.optional().pullback(state: \.combatantDetailState, action: /Action.combatantDetail),
            CombatantTagsViewState.reducer.optional().pullback(state: \.selectedCombatantTagsState, action: /Action.selectedCombatantTags)
        )
    }
}

extension EncounterDetailViewState: NavigationStackItemState {
    var navigationStackItemStateId: String { encounter.key }

    var navigationTitle: String { encounter.name }
    var navigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? { .inline }
}

struct AddCombatantSheet: Identifiable, Equatable {
    let id: UUID
    var state: AddCombatantState

    init(id: UUID = UUID(), state: AddCombatantState) {
        self.id = id
        self.state = state
    }
}

extension AddCombatantSheet {
    static let nullInstance = AddCombatantSheet(state: AddCombatantState.nullInstance)
}

extension EncounterDetailViewState {
    static let nullInstance = EncounterDetailViewState(building: Encounter.nullInstance)
}
