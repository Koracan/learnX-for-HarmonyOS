#!/usr/bin/env python3
"""learnOH AppGallery 应用介绍截图合成器（海报式：背景 + 设备框 + 文案）。

输入：设备原始帧（未裁切的整屏 PNG）
输出：精确到官方规格的画布 PNG
  phone     9:16  1080x1920
  tablet    2:3   1280x1920
  landscape 16:9  1920x1080

两种语言的排版差异（--lang）：
  zh（默认）：逐字断行（中文没有词边界），横版标题**真竖排**（一列一字，先右列后左列）。
  en        ：按**词**断行（否则 "Noti/ce" 会被劈开），横版标题**整行旋转 90°**
              （拉丁文没有竖排传统，逐字竖排会得到一列字母）。

用法：
  python scripts/appgallery/compose.py --palette neutral --group phone --lang en \
      --frame .scratch/appgallery/frames-en/phone-1-notices-raw.png \
      --headline "Never Miss a Notice" \
      --out .scratch/appgallery/evidence/final-en/phone-1-notices-1080x1920.png
"""
from __future__ import annotations
import argparse, math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\hms\previewer\resources\fonts"
FONT_CJK = os.path.join(FONT_DIR, "HarmonyOS_Sans_SC.ttf")
FONT_LATIN = os.path.join(FONT_DIR, "HarmonyOS_Sans.ttf")
# 兜底字体：**不用微软雅黑**（msyh 不可商用）。这里只认 SDK 自带的开源字体（Noto CJK，OFL）。
FONT_FALLBACK = os.path.join(FONT_DIR, "NotoSansCJK-Regular.ttc")

# 官方规格（developer.huawei.com 应用素材规范）
SIZES = {
    "phone": (1080, 1920),
    "tablet": (1280, 1920),
    "landscape": (1920, 1080),
}

# 配色方案。top/bottom = 背景竖向渐变端点；title/sub = 文案色；bezel = 设备框描边；shadow = 投影强度
PALETTES = {
    "brand": dict(top="#9A25AE", bottom="#4A0A55", title="#FFFFFF", sub="#F3D9F7",
                  bezel="#FFFFFF", shadow=110, accent="#F9ABFF"),
    "lilac": dict(top="#FFD6FE", bottom="#F6ECFA", title="#4A0A55", sub="#6B4A72",
                  bezel="#FFFFFF", shadow=70, accent="#9A25AE"),
    "neutral": dict(top="#FFFFFF", bottom="#EDEFF3", title="#1C1C1E", sub="#5B5B60",
                    bezel="#FFFFFF", shadow=80, accent="#9A25AE"),
    "tri": dict(top="#9A25AE", bottom="#4A0A55", title="#FFFFFF", sub="#F3D9F7",
                bezel="#FFFFFF", shadow=110, accent="#F9ABFF"),
}
# 三组各一色（palette "tri" 时按组覆盖）
TRI = {
    "phone": dict(top="#9A25AE", bottom="#4A0A55", title="#FFFFFF", sub="#F3D9F7",
                  bezel="#FFFFFF", shadow=110, accent="#F9ABFF"),
    "tablet": dict(top="#0F6F7A", bottom="#06343C", title="#FFFFFF", sub="#CDE9EC",
                   bezel="#FFFFFF", shadow=110, accent="#7FE3EE"),
    "landscape": dict(top="#1F2937", bottom="#0B1220", title="#FFFFFF", sub="#C7CFDB",
                      bezel="#FFFFFF", shadow=110, accent="#8FA6C8"),
}


def hex_rgb(s: str):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def font_chain(lang: str):
    """按语言给候选字体排序：en 优先拉丁字面，zh 优先中文字面，兜底同一套开源字体。"""
    if lang == "en":
        return (FONT_LATIN, FONT_CJK, FONT_FALLBACK)
    return (FONT_CJK, FONT_LATIN, FONT_FALLBACK)


