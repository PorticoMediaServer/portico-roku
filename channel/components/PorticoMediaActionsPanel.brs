sub init()
    m.title = m.top.findNode("title")
    m.actions = [m.top.findNode("action0"), m.top.findNode("action1"), m.top.findNode("action2")]
    m.title.font = PorticoFont("600", 24)
    m.title.color = "#F4F7FA"
end sub

sub render()
    model = m.top.model
    if model = invalid or Type(model) <> "roAssociativeArray" then return
    m.title.text = Left(model.title.ToStr(), 80)
    source = model.actions
    if source = invalid or GetInterface(source, "ifArray") = invalid then source = []
    for index = 0 to m.actions.count() - 1
        node = m.actions[index]
        node.visible = index < source.count()
        node.focused = node.visible and index = m.top.focusedAction
        if node.visible then node.model = source[index]
    end for
    m.top.focusSemanticId = "media-action.unavailable"
    if m.top.focusedAction >= 0 and m.top.focusedAction < source.Count()
        actionId = "unknown"
        if source[m.top.focusedAction].id <> invalid then actionId = source[m.top.focusedAction].id.ToStr()
        m.top.focusSemanticId = "media-action." + actionId
    end if
    height = 82 + (source.count() * 68)
    if height < 150 then height = 150
    m.top.findNode("surface").height = height
    m.top.findNode("shadow").height = height + 20
end sub
