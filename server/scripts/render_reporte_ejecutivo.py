#!/usr/bin/env python3
import json
import math
import re
import sys
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

SECTION_ORDER = [
    "resumen_ejecutivo",
    "informacion_sistema",
    "cuentas_privilegios",
    "politicas_seguridad",
    "configuracion_red",
    "superficie_exposicion",
    "recursos_y_servicios",
    "eventos_autenticacion",
    "errores_y_logs",
    "hallazgos_y_recomendaciones",
]

FINAL_SECTION_KEY = "hallazgos_y_recomendaciones"
GROUP_TITLES = {
    "criticos": "Hallazgos criticos",
    "atencion": "Hallazgos de atencion",
    "informativos": "Hallazgos informativos",
}

DARK_GRAY = colors.HexColor("#1F2933")
MID_GRAY = colors.HexColor("#52606D")
LIGHT_GRAY = colors.HexColor("#CBD2D9")
ACCENT = colors.HexColor("#2B6CB0")
ROW_HDR = colors.HexColor("#E2E8F0")
ROW_ALT = colors.HexColor("#F5F7FA")
WARN = colors.HexColor("#C53030")
ATTN = colors.HexColor("#B7791F")
INFO_CLR = colors.HexColor("#276749")

CONFIDENTIAL_TEXT = "Confidencial - Uso interno de TI"

TECHNICAL_PATTERN = re.compile(r"([A-Za-z]:\\|\\\\|\b\d{1,3}(?:\.\d{1,3}){3}\b|\b0x[0-9a-fA-F]+\b|\.exe\b|\.dll\b|%SystemRoot%|/)")


def build_styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=DARK_GRAY,
            alignment=TA_LEFT,
            spaceAfter=6,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=10,
            leading=13,
            textColor=MID_GRAY,
            spaceAfter=7,
        ),
        "section": ParagraphStyle(
            "Section",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=14,
            textColor=DARK_GRAY,
            spaceBefore=10,
            spaceAfter=4,
        ),
        "summary": ParagraphStyle(
            "Summary",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=MID_GRAY,
            spaceAfter=6,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=DARK_GRAY,
            spaceAfter=4,
        ),
        "body_mono": ParagraphStyle(
            "BodyMono",
            parent=base["BodyText"],
            fontName="Courier",
            fontSize=8,
            leading=11,
            textColor=DARK_GRAY,
            spaceAfter=4,
        ),
        "subsection": ParagraphStyle(
            "Subsection",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=11,
            textColor=MID_GRAY,
            spaceBefore=6,
            spaceAfter=3,
        ),
        "label": ParagraphStyle(
            "Label",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=11,
            textColor=MID_GRAY,
            spaceAfter=2,
        ),
        "hallazgo_title": ParagraphStyle(
            "HallazgoTitle",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
            textColor=DARK_GRAY,
            spaceAfter=3,
        ),
        "footer": ParagraphStyle(
            "Footer",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.5,
            leading=9,
            textColor=MID_GRAY,
        ),
        "table_header": ParagraphStyle(
            "TableHeader",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10,
            textColor=DARK_GRAY,
        ),
        "table_cell": ParagraphStyle(
            "TableCell",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=10,
            textColor=DARK_GRAY,
        ),
        "table_cell_mono": ParagraphStyle(
            "TableCellMono",
            parent=base["BodyText"],
            fontName="Courier",
            fontSize=8,
            leading=9.5,
            textColor=DARK_GRAY,
        ),
        "table_cell_warn": ParagraphStyle(
            "TableCellWarn",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10,
            textColor=WARN,
        ),
        "table_cell_attn": ParagraphStyle(
            "TableCellAttn",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10,
            textColor=ATTN,
        ),
        "table_cell_ok": ParagraphStyle(
            "TableCellOk",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=10,
            textColor=INFO_CLR,
        ),
    }


def section_has_content(section):
    if not section:
        return False
    for key in ("summary", "paragraph"):
        value = section.get(key, "")
        if isinstance(value, str) and value.strip():
            return True
    for key in ("blocks", "tables"):
        value = section.get(key)
        if isinstance(value, list) and len(value) > 0:
            return True
    return False


