#!/bin/bash
# =============================================================================
# Diyar OS — Icon Theme Builder
# scripts/build-icons.sh
#
# يعالج الصور الأصلية ويبني حزمة الأيقونات الرسمية لنظام ديار
# المتطلبات: imagemagick
# الاستخدام: bash scripts/build-icons.sh
# =============================================================================

set -e

# ── التحقق من وجود ImageMagick ────────────────────────────────────────────────
if ! command -v convert &>/dev/null; then
    echo "خطأ: ImageMagick غير مثبت."
    echo "قم بالتثبيت عبر: sudo apt install imagemagick"
    exit 1
fi

# ── المسارات ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RAW_DIR="${ROOT_DIR}/raw_images"
ICON_THEME_DIR="${ROOT_DIR}/diyar-icons"
WALLPAPER_DIR="${ROOT_DIR}/wallpapers"
OUTPUT_DIR="${ROOT_DIR}/output"

# ── أحجام الأيقونات القياسية ──────────────────────────────────────────────────
SIZES=(16 22 24 32 48 64 128 256)

# ── ألوان ديار للتأثيرات ──────────────────────────────────────────────────────
GOLD="#C9963A"
NAVY="#0D1525"
TEAL="#1A6B7C"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   🚀 Diyar OS — بناء حزمة الأيقونات الرسمية          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── دالة تحليل لون الخلفية الغالب ────────────────────────────────────────────
detect_bg_color() {
    local img="$1"
    # أخذ لون الزاوية العلوية اليسرى كمرجع للخلفية
    convert "$img" -format "%[pixel:u.p{0,0}]" info: 2>/dev/null || echo "white"
}

# ── دالة المعالجة الذكية للأيقونة ────────────────────────────────────────────
process_to_icon() {
    local input_file="$1"
    local icon_name="$2"
    local remove_bg="${3:-auto}"   # auto, white, dark, none

    if [[ ! -f "$input_file" ]]; then
        echo "  ⚠  الملف غير موجود: $input_file — تم التخطي"
        return 0
    fi

    echo "  ⚙  معالجة: $(basename "$input_file") → $icon_name"

    # كشف لون الخلفية تلقائياً
    local bg_pixel
    bg_pixel=$(convert "$input_file" -format "%[pixel:u.p{0,0}]" info: 2>/dev/null || echo "white")

    for SIZE in "${SIZES[@]}"; do
        local dest_dir="${ICON_THEME_DIR}/${SIZE}x${SIZE}/apps"
        mkdir -p "$dest_dir"

        local out="${dest_dir}/${icon_name}.png"

        # ── سلسلة المعالجة ──────────────────────────────────────────────────
        if [[ "$remove_bg" == "none" ]]; then
            # بدون إزالة خلفية — فقط تغيير الحجم
            convert "$input_file" \
                -filter Lanczos \
                -resize "${SIZE}x${SIZE}" \
                -gravity Center \
                -extent "${SIZE}x${SIZE}" \
                "$out"
        elif [[ "$remove_bg" == "dark" ]]; then
            # إزالة خلفية داكنة
            convert "$input_file" \
                -fuzz 12% -transparent black \
                -trim +repage \
                -bordercolor transparent -border 4% \
                -filter Lanczos \
                -resize "${SIZE}x${SIZE}" \
                -gravity Center \
                -background transparent \
                -extent "${SIZE}x${SIZE}" \
                "$out"
        else
            # إزالة خلفية بيضاء (الافتراضي)
            # المراحل:
            # 1. إزالة الخلفية البيضاء بـ fuzz للتعامل مع درجاتها
            # 2. قص الهوامش الفارغة
            # 3. إضافة هامش شفاف للحماية
            # 4. تغيير الحجم بخوارزمية Lanczos الدقيقة
            # 5. توسيط في إطار مربع
            convert "$input_file" \
                -fuzz 15% -transparent white \
                -alpha set \
                -trim +repage \
                -bordercolor transparent -border 5% \
                -filter Lanczos \
                -resize "${SIZE}x${SIZE}" \
                -gravity Center \
                -background transparent \
                -extent "${SIZE}x${SIZE}" \
                "$out"
        fi

        # تحسين للأحجام الصغيرة: زيادة حدة الحواف
        if [[ $SIZE -le 32 ]]; then
            convert "$out" \
                -sharpen 0x0.5 \
                "$out"
        fi
    done

    echo "     ✅ تم: ${#SIZES[@]} حجم (16px → 256px)"
}

