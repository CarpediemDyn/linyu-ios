"""Capture only unauthenticated views from the verified, unmodified release APK."""
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def adb(*args):
    return subprocess.check_output(["adb", *args])


def tap_when_visible(label):
    for _ in range(8):
        adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
        tree = ET.fromstring(adb("shell", "cat", "/sdcard/window.xml"))
        node = next((n for n in tree.iter("node") if n.get("text") == label), None)
        if node is not None:
            x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.attrib["bounds"]))
            adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return
        time.sleep(1)
    raise RuntimeError(f"Original APK UI did not display {label!r}")


def capture(name):
    png = adb("exec-out", "screencap", "-p")
    if not png.startswith(b"\x89PNG"):
        raise RuntimeError("Android screenshot did not contain PNG data")
    (Path("work/android-reference") / f"{name}.png").write_bytes(png)


if __name__ == "__main__":
    print(adb("shell", "getprop", "ro.product.cpu.abilist").decode().strip(), flush=True)
    print(adb("install", "work/android-reference/linyu.apk").decode().strip(), flush=True)
    adb("shell", "am", "start", "-W", "-n", "com.hualala.linyu/.MainActivity")
    time.sleep(4)
    capture("login-sms")
    tap_when_visible("密码登录")
    time.sleep(1)
    capture("login-password")
