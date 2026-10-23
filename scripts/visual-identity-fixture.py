"""Open the actual compiled identity component in synthetic, credential-free state."""
import hashlib
import sys
import zipfile
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
state = sys.argv[3] if len(sys.argv) > 3 else "identity"
assert state in ("identity", "frontdoor", "hosted-form", "local-form", "factor", "recovery", "required-factor", "required-password")
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
 session.addFields({ busy: false, error: "", note: "", hasRecovery: false, hasAccount: false, recovery: { kind: "changed", serverName: "Basement server", origin: "http://192.168.1.20:32500", serverId: "fixture-only" } })
 m.global.addFields({ textScale: 1.0, reduceMotion: false, region: "", session: session })
 screen = m.top.createChild("ScreenServerIdentity")
 screen.callFunc("enter")
 print "VISUAL_COMPONENT_READY: actual compiled screen; synthetic state; no auth/transport"
end sub
'''
if state == "frontdoor":
    scene = scene.replace('"ScreenServerIdentity"', '"ScreenActivation"')
credential = state in ("hosted-form", "local-form", "factor", "recovery", "required-factor", "required-password")
if credential:
    scene = '''sub init()
 m.top.backgroundUri = ""
 m.top.backgroundColor = "0x071018FF"
 session = CreateObject("roSGNode", "VisualCredentialSession")
 session.connection = { signIn: "local", serverName: "Portico demo", origin: "http://192.168.1.20:32500", pin: { serverId: "fixture-only", publicKey: "fixture-only" } }
 session.accountCredentialState = { phase: "idle" }
 m.global.addFields({ textScale: 1.0, reduceMotion: false, region: "", session: session })
 screen = m.top.createChild("ScreenTVCredentials")
 screen.kind = "KIND"
 screen.callFunc("enter")
 EXTRA
 print "VISUAL_COMPONENT_READY: actual compiled screen; synthetic state; no auth/transport"
end sub
'''.replace('KIND', 'local' if state == 'local-form' else 'portico')
    extra = ''
    if state in ('factor', 'recovery'):
        extra = 'session.accountCredentialState = { phase: "challenge", expiresAt: "2099-01-01T00:00:00Z" }'
    scene = scene.replace('EXTRA', extra)
    if state.startswith('required-'):
        kind = 'password-change' if state == 'required-password' else 'two-step-setup'
        info = '{ kind: "' + kind + '", serverName: "Portico demo", username: "nana_r", origin: "http://192.168.1.20:32500", url: "http://192.168.1.20:32500/settings/profile", address: "192.168.1.20:32500/settings/profile", portico: false }'
        scene = scene.replace('screen = m.top.createChild("ScreenTVCredentials")', 'session.requiredSignIn = ' + info + '\n screen = m.top.createChild("ScreenTVRequiredSignIn")')
        scene = scene.replace('screen.kind = "portico"', '')
    # The capture fixture owns these no-op callbacks. No product component or transport is edited.
    session_xml = '''<component name="VisualCredentialSession" extends="Node"><interface>
<field id="busy" type="boolean" value="false"/><field id="error" type="string" value=""/>
<field id="username" type="string" value=""/><field id="phase" type="string" value="signedOut"/>
<field id="directStep" type="string" value=""/><field id="directFailure" type="assocarray"/>
<field id="requiresTwoStepSetup" type="boolean" value="false"/>
<field id="requiredSignIn" type="assocarray"/>
<field id="connection" type="assocarray"/><field id="accountCredentialState" type="assocarray"/>
<function name="beginAccountCredentials"/><function name="submitAccountCredentials"/>
<function name="cancelAccountCredentials"/><function name="cancelStep"/>
</interface><script type="text/brightscript" uri="pkg:/components/VisualCredentialSession.brs"/></component>'''
    session_brs = '''sub beginAccountCredentials()
end sub
sub submitAccountCredentials(input as object)
end sub
sub cancelAccountCredentials()
end sub
sub cancelStep()
end sub
'''
with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as fixture:
    for entry in original.infolist():
        if entry.filename != "source/Main.brs":
            fixture.writestr(entry, original.read(entry))
    fixture.writestr("source/Main.brs", main)
    fixture.writestr("components/VisualIdentityScene.xml", '<component name="VisualIdentityScene" extends="Scene"><script type="text/brightscript" uri="pkg:/components/VisualIdentityScene.brs"/></component>')
    fixture.writestr("components/VisualIdentityScene.brs", scene)
    if credential:
        fixture.writestr("components/VisualCredentialSession.xml", session_xml)
        fixture.writestr("components/VisualCredentialSession.brs", session_brs)
print("Component-only visual fixture; every product component byte is unchanged.")
print("Product ZIP SHA256:", hashlib.sha256(source.read_bytes()).hexdigest())
print("Fixture ZIP SHA256:", hashlib.sha256(destination.read_bytes()).hexdigest())
