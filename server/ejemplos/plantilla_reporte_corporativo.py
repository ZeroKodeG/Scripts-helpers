# -*- coding: utf-8 -*-
"""
PLANTILLA DE REFERENCIA - Reporte PDF con estilo corporativo (ReportLab)
=========================================================================

Este script es una BASE REUTILIZABLE para generar reportes en PDF con el
estilo corporativo definido para el equipo de TI. Contiene datos ficticios
(dummy) de auditoria tecnica unicamente para ilustrar: portada, las 10
secciones canonicas, tablas con color semantico, hallazgos Critico /
Atencion / Informativo y cierre.

En el pipeline de "Generar PDF" del backend, este archivo se copia al
directorio temporal de opencode como REFERENCIA DE ESTILO (paleta, tablas,
hallazgos, tipografia). La estructura del JSON canonico la define el prompt
`prompts/reporte_ejecutivo.txt`, no las secciones de este ejemplo.

Para un reporte nuevo local:
  1. Copiar este archivo con un nombre descriptivo.
  2. Cambiar las constantes REPORT_NAME / REPORT_ID / ORG / FECHA.
  3. Reemplazar el contenido dummy, reutilizando section(), subsection(),
     make_table(), finding() y add_image().
  4. No modificar la paleta ni las reglas de layout salvo cambio de estandar.

Requisitos: pip install reportlab
"""

from reportlab.lib.pagesizes import LETTER
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table, TableStyle,
    Image, HRFlowable,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas as pdfcanvas
from reportlab.pdfbase.pdfmetrics import stringWidth

# ===========================================================================
# 1. PALETA DE COLORES CORPORATIVA (no cambiar los valores hex)
# ===========================================================================
DARK_GRAY  = colors.HexColor("#1F2933")   # encabezado de pagina, titulos de seccion
MID_GRAY   = colors.HexColor("#52606D")   # texto descriptivo, subtitulos, pie de pagina
LIGHT_GRAY = colors.HexColor("#CBD2D9")   # bordes de tabla, linea del pie
ACCENT     = colors.HexColor("#2B6CB0")   # linea de acento, borde inferior de cabecera de tabla
ROW_HDR    = colors.HexColor("#E2E8F0")   # fondo de cabecera de tabla
ROW_ALT    = colors.HexColor("#F5F7FA")   # filas alternadas (zebra striping)
WARN       = colors.HexColor("#C53030")   # alertas y valores criticos -> siempre negrita
ATTN       = colors.HexColor("#B7791F")   # valores de atencion / severidad media
INFO_CLR   = colors.HexColor("#276749")   # valores positivos y estados OK
WHITE      = colors.white
# Nunca usar negro puro (#000000). Todo el texto corre sobre DARK_GRAY o MID_GRAY.

CONTENT_WIDTH = 510  # pt - ancho util de contenido, ninguna tabla/imagen puede excederlo
PAGE_W, PAGE_H = LETTER
MARGIN = 1.8 * cm

# ===========================================================================
# 2. METADATOS DEL REPORTE (cambiar por cada reporte nuevo)
# ===========================================================================
REPORT_NAME = "Auditoria Tecnica de Seguridad - Servidor DEMO-SRV01"
REPORT_ID = "DEMO-SRV01-20260714"
ORG = "Organizacion Demo"
FECHA = "14 de julio de 2026"

OUT_PATH = "Ejemplo_Reporte_Corporativo.pdf"

# ===========================================================================
# 3. ESTILOS DE TEXTO
# ===========================================================================
styles = getSampleStyleSheet()

def pstyle(name, size=9, color=MID_GRAY, bold=False, mono=False, leading=None,
           align=TA_LEFT, spaceBefore=0, spaceAfter=0):
    """Fabrica de ParagraphStyle: tipografia general Helvetica, monoespaciada
    Courier reservada para datos tecnicos (codigos, IDs, rutas, IPs, hashes)."""
    font = "Helvetica-Bold" if bold else "Helvetica"
    if mono:
        font = "Courier"
    return ParagraphStyle(
        name, parent=styles["Normal"], fontName=font, fontSize=size,
        textColor=color, leading=leading or size * 1.35, alignment=align,
        spaceBefore=spaceBefore, spaceAfter=spaceAfter,
    )

