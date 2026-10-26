#!/usr/bin/env python3
"""把 shell/zsh 产物里的编译期占位前缀换成真实 $WTOOL_HOME/usr。

用法:
  zsh-prefix.py patch   <产物根 usr/> <build/prefix-placeholder> <$WTOOL_HOME/usr>
  zsh-prefix.py restore <产物根 usr/>

为什么不能简单 replace：
  · 二进制里的路径是 NUL 结尾的 C 字符串，占位符后面还有 /lib/zsh/5.9.2 之类后缀。
    替换时要把「占位符 + 后缀」当成一个整体缩成「新前缀 + 后缀」，NUL 补在整段
    区域的末尾 —— 直接 replace 会把后缀截掉（实测过）。
  · 所以 sidecar 记下占位符长度；重复安装/换 WTOOL_HOME/卸载时按同一块区域改回来。
"""
import json
import os
import sys
import tempfile

MODE = sys.argv[1]
ROOT = os.path.abspath(sys.argv[2])
SIDE = os.path.join(ROOT, 'lib', 'zsh', '.zsh-wtool-patch')


def die(msg):
    print('zsh-prefix: ' + msg, file=sys.stderr)
    raise SystemExit(1)


def read_sidecar():
    if not os.path.isfile(SIDE):
        return None
    try:
        with open(SIDE, encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        die('读不了 %s：%s' % (SIDE, e))


def atomic_write(path, data, mode):
    fd, tmp = tempfile.mkstemp(prefix='.' + os.path.basename(path) + '.',
                               dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def patch_elf(data, old, new, region_prefix_len):
    """old+suffix -> new+suffix；整段区域长度 = region_prefix_len + len(suffix)。"""
    data = bytearray(data)
    pos = 0
    n = 0
    while True:
        i = data.find(old, pos)
        if i < 0:
            break
        end = data.find(b'\x00', i)
        if end < 0:
            die('ELF 里的路径没有 NUL 结尾，不敢改')
        suffix = bytes(data[i + len(old):end])
        region_len = region_prefix_len + len(suffix)
        if i + region_len >= len(data) or data[i + region_len] != 0:
            die('ELF 里的路径区越界/结尾不是 NUL，产物形状不对')
        repl = new + suffix
        if len(repl) > region_len:
            die('路径太长：字符串区 %d 字节，新串 %d 字节' % (region_len, len(repl)))
        data[i:i + region_len] = repl + b'\x00' * (region_len - len(repl))
        pos = i + 1
        n += 1
    return bytes(data), n


def is_elf(data):
    return data[:4] == b'\x7fELF'


def discover(ph, old, target):
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if not os.path.islink(os.path.join(dirpath, d))]
        for name in filenames:
            p = os.path.join(dirpath, name)
            if p == SIDE or os.path.islink(p) or not os.path.isfile(p):
                continue
            with open(p, 'rb') as f:
                data = f.read()
            if ph in data or (old and old in data) or target in data:
                out.append(os.path.relpath(p, ROOT))
    return out


def refresh_hardlink():
    z = os.path.join(ROOT, 'bin', 'zsh')
    if not os.path.isfile(z):
        return
    bindir = os.path.dirname(z)
    with open(z, 'rb') as f:
        zdata = f.read()
    for name in os.listdir(bindir):
        if not name.startswith('zsh-'):
            continue
        p = os.path.join(bindir, name)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        with open(p, 'rb') as f:
            if f.read() != zdata:
                continue
        os.unlink(p)
        os.link(z, p)


side = read_sidecar()

if MODE == 'patch':
    if len(sys.argv) != 5:
        die('patch 用法: patch <usr根> <placeholder文件> <目标前缀>')
    target = os.fsencode(sys.argv[4])
    if not target or b'\x00' in target or b'\n' in target:
        die('目标前缀不合法')
    ph = None
    old = b''
    if side:
        ph = os.fsencode(side.get('placeholder', ''))
        old = os.fsencode(side.get('prefix', ''))
    if not ph:
        try:
            with open(sys.argv[3], encoding='utf-8') as f:
                ph = os.fsencode(f.readline().strip())
        except OSError:
            ph = b''
    if not ph or b'\x00' in ph or b'\n' in ph:
        die('占位前缀不合法（空/含 NUL/换行）')
    if len(target) > len(ph):
        die('目标前缀 %d 字节 > 占位符 %d 字节：路径太长，装不了' % (len(target), len(ph)))

    files = discover(ph, old, target)
    if not files:
        z = os.path.join(ROOT, 'bin', 'zsh')
        if os.path.isfile(z):
            with open(z, 'rb') as f:
                zd = f.read()
            if target in zd:
                print('zsh-prefix: 已经是 %s，不重复打补丁' % target.decode(errors='replace'))
                raise SystemExit(0)
        die('产物里找不到占位前缀，也不像已经打过补丁 —— 重跑 wtool build shell/zsh（或重新下载产物）')

    patched = []
    for rel in files:
        p = os.path.join(ROOT, rel)
        st = os.stat(p)
        with open(p, 'rb') as f:
            data = f.read()
        if ph in data:
            use_old = ph
        elif old and old in data:
            use_old = old
        elif target in data:
            patched.append(rel)
            continue
        else:
            continue
        if use_old == target:
            patched.append(rel)
            continue
        if is_elf(data):
            new, n = patch_elf(data, use_old, target, len(ph))
        elif b'\x00' in data:
            die('%s 含 NUL 但不是 ELF，不敢改' % rel)
        else:
            new = data.replace(use_old, target)
            n = data.count(use_old)
        if n == 0:
            continue
        atomic_write(p, new, st.st_mode)
        patched.append(rel)
        print('zsh-prefix: %s：%d 处 %s… -> %s' %
              (rel, n, use_old.decode(errors='replace')[:48],
               target.decode(errors='replace')))
    refresh_hardlink()

    # 写 sidecar 前先确认 zsh 本体真的改对了（别把坏的当成装好）
    z = os.path.join(ROOT, 'bin', 'zsh')
    with open(z, 'rb') as f:
        zd = f.read()
    if ph in zd or (old and old != target and old in zd):
        die('zsh 二进制里还残留旧前缀，没改干净')
    if target not in zd:
        die('zsh 二进制里没有目标前缀，补丁没打上')
    _side = json.dumps({'schema': 1,
                        'placeholder': ph.decode(),
                        'prefix': target.decode(),
                        'files': sorted(patched)},
                       ensure_ascii=False, sort_keys=True) + '\n'
    atomic_write(SIDE, _side.encode(), 0o644)
    print('zsh-prefix: OK（%d 个文件）' % len(patched))

elif MODE == 'restore':
    if not side:
        print('zsh-prefix: 没有 sidecar，跳过还原')
        raise SystemExit(0)
    ph = os.fsencode(side['placeholder'])
    old = os.fsencode(side['prefix'])
    for rel in side.get('files', []):
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        st = os.stat(p)
        with open(p, 'rb') as f:
            data = f.read()
        if old not in data:
            continue
        if is_elf(data):
            new, n = patch_elf(data, old, ph, len(ph))
        elif b'\x00' in data:
            die('%s 含 NUL 但不是 ELF，不敢改' % rel)
        else:
            new = data.replace(old, ph)
            n = data.count(old)
        if n:
            atomic_write(p, new, st.st_mode)
            print('zsh-prefix: 还原 %s（%d 处）' % (rel, n))
    refresh_hardlink()
    os.unlink(SIDE)
    print('zsh-prefix: OK（已还原成占位前缀）')
else:
    die('mode 只有 patch / restore')
