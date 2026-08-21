sub init()
    m.surface = m.top.findNode("surface")
    m.title = [m.top.findNode("title0"), m.top.findNode("title1")]
    m.meta = m.top.findNode("meta")
    m.summary = [m.top.findNode("summary0"), m.top.findNode("summary1"), m.top.findNode("summary2")]
    for each line in m.title
        line.font = PorticoFont("600", 24)
        line.color = "#F4F7FA"
    end for
    m.meta.font = PorticoFont("500", 18)
    m.meta.color = "#8F9BA6"
    for each line in m.summary
        line.font = PorticoFont("400", 18)
        line.color = "#C7D0D8"
    end for
end sub

sub render()
    model = m.top.model
    if model = invalid then return
    resource = m.top.tileKind = "resource"
    width = 250
    height = 150
    titleSize = 24
    titleLineHeight = 30
    summarySize = 18
    if resource
        width = 848
        height = 144
        titleSize = 25
        titleLineHeight = 31
        summarySize = 19
    end if
    m.top.focusable = true
    m.surface.width = width
    m.surface.height = height
    m.surface.loadWidth = width
    m.surface.loadHeight = height
    prefix = "browse-facet"
    if resource then prefix = "browse-resource"
    if m.top.focused then prefix = prefix + "-focus" else prefix = prefix + "-idle"
    m.surface.uri = "pkg:/images/ui/" + prefix + ".png"

    padding = 20
    contentWidth = width - (padding * 2)
    for each line in m.title
        line.font = PorticoFont("600", titleSize)
    end for
    for each line in m.summary
        line.font = PorticoFont("400", summarySize)
    end for
    titleLines = PorticoBreakText(model.title, contentWidth, titleSize, "600", 2)
    for index = 0 to m.title.count() - 1
        m.title[index].translation = [padding, 18 + (index * titleLineHeight)]
        m.title[index].width = contentWidth
        m.title[index].height = titleLineHeight
        m.title[index].visible = index < titleLines.count()
        m.title[index].text = ""
        if index < titleLines.count() then m.title[index].text = titleLines[index]
    end for
    metaY = 26 + (titleLines.count() * titleLineHeight)
    m.meta.translation = [padding, metaY]
    m.meta.width = contentWidth
    m.meta.height = 24
    m.meta.text = ""
    if model.meta <> invalid then m.meta.text = Left(model.meta.ToStr(), 80)
    summaryValue = ""
    if model.summary <> invalid then summaryValue = model.summary.ToStr()
    maximumSummaryLines = 3
    if resource then maximumSummaryLines = 2
    summaryLines = PorticoBreakText(summaryValue, contentWidth, summarySize, "400", maximumSummaryLines)
    for index = 0 to m.summary.count() - 1
        m.summary[index].translation = [padding, metaY + 33 + (index * 26)]
        m.summary[index].width = contentWidth
        m.summary[index].height = 26
        m.summary[index].visible = index < summaryLines.count()
        m.summary[index].text = ""
        if index < summaryLines.count() then m.summary[index].text = summaryLines[index]
    end for
end sub