def load_font(size: int, weight: str = "regular", lang: str = "zh"):
    for path in font_chain(lang):
        if os.path.exists(path):
            break
    else:
        raise RuntimeError("找不到可用字体：SDK 字体目录下既没有 HarmonyOS_Sans 也没有 NotoSansCJK")
    f = ImageFont.truetype(path, size)
    if weight == "bold":
        try:  # 变量字体优先取 Bold 轴
            names = [n.decode() if isinstance(n, bytes) else n for n in f.get_variation_names()]
            for cand in ("Bold", "SemiBold", "Medium"):
                if cand in names:
                    f.set_variation_by_name(cand)
                    return f
        except Exception:
            pass
    return f


def gradient(w: int, h: int, top: str, bottom: str) -> Image.Image:
    a, b = hex_rgb(top), hex_rgb(bottom)
    strip = Image.new("RGB", (1, 256))
    px = strip.load()
    for y in range(256):
        t = y / 255.0
        px[0, y] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return strip.resize((w, h), Image.BILINEAR).convert("RGB")


def wrap_cjk(draw: ImageDraw.ImageDraw, text: str, font, max_w: int):
    """逐字断行：中文没有词边界，只能按字宽贪心塞。"""
    lines, cur = [], ""
    for ch in text:
        probe = cur + ch
        if draw.textlength(probe, font=font) <= max_w or not cur:
            cur = probe
        else:
            lines.append(cur); cur = ch
    if cur:
        lines.append(cur)
    return lines


def wrap_words(draw: ImageDraw.ImageDraw, text: str, font, max_w: int):
    """按词断行：拉丁文按字符断会把单词劈成两半（"Noti"/"ce"）。"""
    lines, cur = [], ""
    for word in text.split():
        probe = (cur + " " + word).strip()
        if draw.textlength(probe, font=font) <= max_w or not cur:
            cur = probe
        else:
            lines.append(cur); cur = word
    if cur:
        lines.append(cur)
    return lines


def wrap_text(draw, text, font, max_w, lang):
    return wrap_cjk(draw, text, font, max_w) if lang != "en" else wrap_words(draw, text, font, max_w)


def fit_lines(draw, text, base_size, max_w, max_lines, lang, weight="bold"):
    """从 base_size 往下缩，直到断行数 <= max_lines（英文长标题不能撑成三行）。"""
    size = base_size
    while size > 14:
        f = load_font(size, weight, lang)
        lines = wrap_text(draw, text, f, max_w, lang)
        if len(lines) <= max_lines:
            if lang == "en" and len(lines) == 2:
                balanced = balance_two_lines(draw, text, f, max_w)
                if balanced is not None:
                    lines = balanced
            return size, f, lines
        size = round(size * 0.94)
    f = load_font(14, weight, lang)
    return 14, f, wrap_text(draw, text, f, max_w, lang)


def balance_two_lines(draw, text: str, font, max_w: int):
    """两行标题时把断点挪到让两行宽度最接近的位置。

    贪心断行会给出 "Everything in One / Place" 这种尾巴只有一个词的排版，
    这里枚举所有断点，取两行宽度差最小且都塞得下的那个。
    """
    words = text.split()
    if len(words) < 2:
        return None
    best = None
    for i in range(1, len(words)):
        l1, l2 = " ".join(words[:i]), " ".join(words[i:])
        w1, w2 = draw.textlength(l1, font=font), draw.textlength(l2, font=font)
        if w1 <= max_w and w2 <= max_w:
            score = abs(w1 - w2)
            if best is None or score < best[0]:
                best = (score, [l1, l2])
    return None if best is None else best[1]


