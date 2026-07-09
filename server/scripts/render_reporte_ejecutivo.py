#!/usr/bin/env python3
import json
import sys
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

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


def build_styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "ReportTitle",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=16,
            leading=20,
            textColor=colors.HexColor("#1F2933"),
            alignment=TA_LEFT,
            spaceAfter=6,
        ),
        "subtitle": ParagraphStyle(
            "ReportSubtitle",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#52606D"),
            spaceAfter=10,
        ),
        "section": ParagraphStyle(
            "SectionTitle",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=14,
            textColor=colors.HexColor("#1F2933"),
            spaceBefore=10,
            spaceAfter=4,
        ),
        "summary": ParagraphStyle(
            "Summary",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#52606D"),
            spaceAfter=6,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#1F2933"),
            spaceAfter=4,
        ),
        "group": ParagraphStyle(
            "GroupTitle",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=10,
            leading=12,
            textColor=colors.HexColor("#1F2933"),
            spaceBefore=6,
            spaceAfter=4,
        ),
        "hallazgo_title": ParagraphStyle(
            "HallazgoTitle",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#1F2933"),
            spaceAfter=3,
        ),
        "label": ParagraphStyle(
            "Label",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#52606D"),
            spaceAfter=2,
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


def add_textory_section(story, section, styles):
    if not section:
        return
    story.append(Paragraph(escape(section.get("title", "")), styles["section"]))
    summary = section.get("summary") or section.get("paragraph")
    if isinstance(summary, str) and summary.strip():
        story.append(Paragraph(escape(summary), styles["summary"]))

    for block in section.get("blocks", []):
        if isinstance(block, str) and block.strip():
            story.append(Paragraph(escape(block), styles["body"]))

    for table in section.get("tables", []):
        title = table.get("title") if isinstance(table, dict) else None
        if isinstance(title, str) and title.strip():
            story.append(Paragraph(escape(title), styles["group"]))
        rows = table.get("rows", []) if isinstance(table, dict) else []
        if rows:
            rendered = []
            for row in rows:
                if isinstance(row, dict):
                    rendered.append("; ".join("%s: %s" % (k, row[k]) for k in row))
                elif isinstance(row, list):
                    rendered.append(" | ".join(str(item) for item in row))
                elif isinstance(row, str):
                    rendered.append(row)
            if rendered:
                story.append(Paragraph(escape("<br/>".join(rendered)), styles["body"]))


def build_hallazgo_flowables(item, styles):
    title = Paragraph(
        "<b>%s - %s</b>" % (escape(item["severity"]), escape(item["title"])),
        styles["hallazgo_title"],
    )
    evidencia_label = Paragraph("<b>Evidencia</b>", styles["label"])
    evidencia_body = Paragraph(escape(item["evidence"]), styles["body"])
    recomendacion_label = Paragraph("<b>Recomendacion</b>", styles["label"])
    recomendacion_body = Paragraph(escape(item["recommendation"]), styles["body"])
    return [
        title,
        Spacer(1, 4),
        evidencia_label,
        evidencia_body,
        Spacer(1, 4),
        recomendacion_label,
        recomendacion_body,
        Spacer(1, 8),
    ]


def add_final_section(story, section, styles):
    story.append(Paragraph(escape(section.get("title", "")), styles["section"]))
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
        story.append(Paragraph(GROUP_TITLES[key], styles["group"]))
        for item in items:
            story.extend(build_hallazgo_flowables(item, styles))

    if not any_group:
        story.append(
            Paragraph(
                "Informativo - Sin hallazgos accionables relevantes en la evidencia analizada.",
                styles["body"],
            )
        )


def main():
    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, "r", encoding="utf-8") as fh:
        report = json.load(fh)

    styles = build_styles()
    metadata = report["metadata"]
    sections = report["sections"]
    story = [
        Paragraph(escape(metadata["reportTitle"]), styles["title"]),
        Paragraph(
            escape("%s | %s | %s" % (metadata["reportId"], metadata["organization"], metadata["localDateTime"])),
            styles["subtitle"],
        ),
    ]

    for key in SECTION_ORDER[:-1]:
        section = sections.get(key)
        if section_has_content(section):
            add_textory_section(story, section, styles)

    add_final_section(story, sections[FINAL_SECTION_KEY], styles)

    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.8 * cm,
        bottomMargin=1.8 * cm,
        title=metadata["reportTitle"],
        author=metadata["organization"],
        subject="Reporte ejecutivo homologado de auditoria tecnica",
    )
    doc.build(story)


if __name__ == "__main__":
    main()