st_body          = pstyle("body", 9, MID_GRAY)
st_title         = pstyle("title", 17, DARK_GRAY, bold=True, leading=20)
st_subtitle      = pstyle("subtitle", 10, MID_GRAY)
st_section_title = pstyle("section_title", 11, DARK_GRAY, bold=True, leading=13)
st_section_desc  = pstyle("section_desc", 9, MID_GRAY, leading=13)
st_subsection    = pstyle("subsection", 9, MID_GRAY, bold=True, spaceBefore=8, spaceAfter=3)
st_table_hdr     = pstyle("table_hdr", 8.5, DARK_GRAY, bold=True, leading=10.5)
st_table_cell    = pstyle("table_cell", 9, DARK_GRAY, leading=11)
st_table_mono    = pstyle("table_mono", 8, DARK_GRAY, mono=True, leading=10)
st_table_warn    = pstyle("table_warn", 9, WARN, bold=True, leading=11)
st_table_attn    = pstyle("table_attn", 9, ATTN, bold=True, leading=11)
st_table_info    = pstyle("table_info", 9, INFO_CLR, leading=11)
st_finding       = pstyle("finding", 9, DARK_GRAY, leading=13, spaceAfter=6)
st_closing       = pstyle("closing", 9, MID_GRAY, leading=13)
st_caption       = pstyle("caption", 8, MID_GRAY, spaceBefore=3, spaceAfter=14)

# ===========================================================================
# 4. ENCABEZADO Y PIE DE PAGINA (se dibujan automaticamente en cada pagina)
# ===========================================================================
def draw_header_footer(c: pdfcanvas.Canvas, doc):
    c.saveState()

    strip_h = 1.1 * cm
    c.setFillColor(DARK_GRAY)
    c.rect(0, PAGE_H - strip_h, PAGE_W, strip_h, fill=1, stroke=0)

    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(MARGIN, PAGE_H - strip_h + (strip_h - 8) / 2 + 1, REPORT_NAME)

    c.setFont("Helvetica", 8)
    right_txt = f"{REPORT_ID} | {ORG} | {FECHA}"
    w = stringWidth(right_txt, "Helvetica", 8)
    c.drawString(PAGE_W - MARGIN - w, PAGE_H - strip_h + (strip_h - 8) / 2 + 1, right_txt)

    c.setStrokeColor(ACCENT)
    c.setLineWidth(2.5)
    c.line(0, PAGE_H - strip_h, PAGE_W, PAGE_H - strip_h)

    footer_line_y = 1.3 * cm
    c.setStrokeColor(LIGHT_GRAY)
    c.setLineWidth(0.5)
    c.line(MARGIN, footer_line_y, PAGE_W - MARGIN, footer_line_y)

    c.setFillColor(MID_GRAY)
    c.setFont("Helvetica", 7.5)
    c.drawString(MARGIN, footer_line_y - 10, "Confidencial — Uso interno de TI")
    page_txt = f"Pagina {doc.page}"
    w2 = stringWidth(page_txt, "Helvetica", 7.5)
    c.drawString(PAGE_W - MARGIN - w2, footer_line_y - 10, page_txt)

    c.restoreState()

# ===========================================================================
# 5. FUNCIONES REUTILIZABLES PARA CONSTRUIR EL CONTENIDO
# ===========================================================================
story = []

def section(title, desc):
    """Titulo de seccion (bold 11pt) + linea de acento 0.8pt + parrafo
    descriptivo obligatorio (2-4 lineas)."""
    story.append(Paragraph(title, st_section_title))
    story.append(HRFlowable(width=CONTENT_WIDTH, thickness=0.8, color=ACCENT,
                             spaceBefore=2, spaceAfter=6))
    story.append(Paragraph(desc, st_section_desc))
    story.append(Spacer(1, 8))

