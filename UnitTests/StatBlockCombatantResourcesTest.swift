//
//  StatBlockCombatantResourcesTest.swift
//  UnitTests
//
//  Created by Thomas Visser on 20/10/2019.
//  Copyright © 2019 Thomas Visser. All rights reserved.
//

import Foundation
import XCTest
@testable import Construct
import Combine

class StatBlockCombatantResourcesTest: XCTestCase {

    func testSpellcasting() {
        var monster = Fixtures.monster
        monster.stats.features = [CreatureFeature(name: "Spellcasting", description: "The naga is an 11th-level spellcaster. Its spellcasting ability is Wisdom (spell save DC 16, +8 to hit with spell attacks), and it needs only verbal components to cast its spells. It has the following cleric spells prepared:\n\n• Cantrips (at will): mending, sacred flame, thaumaturgy\n• 1st level (4 slots): command, cure wounds, shield of faith\n• 2nd level (3 slots): calm emotions, hold person\n• 3rd level (3 slots): bestow curse, clairvoyance\n• 4th level (3 slots): banishment, freedom of movement\n• 5th level (2 slots): flame strike, geas\n• 6th level (1 slot): true seeing")]
        monster.stats.actions = []

        let resources = monster.stats.extractResources()
        XCTAssertEqual(resources.count, 6)
        XCTAssertEqual(resources[0].title, "1st level spell slots")
        XCTAssertEqual(resources[0].slots, [false, false, false, false])
        XCTAssertEqual(resources[5].title, "6th level spell slots")
        XCTAssertEqual(resources[5].slots, [false])
    }

    func testRechargingAction() {
        var monster = Fixtures.monster
        monster.stats.features = []
        monster.stats.actions = [CreatureAction(name: "Cold Breath (Recharge 5-6)", description: "The dragon exhales an icy blast of hail in a 15-foot cone. Each creature in that area must make a DC 12 Constitution saving throw, taking 22 (5d8) cold damage on a failed save, or half as much damage on a successful one.")]

        let resources = monster.stats.extractResources()
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources[0].title, "Cold Breath (Recharge 5-6)")
        XCTAssertEqual(resources[0].slots, [false])
    }
}
