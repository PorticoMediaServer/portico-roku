sub init()
    m.heading = m.top.findNode("heading")
    m.reserved = m.top.findNode("reserved")
    ' Reserved rows protect the authoritative layout while data resolves, but
    ' do not introduce a new visible placeholder treatment.
    m.reserved.opacity = 0.0
    m.cards = []
    m.reservedSlots = []
    for index = 0 to 6
        m.cards.push(m.top.findNode("card" + index.ToStr()))
        slot = m.top.findNode("reserved" + index.ToStr())
        slot.translation = [index * 232, 52]
        PorticoRectangle(slot, [0, 0], 202, 321, "#151F29")
        PorticoRectangle(slot, [0, 334], 154, 18, "#151F29")
        PorticoRectangle(slot, [0, 363], 104, 14, "#101820")
        m.reservedSlots.push(slot)
    end for
    m.heading.font = PorticoFont("600", 30)
    m.heading.color = "#F4F7FA"
    m.heading.vertAlign = "top"
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    headingY = 0
    if m.top.compensation <> invalid and m.top.compensation.sectionHeadingY <> invalid then headingY = m.top.compensation.sectionHeadingY
    m.heading.translation = [0, headingY]
    m.heading.text = homeShelfText(model.title, "")
    m.reserved.visible = false
    for each card in m.cards
        card.visible = false
        card.focused = false
    end for

    items = homeShelfArray(model.items)
    if items.count() = 0
        ' Empty, unresolved, and failed advertised rows keep their position for
        ' the active visit without introducing visible placeholder or status UI.
        ' The product frame owns terminal page errors after recovery is exhausted.
        m.reserved.visible = true
        return
    end if

    firstVisible = 0
    if m.top.focusedIndex >= 7 then firstVisible = m.top.focusedIndex - 6
    for visibleIndex = 0 to m.cards.count() - 1
        itemIndex = firstVisible + visibleIndex
        if itemIndex >= items.count() then exit for
        card = m.cards[visibleIndex]
        card.translation = [visibleIndex * 232, 52]
        card.model = items[itemIndex]
        card.compensation = m.top.compensation
        card.focused = m.top.focused and itemIndex = m.top.focusedIndex
        card.visible = true
    end for
end sub

function homeShelfArray(value as dynamic) as object
    if value <> invalid and GetInterface(value, "ifArray") <> invalid then return value
    return []
end function

function homeShelfText(value as dynamic, fallback as string) as string
    if value = invalid or value.ToStr().Trim() = "" then return fallback
    return value.ToStr()
end function
