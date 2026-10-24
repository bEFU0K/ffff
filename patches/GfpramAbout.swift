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

// MARK: - «О GFPGRAM»: описание клиента. 5 нажатий подряд на «Версия» открывают админ-меню.

private func gfpramAboutEntries(adminUnlocked: Bool) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.hero(-2, "GFPGRAM", "Клиент Telegram с режимом призрака, анти-удалением и Premium-функциями"))

    entries.append(.header(0, "ЧТО УМЕЕТ КЛИЕНТ"))
    entries.append(.feature(1, "Режим призрака", "Не читает чаты, не показывает «печатает» и «в сети», не отмечает истории и «прослушано».", 0, 3, 1))
    entries.append(.feature(2, "Анти-удаление", "Удалённые сообщения остаются с маркером 🗑, изменённые с ✏️.", 0, 7, 1))
    entries.append(.feature(3, "История правок", "Все версии изменённого сообщения в отдельном окне.", 0, 9, 1))
    entries.append(.feature(4, "Обход запретов", "Копирование и пересылка из закрытых чатов и каналов.", 0, 5, 1))
    entries.append(.feature(5, "Иконки и шрифты", "Свои иконки приложения, в том числе Premium, и 10 шрифтов интерфейса.", 0, 10, 1))

    entries.append(.header(100, "PREMIUM"))
    entries.append(.feature(101, "Автоответчик и слова-триггеры", "Отвечают сами, когда вас нет в сети или ночью. Авто-реакции и заглушка при упоминании.", 0, 6, 1))
    entries.append(.feature(102, "Значки и бэкап", "Значок «#», ⭐ рядом с именем, бэкап данных аккаунта.", 0, 4, 1))

    entries.append(.header(200, "О ПРИЛОЖЕНИИ"))
    entries.append(.action(201, "Версия", AyuSettings.version, 1))
    entries.append(.iconAction(202, "Тех-поддержка", "@" + AyuPremium.supportUsername, 4, 101))
    if adminUnlocked {
        entries.append(.action(203, "Админ-панель", "", 2))
    }
    entries.append(.footer(204, "GFPGRAM сделан на основе Telegram-iOS. Значки «#» и описания работают только на вашем устройстве, другие пользователи их не видят."))
    return entries
}

public func gfpramAboutController(context: AccountContext) -> ViewController {
    AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?
    var taps = 0
    var lastTap: Double = 0

    let openAdmin: () -> Void = {
        if AyuSettings.adminUnlocked {
            pushImpl?(gfpramAdminController(context: context))
            return
        }
        // Без ключа админ-панель не открывается: иначе любой, кто нажал 5 раз, мог бы выдавать себе Premium
        presentImpl?(promptController(context: context, text: "Введите ключ", value: nil, placeholder: "", apply: { value in
            guard let value = value else {
                return
            }
            if AyuSettings.verifyAdminCode(value) {
                refresh.set(true)
                pushImpl?(gfpramAdminController(context: context))
            }
        }))
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            switch kind {
            case 1:
                let now = Date().timeIntervalSince1970
                if now - lastTap > 2.0 {
                    taps = 0
                }
                lastTap = now
                taps += 1
                if taps >= 5 {
                    taps = 0
                    openAdmin()
                }
            case 2:
                pushImpl?(gfpramAdminController(context: context))
            case 4:
                gfpramOpenSupport(context: context)
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("О GFPGRAM"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramAboutEntries(adminUnlocked: AyuSettings.adminUnlocked), style: .blocks, animateChanges: false)
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
