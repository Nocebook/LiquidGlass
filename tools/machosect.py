import struct, sys, os

def load(path):
    """返回 (data, base)：FAT 时取第一个 arm64 切片，并把 data 裁到该切片。"""
    raw = open(path, "rb").read()
    magic = struct.unpack(">I", raw[:4])[0]
    if magic in (0xcafebabe, 0xcafebabf):
        n = struct.unpack(">I", raw[4:8])[0]
        best = None
        for i in range(n):
            if magic == 0xcafebabe:
                off = 8 + i * 20
                ct, st, o, sz, al = struct.unpack(">iiIII", raw[off:off+20])
            else:
                off = 8 + i * 32
                ct, st, o, sz, al = struct.unpack(">iiQQI4x", raw[off:off+32])
            if best is None:
                best = (ct, st, o, sz)
        ct, st, o, sz = best
        return raw[o:o+sz], o
    return raw, 0


def sections(path):
    d = load(path)[0]
    magic = struct.unpack("<I", d[:4])[0]
    assert magic == 0xfeedfacf, hex(magic)
    cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, res = struct.unpack("<iiIIIII", d[:32])
    off = 32
    out = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", d[off:off+8])
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = d[off+8:off+24].split(b"\x00")[0].decode()
            nsects = struct.unpack("<I", d[off+64:off+68])[0]
            so = off + 72
            for _ in range(nsects):
                sect = d[so:so+16].split(b"\x00")[0].decode()
                seg = d[so+16:so+32].split(b"\x00")[0].decode()
                addr, size = struct.unpack("<QQ", d[so+32:so+48])
                offset = struct.unpack("<I", d[so+48:so+52])[0]
                out.append((seg, sect, offset, size))
                so += 80
        off += cmdsize
    return d, out

def dump(path):
    d, sects = sections(path)
    print("file", os.path.basename(path), "size", len(d))
    for seg, sect, off, size in sects:
        if size and sect not in ("__text", "__unwind_info", "__eh_frame"):
            print(f"  {seg},{sect:24s} size={size}")
    return d, sects

def cstr_section(path, sectname):
    d, sects = sections(path)
    for seg, sect, off, size in sects:
        if sect == sectname:
            blob = d[off:off+size]
            return [s.decode("utf-8", "replace") for s in blob.split(b"\x00") if s]
    return []

def needles(path, names):
    d = open(path, "rb").read()
    for n in names:
        print(f"  {n:30s} x{d.count(n.encode())}")
