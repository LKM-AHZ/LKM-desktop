#!/usr/bin/env python3
"""Prepare pinned, SHA-256 checked OHOS media runtimes; generated binaries stay untracked."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
MPV_COMMIT = 'd424290ea300c140a1f563f44a8f0461628a3aa4'
MPV_PATH = 'libs/ohos/media_kit_libs_ohos_video/ohos/libs/arm64-v8a/libmpv.so.2'
MPV_HASH = '45febf6194b02561572b98659e5c13b672bf86503dd4835688a284326ba18811'
RTC_HASH = '39f42ab2d86bdafad47102b80e69f0f0adb49b66061a9f7931b6cd5d00510ad4'


def checked(path, digest, size):
    return path.is_file() and path.stat().st_size == size and hashlib.sha256(path.read_bytes()).hexdigest() == digest


def prepare(media_source=None, rtc_source=None):
    cache = ROOT / '.dart_tool/ohos-media-runtimes'
    cache.mkdir(parents=True, exist_ok=True)
    mpv = cache / 'libmpv.so'
    if not checked(mpv, MPV_HASH, 97819184):
        if media_source:
            source = Path(media_source)
            revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
            if revision != MPV_COMMIT:
                raise ValueError('Media source must be at the pinned commit')
            shutil.copyfile(source / MPV_PATH, mpv)
        else:
            repo = cache / 'media-source'
            if not (repo / '.git').is_dir():
                subprocess.run(['git', 'init', str(repo)], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['git', '-C', str(repo), '-c', 'http.userAgent=Mozilla/5.0',
                            'fetch', '--depth=1', 'https://gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit.git',
                            MPV_COMMIT], check=True)
            with mpv.open('wb') as output:
                subprocess.run(['git', '-C', str(repo), 'show', f'{MPV_COMMIT}:{MPV_PATH}'], stdout=output, check=True)
    if not checked(mpv, MPV_HASH, 97819184):
        raise ValueError('OHOS libmpv hash/length mismatch')
    destination = ROOT / 'packages/media_kit_libs_ohos_video/ohos/libs/arm64-v8a/libmpv.so'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(mpv, destination)
    outputs = {'libmpv.so': MPV_HASH}
    rtc_package = ROOT / 'packages/flutter_webrtc'
    if rtc_package.is_dir():
        rtc = cache / 'libohos_webrtc.so'
        if not checked(rtc, RTC_HASH, 11091832):
            if rtc_source:
                shutil.copyfile(Path(rtc_source) / 'ohos/libs/arm64-v8a/libohos_webrtc.so', rtc)
            else:
                request = urllib.request.Request(
                    'https://gitcode.com/CPF-Flutter/fluttertpc_flutter_webrtc.git/info/lfs/objects/batch',
                    data=json.dumps({'operation': 'download', 'transfers': ['basic'],
                                     'objects': [{'oid': RTC_HASH, 'size': 11091832}]}).encode(),
                    headers={'User-Agent': 'Mozilla/5.0', 'Content-Type': 'application/vnd.git-lfs+json',
                             'Accept': 'application/vnd.git-lfs+json'},
                )
                with urllib.request.urlopen(request, timeout=60) as response:
                    object_info = json.load(response)['objects'][0]
                request = urllib.request.Request(object_info['actions']['download']['href'], headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(request, timeout=120) as response, rtc.open('wb') as output:
                    shutil.copyfileobj(response, output)
        if not checked(rtc, RTC_HASH, 11091832):
            raise ValueError('OHOS WebRTC hash/length mismatch')
        destination = rtc_package / 'ohos/libs/arm64-v8a/libohos_webrtc.so'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(rtc, destination)
        outputs['libohos_webrtc.so'] = RTC_HASH
    return outputs


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--media-source', type=Path)
    parser.add_argument('--rtc-source', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.media_source, args.rtc_source), indent=2))
