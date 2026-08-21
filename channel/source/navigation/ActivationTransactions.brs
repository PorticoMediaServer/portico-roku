function PorticoActivationTransactionsCreate() as object
    return {activeKey: "", active: invalid, sequence: 0, viewerEpoch: -1, routeEpoch: -1, state: "idle", coalescedCount: 0}
end function

' One physical OK press owns at most one semantic activation. Roku may repeat a
' key-down notification; release closes the transaction and permits a new press.
function PorticoActivationBegin(transactions as dynamic, semanticId as string, kind as string, viewerEpoch as integer, routeEpoch as integer) as dynamic
    if transactions = invalid or semanticId = "" or kind = "" then return invalid
    key = viewerEpoch.ToStr() + ":" + routeEpoch.ToStr() + ":" + kind + ":" + semanticId
    if transactions.activeKey = key
        transactions.coalescedCount = transactions.coalescedCount + 1
        return invalid
    end if
    if transactions.activeKey <> "" then return invalid
    transactions.sequence = transactions.sequence + 1
    transactions.activeKey = key
    transactions.viewerEpoch = viewerEpoch
    transactions.routeEpoch = routeEpoch
    transaction = {id: key + ":" + transactions.sequence.ToStr(), sequence: transactions.sequence, semanticId: semanticId, kind: kind, viewerEpoch: viewerEpoch, routeEpoch: routeEpoch, state: "requested"}
    transactions.active = transaction
    transactions.state = "requested"
    return transaction
end function

function PorticoActivationMarkCommitting(transactions as dynamic, transaction as dynamic, viewerEpoch as integer, routeEpoch as integer) as boolean
    if not PorticoActivationIsCurrent(transactions, transaction, viewerEpoch, routeEpoch) then return false
    if transactions.state = "committing" then return true
    if transactions.state <> "requested" then return false
    transactions.state = "committing"
    transactions.active.state = "committing"
    return true
end function

function PorticoActivationCommit(transactions as dynamic, transaction as dynamic, viewerEpoch as integer, routeEpoch as integer) as boolean
    if not PorticoActivationIsCurrent(transactions, transaction, viewerEpoch, routeEpoch) then return false
    if transactions.state <> "committing" then return false
    transactions.state = "committed"
    transactions.active.state = "committed"
    return true
end function

function PorticoActivationIsCurrent(transactions as dynamic, transaction as dynamic, viewerEpoch as integer, routeEpoch as integer) as boolean
    if transactions = invalid or transaction = invalid or transactions.active = invalid then return false
    if transactions.active.id <> transaction.id then return false
    if transaction.viewerEpoch <> viewerEpoch or transaction.routeEpoch <> routeEpoch then return false
    return transactions.state = "requested" or transactions.state = "committing"
end function

sub PorticoActivationCancel(transactions as dynamic)
    if transactions = invalid then return
    if transactions.active <> invalid then transactions.active.state = "cancelled"
    transactions.state = "cancelled"
    transactions.activeKey = ""
end sub

sub PorticoActivationRelease(transactions as dynamic)
    if transactions = invalid then return
    if transactions.state = "requested" or transactions.state = "committing" then PorticoActivationCancel(transactions)
    transactions.activeKey = ""
    transactions.active = invalid
    transactions.state = "idle"
end sub

sub PorticoActivationFence(transactions as dynamic, viewerEpoch as integer, routeEpoch as integer)
    if transactions = invalid then return
    if (transactions.viewerEpoch <> viewerEpoch or transactions.routeEpoch <> routeEpoch) and (transactions.state = "requested" or transactions.state = "committing") then PorticoActivationCancel(transactions)
end sub
