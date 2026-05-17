[app]
title = Bubble Translator
package.name = bubbletrans
package.domain = org.test
source.dir = .
source.include_exts = py,png,jpg,kv,atlas
version = 1.0
requirements = python3,kivy,pyjnius,requests,deep-translator,langdetect,urllib3,charset-normalizer,idna,certifi
orientation = portrait
android.permissions = SYSTEM_ALERT_WINDOW, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PROJECTION
android.api = 33
android.minapi = 24
android.ndk_api = 24
android.archs = arm64-v8a, armeabi-v7a
android.allow_backup = True
android.gradle_dependencies = com.google.android.gms:play-services-mlkit-text-recognition:19.0.0
services = BubbleService:service.py:foreground

[buildozer]
log_level = 2
warn_on_root = 1
