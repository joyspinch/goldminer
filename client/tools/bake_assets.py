#!/usr/bin/env python3
"""bake_assets.py — 黄金矿工 素材流水线（统一命名 + 瘦身 + 朝向精灵表 + UI 底板）。

为什么要有这个脚本
------------------
1. **统一成一套**：老版小图（`x.png`）与新版 AI 美术（`x2.png`）并存两套，
   运行时还留着「优先 x2、回退 x」的分支。流水线把新版美术统一落成
   `x.png` 一套，老版整批删除，运行时只认一个名字。
2. **压体积**：原图是 1024² 级别的未处理素材，入库 3.4MB。这里按
   **实际显示尺寸的 2 倍**缩放并做调色板量化——屏幕上最多就那么点像素，
   留着 4 倍分辨率只是白占仓库。
3. **朝向帧**：引擎运行时转不了图（`Canvas.BlitImage` 只有源矩形，没有
   旋转、没有水平翻转），所以爪子的方向帧与矿工的左右帧必须离线烘好。
4. **UI 底板**：画布 HUD 面板走九宫格自切的美术底板（引擎没有
   border-image，九宫格得自己裁源矩形拼 9 块）。底板是程序化生成的，
   不进 AI 素材流程。

原图不入库
----------
产物即入库素材（`client/assets/`）。原图只在 git 历史里，需要重跑流水线时：

    git archive 2fda476 client/assets | tar -x -C build/art_raw
    python client/tools/bake_assets.py --src build/art_raw --dst client/assets

`--ui-only` 只重生成程序化 UI 底板（不需要原图，随时可跑）。

用法
----
    python client/tools/bake_assets.py [--src DIR] [--dst DIR] [--ui-only]
"""

import argparse
import os
import shutil

from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# 尺寸口径（与 client/src/GoldminerFacing.zan 钉死，改这里必须同步改那里）
# ---------------------------------------------------------------------------

# 爪方向精灵表：12 帧覆盖摆角区间 [25,155]，步长 130/12 ≈ 10.833°。
CLAW_FRAMES = 12
CLAW_MIN_ANGLE = 25.0
CLAW_MAX_ANGLE = 155.0
# 原图 93×110，绿色指示灯在 (42..51, 5..13)——铰点取爪顶正中 (46, 2)。
CLAW_HINGE_SRC = (46, 2)
# 帧画布：绕铰点旋转 ±65° 后的并集包围盒 + 1px 余量。
CLAW_FRAME_W = 240
CLAW_FRAME_H = 151
CLAW_HINGE_X = 120
CLAW_HINGE_Y = 43
# 爪子原画高度（源像素）；运行时按 ClawDisplayH/CLAW_ART_H 缩放。
CLAW_ART_H = 110

# 矿工朝向精灵表：两帧（原图 / 水平镜像），每帧 190×272。
MINER_FRAME_W = 190
MINER_FRAME_H = 272

# 物品表：kind → (纹理基名, 显示半径)。显示长边 = rad*2，入库长边 = rad*4。
ITEMS = [
    ("gold_s", 24), ("gold_m", 30), ("gold_l", 38), ("diamond", 26),
    ("chest", 34), ("bag", 30), ("rock", 34), ("skull", 26),
    ("tnt", 30), ("bomb", 24), ("coin", 18),
]

# 入库长边覆盖：炸弹这张图一图两用——场上是「炸弹」道具，拆弹面板里
# 是同一张弹体（58×72 显示）。按面板的 2 倍留，场上那点像素富余。
ITEM_LONG_EDGE = {"bomb": 160}

# 背景带：营地(天空) / 地层(岩层)。
BAND_W, BAND_H = 640, 427
BAND_COLORS_SKY = 64
BAND_COLORS_ROCK = 48

# 界面底板尺寸（九宫格源图）。
BOARD_W, BOARD_H = 64, 64
BOARD_BORDER = 16
TROUGH_W, TROUGH_H = 48, 16
TROUGH_BORDER = 5
GAUGE_W, GAUGE_H = 48, 14
GAUGE_BORDER = 4

# 配色（与 client/src/GoldminerPalette.zan 一一对应）。
GOLD = (232, 190, 96)
GOLD_DEEP = (168, 122, 42)
GOLD_EDGE = (255, 226, 158)
ROCK = (58, 50, 44)
ROCK_LIGHT = (84, 73, 62)
ROCK_DARK = (26, 22, 19)
ORE = (122, 96, 58)
ORE_BRIGHT = (168, 136, 74)
ALERT = (188, 72, 48)
ALERT_DEEP = (120, 34, 22)
INK = (18, 15, 12)


