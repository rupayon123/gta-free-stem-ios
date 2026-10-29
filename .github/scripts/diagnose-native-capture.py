"""CI-only source-bound capture diagnosis. Never a substitute for reliability tests."""
from pathlib import Path
import base64
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import time
import uuid

BUNDLE = "com.rupayonhaldar.gtafreestem"
TARGET = "25df39cbd1effdef3807b58ba3403687a752587b"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"


def emit(label, **fields):
    print("CAPTURE_DIAGNOSTIC " + json.dumps(dict(label=label, **fields), sort_keys=True), flush=True)


def stop_owned_process(process):
    process.terminate()
    try:
        process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate(timeout=3)


def bounded_output(value):
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    value = value or ""
    return value if len(value) <= 6000 else value[:4500] + "\n...bounded output...\n" + value[-1500:]


def command(label, args, timeout=10, sample_timeout=False):
    started = time.monotonic()
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        output, _ = process.communicate(timeout=timeout)
        result = dict(code=process.returncode, timedOut=False, output=bounded_output(output), seconds=round(time.monotonic() - started, 3))
    except subprocess.TimeoutExpired as error:
        partial_output = bounded_output(error.output)
        if sample_timeout:
            # Sample only this diagnostic's own hung child, before terminating it.
            command(label + "-owned-command-stack", ["/usr/bin/sample", str(process.pid), "1", "1"], timeout=5)
        stop_owned_process(process)
        result = dict(code=None, timedOut=True, output=partial_output, seconds=round(time.monotonic() - started, 3))
    emit(label, **result)
    return result


def required(label, args, timeout=10):
    result = command(label, args, timeout)
    if result["code"] != 0:
        raise RuntimeError(label + " failed or timed out")
    return result["output"].strip()


