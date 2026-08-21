function PorticoFont(weight as string, size as integer) as object
    font = CreateObject("roSGNode", "Font")
    font.uri = "pkg:/fonts/manrope-" + weight + ".ttf"
    font.size = size
    return font
end function

function PorticoLabel(parent as object, text as string, translation as object, width as integer, height as integer, size as integer, weight as string, color as string) as object
    label = parent.CreateChild("Label")
    label.text = text
    label.translation = translation
    label.width = width
    label.height = height
    label.font = PorticoFont(weight, size)
    label.color = color
    label.vertAlign = "top"
    return label
end function

function PorticoPoster(parent as object, uri as string, translation as object, width as integer, height as integer, displayMode = "scaleToFill" as string) as object
    poster = parent.CreateChild("Poster")
    poster.translation = translation
    poster.width = width
    poster.height = height
    poster.loadWidth = width
    poster.loadHeight = height
    poster.loadDisplayMode = displayMode
    poster.visible = false
    if uri <> invalid
        poster.visible = true
        poster.uri = uri
    end if
    return poster
end function

function PorticoGlyphWidths(weight as string) as object
    if weight = "700"
        return [400,721,934,1863,1256,1801,1337,521,906,906,929,1143,607,840,607,866,
            1316,876,1191,1163,1217,1172,1243,1067,1225,1243,685,687,1275,1500,1275,1106,
            1827,1341,1262,1477,1401,1170,1047,1464,1443,561,1001,1294,1067,1710,1436,1499,
            1277,1499,1320,1315,1213,1440,1281,1951,1311,1223,1327,847,866,847,1361,1320,
            1077,1152,1232,1151,1234,1204,756,1232,1251,561,577,1076,561,1798,1251,1236,
            1232,1234,798,1083,866,1251,1106,1605,1108,1119,1067,898,601,898,1432]
    else if weight = "600"
        return [400,689,884,1855,1230,1801,1325,489,888,888,911,1147,581,840,573,835,
            1284,844,1174,1144,1205,1167,1243,1046,1203,1243,656,661,1259,1500,1259,1087,
            1821,1317,1250,1461,1381,1160,1033,1446,1419,529,977,1259,1051,1701,1413,1481,
            1254,1481,1301,1287,1207,1428,1257,1925,1278,1186,1294,836,835,836,1353,1320,
            1045,1139,1216,1137,1217,1193,741,1216,1230,529,551,1048,529,1764,1230,1219,
            1216,1217,773,1072,845,1230,1076,1581,1090,1097,1065,878,569,878,1396]
    end if
    return [400,627,784,1841,1178,1803,1303,427,852,852,873,1153,531,840,507,775,
        1220,780,1140,1106,1179,1155,1241,1004,1161,1241,598,611,1229,1500,1229,1047,
        1807,1267,1226,1431,1343,1140,1007,1410,1369,467,927,1187,1021,1681,1369,1447,
        1208,1447,1261,1233,1193,1404,1207,1871,1212,1112,1228,814,775,814,1339,1320,
        979,1111,1184,1107,1185,1169,709,1184,1188,467,501,992,467,1696,1188,1183,
        1184,1185,721,1050,801,1188,1016,1535,1054,1055,1059,839,507,839,1324]
end function

function PorticoTextWidth(value as string, weight as string, size as integer) as integer
    widths = PorticoGlyphWidths(weight)
    units = 0
    for characterIndex = 1 to Len(value)
        code = Asc(Mid(value, characterIndex, 1))
        if code >= 32 and code <= 126
            units = units + widths[code - 32]
        else
            units = units + 1100
        end if
    end for
    return Int((units * size) / 2000)
end function

function PorticoFitPrefix(value as string, weight as string, width as integer, size as integer) as integer
    fitting = 0
    for characterIndex = 1 to Len(value)
        candidate = Left(value, characterIndex)
        if PorticoTextWidth(candidate, weight, size) <= width
            fitting = characterIndex
        else
            exit for
        end if
    end for
    if fitting = 0 then fitting = 1
    return fitting
end function

sub PorticoAppendEllipsis(lines as object, weight as string, width as integer, size as integer)
    if lines = invalid or lines.count() = 0 then return
    lineIndex = lines.count() - 1
    value = lines[lineIndex]
    while Len(value) > 0 and PorticoTextWidth(value + "...", weight, size) > width
        value = Left(value, Len(value) - 1)
    end while
    lines[lineIndex] = value + "..."
end sub

function PorticoWords(value as string) as object
    words = []
    currentWord = ""
    for characterIndex = 1 to Len(value)
        character = Mid(value, characterIndex, 1)
        isWhitespace = character = " " or character = Chr(9) or character = Chr(10) or character = Chr(13)
        if isWhitespace
            if currentWord <> ""
                words.push(currentWord)
                currentWord = ""
            end if
        else
            currentWord = currentWord + character
        end if
    end for
    if currentWord <> "" then words.push(currentWord)
    return words
end function

function PorticoBreakText(value as dynamic, width as integer, size as integer, weight as string, maxLines as integer) as object
    lines = []
    if value = invalid or maxLines <= 0 then return lines
    cleanValue = value.ToStr()
    if cleanValue = "" then return lines

    words = PorticoWords(cleanValue)
    if words.count() = 0 then return lines
    currentLine = ""
    for wordIndex = 0 to words.count() - 1
        remainingWord = words[wordIndex]
        while Len(remainingWord) > 0
            candidate = remainingWord
            if currentLine <> "" then candidate = currentLine + " " + remainingWord
            if PorticoTextWidth(candidate, weight, size) <= width
                currentLine = candidate
                remainingWord = ""
            else if currentLine <> ""
                lines.push(currentLine)
                currentLine = ""
                if lines.count() = maxLines
                    PorticoAppendEllipsis(lines, weight, width, size)
                    return lines
                end if
            else
                prefixLength = PorticoFitPrefix(remainingWord, weight, width, size)
                lines.push(Left(remainingWord, prefixLength))
                remainingWord = Mid(remainingWord, prefixLength + 1)
                if lines.count() = maxLines and (Len(remainingWord) > 0 or wordIndex < words.count() - 1)
                    PorticoAppendEllipsis(lines, weight, width, size)
                    return lines
                end if
            end if
        end while
    end for

    if currentLine <> "" then lines.push(currentLine)
    return lines
end function

sub PorticoRenderLines(parent as object, lines as object, translation as object, width as integer, lineHeight as integer, size as integer, weight as string, color as string)
    if lines = invalid then return
    for index = 0 to lines.count() - 1
        line = PorticoLabel(parent, lines[index], [translation[0], translation[1] + (index * lineHeight)], width, lineHeight, size, weight, color)
        line.maxLines = 1
    end for
end sub

function PorticoRectangle(parent as object, translation as object, width as integer, height as integer, color as string, opacity = 1.0 as float) as object
    rectangle = parent.CreateChild("Rectangle")
    rectangle.translation = translation
    rectangle.width = width
    rectangle.height = height
    rectangle.color = color
    rectangle.opacity = opacity
    return rectangle
end function
