#!/usr/bin/env python3
"""把 deb 的 rootfs 布局挪进 /var/jb。

RootHide Bootstrap 是 rootless 布局，rootfs 只读；theos 的 roothide scheme
出的包却是 /Library、/Applications 这种 rootfs 路径，直接装会失败。
挪进 /var/jb 后，dylib 里的 jbroot 解析由 RootHide 自己处理，不受影响。

用法: python3 tools/relocate_to_jbroot.py <dpkg-deb -R 出来的 stage 目录>
"""

import os
import shutil
import sys

KEEP = {"DEBIAN", "var"}


def merge(src, dst):
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)
        return

    if os.path.isdir(src) and os.path.isdir(dst):
        for name in os.listdir(src):
            merge(os.path.join(src, name), os.path.join(dst, name))
        os.rmdir(src)
    else:
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.move(src, dst)


def main(stage):
    if not os.path.isdir(stage):
        raise SystemExit(f"not a directory: {stage}")

    moved = []
    for name in sorted(os.listdir(stage)):
        if name in KEEP:
            continue
        src = os.path.join(stage, name)
        dst = os.path.join(stage, "var", "jb", name)
        merge(src, dst)
        moved.append("/" + name)

    if not moved:
        print("nothing to relocate")
        return
    print("relocated into /var/jb: " + ", ".join(moved))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