def draw_header_footer(canvas, doc, metadata):
    width, height = letter

    bar_height = 1.1 * cm
    bar_y = height - bar_height
    canvas.saveState()
    canvas.setFillColor(DARK_GRAY)
    canvas.rect(0, bar_y, width, bar_height, stroke=0, fill=1)

    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(2.5)
    canvas.line(0, bar_y, width, bar_y)

    canvas.setFont("Helvetica-Bold", 8)
    canvas.setFillColor(colors.white)
    canvas.drawString(doc.leftMargin, bar_y + 0.35 * cm, metadata["reportTitle"])

    canvas.setFont("Helvetica", 8)
    header_right = "%s | %s | %s" % (
        metadata["reportId"],
        metadata["organization"],
        metadata["localDate"],
    )
    right_width = stringWidth(header_right, "Helvetica", 8)
    canvas.drawString(width - doc.rightMargin - right_width, bar_y + 0.35 * cm, header_right)

    footer_line_y = 1.3 * cm
    canvas.setStrokeColor(LIGHT_GRAY)
    canvas.setLineWidth(0.5)
    canvas.line(doc.leftMargin, footer_line_y, width - doc.rightMargin, footer_line_y)

    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(MID_GRAY)
    canvas.drawString(doc.leftMargin, footer_line_y - 0.45 * cm, CONFIDENTIAL_TEXT)

    page_text = "Pagina %d" % canvas.getPageNumber()
    page_width = stringWidth(page_text, "Helvetica", 7.5)
    canvas.drawString(width - doc.rightMargin - page_width, footer_line_y - 0.45 * cm, page_text)
    canvas.restoreState()


STATUS_EXACT = {
    "critico": "table_cell_warn",
    "atencion": "table_cell_attn",
    "atención": "table_cell_attn",
    "ok": "table_cell_ok",
    "informativo": "table_cell_ok",
}


def style_for_text(value, styles):
    text = str(value).strip()
    lowered = text.lower()
    exact_style = STATUS_EXACT.get(lowered)
    if exact_style:
        return styles[exact_style]
    if any(token in lowered for token in ["critico", "desactivado", "alto", "error", "fallo", "expuesto", "denegado"]):
        return styles["table_cell_warn"]
    if any(token in lowered for token in ["atencion", "atención"]):
        return styles["table_cell_attn"]
    if any(token in lowered for token in ["ok", "sin incidencias", "habilitado", "correcta", "conforme", "activo"]):
        return styles["table_cell_ok"]
    if TECHNICAL_PATTERN.search(text):
        return styles["table_cell_mono"]
    return styles["table_cell"]


def paragraph_for_cell(value, styles, header=False):
    style = styles["table_header"] if header else style_for_text(value, styles)
    return Paragraph(escape(str(value)), style)


def normalize_table_rows(rows):
    if not rows:
        return [], []
    first = rows[0]
    if isinstance(first, dict):
        columns = list(first.keys())
        normalized = [[row.get(column, "") for column in columns] for row in rows]
        return columns, normalized
    if isinstance(first, list):
        width = max(len(row) for row in rows)
        columns = ["Columna %d" % (index + 1) for index in range(width)]
        normalized = [row + [""] * (width - len(row)) for row in rows]
        return columns, normalized
    columns = ["Detalle"]
    normalized = [[row] for row in rows]
    return columns, normalized


def compute_col_widths(columns, normalized_rows, total_width):
    weights = []
    for column_index, column in enumerate(columns):
        longest = len(str(column))
        for row in normalized_rows:
            longest = max(longest, len(str(row[column_index])))
        weights.append(max(1, min(longest, 40)))
    total_weight = sum(weights)
    widths = [total_width * weight / total_weight for weight in weights]
    return widths


def build_table(table_def, styles, total_width):
    columns, normalized_rows = normalize_table_rows(table_def.get("rows", []))
    if not columns:
        return []

    flowables = []
    title = table_def.get("title")
    if isinstance(title, str) and title.strip():
        flowables.append(Paragraph(escape(title), styles["subsection"]))

    data = [[paragraph_for_cell(column, styles, header=True) for column in columns]]
    for row in normalized_rows:
        data.append([paragraph_for_cell(value, styles) for value in row])

    table = Table(data, colWidths=compute_col_widths(columns, normalized_rows, total_width), repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), ROW_HDR),
                ("TEXTCOLOR", (0, 0), (-1, -1), DARK_GRAY),
                ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
                ("LINEBELOW", (0, 0), (-1, 0), 1.2, ACCENT),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
            + [
                ("BACKGROUND", (0, row_index), (-1, row_index), ROW_ALT if row_index % 2 == 0 else colors.white)
                for row_index in range(1, len(data))
            ]
        )
    )
    flowables.extend([table, Spacer(1, 6)])
    return flowables


