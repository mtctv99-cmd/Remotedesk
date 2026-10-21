import sys
sys.stdout.reconfigure(encoding="utf-8")

paths = {
    "old_exe": r"C:\Users\chu.mai\Desktop\Remote\backup\install-20261020\deskagent.exe.bak",
    "old_dll": r"C:\Users\chu.mai\Desktop\Remote\backup\install-20261020\libdeskagent.dll.bak",
    "new_exe": r"C:\Users\chu.mai\AppData\Local\deskagent\deskagent.exe",
    "new_dll": r"C:\Users\chu.mai\AppData\Local\deskagent\librustdesk.dll",
}
needles = [
    b"rustdesk_core_main_args",
    b"free_c_args",
    b"rustdesk_get_app_name",
    b"libdeskagent.dll",
    b"librustdesk.dll",
]
for k, p in paths.items():
    try:
        d = open(p, "rb").read()
    except OSError as e:
        print(k, "ERR", e)
        continue
    print(k, len(d))
    for s in needles:
        print("   ", s.decode(), d.count(s))
