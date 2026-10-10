#!/usr/bin/env python3
"""'토독' 클릭 소리를 합성해서 sounds/todok_0..2.wav 로 저장한다 (표준 라이브러리만 사용).

나무·플라스틱 키캡을 톡 치는 소리를 흉내 낸다: 짧은 노이즈 자극 → 공명 필터 3개 + 낮은 '툭' 성분.
매번 똑같이 들리지 않도록 공명 주파수를 조금씩 바꾼 변형 3개를 만든다.
"""
import math, os, random, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")


def resonator(x, f, q):
    w0 = 2 * math.pi * f / SR
    al = math.sin(w0) / (2 * q)
    b0, b2 = al, -al
    a0, a1, a2 = 1 + al, -2 * math.cos(w0), 1 - al
    y, x1, x2, y1, y2 = [], 0, 0, 0, 0
    for v in x:
        o = (b0 * v + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def tap(seed):
    random.seed(seed)
    n = int(SR * 0.05)
    exc = [random.uniform(-1, 1) * math.exp(-i / SR / 0.0015) for i in range(n)]
    out = [0.0] * n
    for f, q, g in [(1200, 8, 1.0), (2400, 10, 0.5), (4800, 12, 0.2)]:
        for i, v in enumerate(resonator(exc, f * random.uniform(0.97, 1.03), q)):
            out[i] += g * v
    for i in range(n):
        out[i] += 0.35 * math.sin(2 * math.pi * 240 * i / SR) * math.exp(-i / SR / 0.008)
        out[i] += 0.12 * exc[i] if i < 200 else 0
        out[i] *= min(1, (n - i) / (SR * 0.004))
    return out


def write(path, x):
    pk = max(abs(v) for v in x) or 1
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v / pk * 0.85 * 32767)) for v in x))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for j in range(3):
        write(os.path.join(OUT, f"todok_{j}.wav"), tap(100 + j))
    print("sounds/todok_0..2.wav 생성 완료")