def section_heading(title, styles):
    return [
        Paragraph(escape(title), styles["section"]),
        HRFlowable(width="100%", thickness=0.8, color=ACCENT, spaceBefore=0, spaceAfter=6),
    ]


def add_body_paragraph(story, text, styles):
    style = styles["body_mono"] if TECHNICAL_PATTERN.search(text) else styles["body"]
    story.append(Paragraph(escape(text), style))


def add_textory_section(story, section, styles, content_width):
    if not section:
        return
    story.extend(section_heading(section.get("title", ""), styles))
    summary = section.get("summary") or section.get("paragraph")
    if isinstance(summary, str) and summary.strip():
        story.append(Paragraph(escape(summary), styles["summary"]))

    for block in section.get("blocks", []):
        if isinstance(block, str) and block.strip():
            add_body_paragraph(story, block, styles)

    for table_def in section.get("tables", []):
        if isinstance(table_def, dict):
            story.extend(build_table(table_def, styles, content_width))


def build_hallazgo_flowables(item, styles):
    severity = item["severity"]
    title_style = styles["hallazgo_title"]
    if severity == "Critico":
        title_style = ParagraphStyle("HallazgoCritico", parent=styles["hallazgo_title"], textColor=WARN)
    elif severity == "Atencion":
        title_style = ParagraphStyle("HallazgoAtencion", parent=styles["hallazgo_title"], textColor=ATTN)
    elif severity == "Informativo":
        title_style = ParagraphStyle("HallazgoInformativo", parent=styles["hallazgo_title"], textColor=INFO_CLR)

    title = Paragraph("<b>%s - %s</b>" % (escape(severity), escape(item["title"])), title_style)
    return [
        title,
        Spacer(1, 2),
        Paragraph("<b>Evidencia</b>", styles["label"]),
        Paragraph(escape(item["evidence"]), styles["body"]),
        Spacer(1, 3),
        Paragraph("<b>Recomendacion</b>", styles["label"]),
        Paragraph(escape(item["recommendation"]), styles["body"]),
        Spacer(1, 8),
    ]


def add_final_section(story, section, styles):
    story.extend(section_heading(section.get("title", ""), styles))
    summary = section.get("summary", "")
    if summary.strip():
        story.append(Paragraph(escape(summary), styles["summary"]))

    groups = section.get("groups", {})
    any_group = False
    for key in ("criticos", "atencion", "informativos"):
        items = groups.get(key, [])
        if not items:
            continue
        any_group = True
        story.append(Paragraph(GROUP_TITLES[key], styles["subsection"]))
        for item in items:
            story.extend(build_hallazgo_flowables(item, styles))

    if not any_group:
        story.append(Paragraph("Informativo - Sin hallazgos accionables relevantes en la evidencia analizada.", styles["body"]))


def main():
    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, "r", encoding="utf-8") as fh:
        report = json.load(fh)

    styles = build_styles()
    metadata = report["metadata"]
    sections = report["sections"]

    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=2.2 * cm,
        bottomMargin=2.2 * cm,
        title=metadata["reportTitle"],
        author=metadata["organization"],
        subject="Reporte ejecutivo homologado de auditoria tecnica",
        pageCompression=0,
    )

    subtitle_text = "%s | %s | %s | Confidencial" % (
        metadata["reportId"],
        metadata["organization"],
        metadata["localDate"],
    )
    story = [
        Spacer(1, 6),
        Paragraph(escape(metadata["reportTitle"]), styles["title"]),
        Paragraph(escape(subtitle_text), styles["subtitle"]),
        HRFlowable(width="100%", thickness=2, color=ACCENT, spaceBefore=0, spaceAfter=10),
    ]

    for key in SECTION_ORDER[:-1]:
        section = sections.get(key)
        if section_has_content(section):
            add_textory_section(story, section, styles, doc.width)

    add_final_section(story, sections[FINAL_SECTION_KEY], styles)

    story.extend(
        [
            Spacer(1, 8),
            HRFlowable(width="100%", thickness=1, color=ACCENT, spaceBefore=0, spaceAfter=6),
            Paragraph(
                escape(
                    "Documento generado el %s (%s). Clasificacion: %s."
                    % (metadata["localDateTime"], metadata["timeZone"], CONFIDENTIAL_TEXT)
                ),
                styles["summary"],
            ),
        ]
    )

    page_callback = lambda canvas, current_doc: draw_header_footer(canvas, current_doc, metadata)
    doc.build(story, onFirstPage=page_callback, onLaterPages=page_callback)


if __name__ == "__main__":
    main()