def subsection(label):
    """Etiqueta de subseccion: bold 9pt MID_GRAY con espacio superior."""
    story.append(Paragraph(label, st_subsection))

def cell(text, kind="normal"):
    """Construye una celda de tabla con el color semantico correspondiente.
    kind: header | normal | mono | warn | attn | info
    """
    if kind == "header":
        return Paragraph(text, st_table_hdr)
    if kind == "warn":
        return Paragraph(text, st_table_warn)
    if kind == "attn":
        return Paragraph(text, st_table_attn)
    if kind == "info":
        return Paragraph(text, st_table_info)
    if kind == "mono":
        return Paragraph(text, st_table_mono)
    return Paragraph(text, st_table_cell)

def make_table(header, rows, col_widths, row_kinds=None):
    """Tabla estandar del reporte. col_widths debe sumar CONTENT_WIDTH (510)."""
    assert sum(col_widths) == CONTENT_WIDTH, "col_widths debe sumar 510pt exactos"
    data = [[cell(h, "header") for h in header]]
    for i, r in enumerate(rows):
        kinds = row_kinds[i] if row_kinds else ["normal"] * len(r)
        data.append([cell(str(v), k) for v, k in zip(r, kinds)])

    t = Table(data, colWidths=col_widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), ROW_HDR),
        ("LINEBELOW", (0, 0), (-1, 0), 1.2, ACCENT),
        ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4.5),
    ]
    for i in range(1, len(data)):
        style.append(("BACKGROUND", (0, i), (-1, i), ROW_ALT if i % 2 == 0 else WHITE))
    t.setStyle(TableStyle(style))
    return t

def finding(kind, text):
    """Hallazgo fuera de tabla. kind: Critico | Atencion | Informativo."""
    assert kind in ("Critico", "Atencion", "Informativo")
    if kind == "Critico":
        prefix_color = "#C53030"
    elif kind == "Atencion":
        prefix_color = "#B7791F"
    else:
        prefix_color = "#276749"
    html = f'<font color="{prefix_color}"><b>{kind}</b></font>&nbsp;&nbsp;{text}'
    story.append(Paragraph(html, st_finding))

def add_image(path, caption):
    """Inserta una imagen a ancho completo de contenido (510pt) con caption."""
    img = Image(path)
    ratio = img.imageHeight / float(img.imageWidth)
    img.drawWidth = CONTENT_WIDTH
    img.drawHeight = CONTENT_WIDTH * ratio
    max_h = 620
    if img.drawHeight > max_h:
        img.drawHeight = max_h
        img.drawWidth = max_h / ratio
    story.append(img)
    story.append(Paragraph(caption, st_caption))

def fmt_int(n):
    """Formatea enteros con separador de miles en punto (es-LA)."""
    return f"{n:,}".replace(",", ".")

# ===========================================================================
# 6. CONTENIDO DE EJEMPLO (DUMMY) - 10 secciones de auditoria
# ===========================================================================

story.append(Paragraph(REPORT_NAME, st_title))
story.append(Spacer(1, 3))
story.append(Paragraph(f"{REPORT_ID} | {ORG} | {FECHA} | Estado: Borrador de ejemplo", st_subtitle))
story.append(Spacer(1, 6))
story.append(HRFlowable(width=CONTENT_WIDTH, thickness=2, color=ACCENT, spaceAfter=14))

# --- 1. Resumen ejecutivo ---
section(
    "Resumen ejecutivo",
    "Sintesis de los principales riesgos de seguridad del servidor DEMO-SRV01. "
    "La tabla de indicadores concentra el estado de controles clave (firewall, "
    "RDP, cuentas privilegiadas y autenticacion) con color semantico."
)
story.append(make_table(
    ["Indicador", "Valor", "Estado"],
    [
        ["Firewall local", "Desactivado", "Critico"],
        ["RDP en escucha", "3389", "Atencion"],
        ["Cuentas en Administrators", "4", "Atencion"],
        ["Conectividad a dominio", "OK", "OK"],
    ],
    [260, 130, 120],
    row_kinds=[
        ["normal", "mono", "warn"],
        ["normal", "mono", "attn"],
        ["normal", "mono", "attn"],
        ["normal", "mono", "info"],
    ],
))
story.append(Spacer(1, 10))

