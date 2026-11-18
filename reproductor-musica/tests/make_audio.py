# Genera canciones de prueba (WAV con etiquetas INFO de título y artista)
import math, struct, sys, os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
songs = [("Prueba Uno", "Banda Demo", 440), ("Prueba Dos", "Banda Demo", 550), ("Cancion Tres", "Otra Artista", 660)]
for i, (title, artist, f) in enumerate(songs):
    sr, sec = 16000, 12
    data = b"".join(struct.pack("<h", int(6000 * math.sin(2 * math.pi * f * n / sr))) for n in range(sr * sec))
    def sub(tag, txt):
        b = txt.encode() + b"\0"
        if len(b) % 2: b += b"\0"
        return tag + struct.pack("<I", len(b)) + b
    info = b"INFO" + sub(b"INAM", title) + sub(b"IART", artist)
    lst = b"LIST" + struct.pack("<I", len(info)) + info
    fmt = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)
    body = b"WAVE" + fmt + lst + b"data" + struct.pack("<I", len(data)) + data
    open(os.path.join(out, f"{i+1:02d} {title}.wav"), "wb").write(b"RIFF" + struct.pack("<I", len(body)) + body)
