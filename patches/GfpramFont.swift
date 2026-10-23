import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private func gfpramFontEntries() -> [GfpramEntry] {
    let current = AyuSettings.fontFamily
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ШРИФТ ИНТЕРФЕЙСА"))
    for (index, item) in AyuFont.families.enumerated() {
        entries.append(.action(Int32(1 + index), item.title, item.family == current ? "✓" : "", Int32(index)))
    }
    entries.append(.footer(100, "Шрифт меняется во всём приложении и применяется после перезапуска. Если в шрифте нет нужных букв, они остаются системными. Доступно всем, без Premium."))
    return entries
}

public func gfpramFontController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            let index = Int(kind)
            guard index >= 0 && index < AyuFont.families.count else {
                return
            }
            let item = AyuFont.families[index]
            if AyuSettings.fontFamily == item.family {
                return
            }
            AyuSettings.fontFamily = item.family
            refresh.set(true)
            presentImpl?(gfpramAlert(context: context, title: "Шрифт: " + item.title, text: "Полностью закройте приложение (смахните его из переключателя) и откройте снова. Тогда шрифт применится везде."))
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(""), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        var list = gfpramFontEntries()
        list.insert(.hero(-1, "Шрифт приложения", "Выберите шрифт для всего интерфейса. Применится после перезапуска."), at: 0)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: list, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
