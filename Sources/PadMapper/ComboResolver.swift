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
        var pendingSingleRuleDeadlines: [String: Date] = [:]
        var outputLog: [String] = []
    }

    private var state = State()

    var pendingSingleRuleDeadlines: [String: Date] {
        state.pendingSingleRuleDeadlines
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
        return evaluate(profile: profile, now: now)
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
            return Set(rule.triggerKeys).isSubset(of: activeKeys)
        }

        state.pendingSingleRuleDeadlines = state.pendingSingleRuleDeadlines.filter { ruleID, _ in
            guard let rule = enabledRules.first(where: { $0.id == ruleID }) else {
                return false
            }
            let activeKeys = activeKeySet(for: rule.triggerInputMode)
            return Set(rule.triggerKeys).isSubset(of: activeKeys)
        }
    }

    private func evaluate(profile: DeviceProfile, now: Date) -> ComboResolverOutcome {
        let enabledRules = profile.rules.filter(\.enabled)

        for rule in enabledRules where rule.triggerType == .single {
            guard let keyID = rule.triggerKeys.first else { continue }
            guard let pressedAt = keyPressedAt(keyID: keyID, inputMode: rule.triggerInputMode) else {
                state.pendingSingleRuleDeadlines.removeValue(forKey: rule.id)
                continue
            }

            if hasConflictingSuperset(singleRule: rule, rules: enabledRules) {
                let deadline = pressedAt.addingTimeInterval(Double(rule.triggerWindowMs) / 1000)
                state.pendingSingleRuleDeadlines[rule.id] = deadline
            } else {
                state.pendingSingleRuleDeadlines.removeValue(forKey: rule.id)
            }
        }

        let candidateRules = enabledRules.filter { rule in
            let activeKeys = activeKeySet(for: rule.triggerInputMode)
            return Set(rule.triggerKeys).isSubset(of: activeKeys) && isWindowSatisfied(for: rule)
        }.map(RuleCandidate.init)

        let winner = candidateRules
            .filter { candidate in
                if candidate.rule.triggerType == .single, let deadline = state.pendingSingleRuleDeadlines[candidate.rule.id] {
                    return now >= deadline
                }
                return true
            }
            .sorted(by: candidateSort)
            .first

        var triggeredMatches: [TriggerMatch] = []

        if let winner, !state.firedRuleIDs.contains(winner.rule.id) {
            state.firedRuleIDs.insert(winner.rule.id)

            if winner.rule.triggerType == .combo {
                state.pendingSingleRuleDeadlines = state.pendingSingleRuleDeadlines.filter { ruleID, _ in
                    guard let rule = enabledRules.first(where: { $0.id == ruleID }) else {
                        return false
                    }
                    return Set(rule.triggerKeys).isDisjoint(with: winner.rule.triggerKeys)
                }
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
            pendingSingleRuleIDs: state.pendingSingleRuleDeadlines.keys.sorted(),
            outputLog: state.outputLog
        )
    }

    private func logicalKeyID(for physicalKeyID: String, in profile: DeviceProfile) -> String? {
        profile.layout.first(where: { $0.calibrateBinding?.physicalKeyID == physicalKeyID })?.id
    }

    private func hasConflictingSuperset(singleRule: BindingRule, rules: [BindingRule]) -> Bool {
        let singleKeys = Set(singleRule.triggerKeys)
        return rules.contains { rule in
            guard rule.id != singleRule.id else { return false }
            guard rule.triggerInputMode == singleRule.triggerInputMode else { return false }
            let triggerKeys = Set(rule.triggerKeys)
            return triggerKeys.count > singleKeys.count && singleKeys.isSubset(of: triggerKeys)
        }
    }

    private func isWindowSatisfied(for rule: BindingRule) -> Bool {
        guard let firstKeyID = rule.triggerKeys.first, let firstPressedAt = keyPressedAt(keyID: firstKeyID, inputMode: rule.triggerInputMode) else {
            return false
        }

        let timestamps = rule.triggerKeys.compactMap { keyPressedAt(keyID: $0, inputMode: rule.triggerInputMode) }.sorted()
        guard timestamps.count == rule.triggerKeys.count else {
            return false
        }

        let lastTimestamp = timestamps.last ?? firstPressedAt
        let diff = lastTimestamp.timeIntervalSince(timestamps.first ?? firstPressedAt)
        return diff * 1000 <= Double(rule.triggerWindowMs)
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
