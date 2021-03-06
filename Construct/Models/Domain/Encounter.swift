//
//  Models.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 06/06/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import ComposableArchitecture
import Combine

struct Encounter: Equatable, Codable {
    let id: UUID
    var name: String
    var combatants: IdentifiedArray<UUID, Combatant> {
        didSet {
            updateCombatantDiscriminators()
        }
    }
    var partyForDifficulty: Party?

    // The id of the running encounter
    var runningEncounterKey: String?

    var ensureStableDiscriminators: Bool

    init(id: UUID = UUID(), name: String, combatants: [Combatant]) {
        self.id = id
        self.name = name
        self.combatants = IdentifiedArray(combatants, id: \.id)
        self.ensureStableDiscriminators = false
        updateCombatantDiscriminators()
    }

    func filteredCombatants(withInitiative: Bool = false) -> [Combatant] {
        if withInitiative {
            return initiativeOrder
        }
        return self.combatants.filter { $0.initiative == nil }
    }

    var allOrNoCombatantsHaveInitiative: Bool {
        guard let first = combatants.first else { return true }
        return combatants.dropFirst().first { (first.initiative == nil) != ($0.initiative == nil) } == nil
    }

    var allCombatantsHaveInitiative: Bool {
        return combatants.first { $0.initiative == nil } == nil
    }

    var combatantsInDisplayOrder: [Combatant] {
        combatants
            .sorted { a, b in
                guard let ia = a.initiative, let ib = b.initiative else { return false }
                if ia > ib {
                    return true
                } else if ia < ib {
                    return false
                } else {
                    let dsa = a.definition.stats?.abilityScores?.dexterity.score ?? 10
                    let dsb = b.definition.stats?.abilityScores?.dexterity.score ?? 10
                    if dsa > dsb {
                        return true
                    } else if dsa < dsb {
                        return false
                    } else if let idxa = combatants.firstIndex(where: { $0.id == a.id }),
                        let idxb = combatants.firstIndex(where: { $0.id == b.id}) {
                        // tie-breaker 1
                        return idxa < idxb
                    } else {
                        return a.id.uuidString < b.id.uuidString // tie-breaker 2
                    }
                }
            }
    }

    var initiativeOrder: [Combatant] {
        combatantsInDisplayOrder.filter { $0.initiative != nil }
    }

    func initiative(forGroupingHint hint: String) -> Int? {
        combatants.first { $0.definition.initiativeGroupingHint == hint && $0.initiative != nil }?.initiative
    }

    var playerControlledCombatants: [Combatant] {
        combatants.filter { $0.definition.player != nil }
    }

    var partyEntriesForDifficulty: [EncounterDifficulty.PartyEntry] {
        if let party = partyForDifficulty {
            if party.combatantBased {
                let partyCombatants: [Combatant] = (party.combatantParty?.filter?.compactMap { id in
                    combatants.first { $0.id == id }
                } ?? playerControlledCombatants)
                let entries: [EncounterDifficulty.PartyEntry] = partyCombatants.compactMap { c in c.definition.level.map { .init(level: $0, name: c.name) } }
                if !entries.isEmpty {
                    return entries
                }
            } else if let simple = party.simplePartyEntries, !simple.isEmpty {
                return simple.flatMap { Array(repeating: .init(level: $0.level, name: nil), count: $0.count) }
            }
        } else if !playerControlledCombatants.isEmpty {
            let entries: [EncounterDifficulty.PartyEntry] = playerControlledCombatants.compactMap { c in c.definition.level.map { .init(level: $0, name: c.name) } }
            if !entries.isEmpty {
                return entries
            }
        }

        return Array(repeating: .init(level: 2, name: nil), count: 3)
    }

    func combatant(for id: UUID) -> Combatant? {
        return combatants.first { $0.id == id }
    }

    func combatants(with definitionID: String) -> [Combatant] {
        return combatants.filter { $0.definition.definitionID == definitionID }
    }

    mutating func rollInitiative<G>(settings: InitiativeSettings, rng: inout G) where G: RandomNumberGenerator{
        // will be nil if grouping is disabled
        var groupCache: [AnyHashable: Int]?

        if settings.group {
            // build up cache if we're not overwriting
            groupCache = settings.overwrite ? [:] : combatants.reduce(into: Dictionary<AnyHashable, Int>()) { acc, combatant in
                if let initiative = combatant.initiative {
                    acc[combatant.definition.initiativeGroupingHint] = initiative
                }
            }
        }

        for (idx, combatant) in combatants.enumerated() {
            if combatant.definition.player != nil && !settings.rollForPlayerCharacters { continue }
            if combatant.initiative != nil && !settings.overwrite { continue }

            if let initiative = groupCache?[combatant.definition.initiativeGroupingHint] {
                combatants[idx].initiative = initiative
            } else if let modifier = combatant.definition.initiativeModifier {
                // TODO: extract expression to "Rules"
                let initiative = (1.d(20) + modifier).roll(rng: &rng).total
                combatants[idx].initiative = initiative
                groupCache?[combatant.definition.initiativeGroupingHint] = initiative
            }
        }
    }

