#!/usr/bin/env python3
"""Install a verified private IPA from the user's actual Mac. Never create signing assets."""
import argparse,datetime,fnmatch,hashlib,json,plistlib,subprocess,tempfile,zipfile
from pathlib import Path

def run(args):
    return subprocess.run(args,check=True,capture_output=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa',type=Path)
    parser.add_argument('--check-only',action='store_true',help='Validate archive/signature/profile without querying devices or installing')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bound-delta-install-') as scratch:
        root=Path(scratch)
        with zipfile.ZipFile(args.ipa) as archive:
            for name in archive.namelist():
                if name.startswith('/') or '..' in Path(name).parts: raise ValueError('Unsafe archive path')
        run(['ditto','-x','-k',str(args.ipa.resolve()),str(root)])
        apps=list((root/'Payload').glob('*.app'))
        if len(apps)!=1: raise ValueError('Expected one app')
        app=apps[0]
        run(['codesign','--verify','--deep','--strict','-R=anchor apple generic',str(app)])
        profile=plistlib.loads(run(['security','cms','-D','-i',str(app/'embedded.mobileprovision')]).stdout)
        info=plistlib.loads((app/'Info.plist').read_bytes())
        signed=plistlib.loads(run(['codesign','-d','--entitlements',':-',str(app)]).stdout)
        run(['codesign','-d','--extract-certificates='+str(root/'signer'),str(app)])
        certificate=(root/'signer0').read_bytes()
        if certificate not in profile.get('DeveloperCertificates',[]): raise ValueError('Signer certificate not in profile')
        prefix=profile['ApplicationIdentifierPrefix'][0]
        expected=prefix+'.'+info['CFBundleIdentifier']
        if info['CFBundleIdentifier']!='com.evanvonessen.bound.deltaprototype': raise ValueError('Wrong app identifier')
        if not fnmatch.fnmatchcase(expected,profile['Entitlements']['application-identifier']): raise ValueError('Profile does not cover app')
        if signed.get('application-identifier')!=expected or signed.get('com.apple.developer.team-identifier')!=profile['TeamIdentifier'][0]: raise ValueError('Entitlements mismatch')
        if profile['ExpirationDate']<=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None): raise ValueError('Profile expired')
        registered=set(profile.get('ProvisionedDevices',[]))
        if not registered: raise ValueError('No registered-device coverage')
        print('App signature and embedded registered-device profile verified.')
        if args.check_only:return
        devicesJSON=root/'devices.json'
        run(['xcrun','devicectl','list','devices','--json-output',str(devicesJSON)])
        devices=json.loads(devicesJSON.read_text()).get('result',{}).get('devices',[])
        eligible=[]
        for device in devices:
            hardware=device.get('hardwareProperties',{})
            connection=device.get('connectionProperties',{})
            if hardware.get('reality')=='physical' and hardware.get('udid') in registered and connection.get('tunnelState')=='connected':
                eligible.append(device)
        if len(eligible)!=1:
            raise ValueError('Connect the previously registered iPhone to your own Mac and unlock/trust that Mac. This IPA cannot install on an unregistered phone; no device is registered by this tool.')
        run(['xcrun','devicectl','device','install','app','--device',eligible[0]['identifier'],str(app)])
        print('Bound Delta installed. Open it on your iPhone. Developer Mode must already be enabled.')

if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError,subprocess.CalledProcessError) as error:
        if isinstance(error,subprocess.CalledProcessError):
            print('Could not complete validation/install. Check that your Mac has a compatible Xcode, the iPhone is trusted/unlocked, and Developer Mode is enabled. No signing assets were created.')
        else:print(str(error))
        raise SystemExit(1)