# ── دالة بناء أيقونة مربعة بحواف دائرية ─────────────────────────────────────
process_to_rounded_icon() {
    local input_file="$1"
    local icon_name="$2"
    local radius="${3:-15}"   # نسبة دائرية الحواف بالبكسل للحجم 256

    if [[ ! -f "$input_file" ]]; then
        echo "  ⚠  الملف غير موجود: $input_file — تم التخطي"
        return 0
    fi

    echo "  ⚙  معالجة (حواف دائرية): $(basename "$input_file") → $icon_name"

    for SIZE in "${SIZES[@]}"; do
        local dest_dir="${ICON_THEME_DIR}/${SIZE}x${SIZE}/apps"
        mkdir -p "$dest_dir"
        local out="${dest_dir}/${icon_name}.png"

        # حساب نسبة دائرية الحواف بناءً على الحجم
        local r=$(( SIZE * radius / 256 ))
        [[ $r -lt 2 ]] && r=2

        # بناء قناع الحواف الدائرية
        local mask="/tmp/diyar_mask_${SIZE}.png"
        convert -size "${SIZE}x${SIZE}" xc:none \
            -draw "roundrectangle 0,0 $((SIZE-1)),$((SIZE-1)) ${r},${r}" \
            "$mask"

        # تطبيق القناع على الصورة
        convert "$input_file" \
            -filter Lanczos \
            -resize "${SIZE}x${SIZE}" \
            -gravity Center \
            -background transparent \
            -extent "${SIZE}x${SIZE}" \
            "$mask" \
            -alpha off \
            -compose CopyOpacity \
            -composite \
            "$out"

        rm -f "$mask"
    done

    echo "     ✅ تم بحواف دائرية: ${#SIZES[@]} حجم"
}

# ── دالة معالجة الخلفية ───────────────────────────────────────────────────────
process_wallpaper() {
    local input_file="$1"
    local output_name="$2"

    if [[ ! -f "$input_file" ]]; then
        echo "  ⚠  خلفية غير موجودة: $input_file — تم التخطي"
        return 0
    fi

    echo "  🖼  معالجة خلفية: $(basename "$input_file") → $output_name"
    mkdir -p "$WALLPAPER_DIR"

    # نسخة 1920x1080 — معيار Full HD
    convert "$input_file" \
        -filter Lanczos \
        -resize "1920x1080^" \
        -gravity Center \
        -extent "1920x1080" \
        -quality 95 \
        "${WALLPAPER_DIR}/${output_name}-1920x1080.jpg"

    # نسخة 2560x1440 — معيار QHD
    convert "$input_file" \
        -filter Lanczos \
        -resize "2560x1440^" \
        -gravity Center \
        -extent "2560x1440" \
        -quality 95 \
        "${WALLPAPER_DIR}/${output_name}-2560x1440.jpg"

    # نسخة 3840x2160 — معيار 4K
    convert "$input_file" \
        -filter Lanczos \
        -resize "3840x2160^" \
        -gravity Center \
        -extent "3840x2160" \
        -quality 95 \
        "${WALLPAPER_DIR}/${output_name}-4K.jpg"

    # نسخة SVG-compatible PNG للاستخدام المباشر في XFCE4
    convert "$input_file" \
        -filter Lanczos \
        -resize "1920x1080^" \
        -gravity Center \
        -extent "1920x1080" \
        "${WALLPAPER_DIR}/${output_name}.png"

    echo "     ✅ خلفية جاهزة: 1080p + 1440p + 4K + PNG"
}

# ── دالة بناء أيقونة الشعار بأحجام متعددة ────────────────────────────────────
process_logo() {
    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        echo "  ⚠  شعار غير موجود: $input_file — تم التخطي"
        return 0
    fi

    echo "  🔷 معالجة الشعار الرسمي..."
    mkdir -p "$OUTPUT_DIR/logo"

    # شعار بخلفية شفافة بأحجام قياسية
    for SIZE in 16 22 24 32 48 64 128 256 512; do
        convert "$input_file" \
            -fuzz 15% -transparent white \
            -trim +repage \
            -filter Lanczos \
            -resize "${SIZE}x${SIZE}" \
            -gravity Center \
            -background transparent \
            -extent "${SIZE}x${SIZE}" \
            "${OUTPUT_DIR}/logo/diyar-logo-${SIZE}.png"
    done

    # أيقونة .ico للاستخدام في GRUB وغيره
    convert "$input_file" \
        -fuzz 15% -transparent white \
        -trim +repage \
        -filter Lanczos \
        -define icon:auto-resize="256,128,64,48,32,22,16" \
        "${OUTPUT_DIR}/logo/diyar-logo.ico"

    echo "     ✅ الشعار: 9 أحجام PNG + ICO"
}

# ═══════════════════════════════════════════════════════════════════════════════
# التنفيذ الرئيسي
# ═══════════════════════════════════════════════════════════════════════════════

echo "── مرحلة ١: معالجة الأيقونات ──────────────────────────"
echo ""

# الشعار الرئيسي
process_logo "${RAW_DIR}/Diyar-logo.jpg"

