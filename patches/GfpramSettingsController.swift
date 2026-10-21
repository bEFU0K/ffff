import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import LocalizedPeerData
import PromptUI

private final class GfpramArguments {
    let toggle: (String, Bool) -> Void
    let perform: (Int32) -> Void

    init(toggle: @escaping (String, Bool) -> Void, perform: @escaping (Int32) -> Void) {
        self.toggle = toggle
        self.perform = perform
    }
}

private enum GfpramEntry: ItemListNodeEntry {
    case header(Int32, String)
    case toggle(Int32, String, String, Bool)
    case action(Int32, String, String, Int32)
    case footer(Int32, String)

    var entryId: Int32 {
        switch self {
        case let .header(entryId, _):
            return entryId
        case let .toggle(entryId, _, _, _):
            return entryId
        case let .action(entryId, _, _, _):
            return entryId
        case let .footer(entryId, _):
            return entryId
        }
    }

    var section: ItemListSectionId {
        return self.entryId / 100
    }

    var stableId: Int32 {
        return self.entryId
    }

    static func <(lhs: GfpramEntry, rhs: GfpramEntry) -> Bool {
        return lhs.entryId < rhs.entryId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GfpramArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, title, key, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggle(key, newValue)
            })
        case let .action(_, title, label, kind):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: title, label: label, labelStyle: .text, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                arguments.perform(kind)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func gfpramEntries(adminUnlocked: Bool) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    var base: Int32 = 0
    for group in AyuSettings.groups {
        entries.append(.header(base, group.title))
        var index: Int32 = 1
        for toggle in group.toggles {
            entries.append(.toggle(base + index, toggle.title, toggle.key, AyuSettings.value(toggle.key)))
            index += 1
        }
        if !group.footer.isEmpty {
            entries.append(.footer(base + index, group.footer))
        }
        base += 100
    }
    entries.append(.header(base, "ПРИЛОЖЕНИЕ"))
    entries.append(.action(base + 1, "Иконка приложения", "", 0))
    entries.append(.action(base + 2, "О GFPGRAM", AyuSettings.version, 1))
    if adminUnlocked {
        entries.append(.action(base + 3, "Админ-панель", "", 2))
    }
    return entries
}

public func gfpramSettingsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramArguments(
        toggle: { key, newValue in
            AyuSettings.set(key, newValue)
            refresh.set(true)
        },
        perform: { kind in
            switch kind {
            case 0:
                pushImpl?(themeSettingsController(context: context))
            case 1:
                presentImpl?(promptController(context: context, text: "Введите ключ", value: nil, placeholder: "", apply: { value in
                    guard let value = value else {
                        return
                    }
                    if AyuSettings.verifyAdminCode(value) {
                        refresh.set(true)
                        pushImpl?(gfpramAdminController(context: context))
                    }
                }))
            case 2:
                pushImpl?(gfpramAdminController(context: context))
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("GFPGRAM"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramEntries(adminUnlocked: AyuSettings.adminUnlocked), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Админ-панель

private func gfpramAdminEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ЗНАЧОК «#»"))
    entries.append(.action(1, "Выдать значок по @username", "", 10))
    entries.append(.action(2, "Выдать значок себе", "", 11))
    var index: Int32 = 3
    var listIndex: Int32 = 0
    for entry in AyuBadges.entries() {
        entries.append(.action(index, "# " + entry.name, "убрать", 1000 + listIndex))
        index += 1
        listIndex += 1
    }
    entries.append(.footer(index, "Значок «#» показывается рядом с именем пользователя или названием канала только на этом устройстве. Другие пользователи его не видят."))
    entries.append(.header(100, "ДАННЫЕ"))
    entries.append(.action(101, "Забыть маркеры удалённых сообщений", "", 12))
    return entries
}

public func gfpramAdminController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?

    let showMessage: (String) -> Void = { text in
        presentImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]))
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            if kind >= 1000 {
                let entries = AyuBadges.entries()
                let index = Int(kind - 1000)
                if index >= 0 && index < entries.count {
                    AyuBadges.remove(id: entries[index].id)
                    refresh.set(true)
                }
                return
            }
            switch kind {
            case 10:
                presentImpl?(promptController(context: context, text: "Юзернейм пользователя или канала", value: nil, placeholder: "username", apply: { value in
                    guard let value = value else {
                        return
                    }
                    var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.hasPrefix("@") {
                        name.removeFirst()
                    }
                    if name.isEmpty {
                        return
                    }
                    let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
                    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                        switch result {
                        case .progress:
                            return .complete()
                        case let .result(peer):
                            return .single(peer)
                        }
                    }
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { peer in
                        if let peer = peer {
                            AyuBadges.add(id: peer.id.id._internalGetInt64Value(), name: peer.compactDisplayTitle)
                            refresh.set(true)
                        } else {
                            showMessage("Не найдено")
                        }
                    })
                }))
            case 11:
                AyuBadges.add(id: context.account.peerId.id._internalGetInt64Value(), name: "Я")
                refresh.set(true)
            case 12:
                AyuDeleted.clearAll()
                showMessage("Готово")
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Админ-панель"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramAdminEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
