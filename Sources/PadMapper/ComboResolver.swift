import Foundation

struct ComboResolverOutcome {
    var triggeredMatches: [TriggerMatch]
    var snapshot: DebugSnapshot
}

private struct RuleCandidate {
    let rule: BindingRule
}

final class ComboResolver {
    private struct State {
        var activePhysicalKeys: [String: Date] = [:]
        var activeLogicalKeys: [String: PressedKeyState] = [:]
        var firedRuleIDs: Set<String> = []
        var cooldownUntilByRuleID: [String: Date] = [:]
        var outputLog: [String] = []
    }

    private var state = State()

    var pendingSingleRuleDeadlines: [String: Date] {
        [:]
    }

    func process(event: InputEvent, profile: DeviceProfile) -> ComboResolverOutcome {
        if event.isPressed {
            state.activePhysicalKeys[event.physicalKeyID] = event.timestamp
            if let logicalKeyID = logicalKeyID(for: event.physicalKeyID, in: profile) {
                state.activeLogicalKeys[logicalKeyID] = PressedKeyState(logicalKeyID: logicalKeyID, pressedAt: event.timestamp)
            }
        } else {
            state.activePhysicalKeys.removeValue(forKey: event.physicalKeyID)
            if let logicalKeyID = logicalKeyID(for: event.physicalKeyID, in: profile) {
                state.activeLogicalKeys.removeValue(forKey: logicalKeyID)
            }
        }

        cleanupState(profile: profile)
        return evaluate(profile: profile, now: event.timestamp)
    }

    func flushPendingSingles(profile: DeviceProfile, now: Date) -> ComboResolverOutcome {
        cleanupState(profile: profile)
        return ComboResolverOutcome(
            triggeredMatches: [],
            snapshot: snapshot(candidateRuleIDs: [], winningRuleID: nil)
        )
    }

    func appendLog(_ message: String, maxCount: Int = 12) -> DebugSnapshot {
        state.outputLog.append(message)
        if state.outputLog.count > maxCount {
            state.outputLog.removeFirst(state.outputLog.count - maxCount)
        }
        return snapshot(candidateRuleIDs: [], winningRuleID: nil)
    }

    private func cleanupState(profile: DeviceProfile) {
        let enabledRules = profile.rules.filter(\.enabled)

        state.firedRuleIDs = state.firedRuleIDs.filter { ruleID in
            guard let rule = enabledRules.first(where: { $0.id == ruleID }) else {
                return false
            }
            let activeKeys = activeKeySet(for: rule.triggerInputMode)
            return !Set(rule.triggerKeys).isDisjoint(with: activeKeys)
        }

        state.cooldownUntilByRuleID = state.cooldownUntilByRuleID.filter { ruleID, deadline in
            guard enabledRules.contains(where: { $0.id == ruleID }) else {
                return false
            }
            return deadline.timeIntervalSinceNow > -1
        }
    }

    private func evaluate(profile: DeviceProfile, now: Date) -> ComboResolverOutcome {
        let enabledRules = profile.rules.filter(\.enabled)

        let candidateRules = enabledRules.filter { rule in
            let activeKeys = activeKeySet(for: rule.triggerInputMode)
            switch rule.triggerType {
            case .single:
                guard let key = rule.triggerKeys.first else { return false }
                return activeKeys.contains(key)
            case .combo:
                return !Set(rule.triggerKeys).isDisjoint(with: activeKeys)
            }
        }.map(RuleCandidate.init)

        let winner = candidateRules
            .sorted(by: candidateSort)
            .first

        var triggeredMatches: [TriggerMatch] = []

        if let winner,
           !state.firedRuleIDs.contains(winner.rule.id),
           canTrigger(rule: winner.rule, now: now) {
            state.firedRuleIDs.insert(winner.rule.id)
            if winner.rule.triggerType == .combo || winner.rule.triggerKeys.count > 1 {
                state.cooldownUntilByRuleID[winner.rule.id] = now.addingTimeInterval(Double(winner.rule.triggerWindowMs) / 1000)
            }

            triggeredMatches.append(
                TriggerMatch(
                    id: UUID().uuidString,
                    ruleID: winner.rule.id,
                    functionUnitID: winner.rule.functionUnitId,
                    triggerKeys: winner.rule.triggerKeys
                )
            )
        }

        return ComboResolverOutcome(
            triggeredMatches: triggeredMatches,
            snapshot: snapshot(
                candidateRuleIDs: candidateRules.map(\.rule.id).sorted(),
                winningRuleID: winner?.rule.id
            )
        )
    }

    private func snapshot(candidateRuleIDs: [String], winningRuleID: String?) -> DebugSnapshot {
        DebugSnapshot(
            activePhysicalKeys: state.activePhysicalKeys.keys.sorted(),
            activeLogicalKeys: state.activeLogicalKeys.keys.sorted(),
            candidateRuleIDs: candidateRuleIDs,
            winningRuleID: winningRuleID,
            firedRuleIDs: state.firedRuleIDs.sorted(),
            pendingSingleRuleIDs: [],
            outputLog: state.outputLog
        )
    }

    private func logicalKeyID(for physicalKeyID: String, in profile: DeviceProfile) -> String? {
        profile.layout.first(where: { $0.calibrateBinding?.physicalKeyID == physicalKeyID })?.id
    }

    private func canTrigger(rule: BindingRule, now: Date) -> Bool {
        guard rule.triggerType == .combo || rule.triggerKeys.count > 1 else {
            return true
        }
        guard let cooldownUntil = state.cooldownUntilByRuleID[rule.id] else {
            return true
        }
        return now >= cooldownUntil
    }

    private func activeKeySet(for inputMode: TriggerInputMode) -> Set<String> {
        switch inputMode {
        case .logical:
            return Set(state.activeLogicalKeys.keys)
        case .physical:
            return Set(state.activePhysicalKeys.keys)
        }
    }

    private func keyPressedAt(keyID: String, inputMode: TriggerInputMode) -> Date? {
        switch inputMode {
        case .logical:
            return state.activeLogicalKeys[keyID]?.pressedAt
        case .physical:
            return state.activePhysicalKeys[keyID]
        }
    }

    private func candidateSort(lhs: RuleCandidate, rhs: RuleCandidate) -> Bool {
        if lhs.rule.triggerKeys.count != rhs.rule.triggerKeys.count {
            return lhs.rule.triggerKeys.count > rhs.rule.triggerKeys.count
        }
        if lhs.rule.priority != rhs.rule.priority {
            return lhs.rule.priority > rhs.rule.priority
        }
        return lhs.rule.id < rhs.rule.id
    }
}