def text_image(text: str, font, fill, margin: int = 8) -> Image.Image:
    """把一行文字画进一张刚好装下它的透明图（用于整行旋转）。"""
    probe = ImageDraw.Draw(Image.new("RGBA", (4, 4)))
    w = math.ceil(probe.textlength(text, font=font))
    asc, desc = font.getmetrics()
    img = Image.new("RGBA", (w + margin * 2, asc + desc + margin * 2), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((margin, margin), text, font=font, fill=fill)
    return img


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def device_layer(frame: Image.Image, target_h: int, bezel: int, radius: int):
    """把原始帧缩放到目标高度，加圆角 + 描边，返回 (图层, 尺寸)。"""
    w = round(frame.width * target_h / frame.height)
    shot = frame.resize((w, target_h), Image.LANCZOS).convert("RGB")
    inner_r = radius - bezel
    shot = shot.convert("RGBA")
    shot.putalpha(rounded_mask((w, target_h), inner_r))
    layer = Image.new("RGBA", (w + bezel * 2, target_h + bezel * 2), (0, 0, 0, 0))
    layer.paste(shot, (bezel, bezel), shot)
    ImageDraw.Draw(layer).rounded_rectangle(
        [0, 0, layer.width - 1, layer.height - 1], radius=radius,
        outline=(255, 255, 255, 235), width=bezel)
    return layer


def compose(group: str, frame_path: str, headline: str, subtitle: str, palette: str,
            brand: str = "learnOH", out_path: str | None = None,
            lang: str = "zh", title_rotate: str = "none") -> Image.Image:
    W, H = SIZES[group]
    pal = TRI[group] if palette == "tri" else PALETTES[palette]
    canvas = gradient(W, H, pal["top"], pal["bottom"]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    pad = round(W * 0.055)
    # 竖排节奏基准：横版按高度算（16:9 的画布高度小、宽度大），竖版按宽度算。
    S = H if group == "landscape" else W
    brand_f = load_font(round(S * 0.028), "bold", lang)
    head_base = round(S * 0.082)
    sub_f = load_font(round(S * 0.034), "regular", lang)

    # 文案块。竖版（手机/平板）居中排；横版仍靠左，给右侧设备让位。
    text_x, text_w = pad, W - pad * 2

    def put(text: str, cx: int, cy: int, font, fill, anchor: str):
        draw.text((cx, cy), text, font=font, fill=fill, anchor=anchor)

    if group == "landscape" and title_rotate in ("cw", "ccw"):
        # 横版 + 拉丁文：整行标题**旋转 90°**（拉丁文没有逐字竖排的传统）。
        # cw = 顺时针，自上而下读；ccw = 逆时针，自下而上读。
        avail_h = H - round(H * 0.16)
        size = head_base
        head_f = load_font(size, "bold", lang)
        while size > 14 and math.ceil(draw.textlength(headline, font=head_f)) > avail_h:
            size = round(size * 0.94)
            head_f = load_font(size, "bold", lang)
        layer = text_image(headline, head_f, hex_rgb(pal["title"]))
        layer = layer.rotate(-90 if title_rotate == "cw" else 90, expand=True, resample=Image.BICUBIC)
        canvas.alpha_composite(layer, (pad, (H - layer.height) // 2))
        left_w = pad + layer.width + round(S * 0.07)
        put(brand, pad, H - round(H * 0.048), brand_f, hex_rgb(pal["accent"]), "lm")
    elif group == "landscape" and lang == "en":
        # 横版英文 + --title-rotate none：标题**横排**在左栏（拉丁文最自然的读法），
        # 左栏宽度固定，设备区按剩余宽度反推。
        col_w = round(W * 0.30)
        size, head_f, head_lines = fit_lines(draw, headline, head_base, col_w, 3, lang)
        line_h = round(size * 1.18)
        y_top = round((H - line_h * len(head_lines)) / 2)
        for i, line in enumerate(head_lines):
            put(line, pad, y_top + i * line_h + size // 2, head_f, hex_rgb(pal["title"]), "lm")
        left_w = pad + col_w + round(S * 0.04)
        put(brand, pad, H - round(H * 0.048), brand_f, hex_rgb(pal["accent"]), "lm")
    elif group == "landscape":
        # 横版中文：标题**竖排**在左（传统竖排，先右列后左列），应用名在左下角，画面占右侧大部。
        # 用 "|" 显式指定竖排列的断点（例：作业成绩|同屏显示），避免把词从中间劈开。
        head_f = load_font(head_base, "bold", lang)
        parts = [p for p in headline.split("|") if p]
        ncols = len(parts)
        step_y = round(head_f.size * 1.10)
        step_x = round(head_f.size * 1.20)
        block_h = max(len(p) for p in parts) * step_y
        y_top = round((H - block_h) / 2)
        for c, part in enumerate(parts):
            col_x = pad + (ncols - 1 - c) * step_x   # 传统竖排：先右列后左列
            for i, ch in enumerate(part):
                put(ch, col_x, y_top + i * step_y + head_f.size // 2, head_f, hex_rgb(pal["title"]), "mm")
        left_w = pad + ncols * step_x + round(S * 0.06)
        put(brand, pad, H - round(H * 0.048), brand_f, hex_rgb(pal["accent"]), "lm")
    else:
        y = round(H * 0.030)                  # 顶部留白压到 3%
        y += round(brand_f.size * 1.9)
        head_size, head_f, head_lines = fit_lines(draw, headline, head_base, text_w, 2, lang)
        for line in head_lines:
            put(line, W // 2, y + head_size // 2, head_f, hex_rgb(pal["title"]), "mm")
            y += round(head_size * 1.18)
        if subtitle:
            y += round(sub_f.size * 0.3)
            for line in wrap_text(draw, subtitle, sub_f, text_w, lang):
                put(line, W // 2, y + sub_f.size // 2, sub_f, hex_rgb(pal["sub"]), "mm")
                y += round(sub_f.size * 1.3)

    # 设备区
    frame = Image.open(frame_path)
    bezel = max(6, round(W * 0.006))
    if group == "landscape":
        pad_r = round(W * 0.035)
        avail_w = W - left_w - pad_r
        target_h = min(H - round(H * 0.10), round(avail_w * frame.height / frame.width))
        layer = device_layer(frame, target_h, bezel, radius=round(W * 0.016))
        x = W - pad_r - layer.width
        y0 = (H - layer.height) // 2
    else:
        top_margin = y + round(head_size * 0.35)
        bottom_margin = round(H * 0.075)
        target_h = H - top_margin - bottom_margin
        layer = device_layer(frame, target_h, bezel, radius=round(W * 0.030))
        x = (W - layer.width) // 2
        y0 = top_margin

    # 投影
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [x + bezel, y0 + bezel + round(S * 0.012), x + layer.width - bezel, y0 + layer.height],
        radius=round(W * 0.030), fill=(0, 0, 0, pal["shadow"]))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(round(S * 0.020))))
    canvas.alpha_composite(layer, (x, y0))

    # 竖版：应用名底部居中；横版的应用名已在左侧左下角画过。
    if group != "landscape":
        draw2 = ImageDraw.Draw(canvas)
        draw2.text((W // 2, H - round(H * 0.030)), brand, font=brand_f,
                   fill=hex_rgb(pal["accent"]), anchor="mm")

    out = canvas.convert("RGB")
    if out_path:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        out.save(out_path, "PNG", optimize=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--group", required=True, choices=list(SIZES))
    ap.add_argument("--frame", required=True)
    ap.add_argument("--headline", required=True)
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--palette", default="brand", choices=list(PALETTES))
    ap.add_argument("--brand", default="learnOH")
    ap.add_argument("--lang", default="zh", choices=["zh", "en"])
    ap.add_argument("--title-rotate", default="none", choices=["none", "cw", "ccw"])
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    img = compose(a.group, a.frame, a.headline, a.subtitle, a.palette, a.brand, a.out,
                  a.lang, a.title_rotate)
    print(f"wrote {a.out} {img.size[0]}x{img.size[1]} ({os.path.getsize(a.out)/1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
