#!/usr/bin/env python3
"""校验 deb 解包后的路径。

roothide（隐根）的 rootfs 是只读的，包内任何不在 var/jb 下的绝对路径
都会让安装直接失败（error creating directory './rootfs/Library/...': Read-only file system）。
所以打包后必须逐条检查，发现越界路径就中断构建。
"""

import os
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: check_deb_paths.py <staging-dir>")
        return 2

    stage = sys.argv[1]
    bad = []

    for root, dirs, files in os.walk(stage):
        rel = os.path.relpath(root, stage)
        if rel == ".":
            continue
        parts = rel.split(os.sep)
        if parts[0] == "DEBIAN":
            continue
        if parts[0] != "var":
            bad.append(rel)
            continue
        # var 自身和 var/jb 都是合法中间目录
        if len(parts) == 1:
            continue
        if parts[1] != "jb":
            bad.append(rel)

    if bad:
        print("ERROR: 以下路径不在 var/jb 下，roothide 装不进只读 rootfs：")
        for item in bad:
            print("   !", item)
        return 1

    print("path check: all entries under var/jb")
    return 0


if __name__ == "__main__":
    sys.exit(main())