# --- 2. Informacion del sistema ---
section(
    "Informacion del sistema",
    "Datos de identificacion, sistema operativo y hardware del equipo auditado. "
    "Sirve como contexto para interpretar el resto de hallazgos."
)
story.append(make_table(
    ["Campo", "Valor"],
    [
        ["Equipo", "DEMO-SRV01"],
        ["Sistema operativo", "Windows Server 2019"],
        ["Dominio", "demo.local"],
    ],
    [200, 310],
    row_kinds=[
        ["normal", "mono"],
        ["normal", "normal"],
        ["normal", "mono"],
    ],
))
story.append(Spacer(1, 10))

# --- 3. Cuentas y privilegios ---
section(
    "Cuentas y privilegios",
    "Inventario de cuentas locales privilegiadas y membresias relevantes. "
    "Un exceso de administradores eleva el impacto de un compromiso de cuenta."
)
subsection("Grupo Administrators")
story.append(make_table(
    ["Cuenta", "Tipo", "Severidad"],
    [
        ["Administrator", "Local", "Atencion"],
        ["svc-deploy", "Local", "Atencion"],
    ],
    [200, 150, 160],
    row_kinds=[
        ["mono", "normal", "attn"],
        ["mono", "normal", "attn"],
    ],
))
story.append(Spacer(1, 10))

# --- 4. Politicas de seguridad ---
section(
    "Politicas de seguridad",
    "Estado de controles de endurecimiento: firewall, RDP, UAC y politicas "
    "relacionadas. Los valores Critico requieren accion inmediata."
)
story.append(make_table(
    ["Control", "Valor", "Estado"],
    [
        ["EnableFirewall", "0x0", "Critico"],
        ["fDenyTSConnections", "0x0", "Atencion"],
        ["EnableLUA (UAC)", "0x1", "OK"],
    ],
    [220, 150, 140],
    row_kinds=[
        ["normal", "mono", "warn"],
        ["normal", "mono", "attn"],
        ["normal", "mono", "info"],
    ],
))
story.append(Spacer(1, 10))

# --- 5. Configuracion de red ---
section(
    "Configuracion de red",
    "Direccionamiento, DNS y gateway observados en la auditoria. Los datos "
    "tecnicos se muestran en monoespaciada para facilitar la revision."
)
story.append(make_table(
    ["Parametro", "Valor"],
    [
        ["IPv4", "10.0.1.40"],
        ["DNS", "10.0.1.10"],
        ["Gateway", "10.0.1.1"],
    ],
    [200, 310],
    row_kinds=[
        ["normal", "mono"],
        ["normal", "mono"],
        ["normal", "mono"],
    ],
))
story.append(Spacer(1, 10))

# --- 6. Superficie de exposicion ---
section(
    "Superficie de exposicion",
    "Puertos en escucha y servicios asociados. Destaca RDP (3389) como punto "
    "de acceso remoto que conviene restringir por origen."
)
story.append(make_table(
    ["Puerto", "Proceso", "Estado"],
    [
        ["3389", "TermService", "Atencion"],
        ["445", "System", "OK"],
        ["5985", "System", "Atencion"],
    ],
    [120, 240, 150],
    row_kinds=[
        ["mono", "mono", "attn"],
        ["mono", "mono", "info"],
        ["mono", "mono", "attn"],
    ],
))
story.append(Spacer(1, 10))

# --- 7. Recursos y servicios ---
section(
    "Recursos y servicios",
    "Servicios y recursos compartidos relevantes para la superficie interna. "
    "Incluye solo ejemplos ilustrativos de la plantilla."
)
story.append(make_table(
    ["Recurso", "Detalle", "Estado"],
    [
        ["C$", "Admin share habilitado", "Atencion"],
        ["wuauserv", "Running / Automatic", "OK"],
    ],
    [150, 240, 120],
    row_kinds=[
        ["mono", "normal", "attn"],
        ["mono", "normal", "info"],
    ],
))
story.append(Spacer(1, 10))

