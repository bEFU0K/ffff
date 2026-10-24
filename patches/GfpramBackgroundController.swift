import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - «Фон клиента»: свой фон (фото или GIF) под всеми экранами

private func gfpramBackgroundEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ФОН КЛИЕНТА"))
    entries.append(.action(1, "Выбрать фото или GIF", GfpramBackground.kindTitle, 1))
    if GfpramBackground.isEnabled {
        entries.append(.action(2, "Размытие", GfpramBackground.blurTitle, 2))
        entries.append(.action(3, "Затемнение", GfpramBackground.dimTitle, 3))
        entries.append(.toggle(4, "Прозрачные экраны", "gfpBgTransparent", GfpramBackground.transparentScreens))
        entries.append(.action(5, "Убрать фон", "", 4))
    }
    entries.append(.toggle(7, "Градиент на экране звонка", "gfpSkinCalls", GfpramSkin.callsEnabled))
    entries.append(.footer(6, "Фон виден за списком чатов, контактами и настройками. Лучше всего работает в тёмной теме. Чат остаётся со своими обоями, просмотр фото и видео, звонки и экран пароля остаются тёмными. GIF проигрывается плавно, а при включённом в iOS «Уменьшении движения» остаётся картинкой. Если какой-то экран остался чёрным, выключите «Прозрачные экраны», фон останется только там, где он виден."))
    return entries
}

public func gfpramBackgroundController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)

    let arguments = GfpramArguments(
        toggle: { key, value in
            if key == "gfpBgTransparent" {
                GfpramBackground.transparentScreens = value
            } else if key == "gfpSkinCalls" {
                GfpramSkin.callsEnabled = value
            }
            refresh.set(true)
        },
        perform: { kind in
            switch kind {
            case 1:
                GfpramBackground.pickImage(completion: { _ in
                    refresh.set(true)
                })
            case 2:
                GfpramBackground.nextBlur()
                refresh.set(true)
            case 3:
                GfpramBackground.nextDim()
                refresh.set(true)
            case 4:
                GfpramBackground.clear()
                refresh.set(true)
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фон клиента"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramBackgroundEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    gfpramAnimateAppear(controller)
    return controller
}
