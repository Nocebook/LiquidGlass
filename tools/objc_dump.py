#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""极简 ObjC Mach-O class-dump：只依赖 struct，支持 chained fixups 与 relative method list。

用途：在没有 IDA / radare2 的环境里，把 iOS dylib 的类/方法/协议元数据读出来。
输出：类名 + 父类 + 实例方法/类方法选择器 + ivar 名 + 属性名。
"""
import struct
import sys
import json

MASK_ARM64E = (1 << 43) - 1
MASK_64 = (1 << 36) - 1


class Image:
    def __init__(self, data, offset):
        self.d = data
        self.off = offset
        # FAT 里每个切片的 segment/section fileoff 都是相对切片起点的，
        # 换算成真实文件偏移必须补上这个基数，否则整张表会提前 0x4000 读。
        self.fbase = offset
        vals = struct.unpack_from('<IiiIIIII', data, offset)
        self.cputype, self.cpusubtype = vals[1], vals[2]
        self.ncmds, self.sizeofcmds = vals[4], vals[5]
        self.segments = []          # (name, vmaddr, vmsize, fileoff, filesize)
        self.sections = {}          # sectname -> (vmaddr, size, fileoff)
        self.dylibs = []
        self.symtab = None
        self._parse_commands()
        self.base = self.segments[0][1] if self.segments else 0

    def _parse_commands(self):
        pos = self.off + 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack_from('<II', self.d, pos)
            base = cmd & 0x7fffffff
            if base == 0x19:  # LC_SEGMENT_64
                segname = self.d[pos + 8:pos + 24].split(b'\0')[0].decode('ascii', 'replace')
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', self.d, pos + 24)
                nsects = struct.unpack_from('<I', self.d, pos + 64)[0]
                self.segments.append((segname, vmaddr, vmsize, fileoff, filesize))
                spos = pos + 72
                for _s in range(nsects):
                    sname = self.d[spos:spos + 16].split(b'\0')[0].decode('ascii', 'replace')
                    addr, size = struct.unpack_from('<QQ', self.d, spos + 32)
                    offset = struct.unpack_from('<I', self.d, spos + 48)[0]
                    self.sections.setdefault(sname, (addr, size, offset))
                    spos += 80
            elif base in (0xc, 0xd, 0x18, 0x1f, 0x23):  # LC_LOAD_DYLIB 等
                nameoff = struct.unpack_from('<I', self.d, pos + 8)[0]
                nm = self.d[pos + nameoff:pos + cmdsize].split(b'\0')[0].decode('utf-8', 'replace')
                self.dylibs.append(nm)
            elif base == 0x2:  # LC_SYMTAB
                self.symtab = struct.unpack_from('<IIII', self.d, pos + 8)
            pos += cmdsize

    # ---- 地址换算 ----
    def vm2off(self, vmaddr):
        for name, va, vs, fo, fs in self.segments:
            if va <= vmaddr < va + max(vs, 1):
                return self.fbase + fo + (vmaddr - va)
        return None

    def resolve(self, word):
        """把文件里的 8 字节指针（可能是 chained fixup 编码）还原成 vmaddr。"""
        if not word:
            return 0
        if word & (1 << 63):        # bind：指向外部符号，跳过
            return 0
        for mask in (MASK_ARM64E, MASK_64):
            cand = self.base + (word & mask)
            if self.vm2off(cand) is not None and cand >= self.base:
                if cand - self.base < 0x4000000:
                    return cand
        if self.vm2off(word) is not None:
            return word
        return 0

    def cstr(self, vmaddr):
        o = self.vm2off(vmaddr)
        if o is None or o >= len(self.d):
            return ''
        end = self.d.find(b'\0', o)
        return self.d[o:end if end > 0 else o + 64].decode('utf-8', 'replace')

    # ---- ObjC 结构 ----
    def class_list(self):
        sect = self.sections.get('__objc_classlist')
        if not sect:
            return []
        addr, size, off = sect
        off += self.fbase
        out = []
        for i in range(0, size, 8):
            word = struct.unpack_from('<Q', self.d, off + i)[0]
            vm = self.resolve(word)
            if vm:
                out.append(vm)
        return out

    def method_list(self, list_vm):
        o = self.vm2off(list_vm)
        if o is None:
            return []
        entsize_flags, count = struct.unpack_from('<II', self.d, o)
        entsize = entsize_flags & 0xfffc
        if entsize == 0 or count > 20000:
            return []
        out = []
        p = o + 8
        for _ in range(count):
            if entsize == 12:      # 相对表：类型相对字段自身，方法名经 selref 间接指向
                name_off, type_off, imp_off = struct.unpack_from('<iii', self.d, p)
                type_vm = self._vm_of_off(p + 4) + type_off
                name_vm = self._selref_target(self._vm_of_off(p) + name_off)
                out.append((self.cstr(name_vm), self.cstr(type_vm)))
            else:                  # 24 字节绝对（chained fixup）
                name_p, type_p, imp_p = struct.unpack_from('<QQQ', self.d, p)
                out.append((self.cstr(self.resolve(name_p)), self.cstr(self.resolve(type_p))))
            p += entsize
        return out

    def _selref_target(self, vm):
        """相对方法表里 name 字段给的是 selref 槽位，槽位里才是真正的字符串指针。"""
        o = self.vm2off(vm)
        if o is None or o + 8 > len(self.d):
            return vm
        word = struct.unpack_from('<Q', self.d, o)[0]
        target = self.resolve(word)
        return target or vm

    def _vm_of_off(self, fileoff):
        for name, va, vs, fo, fs in self.segments:
            if self.fbase + fo <= fileoff < self.fbase + fo + max(fs, 1):
                return va + (fileoff - self.fbase - fo)
        return 0

    def dump_class(self, class_vm):
        o = self.vm2off(class_vm)
        if o is None:
            return None
        data = struct.unpack_from('<Q', self.d, o + 32)[0]
        ro_vm = self.resolve(data) or (data & ~0x7)
        ro = self.vm2off(ro_vm)
        if ro is None:
            return None
        name_p, methods_p, protocols_p, ivars_p, _weak, props_p = struct.unpack_from('<QQQQQQ', self.d, ro + 24)
        name = self.cstr(self.resolve(name_p))
        if not name:
            return None
        super_p = struct.unpack_from('<Q', self.d, o + 8)[0]
        sup = self.resolve(super_p)
        sup_name = None
        if sup:
            so = self.vm2off(sup)
            if so is not None:
                sd = struct.unpack_from('<Q', self.d, so + 32)[0]
                sro = self.vm2off(self.resolve(sd) or (sd & ~0x7))
                if sro is not None:
                    sp = struct.unpack_from('<Q', self.d, sro + 24)[0]
                    sup_name = self.cstr(self.resolve(sp)) or None
        inst = self.method_list(self.resolve(methods_p)) if methods_p else []
        # 类方法在 metaclass 的 ro 里
        isa = struct.unpack_from('<Q', self.d, o)[0]
        cls_m = []
        isa_vm = self.resolve(isa)
        if isa_vm and isa_vm != class_vm:
            io = self.vm2off(isa_vm)
            if io is not None:
                idata = struct.unpack_from('<Q', self.d, io + 32)[0]
                iro = self.vm2off(self.resolve(idata) or (idata & ~0x7))
                if iro is not None:
                    imp = struct.unpack_from('<Q', self.d, iro + 32)[0]
                    if imp:
                        cls_m = self.method_list(self.resolve(imp))
        props = []
        if props_p:
            po = self.vm2off(self.resolve(props_p))
            if po is not None:
                cnt = struct.unpack_from('<I', self.d, po + 4)[0]
                for i in range(min(cnt, 400)):
                    pv = struct.unpack_from('<Q', self.d, po + 8 + i * 8)[0]
                    pn = self.cstr(self.resolve(pv))
                    if pn:
                        props.append(pn)
        ivars = []
        if ivars_p:
            io = self.vm2off(self.resolve(ivars_p))
            if io is not None:
                cnt = struct.unpack_from('<I', self.d, io + 4)[0]
                esz = struct.unpack_from('<I', self.d, io)[0] & 0xfffc or 32
                for i in range(min(cnt, 400)):
                    nv = struct.unpack_from('<Q', self.d, io + 8 + i * esz + 8)[0]
                    ivn = self.cstr(self.resolve(nv))
                    if ivn:
                        ivars.append(ivn)
        return {
            'name': name, 'super': sup_name,
            'instance': inst, 'class': cls_m,
            'props': props, 'ivars': ivars,
        }


def load_slices(path):
    d = open(path, 'rb').read()
    magic = struct.unpack('>I', d[:4])[0]
    if magic == 0xcafebabe:
        n = struct.unpack('>I', d[4:8])[0]
        out = []
        for k in range(n):
            ct, cs, o, sz, al = struct.unpack('>iiIII', d[8 + k * 20:28 + k * 20])
            out.append((o, cs & 0xffffffff))
        return d, out
    return d, [(0, struct.unpack_from('<i', d, 8)[0] & 0xffffffff)]


def main():
    path = sys.argv[1]
    pattern = sys.argv[2].lower() if len(sys.argv) > 2 else ''
    d, slices = load_slices(path)
    all_classes = []
    for off, sub in slices:
        img = Image(d, off)
        print('# slice cputype=%#x cpusubtype=%#x segs=%d dylibs=%d'
              % (img.cputype & 0xffffffff, sub, len(img.segments), len(img.dylibs)))
        classes = []
        for vm in img.class_list():
            c = img.dump_class(vm)
            if c:
                classes.append(c)
        print('#   classes: %d' % len(classes))
        all_classes.extend(classes)
        if not pattern:
            print('#   dylibs: %s' % img.dylibs)
    seen = set()
    uniq = []
    for c in all_classes:
        if c['name'] in seen:
            continue
        seen.add(c['name'])
        uniq.append(c)
    print('# total unique classes: %d\n' % len(uniq))

    hit = [c for c in uniq if pattern in c['name'].lower()] if pattern else uniq
    for c in sorted(hit, key=lambda x: x['name']):
        print('=== %s : %s' % (c['name'], c['super']))
        if c['ivars']:
            print('    ivars: %s' % ', '.join(c['ivars'][:20]))
        if c['props']:
            print('    props: %s' % ', '.join(c['props'][:20]))
        for sig in c['class']:
            print('    + %s' % sig[0])
        for sig in c['instance']:
            print('    - %s' % sig[0])
    if pattern:
        print('\n# matched %d / %d classes' % (len(hit), len(uniq)))


if __name__ == '__main__':
    main()
