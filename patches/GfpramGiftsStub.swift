import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

/// Заглушка: ставится вместо GfpramGifts.swift, если в этой версии Telegram-iOS нет нужного API коллекций подарков
/// (apply_patches.py пишет причину в лог сборки).
public func gfpramGiftsController(context: AccountContext) -> ViewController {
    let arguments = GfpramArguments(toggle: { _, _ in
    }, perform: { _ in
    })
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Подарки"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries: [GfpramEntry] = [
            .header(0, "ПОДАРКИ"),
            .footer(1, "В этой сборке Telegram-iOS нет подходящего API коллекций подарков, поэтому массовое добавление недоступно. Причина записана в логе сборки (patch-report.txt).")
        ]
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