def manifest(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(folder.rglob("*")) if p.is_file()}


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_OS") != "macOS":
        raise SystemExit("Diagnostic refuses to operate local/user simulators; GitHub macOS job only")
    source = Path(os.environ["APP_SOURCE_ROOT"]).resolve()
    expected = os.environ["EXPECTED_SOURCE_SHA"]
    if expected != TARGET:
        raise SystemExit("Only the reviewed 25df app is authorized for this diagnostic")
    actual = required("app-git-source", ["git", "-C", str(source), "rev-parse", "HEAD"])
    if actual != expected:
        raise SystemExit("App checkout does not match exact reviewed source")
    app = Path(os.environ["RUNNER_TEMP"]) / "GTA-diagnostic-derived/Build/Products/Debug-iphonesimulator/GTAFreeSTEM.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("GTAReleaseSourceCommit") != expected:
        raise SystemExit("Built app source identity differs")
    output = Path(os.environ["RUNNER_TEMP"]) / "GTA-capture-diagnostic"
    output.mkdir(exist_ok=True)
    verifier = output / "verify-native-frame"
    required("compile-existing-frame-verifier", ["xcrun", "swiftc", str(source / ".github/scripts/verify-native-frame.swift"), "-o", str(verifier)], 60)
    simulator_app = Path(os.environ["DEVELOPER_DIR"]) / "Applications/Simulator.app"
    if not simulator_app.is_dir():
        raise SystemExit("Exact Xcode Simulator GUI is absent")
    tooling = Path(__file__).resolve().parents[2]
    tooling_sha = required("tooling-git-source", ["git", "-C", str(tooling), "rev-parse", "HEAD"])
    if tooling_sha != os.environ.get("GITHUB_SHA"):
        raise SystemExit("Diagnostic tooling checkout differs from workflow source")
    emit("identity", appSource=actual, toolingSource=tooling_sha,
         appSourceRoot=str(source), toolingSourceRoot=str(tooling), buildConfiguration="Debug", buildVersion=info.get("CFBundleVersion"), sdk=info.get("DTSDKName"),
         imageVersion=os.environ.get("ImageVersion"), imageOS=os.environ.get("ImageOS"),
         reliabilityTestsExecuted=False, releaseAcceptance=False)
    command("renderer-policy-read-only", ["defaults", "read", "com.apple.CoreSimulator", "FramebufferServerRendererPolicy"])
    command("host-memory-summary", ["vm_stat"])
    command("host-display", ["system_profiler", "SPDisplaysDataType", "-json"], 15)
    command("host-simulator-processes-before", ["pgrep", "-fl", "Simulator.app|CoreSimulator|WindowServer"])
    required("runtime-inventory", ["xcrun", "simctl", "list", "runtimes", "available", "--json"])
    device = required("create-owned-simulator", ["xcrun", "simctl", "create", "GTA Capture Diagnostic " + str(os.environ.get("GITHUB_RUN_ID", "manual")), DEVICE_TYPE, RUNTIME], 20)
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", device):
        raise SystemExit("Unexpected owned simulator identity")
    app_pid = None
    stdout = output / "app.stdout"
    stderr = output / "app.stderr"
    results = {}
    accepted_app_frame = False
    try:
        required("boot-owned-simulator", ["xcrun", "simctl", "boot", device], 30)
        required("boot-status", ["xcrun", "simctl", "bootstatus", device, "-b"], 120)
        command("display-before-gui", ["xcrun", "simctl", "io", device, "enumerate"])
        results["springboardBeforeGUI"] = command("springboard-png-before-gui", ["xcrun", "simctl", "io", device, "screenshot", "--type=png", str(output / "springboard-before.png")], 20, True)
        # Same device, same boot: GUI attachment is the only intentional change.
        required("attach-exact-simulator-gui", ["open", "-a", str(simulator_app), "--args", "-CurrentDeviceUDID", device], 20)
        command("host-simulator-processes-after", ["pgrep", "-fl", "Simulator.app|CoreSimulator|WindowServer"])
        command("display-after-gui", ["xcrun", "simctl", "io", device, "enumerate"])
        results["springboardAfterGUI"] = command("springboard-png-after-gui", ["xcrun", "simctl", "io", device, "screenshot", "--type=png", str(output / "springboard-after.png")], 20, True)
        required("install-reviewed-product", ["xcrun", "simctl", "install", device, str(app)], 60)
        installed = Path(required("installed-product-path", ["xcrun", "simctl", "get_app_container", device, BUNDLE, "app"]))
        if manifest(installed) != manifest(app):
            raise RuntimeError("Installed product is not byte-identical to reviewed build")
        nonce = str(uuid.uuid4())
        launch = required("launch-reviewed-home", ["xcrun", "simctl", "launch", "--terminate-running-process", "--stdout=" + str(stdout), "--stderr=" + str(stderr), device, BUNDLE,
            "-frontend-layout-review", "-screenshot-mode", "-review-screen", "home", "-review-language", "en", "-screenshot-ready-nonce", nonce, "-runtime-ready-nonce", nonce], 30)
        app_pid = int(launch.rsplit(": ", 1)[1])
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            os.kill(app_pid, 0)
            lines = stdout.read_text(errors="replace").splitlines() if stdout.exists() else []
            if "GTA_LAYOUT_REVIEW_READY " + nonce in lines and "GTA_RUNTIME_SHELL_READY " + nonce in lines:
                break
            time.sleep(.25)
        else:
            raise RuntimeError("Exact home never emitted both readiness markers")
        emit("actual-app-ready", pid=app_pid, nonce=nonce, markers=lines[-12:])
        frame = output / "reviewed-home.png"
        results["reviewedAppPNG"] = command("reviewed-app-png", ["xcrun", "simctl", "io", device, "screenshot", "--type=png", str(frame)], 20, True)
        if results["reviewedAppPNG"]["code"] == 0:
            required("unchanged-app-frame-gate", [str(verifier), str(frame), "light"], 10)
            jpeg = output / "reviewed-home.jpg"
            required("bounded-native-preview", ["/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", "74", "-Z", "1100", str(frame), "--out", str(jpeg)])
            data = jpeg.read_bytes()
            if len(data) > 180_000:
                raise RuntimeError("Native diagnostic preview exceeds log bound")
            emit("source-bound-native-frame", appSource=actual, nativePngSha256=hashlib.sha256(frame.read_bytes()).hexdigest(), previewSha256=hashlib.sha256(data).hexdigest(), diagnosticOnly=True)
            print("DIAGNOSTIC_NATIVE_PREVIEW_BEGIN", flush=True)
            encoded = base64.b64encode(data).decode("ascii")
            for offset in range(0, len(encoded), 100):
                print("DIAGNOSTIC_NATIVE_PREVIEW_DATA " + encoded[offset:offset+100])
            print("DIAGNOSTIC_NATIVE_PREVIEW_END", flush=True)
            accepted_app_frame = True
        else:
            command("owned-app-stack", ["/usr/bin/sample", str(app_pid), "1", "1"], 5)
    finally:
        emit("owned-app-streams", stdout=bounded_output(stdout.read_text(errors="replace") if stdout.exists() else ""), stderr=bounded_output(stderr.read_text(errors="replace") if stderr.exists() else ""))
        command("device-rendering-log", ["xcrun", "simctl", "spawn", device, "log", "show", "--last", "1m", "--style", "compact", "--predicate", 'process == "backboardd" OR process == "SpringBoard"'], 10)
        command("host-rendering-log", ["/usr/bin/log", "show", "--last", "2m", "--style", "compact", "--predicate", 'process == "CoreSimulatorService" OR process == "Simulator" OR process == "simctl"'], 10)
        command("final-owned-display", ["xcrun", "simctl", "io", device, "enumerate"])
        command("terminate-only-owned-app", ["xcrun", "simctl", "terminate", device, BUNDLE])
        command("shutdown-only-created-device", ["xcrun", "simctl", "shutdown", device], 20)
        command("delete-only-created-device", ["xcrun", "simctl", "delete", device], 20)
        emit("diagnostic-conclusion", appSource=actual, stages=results, acceptedAppFrame=accepted_app_frame,
             reliabilityTestsExecuted=False, releaseAcceptance=False)
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("Capture-only diagnostic for `" + actual + "`: app frame " + ("accepted" if accepted_app_frame else "unavailable") + ". No reliability tests executed; no release signoff.\n")
    if not accepted_app_frame:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