def kb(n):
    return "%.1f KB" % (n / 1024.0)


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------

def mirror_clean(img):
    """水平镜像且不产生黑边：RGB 预乘 alpha → 镜像 → 反预乘。"""
    import numpy as np
    img = img.convert("RGBA")
    alpha = np.asarray(img.split()[3], dtype=np.float32) / 255.0
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    pre = Image.fromarray(
        np.clip(rgb * alpha[:, :, None], 0, 255).astype(np.uint8), "RGB")
    mpre = np.asarray(pre.transpose(Image.FLIP_LEFT_RIGHT), dtype=np.float32)
    malpha = np.asarray(
        img.split()[3].transpose(Image.FLIP_LEFT_RIGHT), dtype=np.float32) / 255.0
    safe = np.maximum(malpha, 1e-3)[:, :, None]
    straight = np.clip(mpre / safe, 0, 255).astype(np.uint8)
    out = Image.fromarray(straight, "RGB").convert("RGBA")
    out.putalpha(Image.fromarray(
        (np.clip(malpha, 0.0, 1.0) * 255.0).astype(np.uint8), "L"))
    return out


def recut_alpha(img, floor_alpha=6):
    """重新抠 alpha：近透明像素整个丢掉，透明像素的 RGB 清零（不留脏边）。"""
    import numpy as np
    img = img.convert("RGBA")
    arr = np.asarray(img).copy()
    a = arr[:, :, 3]
    dead = a < floor_alpha
    arr[dead, 3] = 0
    arr[dead, 0] = 0
    arr[dead, 1] = 0
    arr[dead, 2] = 0
    return Image.fromarray(arr, "RGBA")


def scale_to(img, long_edge):
    """等比缩放到长边 = long_edge（不放大）。"""
    w, h = img.size
    m = max(w, h)
    if m <= long_edge:
        return img
    s = long_edge / float(m)
    return img.resize((max(1, int(round(w * s))), max(1, int(round(h * s)))),
                      Image.LANCZOS)


def quantize_alpha(img, colors=200):
    """带 alpha 的调色板量化（FASTOCTREE 保 alpha）。"""
    img = img.convert("RGBA")
    if img.mode == "P":
        return img
    q = img.quantize(colors=colors, method=Image.FASTOCTREE, dither=Image.NONE)
    return q


def quantize_opaque(img, colors=64):
    """不透明图的调色板量化（中位切分）。"""
    return img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT,
                                       dither=Image.FLOYDSTEINBERG)


def save(img, path):
    img.save(path, optimize=True)
    print("  %-22s %-11s %s" % (os.path.basename(path),
                                 "%dx%d" % img.size, kb(os.path.getsize(path))))


# ---------------------------------------------------------------------------
# 朝向精灵表
# ---------------------------------------------------------------------------

def bake_claw_sheet(src_path, dst_path):
    """爪子方向精灵表：绕铰点旋转成 12 帧，覆盖摆角区间 [25,155]。

    帧 i 对应游戏摆角 25 + i*(130/12)。原图垂直向下（= 摆角 90），
    正好落在第 6 帧——运行时按角度取帧即可，绳头永远接在铰点上。
    """
    import math
    base = recut_alpha(Image.open(src_path).convert("RGBA"))
    hx, hy = CLAW_HINGE_SRC
    step = (CLAW_MAX_ANGLE - CLAW_MIN_ANGLE) / CLAW_FRAMES
    sheet = Image.new("RGBA", (CLAW_FRAME_W * CLAW_FRAMES, CLAW_FRAME_H),
                      (0, 0, 0, 0))
    for i in range(CLAW_FRAMES):
        game_angle = CLAW_MIN_ANGLE + i * step
        delta = math.radians(game_angle - 90.0)
        cos_d, sin_d = math.cos(delta), math.sin(delta)
        # 输出像素 → 输入像素：input = 源铰点 + R(-Δ)·(输出 - 帧铰点)。
        # 帧铰点是固定点，所以每一帧的绳头位置都一样，运行时只要把帧铰点
        # 对到绳尾即可，绳子与爪头不会错位。
        hx_out, hy_out = CLAW_HINGE_X, CLAW_HINGE_Y
        a = cos_d
        b = sin_d
        c = hx - cos_d * hx_out - sin_d * hy_out
        d = -sin_d
        e = cos_d
        f = hy + sin_d * hx_out - cos_d * hy_out
        frame = base.transform((CLAW_FRAME_W, CLAW_FRAME_H), Image.AFFINE,
                               (a, b, c, d, e, f), resample=Image.BILINEAR,
                               fillcolor=(0, 0, 0, 0))
        sheet.paste(frame, (i * CLAW_FRAME_W, 0), frame)
    save(quantize_alpha(sheet, 96), dst_path)
    return step


