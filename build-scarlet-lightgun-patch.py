"""Build the local, version-pinned Lightgun EXE patch from the menu-fixed game copy."""
from pathlib import Path
import base64
import hashlib
import json
import struct

root = Path(__file__).resolve().parent
original = root / "Game/Hodzero/Binaries/Win64/Hodzero-Win64-Shipping-ScarletAim.exe"
dll = root / "ScarletLightgun.dll"
source = original.read_bytes()
aim = json.loads((root / "scarlet-aim-patch.json").read_text())
sha = lambda data: hashlib.sha256(data).hexdigest().upper()
assert sha(source) == aim["PatchedSHA256"]
out = bytearray(source)
pe, = struct.unpack_from("<I", source, 60)
optional = pe + 24
count, = struct.unpack_from("<H", source, pe + 6)
optional_size, = struct.unpack_from("<H", source, pe + 20)
table = optional + optional_size
sections = [struct.unpack_from("<8sIIII",source,table+40*i) for i in range(count)]

def u32(offset):
    return struct.unpack_from("<I",source,offset)[0]

def offset(rva):
    for _, _, begin, size, raw in sections:
        if begin <= rva < begin + size:
            return raw + rva - begin
    raise ValueError(rva)

def align(value, boundary):
    return (value + boundary - 1) // boundary * boundary

def encoded(value):
    return base64.b64encode(value).decode("ascii")

edits = []
def replace(at, new, expected=None):
    before = source[at:at+len(new)]
    assert len(before) == len(new) and (expected is None or expected == before)
    if before != new:
        edits.append({"Offset":at,"Before":encoded(before),"After":encoded(new)})
        out[at:at+len(new)] = new

assert u32(optional+32) == 0x1000 and u32(optional+36) == 0x200
code_rva = u32(optional + 56)
data_rva = code_rva + 0x1000

# Relocate the import descriptors. All stock thunks stay at their original addresses.
imports = optional + 112 + 8
old_rva, import_size = struct.unpack_from("<II",source,imports)
old = source[offset(old_rva):offset(old_rva)+import_size]
assert old[-20:] == bytes(20) and import_size % 20 == 0
end = next(i for i in range(0,import_size,20) if old[i:i+20] == bytes(20))
data = bytearray(old[:end])
descriptor = len(data)
data.extend(bytes(40))  # One new import descriptor and its zero terminator.
data.extend(bytes(align(len(data), 8) - len(data)))
lookup_rva = data_rva + len(data)
data.extend(bytes(16))
iat_rva = data_rva + len(data)
data.extend(bytes(16))
hint_rva = data_rva + len(data)
data.extend(b"\0\0ScarletLightgunTick\0")
dll_rva = data_rva + len(data)
data.extend(b"ScarletLightgun.dll\0")
struct.pack_into("<IIIII",data,descriptor,lookup_rva,0,0,dll_rva,iat_rva)
struct.pack_into("<Q",data,lookup_rva-data_rva,hint_rva)
struct.pack_into("<Q",data,iat_rva-data_rva,hint_rva)
assert len(data) < 0x1000

# The game's BeginPlay binds its controller tick via this instruction.
# Tail-jump through the new import and let the companion run the original tick.
hook = 0x1dc6bb
code = b"\xff\x25" + struct.pack("<i",iat_rva-code_rva-6)
replace(offset(hook),b"\x48\x8d\x0d"+struct.pack("<i",code_rva-hook-7),
        bytes.fromhex("48 8d 0d 0e 20 00 00"))
replace(pe+6,struct.pack("<H",count+2))
replace(imports,struct.pack("<II",data_rva,descriptor+40))
replace(optional+4,struct.pack("<I",u32(optional+4)+0x200))
replace(optional+8,struct.pack("<I",u32(optional+8)+align(len(data),0x200)))
replace(optional+56,struct.pack("<I",data_rva+0x1000))
assert len(source) % 0x200 == 0
tail = bytearray()
for index, (name, rva, payload, flags) in enumerate((
    (b".sdgun",code_rva,code,0x60000020), (b".sdimp",data_rva,data,0xc0000040),
)):
    raw_size = align(len(payload),0x200)
    raw_at = len(source)+len(tail)
    entry = struct.pack("<8s6I2HI",name,len(payload),rva,raw_size,raw_at,0,0,0,0,flags)
    replace(table+40*(count+index),entry,bytes(40))
    tail.extend(payload.ljust(raw_size,b"\0"))

out.extend(tail)
patch = {"SourceSHA256":sha(source),"PatchedSHA256":sha(out),"SourceLength":len(source),
         "DllSHA256":sha(dll.read_bytes()),"Edits":edits,"Append":encoded(tail)}
(root / "scarlet-lightgun-patch.json").write_text(json.dumps(patch,indent=2)+"\n")
print(patch["PatchedSHA256"])
