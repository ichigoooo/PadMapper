import Foundation
import Testing
@testable import PadMapper

@Test func singleRuleFiresOnceUntilRelease() async throws {
    let profile = makeProfile(rules: [
        BindingRule(id: "single", triggerKeys: ["K00"], triggerType: .single, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100)
    ])
    let resolver = ComboResolver()
    let pressTime = Date()

    let first = resolver.process(event: makeEvent("P00", true, pressTime), profile: profile)
    #expect(first.triggeredMatches.map(\.ruleID) == ["single"])

    let second = resolver.process(event: makeEvent("P00", true, pressTime.addingTimeInterval(0.01)), profile: profile)
    #expect(second.triggeredMatches.isEmpty)

    _ = resolver.process(event: makeEvent("P00", false, pressTime.addingTimeInterval(0.02)), profile: profile)
    let third = resolver.process(event: makeEvent("P00", true, pressTime.addingTimeInterval(0.03)), profile: profile)
    #expect(third.triggeredMatches.map(\.ruleID) == ["single"])
}

@Test func tripleComboRequiresWindow() async throws {
    let profile = makeProfile(rules: [
        BindingRule(id: "combo", triggerKeys: ["K00", "K01", "K02"], triggerType: .combo, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100)
    ])
    let resolver = ComboResolver()
    let now = Date()

    _ = resolver.process(event: makeEvent("P00", true, now), profile: profile)
    _ = resolver.process(event: makeEvent("P01", true, now.addingTimeInterval(0.02)), profile: profile)
    let withinWindow = resolver.process(event: makeEvent("P02", true, now.addingTimeInterval(0.05)), profile: profile)
    #expect(withinWindow.triggeredMatches.map(\.ruleID) == ["combo"])

    let lateResolver = ComboResolver()
    _ = lateResolver.process(event: makeEvent("P00", true, now), profile: profile)
    _ = lateResolver.process(event: makeEvent("P01", true, now.addingTimeInterval(0.04)), profile: profile)
    let outsideWindow = lateResolver.process(event: makeEvent("P02", true, now.addingTimeInterval(0.12)), profile: profile)
    #expect(outsideWindow.triggeredMatches.isEmpty)
}

@Test func longestMatchWinsOverSubset() async throws {
    let profile = makeProfile(rules: [
        BindingRule(id: "single", triggerKeys: ["K00"], triggerType: .single, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100),
        BindingRule(id: "combo", triggerKeys: ["K00", "K01", "K02"], triggerType: .combo, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100)
    ])
    let resolver = ComboResolver()
    let now = Date()

    _ = resolver.process(event: makeEvent("P00", true, now), profile: profile)
    _ = resolver.process(event: makeEvent("P01", true, now.addingTimeInterval(0.01)), profile: profile)
    let outcome = resolver.process(event: makeEvent("P02", true, now.addingTimeInterval(0.02)), profile: profile)
    #expect(outcome.triggeredMatches.map(\.ruleID) == ["combo"])
}

@Test func higherPriorityWinsWhenLengthMatches() async throws {
    let profile = makeProfile(rules: [
        BindingRule(id: "rule-a", triggerKeys: ["K00", "K01"], triggerType: .combo, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100),
        BindingRule(id: "rule-b", triggerKeys: ["K00", "K01"], triggerType: .combo, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 200)
    ])
    let resolver = ComboResolver()
    let now = Date()

    _ = resolver.process(event: makeEvent("P00", true, now), profile: profile)
    let outcome = resolver.process(event: makeEvent("P01", true, now.addingTimeInterval(0.01)), profile: profile)
    #expect(outcome.triggeredMatches.map(\.ruleID) == ["rule-b"])
}

@Test func sharedSingleWaitsThenFiresIfComboNeverForms() async throws {
    let profile = makeProfile(rules: [
        BindingRule(id: "single", triggerKeys: ["K00"], triggerType: .single, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100),
        BindingRule(id: "combo", triggerKeys: ["K00", "K01"], triggerType: .combo, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100)
    ])
    let resolver = ComboResolver()
    let now = Date()

    let initial = resolver.process(event: makeEvent("P00", true, now), profile: profile)
    #expect(initial.triggeredMatches.isEmpty)

    let flush = resolver.flushPendingSingles(profile: profile, now: now.addingTimeInterval(0.081))
    #expect(flush.triggeredMatches.map(\.ruleID) == ["single"])
}

@Test func uncalibratedPhysicalKeyOnlyAppearsInDebug() async throws {
    var profile = makeProfile(rules: [
        BindingRule(id: "single", triggerKeys: ["K00"], triggerType: .single, triggerWindowMs: 80, suppressIndividualKeys: true, functionUnitId: "unit", enabled: true, priority: 100)
    ])
    profile.layout[0].calibrateBinding = nil
    let resolver = ComboResolver()
    let now = Date()

    let outcome = resolver.process(event: makeEvent("P99", true, now), profile: profile)

    #expect(outcome.triggeredMatches.isEmpty)
    #expect(outcome.snapshot.activePhysicalKeys == ["P99"])
    #expect(outcome.snapshot.activeLogicalKeys.isEmpty)
}

@Test func physicalComboCanTriggerWithoutCalibration() async throws {
    var profile = makeProfile(rules: [
        BindingRule(
            id: "physical-combo",
            triggerKeys: ["u7-4-c10", "u7-5-c11", "u7-6-c12"],
            triggerType: .combo,
            triggerInputMode: .physical,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: "unit",
            enabled: true,
            priority: 100
        )
    ])
    profile.layout = profile.layout.map { key in
        var updated = key
        updated.calibrateBinding = nil
        return updated
    }

    let resolver = ComboResolver()
    let now = Date()
    _ = resolver.process(event: makeEvent("u7-4-c10", true, now), profile: profile)
    _ = resolver.process(event: makeEvent("u7-5-c11", true, now.addingTimeInterval(0.02)), profile: profile)
    let outcome = resolver.process(event: makeEvent("u7-6-c12", true, now.addingTimeInterval(0.04)), profile: profile)

    #expect(outcome.triggeredMatches.map(\.ruleID) == ["physical-combo"])
}

private func makeProfile(rules: [BindingRule]) -> DeviceProfile {
    var profile = DeviceProfile.defaultProfile()
    profile.functionUnits = [
        FunctionUnit(id: "unit", name: "Unit", description: nil, actions: [.shortcut(modifiers: [.command], key: "y")], enabled: true)
    ]
    profile.rules = rules
    return profile
}

private func makeEvent(_ physicalKeyID: String, _ isPressed: Bool, _ timestamp: Date) -> InputEvent {
    InputEvent(
        physicalKeyID: physicalKeyID,
        deviceID: "mock-pad",
        isPressed: isPressed,
        timestamp: timestamp,
        usagePage: nil,
        usage: nil,
        elementCookie: nil
    )
}