def bake_miner_sheet(src_path, dst_path):
    """矿工朝向精灵表：帧 0 = 原图，帧 1 = 水平镜像。

    原图是正面视角，靠镜像翻面：镐在观者左侧，镜像后跑到观者右侧，
    朝向一眼可辨。帧 0 = 钩子在观者右侧，帧 1 = 钩子在观者左侧。
    """
    base = recut_alpha(scale_to(Image.open(src_path).convert("RGBA"),
                                MINER_FRAME_H))
    base = base.resize((MINER_FRAME_W, MINER_FRAME_H), Image.LANCZOS)
    left = recut_alpha(mirror_clean(base))
    sheet = Image.new("RGBA", (MINER_FRAME_W * 2, MINER_FRAME_H), (0, 0, 0, 0))
    sheet.paste(base, (0, 0), base)
    sheet.paste(left, (MINER_FRAME_W, 0), left)
    save(quantize_alpha(sheet, 160), dst_path)


# ---------------------------------------------------------------------------
# 程序化 UI 底板（九宫格）
# ---------------------------------------------------------------------------

def bevel_box(w, h, radius, body, top, bottom, edge, width=2):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=body + (246,),
                         outline=edge + (255,), width=width)
    d.rounded_rectangle([width, width, w - 1 - width, h - 1 - width],
                        radius=max(1, radius - 2), outline=top + (200,), width=1)
    d.rounded_rectangle([width, h - 1 - width * 2, w - 1 - width, h - 1 - width],
                        radius=max(1, radius - 2), outline=bottom + (210,), width=1)
    return img


def make_hud_board():
    """HUD 顶栏底板：岩层横梁 + 金色顶边 + 四角铆钉。

    中间区会被横向拉到全屏宽，所以中间必须保持平滑——纹理放角上。
    """
    w, h = BOARD_W, BOARD_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=ROCK + (242,))
    d.rectangle([0, 0, w - 1, 5], fill=GOLD_DEEP + (255,))
    d.rectangle([0, 0, w - 1, 2], fill=GOLD_EDGE + (255,))
    d.rectangle([0, 6, w - 1, 8], fill=ROCK_LIGHT + (200,))
    d.rectangle([0, h - 4, w - 1, h - 1], fill=ROCK_DARK + (255,))
    d.rectangle([0, h - 5, w - 1, h - 5], fill=GOLD_DEEP + (190,))
    # 角上铆钉（落在角切片里，拉伸不变形）
    for (cx, cy) in ((6, 10), (w - 7, 10), (6, h - 9), (w - 7, h - 9)):
        d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=ORE_BRIGHT + (255,))
        d.ellipse([cx - 1, cy - 1, cx + 1, cy + 1], fill=ROCK_DARK + (255,))
    return img


def make_bomb_board():
    """拆弹面板底板：黑铁板 + 红色警示边。"""
    w, h = BOARD_W, BOARD_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=INK + (238,))
    d.rectangle([0, 0, w - 1, 4], fill=ALERT + (255,))
    d.rectangle([0, 4, w - 1, 6], fill=ALERT_DEEP + (255,))
    d.rectangle([0, h - 3, w - 1, h - 1], fill=ALERT_DEEP + (255,))
    for (cx, cy) in ((6, 12), (w - 7, 12), (6, h - 10), (w - 7, h - 10)):
        d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=ALERT + (255,))
    return img


def make_trough():
    """进度条凹槽：暗槽 + 铜边。"""
    w, h = TROUGH_W, TROUGH_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=3, fill=(22, 19, 16, 255),
                         outline=ORE + (255,), width=1)
    d.rectangle([1, 1, w - 2, 2], fill=(8, 7, 6, 200))
    return img


