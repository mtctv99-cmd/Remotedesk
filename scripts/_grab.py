import sys

sys.stdout.reconfigure(encoding="utf-8")
from PIL import ImageGrab

img = ImageGrab.grab(all_screens=True)
img.save(sys.argv[1])
print("saved", sys.argv[1], img.size)
