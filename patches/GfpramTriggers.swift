import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI

private func gfpramTrigShort(_ text: String, _ limit: Int = 24) -> String {
    let single = text.replacingOccurrences(of: "\n", with: " ")
    return single.count > limit ? String(single.prefix(limit)) + "…" : single
}

// MARK: - Окно «Слова-триггеры»: список слов (до 20), у каждого свой ответ и свой чат

private func gfpramTriggerEntries() -> [GfpramEntry] {
    let list = AyuPremiumService.triggers
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "СЛОВА-ТРИГГЕРЫ"))
    entries.append(.toggle(1, "Отвечать на слова", "premiumKeyword", AyuSettings.value("premiumKeyword")))
    entries.append(.toggle(3, "Только когда я не в сети или ночью", "kwAway", AyuSettings.value("kwAway")))
    entries.append(.footer(4, "Когда во входящем сообщении есть слово из списка, приложение отвечает на него вашим текстом. Работает в личных чатах и группах. «Не в сети» — приложение свёрнуто или экран заблокирован; «ночью» — по часам из автоответчика (ночной режим или «Занят»). Не чаще раза в 30 секунд на слово и чат. Если сработало слово, автоответчик в этом чате молчит. Список отдельный у каждого аккаунта."))

    entries.append(.header(100, "СЛОВА: " + String(list.count) + " ИЗ " + String(AyuPremiumService.maxTriggers)))
    for (index, trigger) in list.enumerated() {
        let place = trigger.chatId == nil ? "все чаты" : (trigger.chatTitle ?? "один чат")
        entries.append(.action(Int32(101 + index), "«" + gfpramTrigShort(trigger.word, 20) + "»", gfpramTrigShort(trigger.reply, 14) + " · " + gfpramTrigShort(place, 14), Int32(200 + index)))
    }
    if list.count < AyuPremiumService.maxTriggers {
        entries.append(.action(150, "Добавить слово", "", 1))
    }
    entries.append(.footer(151, "В одном слове можно несколько вариантов через запятую: цена, прайс, сколько стоит. Нажмите на слово, чтобы изменить ответ, выбрать чат или удалить его. В ответе работают {имя}, {чат}, {время}, {дата}."))

    if !list.isEmpty {
        entries.append(.header(300, "СБРОС"))
        entries.append(.action(301, "Удалить все слова", "", 3))
    }
    return entries
}

