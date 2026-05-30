
const {
  Document, Packer, Paragraph, TextRun, TableOfContents,
  Header, Footer, AlignmentType, PageNumber, HeadingLevel,
  LevelFormat, BorderStyle, WidthType, ShadingType
} = require('docx');
const fs = require('fs');

const {
  coverPage, declarationPage, abstractPage, acknowledgementsPage,
  h1, h2, h3, body, pb, spacer, NAVY, BLUE, WHITE, GRAY
} = require('./generate_report_p1');
const { chapter1 } = require('./generate_report_p2');
const { chapter3, chapter4 } = require('./generate_report_p3');
const { chapter5 } = require('./generate_report_p4');
const { chapter6, chapter7, chapter8, chapter9, referencesPage, appendices } = require('./generate_report_p5');
const { screenDescriptions, implementationDeepDive, designDeepDive, additionalTesting, moreLiteratureAndRequirements } = require('./generate_report_p6');
const { algorithmDeepDive, inventoryTheorySection, extendedUsabilityAnalysis, extendedImplementation, extendedChapter8 } = require('./generate_report_p7');
const { deploymentChapter, extendedChapter1, extendedConclusion, extendedLiterature } = require('./generate_report_p8');
const { extendedMethodology, securityAnalysis, businessAnalysis, extendedFutureWork, extendedReferences } = require('./generate_report_p9');

const header = new Header({
  children: [
    new Paragraph({
      alignment: AlignmentType.RIGHT,
      border: { bottom: { style: BorderStyle.SINGLE, size: 1, color: BLUE } },
      children: [
        new TextRun({ text: 'Ma5zony — Graduation Project Dissertation', size: 18, color: '595959', font: 'Calibri' }),
        new TextRun({ text: '\t', size: 18, font: 'Calibri' }),
        new TextRun({ text: 'Ahmed Karam | BUE 2026', size: 18, color: '595959', font: 'Calibri' })
      ]
    })
  ]
});

const footer = new Footer({
  children: [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [
        new TextRun({ text: 'Page ', size: 18, color: '595959', font: 'Calibri' }),
        new TextRun({ children: [PageNumber.CURRENT], size: 18, color: '595959', font: 'Calibri' }),
        new TextRun({ text: ' of ', size: 18, color: '595959', font: 'Calibri' }),
        new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 18, color: '595959', font: 'Calibri' })
      ]
    })
  ]
});

const tocPage = [
  new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 400, after: 200 },
    children: [new TextRun({ text: 'Table of Contents', bold: true, size: 32, color: NAVY, font: 'Calibri Light' })]
  }),
  new TableOfContents('Table of Contents', {
    hyperlink: true,
    headingStyleRange: '1-3',
    stylesWithLevels: [
      { styleName: 'Heading1', level: 1 },
      { styleName: 'Heading2', level: 2 },
      { styleName: 'Heading3', level: 3 },
    ]
  }),
  new Paragraph({ children: [] }),
  pb()
];

const allContent = [
  ...coverPage(),
  ...declarationPage(),
  ...abstractPage(),
  ...acknowledgementsPage(),
  ...tocPage,
  ...chapter1(),
  ...extendedChapter1(),
  ...moreLiteratureAndRequirements(),
  ...extendedLiterature(),
  ...chapter3(),
  ...chapter4(),
  ...deploymentChapter(),
  ...chapter5(),
  ...extendedImplementation(),
  ...screenDescriptions(),
  ...implementationDeepDive(),
  ...algorithmDeepDive(),
  ...inventoryTheorySection(),
  ...chapter6(),
  ...designDeepDive(),
  ...extendedUsabilityAnalysis(),
  ...chapter7(),
  ...additionalTesting(),
  ...chapter8(),
  ...extendedChapter8(),
  ...chapter9(),
  ...extendedConclusion(),
  ...extendedMethodology(),
  ...securityAnalysis(),
  ...businessAnalysis(),
  ...extendedFutureWork(),
  ...extendedReferences(),
  ...referencesPage(),
  ...appendices(),
];

const doc = new Document({
  styles: {
    default: {
      document: { run: { font: 'Calibri', size: 22 } }
    },
    paragraphStyles: [
      {
        id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 32, bold: true, color: NAVY, font: 'Calibri Light' },
        paragraph: { spacing: { before: 400, after: 200 }, outlineLevel: 0 }
      },
      {
        id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 26, bold: true, color: NAVY, font: 'Calibri Light' },
        paragraph: { spacing: { before: 300, after: 160 }, outlineLevel: 1 }
      },
      {
        id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 24, bold: true, color: NAVY, font: 'Calibri' },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 2 }
      }
    ]
  },
  numbering: {
    config: [
      {
        reference: 'bullet-list',
        levels: [{
          level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } }
        }]
      }
    ]
  },
  sections: [{
    properties: {
      page: { margin: { top: 1440, right: 1080, bottom: 1440, left: 1440 } }
    },
    headers: { default: header },
    footers: { default: footer },
    children: allContent
  }]
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = 'C:/Users/akara/Development/projects/Ma5zony_project/Ma5zony_Project_Report.docx';
  fs.writeFileSync(outPath, buffer);
  console.log('Document written to', outPath);
  const stats = fs.statSync(outPath);
  console.log('File size:', Math.round(stats.size / 1024), 'KB');
}).catch(err => {
  console.error('Error generating document:', err);
  process.exit(1);
});