def make_gauge():
    """进度条填充：金矿脉条。"""
    w, h = GAUGE_W, GAUGE_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=GOLD_DEEP + (255,))
    d.rectangle([0, 0, w - 1, 3], fill=GOLD + (255,))
    d.rectangle([0, 0, 2, h - 1], fill=GOLD_EDGE + (255,))
    d.rectangle([0, h - 2, w - 1, h - 1], fill=(96, 68, 24, 255))
    return img


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def migrate(src, dst):
    os.makedirs(dst, exist_ok=True)
    print("== 物品贴图（统一成 x.png 一套，长边 = 半径×4） ==")
    for tex, rad in ITEMS:
        raw = os.path.join(src, tex + "2.png")
        if not os.path.exists(raw):
            raw = os.path.join(src, tex + ".png")
        if not os.path.exists(raw):
            print("  !! 缺少源图：%s" % tex)
            continue
        img = Image.open(raw).convert("RGBA")
        edge = ITEM_LONG_EDGE.get(tex, rad * 4)
        img = scale_to(img, edge)
        img = quantize_alpha(img, 200)
        save(img, os.path.join(dst, tex + ".png"))

    print("== 场景与物件 ==")
    camp = os.path.join(src, "camp2.png")
    if os.path.exists(camp):
        img = Image.open(camp).convert("RGB").resize((BAND_W, BAND_H), Image.LANCZOS)
        save(quantize_opaque(img, BAND_COLORS_SKY),
             os.path.join(dst, "camp.png"))
    mine = os.path.join(src, "mine2.png")
    if os.path.exists(mine):
        img = Image.open(mine).convert("RGB").resize((BAND_W, BAND_H), Image.LANCZOS)
        save(quantize_opaque(img, BAND_COLORS_ROCK),
             os.path.join(dst, "mine.png"))
    glow = os.path.join(src, "glow2.png")
    if os.path.exists(glow):
        img = Image.open(glow).convert("RGBA")
        img = scale_to(img, 192)
        save(quantize_alpha(img, 64), os.path.join(dst, "glow.png"))
    bg = os.path.join(src, "bg.jpg")
    if os.path.exists(bg):
        img = Image.open(bg).convert("RGB")
        img = img.resize((640, 480), Image.LANCZOS)
        out = os.path.join(dst, "bg.jpg")
        img.save(out, quality=72, optimize=True)
        print("  %-22s %-11s %s" % ("bg.jpg", "640x480",
                                    kb(os.path.getsize(out))))
    dyn = os.path.join(src, "dyn2.png")
    if os.path.exists(dyn):
        img = scale_to(Image.open(dyn).convert("RGBA"), 120)
        save(quantize_alpha(img, 160), os.path.join(dst, "dynamite.png"))

    print("== 朝向精灵表 ==")
    claw = os.path.join(src, "claw.png")
    if os.path.exists(claw):
        step = bake_claw_sheet(claw, os.path.join(dst, "claw_sheet.png"))
        print("  帧步长 = %.4f°（覆盖 %.0f..%.0f）" % (
            step, CLAW_MIN_ANGLE, CLAW_MAX_ANGLE))
    miner = os.path.join(src, "miner2.png")
    if os.path.exists(miner):
        bake_miner_sheet(miner, os.path.join(dst, "miner_sheet.png"))


def bake_ui(dst):
    os.makedirs(dst, exist_ok=True)
    print("== 程序化 UI 底板 ==")
    save(make_hud_board(), os.path.join(dst, "ui_hud_board.png"))
    save(make_bomb_board(), os.path.join(dst, "ui_bomb_board.png"))
    save(make_trough(), os.path.join(dst, "ui_trough.png"))
    save(make_gauge(), os.path.join(dst, "ui_gauge.png"))


def prune(dst, src):
    """删掉被取代的老文件：x2 一套、老版小图、未引用的结果图与顶栏图。"""
    print("== 清理被取代的老文件 ==")
    legacy = []
    for tex, _ in ITEMS:
        legacy.append(tex + "2.png")
    legacy += ["camp2.png", "mine2.png", "glow2.png", "dyn2.png", "bomb2.png",
               "miner2.png", "miner.png", "result2.png", "top2.png", "claw.png"]
    for name in legacy:
        p = os.path.join(dst, name)
        if os.path.exists(p):
            os.remove(p)
            print("  删除 %s" % name)


def report(dst):
    total = 0
    files = []
    for root, _, names in os.walk(dst):
        for n in names:
            p = os.path.join(root, n)
            size = os.path.getsize(p)
            total += size
            files.append((size, os.path.relpath(p, dst).replace("\\", "/")))
    files.sort(reverse=True)
    print("== 产物清单（%s，共 %s） ==" % (dst, kb(total)))
    for size, rel in files:
        print("  %9s  %s" % (kb(size), rel))
    return total


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--src", default=os.path.join(root, "client", "assets"))
    ap.add_argument("--dst", default=os.path.join(root, "client", "assets"))
    ap.add_argument("--ui-only", action="store_true",
                    help="只重生成程序化 UI 底板（不需要原图）")
    ap.add_argument("--no-prune", action="store_true", help="不删老文件")
    args = ap.parse_args()

    if args.ui_only:
        bake_ui(args.dst)
        report(args.dst)
        return

    migrate(args.src, args.dst)
    bake_ui(args.dst)
    if not args.no_prune:
        prune(args.dst, args.src)
    report(args.dst)


if __name__ == "__main__":
    main()
