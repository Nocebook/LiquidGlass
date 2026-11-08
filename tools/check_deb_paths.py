#!/usr/bin/env python3
"""校验打包目录里没有 /var/jb 之外的绝对路径。

RootHide 的 rootfs 只读，包里出现 /Library、/Applications 这类路径时
安装会直接失败。这个检查让 CI 在出包阶段就红，而不是装到手机上才发现。

用法: python3 tools/check_deb_paths.py <stage 目录>
"""

import os
import sys


def main(stage):
    if not os.path.isdir(stage):
        raise SystemExit(f"not a directory: {stage}")

    bad = []
    for root, dirs, _files in os.walk(stage):
        rel = os.path.relpath(root, stage)
        if rel == ".":
            continue

        top = rel.split(os.sep)[0]
        if top == "DEBIAN":
            dirs[:] = []
            continue
        if top != "var":
            bad.append(rel)

    if bad:
        print("ERROR: 以下目录不在 /var/jb 下，RootHide 上装不进去：", file=sys.stderr)
        for item in bad[:40]:
            print("  /" + item.replace(os.sep, "/"), file=sys.stderr)
        return 1

    print("path check ok：所有内容都在 /var/jb 下")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    sys.exit(main(sys.argv[1]))