    var _isUpdatingCombatantDiscriminators = false
    mutating private func updateCombatantDiscriminators() {
        guard !_isUpdatingCombatantDiscriminators else { return }
        _isUpdatingCombatantDiscriminators = true

        if ensureStableDiscriminators {
            for i in combatants.indices {
                guard combatants[i].discriminator == nil else { continue }

                let set = combatants.filter { $0.definition.definitionID == combatants[i].definition.definitionID }
                guard set.count > 1 else { continue }

                let max = set.compactMap { $0.discriminator }.max() ?? 0
                combatants[i].discriminator = max + 1
            }
        } else {
            for i in combatants.indices {
                let set = combatants.filter { $0.definition.definitionID == combatants[i].definition.definitionID }
                if set.count > 1 {
                    combatants[i].discriminator = set.firstIndex { $0.id == combatants[i].id }.map { $0 + 1 }
                } else {
                    combatants[i].discriminator = nil
                }
            }
        }

        _isUpdatingCombatantDiscriminators = false
    }

    enum Action: Equatable {
        case name(String)
        case combatant(UUID, CombatantAction)
        case initiative(InitiativeSettings)
        case add(Combatant)
        case addByKey(CompendiumItemKey, CompendiumItemGroup?)
        case remove(Combatant)
        case duplicate(Combatant)
        case partyForDifficulty(Party)
        case refreshCompendiumItems
    }

    static let reducer: Reducer<Encounter, Action, Environment> = Reducer.combine(
        Reducer { state, action, env in
            switch action {
            case .name(let n):
                state.name = n
            case .combatant: break
            case .initiative(let settings):
                state.rollInitiative(settings: settings, rng: &env.rng)
            case .add(let combatant):
                state.combatants.append(combatant)
            case .addByKey(let key, let party):
                return Effect<Action?, Never>.future { callback in
                    do {
                        if let entry = try env.compendium.get(key), let combatant = entry.item as? CompendiumCombatant {
                            let combatant = Combatant(
                                compendiumCombatant: combatant,
                                party: party.map { CompendiumItemReference(itemTitle: $0.title, itemKey: $0.key) }
                            )
                            callback(.success(.add(combatant)))
                            return
                        }
                    } catch { }

                    callback(.success(nil))
                }.compactMap { $0 }.eraseToEffect()
            case .remove(let combatant):
                if let idx = state.combatants.firstIndex(where: { $0.id == combatant.id }) {
                    state.combatants.remove(at: idx)
                }
            case .duplicate(let combatant):
                let idx = state.combatants.firstIndex(where: { $0.id == combatant.id }) ?? (state.combatants.count-1)
                state.combatants.insert(Combatant(discriminator: nil, definition: combatant.definition, hp: combatant.hp, resources: combatant.resources.elements, initiative: combatant.initiative), at: idx+1)
            case .partyForDifficulty(let p):
                state.partyForDifficulty = p
            case .refreshCompendiumItems:
                return state.combatants.publisher.compactMap { combatant in
                    if var def = combatant.definition as? CompendiumCombatantDefinition {
                        if let entry = try? env.compendium.get(def.item.key), let item = entry.item as? CompendiumCombatant {
                            def.item = item
                            return .combatant(combatant.id, .setDefinition(Combatant.CodableCombatDefinition(definition: def)))
                        }
                    }
                    return nil
                }.eraseToEffect()
            }
            return .none
        },
        combatantReducer.forEach(state: \.combatants, action: /Action.combatant, environment: { $0 })
    )

    struct Party: Codable, Equatable { // should be enum, but struct gives us auto-codable
        var simplePartyEntries: [SimplePartyEntry]?
        var combatantParty: CombatantParty?
        var combatantBased: Bool

        struct CombatantParty: Codable, Equatable {
            var _filter: [UUID]? // if nil, all player controlled combatants are in the party
            var filter: [UUID]? {
                get { _filter }
                set { _filter = newValue }
            }

            init(filter: [UUID]?) {
                self.filter = filter
            }
        }

        struct SimplePartyEntry: Codable, Identifiable, Equatable {
            let id: UUID
            var level: Int
            var count: Int

            init(level: Int, count: Int) {
                self.id = UUID()
                self.level = level
                self.count = count
            }
        }
    }
}

struct InitiativeSettings: Equatable {
    var group: Bool
    var rollForPlayerCharacters: Bool
    var overwrite: Bool

    static let `default` = InitiativeSettings(group: true, rollForPlayerCharacters: false, overwrite: false)
}

extension Encounter: KeyValueStoreEntity {
    static let keyValueStoreEntityKeyPrefix = "encounter"

    var key: String {
        Self.key(id)
    }

    static func key(_ id: UUID) -> String {
        return "\(Self.keyValueStoreEntityKeyPrefix)_\(id)"
    }
}

extension Encounter {
    static let scratchPadEncounterId = UUID(uuidString: "641EA02F-1B8A-4A0B-9AD7-7D7068A4C014")!

    var isScratchPad: Bool {
        id == Self.scratchPadEncounterId
    }
}

extension Encounter {
    static let nullInstance = Encounter(name: "", combatants: [])
}
