"""Arma docs/manual/Manual_de_uso.docx con las capturas de docs/manual/img/.

    flutter test tool/screenshots/manual_screenshots_test.dart   # capturas
    python tool/manual/build_manual.py                           # documento

Necesita: pip install python-docx pillow
"""
from pathlib import Path

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IMG = ROOT / "docs" / "manual" / "img"
OUT = ROOT / "docs" / "manual" / "Manual_de_uso.docx"
CROPPED = ROOT / "docs" / "manual" / "img" / "_recortes"

ACCENT = RGBColor(0x44, 0x5E, 0x91)

# Alto (px) hasta donde hay contenido en cada captura (el resto es fondo vacío).
CROP = {
    "01_principal": 830,
    "02_agregar": 940,
    "03_corte_ticket": 1080,
    "04_corte_dia": 1200,
    "05_jira": 900,
    "06_ventana": 1140,
    "07_cerrar": 960,
    "08_vista_simple": 300,
    "09_filtros": 1140,
}


def crop(name: str) -> Path:
    CROPPED.mkdir(exist_ok=True)
    img = Image.open(IMG / f"{name}.png")
    img = img.crop((0, 0, img.width, min(CROP[name], img.height)))
    path = CROPPED / f"{name}.png"
    img.save(path)
    return path


def shade(cell, hex_fill: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    tc_pr.append(shd)


def no_borders(table) -> None:
    tbl_pr = table._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "nil")
        borders.append(el)
    tbl_pr.append(borders)


doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21), Cm(29.7)
sec.left_margin = sec.right_margin = Cm(2)
sec.top_margin = sec.bottom_margin = Cm(1.8)

base = doc.styles["Normal"]
base.font.name = "Calibri"
base.font.size = Pt(11)
base.paragraph_format.space_after = Pt(3)


def heading(text: str) -> None:
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(15)
    r.font.color.rgb = ACCENT


def bullets(cell_or_doc, items) -> None:
    for item in items:
        p = cell_or_doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.5)
        p.paragraph_format.first_line_indent = Cm(-0.4)
        p.paragraph_format.space_after = Pt(3)
        p.add_run("•  ")
        if isinstance(item, tuple):
            r = p.add_run(item[0])
            r.bold = True
            p.add_run(item[1])
        else:
            p.add_run(item)


def picture(cell, name: str, width_cm: float) -> None:
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(str(crop(name)), width=Cm(width_cm))


def row(left_name, items, img_w=7.2, img_left=True, caption_cell=None) -> None:
    """Captura a un lado y la explicación breve al otro."""
    t = doc.add_table(rows=1, cols=2)
    no_borders(t)
    t.autofit = False
    a, b = t.rows[0].cells
    img_cell, txt_cell = (a, b) if img_left else (b, a)
    a.width, b.width = (Cm(img_w + 0.4), Cm(17 - img_w - 0.4)) if img_left else (
        Cm(17 - img_w - 0.4), Cm(img_w + 0.4))
    picture(img_cell, left_name, img_w)
    txt_cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    txt_cell.paragraphs[0].paragraph_format.space_after = Pt(0)
    bullets(txt_cell, items)
    # El primer párrafo vacío de la celda de texto sobra.
    first = txt_cell.paragraphs[0]
    if not first.text:
        first._element.getparent().remove(first._element)


def pair(left_name, right_name, left_cap, right_cap, w=8.2) -> None:
    """Dos capturas lado a lado con su pie."""
    t = doc.add_table(rows=2, cols=2)
    no_borders(t)
    for i, (name, cap) in enumerate(((left_name, left_cap), (right_name, right_cap))):
        picture(t.rows[0].cells[i], name, w)
        c = t.rows[1].cells[i].paragraphs[0]
        c.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = c.add_run(cap)
        r.italic = True
        r.font.size = Pt(9.5)


# ---------------------------------------------------------------- portada breve
p = doc.add_paragraph()
r = p.add_run("my-jira-work-time")
r.bold = True
r.font.size = Pt(28)
r.font.color.rgb = ACCENT
p.paragraph_format.space_after = Pt(0)
p = doc.add_paragraph()
r = p.add_run("Manual de uso")
r.font.size = Pt(14)
r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
p = doc.add_paragraph("Cronometra tus tickets y súbelos a Jira.")

