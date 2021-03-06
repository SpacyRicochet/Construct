//
//  CompendiumItemDetailView.swift
//  SwiftUITest
//
//  Created by Thomas Visser on 23/09/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import SwiftUI
import ComposableArchitecture

struct CompendiumItemDetailView: View {
    @EnvironmentObject var env: Environment

    var store: Store<CompendiumEntryDetailViewState, CompendiumItemDetailViewAction>
    @ObservedObject var viewStore: ViewStore<CompendiumEntryDetailViewState, CompendiumItemDetailViewAction>

    init(store: Store<CompendiumEntryDetailViewState, CompendiumItemDetailViewAction>) {
        self.store = store
        self.viewStore = ViewStore(store)
    }

    var item: CompendiumItem {
        viewStore.state.item
    }

    var body: some View {
        return ScrollView {
            VStack {
                Group {
                    (item as? Monster).map {
                        CompendiumMonsterDetailView(monster: $0) { m in
                            StatBlockView(stats: m.stats, onTap: onTap(m.stats))
                        }
                    }

                    (item as? Spell).map {
                        CompendiumSpellDetailView(spell: $0)
                    }

                    (item as? Character).map {
                        CompendiumCharacterDetailView(character: $0) { c in
                            StatBlockView(stats: c.stats, onTap: onTap(c.stats))
                        }
                    }

                    (item as? CompendiumItemGroup).map {
                        CompendiumItemGroupDetailView(group: $0)
                    }
                }

                (viewStore.state.entry.source?.displayName).map {
                    Text($0)
                        .font(.footnote).italic()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(12)
        }
        .background(Group {
            with(menuItems) { items in
                if items.count == 1 {
                    EmptyView().navigationBarItems(trailing: Button(action: {
                        items[0].action()
                    }) {
                        Text(items[0].text)
                    })
                } else if items.count > 1 {
                    EmptyView().navigationBarItems(trailing: Menu(content: {
                        ForEach(menuItems, id: \.text) { item in
                            Button(action: item.action) {
                                Label(item.text, systemImage: item.systemImage)
                            }
                        }
                    }) {
                        Image(systemName: "ellipsis.circle").frame(width: 30, height: 30, alignment: .trailing)
                    })
                }
            }
        })
        .stateDrivenNavigationLink(
            store: store,
            state: /CompendiumEntryDetailViewState.NextScreenState.creatureEdit,
            action: /CompendiumItemDetailViewAction.NextScreenAction.creatureEdit,
            isActive: { _ in true },
            destination: CreatureEditView.init
        )
        .stateDrivenNavigationLink(
            store: store,
            state: /CompendiumEntryDetailViewState.NextScreenState.groupEdit,
            action: /CompendiumItemDetailViewAction.NextScreenAction.groupEdit,
            isActive: { _ in true },
            destination: CompendiumItemGroupEditView.init
        )
        .navigationBarTitle(Text(viewStore.state.navigationTitle), displayMode: .inline)
        .popover(popoverBinding)
    }

    var editViewState: CreatureEditViewState? {
        switch item {
        case let monster as Monster: return CreatureEditViewState(edit: monster)
        case let character as Character: return CreatureEditViewState(edit: character)
        default: return nil
        }
    }

    var menuItems: [MenuItem] {
        switch item {
        case let monster as Monster: return [
            MenuItem(text: "Save as NPC", systemImage: "plus.square.on.square") {
                self.viewStore.send(.onSaveMonsterAsNPCButton(monster))
            },
            MenuItem(text: "Edit", systemImage: "pencil") {
                if let evs = self.editViewState {
                    self.viewStore.send(.setNextScreen(.creatureEdit(evs)))
                }
            }
        ]
        case is Character: return [
            MenuItem(text: "Edit", systemImage: "pencil") {
                if let evs = self.editViewState {
                    self.viewStore.send(.setNextScreen(.creatureEdit(evs)))
                }
            }
        ]
        case let group as CompendiumItemGroup: return [
            MenuItem(text: "Edit", systemImage: "pencil") {
                self.viewStore.send(.setNextScreen(.groupEdit(CompendiumItemGroupEditState(mode: .edit, group: group))))
            }
        ]
        default: return []
        }
    }

    func onTap(_ stats: StatBlock) -> ((StatBlockView.TapTarget) -> Void)? {
        { target in
            switch target {
            case .ability(let a):
                let modifier: Int = stats.abilityScores?.score(for: a).modifier.modifier ?? 0
                self.viewStore.send(.popover(.rollCheck(modifier)))
            case .action(let a, let p):
                if let action = DiceAction(title: a.name, parsedAction: p, env: env) {
                    self.viewStore.send(.popover(.creatureAction(DiceActionViewState(action: action))))
                }
            }
        }
    }

    var popoverBinding: Binding<AnyView?> {
        Binding(get: {
            switch viewStore.state.popover {
            case .creatureAction:
                return IfLetStore(store.scope(state: { $0.createActionPopover }, action: { .creatureActionPopover($0) })) { store in
                    return DiceActionView(
                        store: store
                    )
                }.eraseToAnyView
            case .rollCheck(let modifier):
                return NumberEntryPopover(environment: self.env, rollD20WithModifier: modifier, onOutcomeSelected: { _ in
                    self.viewStore.send(.popover(nil))
                }).eraseToAnyView
            case nil: return nil
            }
        }, set: {
            assert($0 == nil)
            self.viewStore.send(.popover(nil))
        })
    }

    struct MenuItem {
        let text: String
        let systemImage: String
        let action: () -> Void
    }
}

struct CompendiumCharacterDetailView: View {
    let character: Character
    let statBlockView: (Character) -> StatBlockView

    var body: some View {
        SectionContainer {
            statBlockView(character)
        }
    }
}

struct CompendiumMonsterDetailView: View {
    let monster: Monster
    let statBlockView: (Monster) -> StatBlockView

    var body: some View {
        SectionContainer {
            statBlockView(monster)
        }
    }
}

struct CompendiumSpellDetailView: View {
    @EnvironmentObject var env: Environment
    let spell: Spell

    var body: some View {
        SectionContainer {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    Text(spell.name).font(.title).lineLimit(nil)
                    Text(spell.subheading(env)).italic().lineLimit(nil)
                }

                Divider()

                Group {
                    HStack {
                        StatBlockView.line(title: "Casting time", text: spell.castingTime)
                        if spell.ritual {
                            Text("(Ritual)")
                        }
                    }
                    StatBlockView.line(title: "Range", text: spell.range)
                    StatBlockView.line(title: "Components", text: spell.componentsSummary)
                    HStack {
                        StatBlockView.line(title: "Duration", text: spell.duration)
                        if spell.concentration {
                            Text("(Concentration)")
                        }
                    }
                }

                Divider()

                Text(spell.description)
                spell.higherLevelDescription.map { StatBlockView.line(title: "At Higher Levels.", text: $0) }
                spell.material.map { Text("* \($0)").font(.footnote).italic() }

                spell.classSummary.map { summary in
                    Group {
                        Divider()
                        Text(verbatim: summary).font(.footnote)
                    }
                }
            }
        }
    }
}

extension Spell {
    func subheading(_ env: Environment) -> String {
        let levelText: String
        if let level = level {
            levelText = "\(env.ordinalFormatter.stringWithFallback(for: level)) level"
        } else {
            levelText = "Cantrip"
        }

        return "\(levelText) (\(school))"
    }

    var componentsSummary: String {
        let list = components.compactMap { $0.rawValue.first.map { String($0).uppercased() } }.joined(separator: ", ")
        if components.contains(.material) {
            return "\(list) *"
        } else {
            return list
        }
    }

    var classSummary: String? {
        guard !classes.isEmpty, let list = ListFormatter().string(for: classes) else { return nil }
        return "Classes: \(list)"
    }
}
