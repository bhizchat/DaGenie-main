//  FlowLayout.swift – adaptive wrapping layout using SwiftUI `Layout` protocol (iOS 16+)
import SwiftUI

@available(iOS 16.0, *)
struct FlowLayout<Data: RandomAccessCollection, Content: View>: Layout where Data.Element: Hashable {
    let items: Data
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat
    let content: (Data.Element) -> Content

    init(items: Data,
         itemSpacing: CGFloat = 8,
         rowSpacing: CGFloat = 8,
         @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.itemSpacing = itemSpacing
        self.rowSpacing = rowSpacing
        self.content = content
    }

    // MARK: Layout protocol
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let subSize = subview.sizeThatFits(.unspecified)
            if rowWidth + subSize.width > maxWidth {
                // move to next row
                maxRowWidth = max(maxRowWidth, rowWidth)
                totalHeight += rowHeight + rowSpacing
                rowWidth = subSize.width + itemSpacing
                rowHeight = subSize.height
            } else {
                rowWidth += subSize.width + itemSpacing
                rowHeight = max(rowHeight, subSize.height)
            }
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subSize = subview.sizeThatFits(.unspecified)
            if x + subSize.width > bounds.maxX {
                // wrap to next row
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(subSize))
            x += subSize.width + itemSpacing
            rowHeight = max(rowHeight, subSize.height)
        }
    }


    @ViewBuilder func callAsFunction() -> some View {
        ForEach(items, id: \.self) { item in
            content(item)
        }
    }

    }