# الأيقونات بإزالة خلفية بيضاء
process_to_rounded_icon "${RAW_DIR}/Diyar-terminal.jpg"       "utilities-terminal"
process_to_rounded_icon "${RAW_DIR}/Diyar-browser.jpg"        "web-browser"
process_to_rounded_icon "${RAW_DIR}/Diyar-home_file.jpg"      "user-home"
process_to_rounded_icon "${RAW_DIR}/Diyar-home_file.jpg"      "folder-home"
process_to_rounded_icon "${RAW_DIR}/Diyar-Software_Center.jpg" "software-center"
process_to_rounded_icon "${RAW_DIR}/Diyar_setting.jpg"        "preferences-desktop"

# نسخ اسم الشعار كأيقونة التوزيعة
process_to_rounded_icon "${RAW_DIR}/Diyar-logo.jpg"           "distributor-logo-diyar"
process_to_rounded_icon "${RAW_DIR}/Diyar-logo.jpg"           "start-here"

echo ""
echo "── مرحلة ٢: معالجة الخلفيات ────────────────────────────"
echo ""

process_wallpaper "${RAW_DIR}/Diyar_wallpaper.jpg"         "diyar-default"
process_wallpaper "${RAW_DIR}/Diyar-abstract_wallpaper.jpg" "diyar-abstract"

echo ""
echo "── مرحلة ٣: بناء ملف index.theme ──────────────────────"
echo ""

# بناء قائمة المجلدات للـ index.theme
DIRS_LIST=""
for SIZE in "${SIZES[@]}"; do
    DIRS_LIST+="${SIZE}x${SIZE}/apps,"
done
DIRS_LIST="${DIRS_LIST%,}"  # حذف الفاصلة الأخيرة

cat > "${ICON_THEME_DIR}/index.theme" <<EOF
[Icon Theme]
Name=Diyar
Name[ar]=ديار
Comment=Official Icon Theme for Diyar OS — روح الشرق في كل أيقونة
Comment[ar]=ثيم الأيقونات الرسمي لنظام ديار
Encoding=UTF-8

# الثيمات الاحتياطية عند عدم وجود الأيقونة في ديار
Inherits=Papirus-Dark,hicolor

Directories=${DIRS_LIST}

EOF

# إضافة قسم لكل حجم
for SIZE in "${SIZES[@]}"; do
cat >> "${ICON_THEME_DIR}/index.theme" <<EOF
[${SIZE}x${SIZE}/apps]
Size=${SIZE}
Context=Applications
Type=Fixed

EOF
done

echo "  ✅ index.theme جاهز"

echo ""
echo "── مرحلة ٤: بناء هيكل التثبيت ─────────────────────────"
echo ""

mkdir -p "$OUTPUT_DIR"

# سكريبت التثبيت
cat > "${OUTPUT_DIR}/install.sh" <<'INSTALL'
#!/bin/bash
# Diyar OS — تثبيت حزمة الأيقونات والخلفيات
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

echo "[ديار] تثبيت حزمة الأيقونات..."

# أيقونات — للنظام (يحتاج root)
if [[ $EUID -eq 0 ]]; then
    cp -r "${ROOT}/diyar-icons" /usr/share/icons/Diyar
    gtk-update-icon-cache -f -t /usr/share/icons/Diyar
    echo "[OK] أيقونات النظام"

    # خلفيات
    mkdir -p /usr/share/diyar-os/wallpapers
    cp "${ROOT}/wallpapers/"* /usr/share/diyar-os/wallpapers/
    echo "[OK] خلفيات النظام"

    # شعار
    cp "${ROOT}/output/logo/diyar-logo-256.png" /usr/share/pixmaps/diyar-logo.png
    echo "[OK] شعار النظام"
else
    # تثبيت للمستخدم الحالي فقط
    mkdir -p ~/.local/share/icons/Diyar
    cp -r "${ROOT}/diyar-icons/." ~/.local/share/icons/Diyar/
    gtk-update-icon-cache -f -t ~/.local/share/icons/Diyar 2>/dev/null || true

    mkdir -p ~/.local/share/wallpapers
    cp "${ROOT}/wallpapers/"* ~/.local/share/wallpapers/
    echo "[OK] تم التثبيت في المجلد الشخصي"
fi

echo "[ديار] اكتمل التثبيت ✅"
INSTALL
chmod +x "${OUTPUT_DIR}/install.sh"

echo "  ✅ سكريبت التثبيت جاهز"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ✨ اكتملت معالجة الأيقونات بنجاح!                  ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  📁 الأيقونات  : diyar-icons/                        ║"
echo "║  🖼  الخلفيات  : wallpapers/                          ║"
echo "║  🔷 الشعار     : output/logo/                         ║"
echo "║  📦 التثبيت   : output/install.sh                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# إحصاء الملفات المنتجة
ICON_COUNT=$(find "$ICON_THEME_DIR" -name "*.png" 2>/dev/null | wc -l)
WALL_COUNT=$(find "$WALLPAPER_DIR" -name "*.jpg" -o -name "*.png" 2>/dev/null | wc -l)
echo "  إجمالي الأيقونات المنتجة : ${ICON_COUNT} ملف PNG"
echo "  إجمالي الخلفيات          : ${WALL_COUNT} ملف"
echo ""
