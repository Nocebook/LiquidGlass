#!/usr/bin/env python3
"""把 roothide scheme 的 rootfs 布局重定位到 /var/jb。

roothide 的 Theos 不设 THEOS_PACKAGE_INSTALL_PREFIX，产物按 rootfs 绝对路径
（/Library/MobileSubstrate/...、/Applications/...）打进去。而 RootHide Bootstrap
用的是 rootless 布局（/var/jb -> 隐藏根），rootfs 那部分只读，直接装会报
"error creating directory './rootfs/Library/...': Read-only file system"。

所以这里在打包前统一挪进 var/jb：
  Library/      -> var/jb/Library/
  Applications/ -> var/jb/Applications/
  usr/ bin/ 等  -> var/jb/...

dylib 本体已经过 roothide patcher（依赖走 jbroot 解析），移动文件不影响它。
"""

import os
import shutil
import sys

KEEP_TOP = {"DEBIAN", "var"}


def move_merge(src, dst):
    """把 src 目录合并进 dst，已存在的同名目录递归合并。"""
    os.makedirs(dst, exist_ok=True)
    for item in os.listdir(src):
        s = os.path.join(src, item)
        d = os.path.join(dst, item)
        if os.path.isdir(s) and os.path.isdir(d):
            move_merge(s, d)
        else:
            if os.path.exists(d):
                os.remove(d)
            shutil.move(s, d)
    os.rmdir(src)


def main():
    if len(sys.argv) != 2:
        print("usage: relocate_to_jbroot.py <staging-dir>")
        return 2

    stage = sys.argv[1]
    jb = os.path.join(stage, "var", "jb")
    moved = []

    for name in sorted(os.listdir(stage)):
        if name in KEEP_TOP:
            continue
        src = os.path.join(stage, name)
        dst = os.path.join(jb, name)
        os.makedirs(jb, exist_ok=True)

        if os.path.isdir(src):
            if os.path.isdir(dst):
                move_merge(src, dst)
            else:
                shutil.move(src, dst)
        else:
            if os.path.exists(dst):
                os.remove(dst)
            shutil.move(src, dst)
        moved.append(name)

    print("relocated into var/jb:", ", ".join(moved) if moved else "(nothing)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