# --- 8. Eventos de autenticacion ---
section(
    "Eventos de autenticacion",
    "Eventos de seguridad asociados a logons (4624/4625) y uso de privilegios. "
    "Picos de fallos pueden indicar fuerza bruta o credenciales invalidas."
)
story.append(make_table(
    ["Evento", "Conteo (ejemplo)", "Estado"],
    [
        ["4625 Fallos de logon", "128", "Atencion"],
        ["4624 Logons exitosos", "45", "OK"],
    ],
    [220, 150, 140],
    row_kinds=[
        ["normal", "mono", "attn"],
        ["normal", "mono", "info"],
    ],
))
story.append(Spacer(1, 10))

# --- 9. Errores y logs ---
section(
    "Errores y logs",
    "Indicadores de integridad del registro de eventos y errores de System. "
    "La limpieza de logs es un indicador de posible manipulacion."
)
story.append(make_table(
    ["Indicador", "Valor", "Estado"],
    [
        ["Evento 1102 (log cleared)", "No detectado", "OK"],
        ["7045 Nuevo servicio", "1 en ventana", "Atencion"],
    ],
    [240, 150, 120],
    row_kinds=[
        ["normal", "normal", "info"],
        ["normal", "mono", "attn"],
    ],
))
story.append(Spacer(1, 10))

# --- 10. Hallazgos y recomendaciones ---
section(
    "Hallazgos y recomendaciones",
    "Consolidacion final de hallazgos accionables. Prefijos con color "
    "semantico: Critico (rojo), Atencion (ambar) e Informativo (verde)."
)
finding("Critico", "Firewall deshabilitado (EnableFirewall=0x0). Activar perfiles y revisar reglas.")
finding("Atencion", "RDP (3389) en escucha sin restriccion de origen evidente. Limitar por firewall/VPN.")
finding("Informativo", "Conectividad al controlador de dominio sin perdida en la prueba de ejemplo.")

# ===========================================================================
# 7. ANEXO VISUAL (opcional) - fuera del pipeline JSON del backend
# ===========================================================================
# section(
#     "Anexo Visual",
#     "Incluye capturas de pantalla u otras imagenes de respaldo referenciadas "
#     "en el cuerpo del reporte."
# )
# add_image("ruta/a/imagen.png", "Figura 1. Descripcion de la imagen.")

# ===========================================================================
# 8. BLOQUE DE CIERRE (siempre al final del documento)
# ===========================================================================
story.append(HRFlowable(width=CONTENT_WIDTH, thickness=1, color=ACCENT, spaceBefore=10, spaceAfter=10))
story.append(Paragraph(
    f"Documento generado el {FECHA}. Fuente: reportes de auditoria (sistema, red, logs). "
    "Clasificacion: Confidencial — Uso interno de TI.",
    st_closing,
))

# ===========================================================================
# 9. ARMADO DEL DOCUMENTO
# ===========================================================================
doc = BaseDocTemplate(
    OUT_PATH, pagesize=LETTER,
    leftMargin=MARGIN, rightMargin=MARGIN,
    topMargin=MARGIN + 1.1 * cm + 0.35 * cm,
    bottomMargin=1.3 * cm + 0.5 * cm,
    title=f"{REPORT_NAME} - {REPORT_ID}",
    author="Equipo de TI",
    subject="Plantilla de estilo para auditoria tecnica de seguridad",
)
frame = Frame(doc.leftMargin, doc.bottomMargin, CONTENT_WIDTH,
              PAGE_H - doc.topMargin - doc.bottomMargin, id="normal",
              leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=draw_header_footer)])

if __name__ == "__main__":
    doc.build(story)
    print("PDF de ejemplo generado en:", OUT_PATH)
