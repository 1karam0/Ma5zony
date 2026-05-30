
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, VerticalAlign, PageNumber, PageBreak, LevelFormat,
  TableOfContents, UnderlineType
} = require('docx');
const fs = require('fs');

// ── Design tokens (from DissertationTemplate theme) ──────────────────────────
const NAVY   = '44546A';
const BLUE   = '4472C4';
const WHITE  = 'FFFFFF';
const LIGHT  = 'EBF3FB';
const GRAY   = 'F2F2F2';
const BLACK  = '000000';
const GREEN  = '008060';

const tbl = { style: BorderStyle.SINGLE, size: 1, color: 'CCCCCC' };
const cb  = { top: tbl, bottom: tbl, left: tbl, right: tbl };

// ── Helpers ──────────────────────────────────────────────────────────────────
function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 400, after: 200 },
    children: [new TextRun({ text, bold: true, size: 32, color: NAVY, font: 'Calibri Light' })]
  });
}
function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 300, after: 160 },
    children: [new TextRun({ text, bold: true, size: 26, color: NAVY, font: 'Calibri Light' })]
  });
}
function h3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 240, after: 120 },
    children: [new TextRun({ text, bold: true, size: 24, color: NAVY, font: 'Calibri' })]
  });
}
function body(text) {
  return new Paragraph({
    spacing: { before: 120, after: 120, line: 360 },
    children: [new TextRun({ text, size: 22, font: 'Calibri' })]
  });
}
function bodyBold(label, text) {
  return new Paragraph({
    spacing: { before: 120, after: 120, line: 360 },
    children: [
      new TextRun({ text: label, bold: true, size: 22, font: 'Calibri' }),
      new TextRun({ text, size: 22, font: 'Calibri' })
    ]
  });
}
function code(text) {
  return new Paragraph({
    spacing: { before: 80, after: 80 },
    indent: { left: 720 },
    children: [new TextRun({ text, font: 'Courier New', size: 18, color: '2B2B2B' })]
  });
}
function caption(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 80, after: 200 },
    children: [new TextRun({ text, italics: true, size: 20, color: '595959', font: 'Calibri' })]
  });
}
function pb() { return new Paragraph({ children: [new PageBreak()] }); }
function spacer() { return new Paragraph({ spacing: { before: 160, after: 0 }, children: [new TextRun('')] }); }

function hdrRow(cols) {
  return new TableRow({
    tableHeader: true,
    children: cols.map(c => new TableCell({
      borders: cb,
      shading: { fill: BLUE, type: ShadingType.CLEAR },
      children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: c, bold: true, color: WHITE, size: 20, font: 'Calibri' })] })]
    }))
  });
}
function dataRow(cols) {
  return new TableRow({
    children: cols.map(c => new TableCell({
      borders: cb,
      children: [new Paragraph({ children: [new TextRun({ text: c, size: 20, font: 'Calibri' })] })]
    }))
  });
}
function altRow(cols, shade) {
  return new TableRow({
    children: cols.map(c => new TableCell({
      borders: cb,
      shading: { fill: shade ? GRAY : WHITE, type: ShadingType.CLEAR },
      children: [new Paragraph({ children: [new TextRun({ text: c, size: 20, font: 'Calibri' })] })]
    }))
  });
}
function makeTable(headers, rows, widths) {
  return new Table({
    columnWidths: widths,
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    rows: [
      hdrRow(headers),
      ...rows.map((r, i) => altRow(r, i % 2 === 1))
    ]
  });
}

// ── COVER PAGE ────────────────────────────────────────────────────────────────
function coverPage() {
  return [
    new Paragraph({ spacing: { before: 1440, after: 0 }, alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: 'THE BRITISH UNIVERSITY IN EGYPT', bold: true, size: 28, font: 'Calibri Light', color: NAVY })] }),
    new Paragraph({ spacing: { before: 80, after: 0 }, alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: 'Faculty of Computing and Digital Technology', size: 24, font: 'Calibri Light', color: NAVY })] }),
    new Paragraph({ spacing: { before: 80, after: 0 }, alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: 'Department of Computer Science', size: 24, font: 'Calibri Light', color: NAVY })] }),
    spacer(), spacer(),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 240, after: 240 },
      children: [new TextRun({ text: '─────────────────────────────────────────', size: 22, color: BLUE, font: 'Calibri' })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 200, after: 200 },
      children: [new TextRun({ text: 'Ma5zony', bold: true, size: 72, font: 'Calibri Light', color: NAVY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 160, after: 160 },
      children: [new TextRun({ text: 'An Intelligent Inventory Management and Demand Forecasting System', bold: true, size: 32, font: 'Calibri Light', color: BLUE })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 160, after: 160 },
      children: [new TextRun({ text: 'for Small and Medium-Sized Enterprises', size: 28, font: 'Calibri Light', color: NAVY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 240, after: 240 },
      children: [new TextRun({ text: '─────────────────────────────────────────', size: 22, color: BLUE, font: 'Calibri' })] }),
    spacer(), spacer(),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 200, after: 80 },
      children: [new TextRun({ text: 'A Dissertation Submitted in Partial Fulfilment', size: 22, font: 'Calibri' })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 0, after: 80 },
      children: [new TextRun({ text: 'of the Requirements for the Degree of', size: 22, font: 'Calibri' })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 0, after: 200 },
      children: [new TextRun({ text: 'Bachelor of Science in Computer Science', bold: true, size: 24, font: 'Calibri' })] }),
    spacer(),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 160, after: 80 },
      children: [new TextRun({ text: 'Submitted by:', bold: true, size: 22, font: 'Calibri', color: NAVY })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 0, after: 80 },
      children: [new TextRun({ text: 'Ahmed Karam', bold: true, size: 26, font: 'Calibri Light', color: BLUE })] }),
    spacer(),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 160, after: 80 },
      children: [new TextRun({ text: 'Academic Year: 2025 – 2026', size: 22, font: 'Calibri', color: '595959' })] }),
    pb()
  ];
}

