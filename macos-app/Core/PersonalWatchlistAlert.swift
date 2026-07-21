import Foundation

struct PersonalWatchlistAlertTrigger: Hashable {
    let kind: PersonalWatchlistAlertKind
    let threshold: Double
    let currentPrice: Double
    let changeSinceFollowPct: Double?
}

struct PersonalWatchlistAlertEvaluation: Hashable {
    let triggers: [PersonalWatchlistAlertTrigger]
    let nextState: PersonalWatchlistAlertState
}

enum PersonalWatchlistAlertEvaluator {
    static func evaluate(
        rules: PersonalWatchlistAlertRules,
        previousState: PersonalWatchlistAlertState,
        currentPrice: Double?,
        baselinePrice: Double?,
        triggeredAt: String,
        commitNewTriggers: Bool = true
    ) -> PersonalWatchlistAlertEvaluation {
        guard !rules.isEmpty else {
            return PersonalWatchlistAlertEvaluation(
                triggers: [],
                nextState: PersonalWatchlistAlertState()
            )
        }

        let configuredKinds = rules.configuredKinds
        var nextState = previousState
        nextState.breachedKinds.formIntersection(configuredKinds)
        nextState.lastTriggeredAtByKind = nextState.lastTriggeredAtByKind.filter {
            configuredKinds.contains($0.key)
        }

        let validCurrentPrice = currentPrice.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let changePct: Double? = {
            guard let validCurrentPrice,
                  let baselinePrice,
                  baselinePrice.isFinite,
                  baselinePrice > 0 else { return nil }
            return (validCurrentPrice / baselinePrice - 1) * 100
        }()

        var triggers: [PersonalWatchlistAlertTrigger] = []

        func evaluateRule(
            kind: PersonalWatchlistAlertKind,
            threshold: Double?,
            observedValue: Double?,
            isBreached: (Double, Double) -> Bool
        ) {
            guard let threshold,
                  threshold.isFinite,
                  threshold > 0,
                  let observedValue,
                  observedValue.isFinite,
                  let validCurrentPrice else { return }

            if isBreached(observedValue, threshold) {
                guard !nextState.breachedKinds.contains(kind) else { return }
                triggers.append(
                    PersonalWatchlistAlertTrigger(
                        kind: kind,
                        threshold: threshold,
                        currentPrice: validCurrentPrice,
                        changeSinceFollowPct: changePct
                    )
                )
                if commitNewTriggers {
                    nextState.breachedKinds.insert(kind)
                    nextState.lastTriggeredAtByKind[kind] = triggeredAt
                }
            } else {
                nextState.breachedKinds.remove(kind)
            }
        }

        evaluateRule(
            kind: .priceAbove,
            threshold: rules.priceAbove,
            observedValue: validCurrentPrice,
            isBreached: { $0 >= $1 }
        )
        evaluateRule(
            kind: .priceBelow,
            threshold: rules.priceBelow,
            observedValue: validCurrentPrice,
            isBreached: { $0 <= $1 }
        )
        evaluateRule(
            kind: .gainSinceFollow,
            threshold: rules.gainSinceFollowPct,
            observedValue: changePct,
            isBreached: { $0 >= $1 }
        )
        evaluateRule(
            kind: .lossSinceFollow,
            threshold: rules.lossSinceFollowPct,
            observedValue: changePct,
            isBreached: { $0 <= -$1 }
        )

        return PersonalWatchlistAlertEvaluation(triggers: triggers, nextState: nextState)
    }
}
