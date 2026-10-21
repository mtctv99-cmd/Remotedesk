import sys

sys.stdout.reconfigure(encoding="utf-8")
path = sys.argv[1]
needles = sys.argv[2:]
d = open(path, "rb").read()
for s in needles:
    u16 = d.count(s.encode("utf-16-le"))
    u8 = d.count(s.encode("utf-8"))
    print(f"{s!r}: utf16={u16} utf8={u8}")
