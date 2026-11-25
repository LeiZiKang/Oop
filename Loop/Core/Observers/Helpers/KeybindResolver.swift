//
//  KeybindResolver.swift
//  Loop
//
//  Created by Kai Azim on 2026-08-28.
//

import CoreGraphics

/// Matches keyboard events without mutating `KeybindTrigger` state
enum KeybindResolver {
    enum EventType {
        case keyDown
        case keyUp
        case flagsChanged
    }

    struct TriggerConfiguration {
        let keys: Set<CGKeyCode>
        let isSideDependent: Bool

        var normalizedKeys: Set<CGKeyCode> {
            isSideDependent ? keys : keys.baseModifiers
        }
    }

    struct Input {
        let eventType: EventType
        let isRepeat: Bool
        var releasedKey: CGKeyCode?
        let pressedKeys: Set<CGKeyCode>
        let modifierKeys: Set<CGKeyCode>
        let trigger: TriggerConfiguration
        let isLoopOpen: Bool
        let actionsByKeybind: [Set<CGKeyCode>: WindowAction]
        let bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction]
    }

    enum Effect: Equatable {
        case none
        case open(
            action: WindowAction,
            overrideExistingTriggerDelayAction: Bool
        )
        case close(
            force: Bool,
            notifyDoubleClickKeyUp: Bool
        )
    }

    enum HandlingIntent: Equatable {
        case forward
        case consume
        case opening

        case consumeIfLoopOpenOtherwiseOpening

        func resolve(isLoopOpenAfterEffect: Bool) -> ResolvedHandling {
            switch self {
            case .forward:
                .forward
            case .consume:
                .consume
            case .opening:
                .opening
            case .consumeIfLoopOpenOtherwiseOpening:
                isLoopOpenAfterEffect ? .consume : .opening
            }
        }
    }

    enum ResolvedHandling: Equatable {
        case forward
        case consume
        case opening
    }

    struct Decision {
        let effect: Effect
        let handling: HandlingIntent
    }

    /// Resolves an event using eager, exact key matching.
    ///
    /// Key-up events never match actions, so releasing a chord cannot trigger its subset.
    static func resolve(_ input: Input) -> Decision {
        let modifierKeys = input.trigger.isSideDependent
            ? input.modifierKeys
            : input.modifierKeys.baseModifiers
        let allPressedKeys = input.pressedKeys.union(modifierKeys)
        let triggerKeys = input.trigger.normalizedKeys
        let containsTrigger = allPressedKeys.isSuperset(of: triggerKeys)
        let actionKeys = allPressedKeys.subtracting(triggerKeys).baseModifiers
        let allPressedKeysBaseModifiers = allPressedKeys.baseModifiers

        if input.isLoopOpen, input.pressedKeys.contains(.kVK_Escape) {
            return .init(
                effect: .close(force: true, notifyDoubleClickKeyUp: false),
                handling: .consume
            )
        }

        if input.eventType == .keyUp {
            // A function key is released through keyUp. Releasing an action key must leave the session open.
            if let releasedKey = input.releasedKey, triggerKeys.contains(releasedKey),
               allPressedKeys.isEmpty || allPressedKeys.union([releasedKey]).isSuperset(of: triggerKeys) {
                return .init(
                    effect: .close(
                        force: false,
                        notifyDoubleClickKeyUp: !input.isLoopOpen && allPressedKeys.isEmpty
                    ),
                    handling: .forward
                )
            }

            return .init(effect: .none, handling: .forward)
        }

        if input.isLoopOpen, input.eventType == .flagsChanged, !containsTrigger {
            return .init(
                effect: .close(force: false, notifyDoubleClickKeyUp: false),
                handling: .forward
            )
        }

        if containsTrigger {
            if let action = input.actionsByKeybind[actionKeys] {
                return actionDecision(
                    action,
                    isRepeat: input.isRepeat
                )
            }

            if allPressedKeys == triggerKeys {
                return .init(
                    effect: .open(
                        action: .init(.noSelection),
                        overrideExistingTriggerDelayAction: !input.isRepeat
                    ),
                    handling: .opening
                )
            }
        } else if let action = input.bypassedActionsByKeybind[allPressedKeysBaseModifiers] {
            return actionDecision(
                action,
                isRepeat: input.isRepeat
            )
        } else {
            return .init(
                effect: .close(
                    force: false,
                    notifyDoubleClickKeyUp: allPressedKeys.isEmpty
                ),
                handling: .forward
            )
        }

        return .init(effect: .none, handling: .forward)
    }

    private static func actionDecision(
        _ action: WindowAction,
        isRepeat: Bool
    ) -> Decision {
        let shouldActivate = !isRepeat || (
            action.direction != .cycle && action.allowsRapidRepeat
        )

        return .init(
            effect: shouldActivate
                ? .open(action: action, overrideExistingTriggerDelayAction: true)
                : .none,
            handling: .consumeIfLoopOpenOtherwiseOpening
        )
    }
}