public func gfpramTriggersController(context: AccountContext) -> ViewController {
    AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramArguments(
        toggle: { key, value in
            AyuSettings.set(key, value)
            refresh.set(true)
        },
        perform: { kind in
            if kind >= 200 {
                let index = Int(kind - 200)
                if index < AyuPremiumService.triggers.count {
                    pushImpl?(gfpramTriggerEditController(context: context, index: index, onChange: { refresh.set(true) }))
                }
                return
            }
            switch kind {
            case 1:
                if AyuPremiumService.triggers.count >= AyuPremiumService.maxTriggers {
                    presentImpl?(gfpramAlert(context: context, title: nil, text: "Можно не больше \(AyuPremiumService.maxTriggers) слов"))
                    return
                }
                presentImpl?(promptController(context: context, text: "Слово-триггер (можно несколько через запятую)", value: nil, placeholder: "", apply: { word in
                    guard let word = word?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else {
                        return
                    }
                    var list = AyuPremiumService.triggers
                    if list.count < AyuPremiumService.maxTriggers {
                        list.append(AyuTrigger(word: word, reply: "{имя}, привет! Сообщение получил, отвечу позже."))
                        AyuPremiumService.triggers = list
                    }
                    refresh.set(true)
                    let newIndex = list.count - 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: {
                        pushImpl?(gfpramTriggerEditController(context: context, index: newIndex, onChange: { refresh.set(true) }))
                    })
                }))
            case 3:
                presentImpl?(gfpramAlert(context: context, title: "Удалить все слова?", text: "Список слов-триггеров этого аккаунта будет очищен.", actions: [
                    TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                        AyuPremiumService.triggers = []
                        refresh.set(true)
                    })
                ]))
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(""), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        var list = gfpramTriggerEntries()
        list.insert(.hero(-1, "Слова-триггеры", "Слово в сообщении — и приложение отвечает само. До 20 слов, у каждого свой ответ и свой чат."), at: 0)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: list, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    gfpramAnimateAppear(controller)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Окно одного слова: слово, ответ, чат

private func gfpramTriggerEditEntries(index: Int) -> [GfpramEntry] {
    let list = AyuPremiumService.triggers
    var entries: [GfpramEntry] = []
    guard index < list.count else {
        return entries
    }
    let trigger = list[index]
    entries.append(.header(0, "СЛОВО №" + String(index + 1)))
    entries.append(.action(1, "Слово", gfpramTrigShort(trigger.word), 1))
    entries.append(.action(2, "Ответ", gfpramTrigShort(trigger.reply), 2))
    entries.append(.action(3, "Чат", trigger.chatId == nil ? "все чаты" : gfpramTrigShort(trigger.chatTitle ?? "один чат"), 3))
    entries.append(.footer(4, "Чат: @username, ссылка t.me/… или пусто — тогда слово работает во всех чатах. Для личного чата укажите @username человека."))
    entries.append(.header(100, "УДАЛЕНИЕ"))
    entries.append(.action(101, "Удалить это слово", "", 4))
    return entries
}

func gfpramTriggerEditController(context: AccountContext, index: Int, onChange: @escaping () -> Void) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?
    var popImpl: (() -> Void)?

    let update: (@escaping (inout AyuTrigger) -> Void) -> Void = { change in
        var list = AyuPremiumService.triggers
        guard index < list.count else {
            return
        }
        change(&list[index])
        AyuPremiumService.triggers = list
        refresh.set(true)
        onChange()
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            let list = AyuPremiumService.triggers
            guard index < list.count else {
                return
            }
            switch kind {
            case 1:
                presentImpl?(promptController(context: context, text: "Слово-триггер", value: list[index].word, placeholder: "", apply: { value in
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                        return
                    }
                    update({ $0.word = value })
                }))
            case 2:
                presentImpl?(promptController(context: context, text: "Ответ на слово", value: list[index].reply, placeholder: "", apply: { value in
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                        return
                    }
                    update({ $0.reply = value })
                }))
            case 3:
                presentImpl?(promptController(context: context, text: "Чат: @username или ссылка t.me. Пусто = все чаты", value: nil, placeholder: "@username", apply: { value in
                    guard let value = value else {
                        return
                    }
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        update({
                            $0.chatId = nil
                            $0.chatTitle = nil
                        })
                        return
                    }
                    gfpramResolve(context: context, name: value, completion: { peer in
                        if let peer = peer {
                            let chatId = peer.id.toInt64()
                            let title = peer.compactDisplayTitle
                            update({
                                $0.chatId = chatId
                                $0.chatTitle = title
                            })
                        } else {
                            presentImpl?(gfpramAlert(context: context, title: nil, text: "Чат не найден. Проверьте @username."))
                        }
                    })
                }))
            case 4:
                presentImpl?(gfpramAlert(context: context, title: "Удалить слово?", text: "«" + list[index].word + "» и его ответ будут удалены.", actions: [
                    TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                        var current = AyuPremiumService.triggers
                        if index < current.count {
                            current.remove(at: index)
                            AyuPremiumService.triggers = current
                        }
                        onChange()
                        popImpl?()
                    })
                ]))
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Слово-триггер"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramTriggerEditEntries(index: index), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    gfpramAnimateAppear(controller)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    popImpl = { [weak controller] in
        let _ = controller?.navigationController?.popViewController(animated: true)
    }
    return controller
}
