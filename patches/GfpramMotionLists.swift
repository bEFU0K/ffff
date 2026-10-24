import Foundation
import UIKit
import Display
import SwiftSignalKit
import ItemListUI

/// Волна появления строк в экранах GFPGRAM.
func gfpramAnimateAppear(_ controller: ItemListController) {
    //GFP_STAGGER_BEGIN
    let _ = (controller.ready.get() |> take(1) |> deliverOnMainQueue).start(next: { [weak controller] _ in
        DispatchQueue.main.async {
            guard let controller = controller else {
                return
            }
            var nodes: [ListViewItemNode] = []
            controller.forEachItemNode { node in
                nodes.append(node)
            }
            nodes.sort { $0.frame.minY < $1.frame.minY }
            GfpramMotion.staggerIn(nodes.map { $0.view })
        }
    })
    //GFP_STAGGER_END
}
