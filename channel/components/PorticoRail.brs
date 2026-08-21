sub init()
    m.surface = m.top.findNode("surface")
    m.collapsedBrandBed = m.top.findNode("collapsedBrandBed")
    m.symbol = m.top.findNode("symbol")
    m.wordmark = m.top.findNode("wordmark")
    m.divider = m.top.findNode("divider")
    m.itemNodes = []
    for index = 0 to 10
        item = m.top.findNode("item" + index.ToStr())
        item.visible = false
        m.itemNodes.push(item)
    end for

    m.surface.uri = "pkg:/images/ui/rail-bed-collapsed.png"
    m.collapsedBrandBed.uri = "pkg:/images/ui/brand-mark-bed.png"
    m.symbol.uri = "pkg:/images/brand/portico-symbol.png"
    m.wordmark.uri = "pkg:/images/brand/portico-wordmark.png"
end sub

sub applyViewState()
    state = m.top.viewState
    if state = invalid then return
    model = state.model
    if model = invalid or model.primaryItems = invalid or model.libraryItems = invalid or model.bottomItems = invalid then return

    width = 80
    if state.expanded = true then width = 280
    m.surface.width = width
    m.surface.loadWidth = width
    m.surface.uri = "pkg:/images/ui/rail-bed-collapsed.png"
    if state.expanded = true then m.surface.uri = "pkg:/images/ui/rail-bed-expanded.png"
    m.collapsedBrandBed.visible = not state.expanded
    m.symbol.visible = not state.expanded
    m.wordmark.visible = state.expanded
    m.divider.width = width - 32

    for each item in m.itemNodes
        item.visible = false
    end for
    nextIndex = renderSection(model.primaryItems, 0, 0, 68, 0, state)
    nextIndex = renderSection(model.libraryItems, 357, model.primaryItems.count(), 66, nextIndex, state)
    renderSection(model.bottomItems, 812, model.primaryItems.count() + model.libraryItems.count(), 66, nextIndex, state)
end sub

function renderSection(sectionItems as object, baseY as integer, focusOffset as integer, itemPitch as integer, nodeOffset as integer, state as object) as integer
    for index = 0 to sectionItems.count() - 1
        if nodeOffset + index >= m.itemNodes.count() then return m.itemNodes.count()
        sourceModel = sectionItems[index]
        displayModel = {
            id: sourceModel.id,
            route: sourceModel.route,
            label: sourceModel.label,
            iconId: sourceModel.iconId,
            selected: (focusOffset + index) = state.selectedIndex
        }
        item = m.itemNodes[nodeOffset + index]
        item.model = displayModel
        item.expanded = state.expanded
        item.focused = (focusOffset + index) = state.focusedIndex
        item.translation = [0, baseY + (index * itemPitch)]
        item.visible = true
    end for
    return nodeOffset + sectionItems.count()
end function