// ── DECLARATION ───────────────────────────────────────────────────────────────
function declarationPage() {
  return [
    h1('Declaration of Originality'),
    spacer(),
    body('I hereby declare that the dissertation titled "Ma5zony: An Intelligent Inventory Management and Demand Forecasting System for Small and Medium-Sized Enterprises" is entirely my own work. The system described in this dissertation, including all software design, implementation, testing, and evaluation, was carried out independently by me as part of my final-year project at The British University in Egypt.'),
    spacer(),
    body('All sources consulted and referenced throughout this work have been properly cited according to the academic conventions required by the University. Any material quoted or closely paraphrased from external sources has been clearly acknowledged. I have not submitted this work, in whole or in part, for any other academic qualification or professional award.'),
    spacer(),
    body('I confirm that this work does not contain any material that infringes upon the intellectual property rights of any third party, and that all code written for this project is my own unless explicitly stated otherwise.'),
    spacer(), spacer(),
    new Paragraph({ spacing: { before: 200, after: 80 }, children: [new TextRun({ text: 'Signature: ___________________________', size: 22, font: 'Calibri' })] }),
    new Paragraph({ spacing: { before: 80, after: 80 }, children: [new TextRun({ text: 'Name: Ahmed Karam', size: 22, font: 'Calibri' })] }),
    new Paragraph({ spacing: { before: 80, after: 80 }, children: [new TextRun({ text: 'Date: May 2026', size: 22, font: 'Calibri' })] }),
    pb()
  ];
}

// ── ABSTRACT ──────────────────────────────────────────────────────────────────
function abstractPage() {
  return [
    h1('Abstract'),
    spacer(),
    body('This dissertation presents Ma5zony, a web-based inventory management and demand forecasting platform built specifically for small and medium-sized enterprises (SMEs). The system was designed with a single overriding goal: to bring the kind of intelligent supply chain tooling that large corporations take for granted within reach of businesses that typically lack both the budget and the technical staff to operate enterprise-grade systems.'),
    spacer(),
    body('Ma5zony was developed using Flutter for the web frontend, Firebase for authentication and real-time data persistence, and Firebase Cloud Functions for server-side logic including third-party integrations. The application implements five demand forecasting algorithms — Simple Moving Average (SMA), Weighted Moving Average (WMA), Single Exponential Smoothing (SES), Holt\'s Double Exponential Smoothing, and the Holt-Winters seasonal method — giving business owners the ability to model their demand patterns with an appropriate level of statistical rigour.'),
    spacer(),
    body('Beyond forecasting, the system covers the complete operational cycle of an SME inventory process: product catalogue management with Shopify import, supplier and warehouse management, automatic replenishment recommendations based on reorder-point theory, purchase order generation, manufacturing workflow with bill-of-materials costing, and a real-time ABC-XYZ product classification matrix. A Shopify OAuth integration allows demand data to be populated automatically from live sales history.'),
    spacer(),
    body('The design and implementation placed usability at the centre of every decision. An interactive spotlight-based onboarding tour guides new users through the exact data-entry sequence required before any intelligent feature can produce meaningful output. Setup health banners surface configuration gaps proactively. Public token-based portals let suppliers, manufacturers, and factory contacts respond to orders without needing a system account.'),
    spacer(),
    body('The dissertation discusses not only the final architecture but also the significant pivots made during development — including a full rethink of the product-sourcing classification model, a correction to the warehouse stock denormalisation approach, and a resequencing of the onboarding tour steps. Honest reflection on these decisions forms a substantial part of the analysis chapters.'),
    spacer(),
    bodyBold('Keywords: ', 'Inventory Management, Demand Forecasting, Flutter, Firebase, SME, Usability, Supply Chain, Shopify Integration, Replenishment Optimisation.'),
    pb()
  ];
}

// ── ACKNOWLEDGEMENTS ──────────────────────────────────────────────────────────
function acknowledgementsPage() {
  return [
    h1('Acknowledgements'),
    spacer(),
    body('Building a production-grade web application from scratch over the course of a single academic year is not a solitary exercise, and I owe genuine thanks to a number of people who made this project possible.'),
    spacer(),
    body('First and foremost, I want to thank my dissertation supervisor for the guidance, critical feedback, and encouragement offered at every stage of the project. The conversations about system design, data modelling trade-offs, and the importance of honest documentation of failure as well as success shaped the direction of this work in ways I did not fully appreciate at the time.'),
    spacer(),
    body('I am grateful to the faculty of Computing and Digital Technology at The British University in Egypt for providing an environment that genuinely encourages students to build real systems and grapple with real problems rather than toy examples. The skills I developed in software engineering, database design, and human-computer interaction modules fed directly into this project.'),
    spacer(),
    body('Thanks are also due to the small-business owners who took the time to discuss their inventory headaches with me during the early requirements-gathering phase. Their frustration with spreadsheets-as-ERP and with tools that assume a dedicated IT department informed virtually every feature decision in Ma5zony.'),
    spacer(),
    body('Finally, I want to thank my family for tolerating the late nights, the occasional project-related despair, and the relentless monologues about forecasting algorithms and Firebase security rules. Their patience throughout was, to put it plainly, exceptional.'),
    pb()
  ];
}

module.exports = { coverPage, declarationPage, abstractPage, acknowledgementsPage,
  h1, h2, h3, body, bodyBold, code, caption, pb, spacer, makeTable,
  NAVY, BLUE, WHITE, LIGHT, GRAY, BLACK, GREEN, cb, tbl };
