"""Real Debug simulator frames, source data unchanged, no release publication."""
from pathlib import Path
import base64, hashlib, json, os, re, subprocess, time

def run(*args, timeout=30, check=True):
    return subprocess.run(args,check=check,timeout=timeout,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT).stdout.strip()

destination=os.environ['TEST_DESTINATION']
if not destination.startswith('platform=iOS Simulator,id='):raise SystemExit('Unexpected destination')
device=destination.split('id=',1)[1]
if not re.fullmatch(r'[A-Fa-f0-9-]{36}',device):raise SystemExit('Invalid simulator ID')
root=Path(os.environ['RUNNER_TEMP']);output=root/'GTAFreeSTEM-map-preview';output.mkdir(exist_ok=True)
app=root/'GTAFreeSTEM-derived-data/Build/Products/Debug-iphonesimulator/GTAFreeSTEM.app'
if not app.is_dir():raise SystemExit('Current candidate did not produce a native app')
verifier=root/'verify-map-native-frame'
run('xcrun','swiftc','.github/scripts/verify-native-frame.swift','-o',str(verifier),timeout=60)
inventory=json.loads(run('xcrun','simctl','list','devices','available','--json'))['devices']
match=[x for xs in inventory.values() for x in xs if x.get('udid')==device]
if len(match)!=1:raise SystemExit('Exact runner simulator missing')
if match[0]['state']=='Shutdown':run('xcrun','simctl','boot',device)
run('xcrun','simctl','bootstatus',device,'-b',timeout=120)
bundle='com.rupayonhaldar.gtafreestem'

def bundle_manifest(directory):
    return {str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(directory.rglob('*')) if path.is_file()}

# xcodebuild test has already installed this app on the same destination.
# Reuse it only when every installed file matches the exact tested product.
# A redundant install after opening Simulator can stall behind its UI attach.
expected_manifest=bundle_manifest(app)
if not expected_manifest:raise SystemExit('Built native app has no files')
installed_text=run('xcrun','simctl','get_app_container',device,bundle,'app',check=False)
installed=Path(installed_text) if installed_text.startswith('/') else None
reused=bool(installed and installed.is_dir() and bundle_manifest(installed)==expected_manifest)
if not reused:
    run('xcrun','simctl','terminate',device,bundle,check=False)
    run('xcrun','simctl','install',device,str(app),timeout=120)
    installed=Path(run('xcrun','simctl','get_app_container',device,bundle,'app'))
    if bundle_manifest(installed)!=expected_manifest:
        raise SystemExit('Installed native app does not match the tested product')
print('NATIVE_INSTALLED_PRODUCT_VERIFIED '+json.dumps(dict(files=len(expected_manifest),reusedTestedInstallation=reused)),flush=True)
run('open','-a','Simulator','--args','-CurrentDeviceUDID',device)
frames=[]

def emit_frame(name, meta):
    png=output/(name+'.png');jpg=output/(name+'.jpg')
    run('xcrun','simctl','io',device,'screenshot','--type=png',str(png),timeout=60)
    run(str(verifier),str(png),timeout=10)
    run('/usr/bin/sips','-s','format','jpeg','-s','formatOptions','76','-Z','1100',str(png),'--out',str(jpg))
    data=jpg.read_bytes()
    if len(data)>180000:raise SystemExit('Frame exceeds bounded log export')
    meta.update(name=name,commit=os.environ['CANDIDATE_SOURCE_SHA'],sha256=hashlib.sha256(data).hexdigest(),nativePngSha256=hashlib.sha256(png.read_bytes()).hexdigest(),bytes=len(data),format='jpeg',exportMaximumDimension=1100,quality=76)
    print('NATIVE_UI_CAPTURE_META '+json.dumps(meta,sort_keys=True),flush=True)
    print('NATIVE_UI_CAPTURE_BEGIN '+name,flush=True)
    encoded=base64.b64encode(data).decode()
    for start in range(0,len(encoded),100):print('NATIVE_UI_CAPTURE_DATA '+encoded[start:start+100],flush=True)
    print('NATIVE_UI_CAPTURE_END '+name,flush=True)
    return meta

try:
    for name,dark,large,extra in [
        ('ios-map-overview-light',False,False,[]),
        ('ios-map-selected-light',False,False,['-review-map-selected']),
        ('ios-map-detail-light',False,False,['-review-map-selected','-review-map-detail']),
        ('ios-map-overview-dark',True,False,[]),
        ('ios-map-selected-large-text',False,True,['-review-map-selected'])]:
        run('xcrun','simctl','ui',device,'appearance','dark' if dark else 'light')
        run('xcrun','simctl','ui',device,'content_size','accessibility-extra-large' if large else 'large')
        log=output/(name+'.stdout');err=output/(name+'.stderr')
        launched=run('xcrun','simctl','launch','--terminate-running-process','--stdout='+str(log),'--stderr='+str(err),device,bundle,'-preferredTheme','Dark' if dark else 'Light','-start-opportunities','-review-map',*extra,timeout=60)
        pid=int(launched.rsplit(': ',1)[1]);deadline=time.monotonic()+60;ready=None
        while time.monotonic()<deadline:
            os.kill(pid,0)
            if log.is_file():
                ready=re.search(r'GTA_MAP_REVIEW_READY (overview|selected|detail) venues=(\d+) mapped=(\d+) filtered=(\d+)',log.read_text(errors='replace'))
                if ready and int(ready.group(2))>0:break
            time.sleep(.5)
        else:
            print(log.read_text(errors='replace')[-3000:] if log.exists() else 'No native stdout')
            print(err.read_text(errors='replace')[-3000:] if err.exists() else 'No native stderr')
            emit_frame(name+'-not-ready',dict(mode='diagnostic-native-runtime',acceptedState=False,releaseAcceptance=False,physicalDeviceAcceptance=False))
            raise SystemExit('No actual mapped venues reached the native review screen: '+name)
        time.sleep(5)
        os.kill(pid,0)
        meta=dict(mode='normal-source-native-runtime',dark=dark,largeText=large,venues=int(ready.group(2)),mapped=int(ready.group(3)),filtered=int(ready.group(4)),selectedState='-review-map-selected' in extra,detailState='-review-map-detail' in extra,selectionEnteredByDebugFlag=bool(extra),automatedTouchInteraction=False,releaseAcceptance=False,physicalDeviceAcceptance=False)
        frames.append(emit_frame(name,meta))
finally:
    run('xcrun','simctl','terminate',device,bundle,check=False)
    run('xcrun','simctl','shutdown',device,check=False)
print('NATIVE_MAP_CAPTURE_COMPLETE '+json.dumps(dict(frames=len(frames),releaseAcceptance=False,physicalDeviceAcceptance=False)),flush=True)
