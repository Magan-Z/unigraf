"""Собирает картинки для главной страницы сайта (data/web): снимки экранов, картинку для превью ссылки, QR и шрифт.

Нужны библиотеки из tools/requirements-assets.txt (в CI не нужны: готовые файлы лежат в репозитории).
Порядок:
  1) cd app && flutter test tool/screenshots_test.dart --plain-name landing    → /tmp/claude-shots/landing/*.png
  2) cd data && python tools/make_landing_assets.py
Файлы появятся в data/web/img, data/web/fonts, data/web/qr.svg и data/web/qr-teacher.svg. Адрес сайта для QR — в SITE_URL.
"""
import os
import shutil
from pathlib import Path

import segno
from fontTools import subset
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "data" / "web"
SHOTS = Path(os.environ.get("LANDING_SHOTS", "/tmp/claude-shots/landing"))
SITE_URL = "https://magan-z.github.io/unigraf/"
TEACHER_URL = SITE_URL + "teacher/"  # страница «ДЗ с компьютера» для преподавателей (QR на листовке)
FONT = ROOT / "app" / "assets" / "fonts" / "Onest.ttf"

PAPER, PETROL, INK, MUTED, AMBER = (251, 248, 243), (0, 26, 99), (26, 32, 34), (85, 98, 106), (242, 169, 59)


def screenshots() -> None:
    (WEB / "img").mkdir(parents=True, exist_ok=True)
    for name in ("today-light", "today-dark", "week-light", "homework-light", "search-free-light", "search-teacher-light"):
        image = Image.open(SHOTS / f"{name}.png").convert("RGB")
        image = image.resize((600, int(600 * image.height / image.width)), Image.LANCZOS)
        image.save(WEB / "img" / f"{name}.webp", "WEBP", quality=82, method=6)
    for icon in ("Icon-192.png", "Icon-512.png", "apple-touch-icon.png"):
        shutil.copy(ROOT / "app" / "web" / "icons" / icon, WEB / "img" / icon)
    shutil.copy(ROOT / "app" / "web" / "favicon.png", WEB / "img" / "favicon.png")


def font(size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([weight])
    return f


def preview_image() -> None:
    """Картинка 1200×630, которую показывают мессенджеры, когда в чат кидают ссылку на сайт."""
    w, h = 1200, 630
    im = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(im)
    d.rectangle((0, h - 26, w, h), fill=PETROL)
    for i in range(5):  # «лента звонков» внизу: пять пар, третья — янтарная
        d.rectangle((70 + 200 * i, h - 26, 190 + 200 * i, h), fill=AMBER if i == 2 else PETROL)
    icon = Image.open(WEB / "img" / "Icon-512.png").convert("RGBA").resize((112, 112))
    mask = Image.new("L", (112, 112), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 111, 111), radius=30, fill=255)
    im.paste(icon, (70, 56), mask)
    d.text((206, 78), "UniGraf", font=font(52, 800), fill=PETROL)
    big = font(70, 800)
    d.text((70, 200), "Пары, аудитории", font=big, fill=INK)
    d.text((70, 276), "и домашка", font=big, fill=INK)
    width = d.textlength("в телефоне", font=big)
    d.rounded_rectangle((66, 416, 66 + width + 8, 446), radius=6, fill=(255, 231, 191))
    d.text((70, 352), "в телефоне", font=big, fill=INK)
    d.text((70, 470), "Для студентов ИМФИТ · Android и iPhone", font=font(30, 500), fill=MUTED)
    d.text((70, 516), "Без регистрации · работает без интернета", font=font(30, 500), fill=MUTED)
    shot = Image.open(SHOTS / "today-light.png").convert("RGB")
    sw = 300
    shot = shot.resize((sw, int(sw * shot.height / shot.width)), Image.LANCZOS)
    frame = Image.new("RGB", (sw + 16, shot.height + 16), INK)
    outer = Image.new("L", frame.size, 0)
    ImageDraw.Draw(outer).rounded_rectangle((0, 0, frame.size[0] - 1, frame.size[1] - 1), radius=44, fill=255)
    inner = Image.new("L", shot.size, 0)
    ImageDraw.Draw(inner).rounded_rectangle((0, 0, sw - 1, shot.height - 1), radius=36, fill=255)
    frame.paste(shot, (8, 8), inner)
    im.paste(frame, (850, 64), outer)
    im.save(WEB / "img" / "og.png", optimize=True)


def qr_code() -> None:
    qr = segno.make(SITE_URL, error="m")
    qr.save(WEB / "qr.svg", scale=10, border=4, dark="#001A63", light="#FFFFFF", xmldecl=False, svgns=True, nl=False)
    teacher = segno.make(TEACHER_URL, error="m")
    teacher.save(WEB / "qr-teacher.svg", scale=10, border=4, dark="#001A63", light="#FFFFFF", xmldecl=False, svgns=True, nl=False)


def web_font() -> None:
    """Onest только с кириллицей и латиницей: ~50 КБ вместо ~190 КБ."""
    options = subset.Options()
    options.flavor = "woff2"
    options.layout_features = ["*"]
    unicodes = (
        list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + list(range(0x400, 0x500))
        + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x201E, 0x2022, 0x2026, 0x2116, 0x20BD, 0x2192, 0x2190, 0xB7, 0x2212, 0x2713]
    )
    font_file = TTFont(str(FONT))
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font_file)
    (WEB / "fonts").mkdir(parents=True, exist_ok=True)
    subset.save_font(font_file, str(WEB / "fonts" / "onest.woff2"), options)


if __name__ == "__main__":
    screenshots()
    preview_image()
    qr_code()
    web_font()
    total = sum(f.stat().st_size for f in WEB.rglob("*") if f.is_file())
    print(f"Готово. Всё в data/web: {total // 1024} КБ")