# ---------------------------------------------------------------- 1
heading("1. Pantalla principal")
row("01_principal", [
    ("Play / Pausa: ", "inicia o detiene el ticket. Solo corre uno a la vez."),
    ("Ticket en Backlog: ", "al dar play pregunta si lo pones en curso en Jira."),
    ("Limpiar: ", "deja el tiempo en cero."),
    ("Nube: ", "corta y envía el tiempo a Jira."),
    ("Info: ", "detalle del ticket."),
    ("Chip de estado: ", "púlsalo para cambiar el estado del ticket en Jira."),
    ("Hoy 2 h 57 m / 8 h: ", "tu avance del día frente a la meta."),
    ("Barra superior: ", "vista simple, Jira, Ventana (engranaje) y + para agregar."),
])

# ---------------------------------------------------------------- 1b
heading("Buscar, ordenar y filtrar")
row("09_filtros", [
    ("Buscar: ", "escribe en el cuadro de arriba (nombre, clave o descripción)."),
    ("Ordenar: ", "primer icono de la fila: original, nombre, más tiempo, por estado o en curso primero."),
    ("Filtros: ", "segundo icono: estados de Jira, origen, en curso o pausados."),
    ("Finalizados: ", "se ocultan por defecto (no los que corren o tienen tiempo por subir); «Mostrar finalizados» los trae."),
    ("Atajos: ", "con tiempo por subir y arrastran tiempo de otro día."),
    ("Limpiar: ", "aparece «Mostrando X de Y · Limpiar» cuando hay filtros. Se recuerdan al reabrir."),
], img_left=False)

# ---------------------------------------------------------------- 2
heading("2. Agregar un ticket")
row("02_agregar", [
    "Pulsa + y escribe el nombre.",
    "Descripción y enlace son opcionales.",
    "Pulsa Guardar.",
    "Los tickets de Jira se traen solos con Sincronizar (paso 3).",
], img_left=False)

# ---------------------------------------------------------------- 3
heading("3. Conectar con Jira")
row("05_jira", [
    "Pulsa Jira e inicia sesión en el navegador.",
    "La primera vez pide el Client ID y Secret de tu app de Atlassian (botón Credenciales).",
    "Pulsa Sincronizar para traer los tickets asignados a ti.",
    ("Automático: ", "después se sincroniza solo cada 2 horas (se apaga en Ventana)."),
])

# ---------------------------------------------------------------- 4
heading("4. Enviar tiempo a Jira")
pair("03_corte_ticket", "04_corte_dia",
     "Un ticket: nube del ticket", "Todos: nube junto a «Hoy»")
bullets(doc, [
    ("Un ticket: ", "ajusta horas y minutos y pulsa Enviar a Jira."),
    ("Varios: ", "en el Corte del día elige el día trabajado y pulsa Subir o Subir todos."),
    ("Reiniciar el cronómetro: ", "déjalo marcado para empezar de cero después de subir."),
    ("Ojo: ", "un ticket con tiempo de un día anterior no se puede iniciar hasta subirlo o limpiarlo."),
])

# ---------------------------------------------------------------- 5
heading("5. Vista simple")
row("08_vista_simple", [
    "Con un ticket en curso, pulsa el pin de la barra superior.",
    "Queda una ventana pequeña con el nombre, el tiempo y la transparencia.",
    "Para volver: botón de la esquina, doble clic en el nombre o Esc.",
], img_w=6.5)

# ---------------------------------------------------------------- 6
heading("6. Ventana y cierre")
pair("06_ventana", "07_cerrar",
     "Engranaje: transparencia, siempre encima y confirmar al cerrar",
     "Al cerrar con un ticket corriendo")
bullets(doc, [
    ("Sincronizar Jira automáticamente: ", "trae tus tickets cada 2 horas con la app abierta."),
    ("Confirmar al cerrar: ", "pregunta antes de salir (se puede apagar en Ventana)."),
    ("Pausar y cerrar: ", "detiene el ticket y sale."),
    ("Subir a Jira y cerrar: ", "pausa, sube el tiempo y sale; si Jira falla, no cierra."),
    ("Dejar corriendo: ", "sale sin tocar nada; el tiempo sigue contando al volver a abrir."),
])

p = doc.add_paragraph()
p.paragraph_format.space_before = Pt(10)
r = p.add_run("Todo se guarda automáticamente: no hay que pulsar «guardar» para conservar tus tiempos.")
r.italic = True
r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

doc.save(OUT)
print("Escrito:", OUT)
