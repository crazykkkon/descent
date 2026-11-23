"""
打包《坠井者》LÖVE 版：
  dist/descent.love               所有平台通用（装了 LÖVE 的电脑双击即可运行）
  dist/坠井者-windows.zip          解压后双击 坠井者.exe
  dist/坠井者-mac.zip              解压后打开 坠井者.app（未签名，第一次要右键 → 打开）

用法：python3 love/build.py   （在仓库根目录运行；需要联网下载一次官方 LÖVE 运行库，之后用缓存）
"""
import io
import os
import plistlib
import shutil
import sys
import urllib.request
import zipfile

LOVE_VERSION = '11.5'
ROOT = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(ROOT, 'dist')
CACHE = os.path.join(ROOT, '.cache')
GAME_NAME = '坠井者'
BUNDLE_ID = 'com.crazykkkon.descent'
# 打进游戏包的文件（测试和打包脚本本身不打进去）
INCLUDE = ['conf.lua', 'main.lua', 'src', 'assets']
EXCLUDE_FILES = {'src/autotest.lua'}

RUNTIMES = {
    'win': f'https://github.com/love2d/love/releases/download/{LOVE_VERSION}/love-{LOVE_VERSION}-win64.zip',
    'mac': f'https://github.com/love2d/love/releases/download/{LOVE_VERSION}/love-{LOVE_VERSION}-macos.zip',
}


def fetch(kind):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, os.path.basename(RUNTIMES[kind]))
    if not os.path.exists(path):
        print(f'下载 LÖVE {LOVE_VERSION} {kind} 运行库 …')
        with urllib.request.urlopen(RUNTIMES[kind]) as r, open(path, 'wb') as f:
            shutil.copyfileobj(r, f)
    return path


def build_love():
    os.makedirs(DIST, exist_ok=True)
    path = os.path.join(DIST, 'descent.love')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for item in INCLUDE:
            full = os.path.join(ROOT, item)
            if os.path.isfile(full):
                z.write(full, item)
                continue
            for base, _, files in os.walk(full):
                for name in sorted(files):
                    fp = os.path.join(base, name)
                    rel = os.path.relpath(fp, ROOT).replace(os.sep, '/')
                    if rel in EXCLUDE_FILES:
                        continue
                    z.write(fp, rel)
    print('生成', path, os.path.getsize(path) // 1024, 'KB')
    return path


def build_windows(love_file):
    src = fetch('win')
    game = open(love_file, 'rb').read()
    out = os.path.join(DIST, f'{GAME_NAME}-windows.zip')
    folder = f'{GAME_NAME}-windows'
    with zipfile.ZipFile(src) as rz, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as wz:
        for info in rz.infolist():
            name = info.filename.split('/', 1)[1] if '/' in info.filename else info.filename
            if not name or info.is_dir():
                continue
            data = rz.read(info)
            if name == 'love.exe':
                # LÖVE 的官方做法：把游戏包直接接在 love.exe 后面，得到一个独立的 exe
                wz.writestr(f'{folder}/{GAME_NAME}.exe', data + game)
            elif name in ('lovec.exe', 'love.ico', 'game.ico', 'changes.txt', 'readme.txt'):
                continue
            else:
                wz.writestr(f'{folder}/{name}', data)
        wz.writestr(f'{folder}/LICENSE-LOVE.txt', rz.read([i for i in rz.namelist() if i.endswith('license.txt')][0]))
        wz.write(os.path.join(ROOT, 'assets/fonts/OFL.txt'), f'{folder}/LICENSE-FONT.txt')
        wz.writestr(f'{folder}/怎么运行.txt', '双击 坠井者.exe 开始游戏。\nWindows 可能提示"未知发布者"：点"更多信息" → "仍要运行"。\n存档在 %APPDATA%\\LOVE\\descent\\ 里。\n')
    print('生成', out, os.path.getsize(out) // 1024, 'KB')


def build_mac(love_file):
    src = fetch('mac')
    game = open(love_file, 'rb').read()
    out = os.path.join(DIST, f'{GAME_NAME}-mac.zip')
    with zipfile.ZipFile(src) as rz, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as wz:
        for info in rz.infolist():
            name = info.filename
            if not name.startswith('love.app/'):
                continue
            new = f'{GAME_NAME}.app/' + name[len('love.app/'):]
            if info.is_dir():
                continue
            data = rz.read(info)
            if name == 'love.app/Contents/Info.plist':
                plist = plistlib.loads(data)
                plist['CFBundleIdentifier'] = BUNDLE_ID
                plist['CFBundleName'] = GAME_NAME
                plist['CFBundleDisplayName'] = GAME_NAME
                plist.pop('UTExportedTypeDeclarations', None)
                plist.pop('CFBundleDocumentTypes', None)
                data = plistlib.dumps(plist)
            zi = zipfile.ZipInfo(new, info.date_time)
            zi.external_attr = info.external_attr  # 保留可执行权限
            zi.compress_type = zipfile.ZIP_DEFLATED
            wz.writestr(zi, data)
        zi = zipfile.ZipInfo(f'{GAME_NAME}.app/Contents/Resources/descent.love')
        zi.compress_type = zipfile.ZIP_DEFLATED
        wz.writestr(zi, game)
        wz.write(os.path.join(ROOT, 'assets/fonts/OFL.txt'), 'LICENSE-FONT.txt')
        wz.writestr('怎么运行.txt', '解压后打开 坠井者.app。\n这个包没有经过苹果签名：第一次打开请在图标上右键 → 打开 → 打开。\n如果提示"已损坏"，在"终端"里运行：xattr -cr 坠井者.app\n存档在 ~/Library/Application Support/LOVE/descent/ 里。\n')
    print('生成', out, os.path.getsize(out) // 1024, 'KB')


if __name__ == '__main__':
    love_file = build_love()
    if '--love-only' not in sys.argv:
        build_windows(love_file)
        build_mac(love_file)
