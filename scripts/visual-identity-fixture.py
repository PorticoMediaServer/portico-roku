"""Open the actual compiled identity component in synthetic, credential-free state."""
import hashlib
import sys
import zipfile
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
main = '''sub main(args as dynamic)
 screen = CreateObject("roSGScreen")
 port = CreateObject("roMessagePort")
 screen.setMessagePort(port)
 screen.createScene("VisualIdentityScene")
 screen.show()
 while true
  event = wait(0, port)
  if Type(event) = "roSGScreenEvent" and event.isScreenClosed() then return
 end while
end sub
'''
scene = '''sub init()
 m.top.backgroundUri = ""
 m.top.backgroundColor = "0x071018FF"
 session = CreateObject("roSGNode", "Node")
 session.addFields({ busy: false, recovery: { kind: "changed", serverName: "Basement server", origin: "http://192.168.1.20:32500", serverId: "fixture-only" } })
 m.global.addFields({ textScale: 1.0, reduceMotion: false, region: "", session: session })
 screen = m.top.createChild("ScreenServerIdentity")
 screen.callFunc("enter")
 print "VISUAL_IDENTITY_READY: actual compiled ScreenServerIdentity; synthetic state; no auth/transport"
end sub
'''
with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as fixture:
    for entry in original.infolist():
        if entry.filename != "source/Main.brs":
            fixture.writestr(entry, original.read(entry))
    fixture.writestr("source/Main.brs", main)
    fixture.writestr("components/VisualIdentityScene.xml", '<component name="VisualIdentityScene" extends="Scene"><script type="text/brightscript" uri="pkg:/components/VisualIdentityScene.brs"/></component>')
    fixture.writestr("components/VisualIdentityScene.brs", scene)
print("Component-only visual fixture; every product component byte is unchanged.")
print("Product ZIP SHA256:", hashlib.sha256(source.read_bytes()).hexdigest())
print("Fixture ZIP SHA256:", hashlib.sha256(destination.read_bytes()).hexdigest())
