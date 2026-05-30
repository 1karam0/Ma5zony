
// Chapter: System Design Diagrams
const { h1, h2, h3, body, caption, pb, spacer, makeTable, imageBlock } = require('./generate_report_p1');

function diagramsChapter(imgs) {
  const D = imgs || {};

  return [
    h1('Chapter 5 (Supplementary): System Design Diagrams'),
    spacer(),
    body('This chapter presents the key design diagrams produced during the analysis, design, and architecture phases of the Ma5zony project. Together these diagrams document the system at multiple levels of abstraction: from the high-level context in which Ma5zony operates, through the data model and component structure, down to the dynamic behaviour of individual workflows.'),
    spacer(),

    // ── 1. System Context ──────────────────────────────────────────────────
    h2('5.S.1 System Context Diagram'),
    body('The system context diagram (Figure 5.1) positions Ma5zony within its environment. Four human actors interact with the system directly: the SME Owner, who has full access; the Inventory Manager, who handles day-to-day stock operations; the Manufacturer, who receives production orders and updates their status; and the Supplier, who views and acknowledges purchase orders through a public portal. Three external systems are involved: Shopify (from which sales order data is imported), an SMTP email server (used for supplier and manufacturer notifications), and the Firebase infrastructure (Firestore for data persistence, Auth for identity, Hosting for delivery).'),
    spacer(),
    ...imageBlock(D.systemContext, 580, 300, 'Figure 5.1: System Context Diagram'),
    spacer(),

    // ── 2. System Architecture ─────────────────────────────────────────────
    h2('5.S.2 System Architecture Diagram'),
    body('Figure 5.2 shows the three-tier architecture of Ma5zony. The client tier is a Flutter web application running entirely in the browser. State is managed through a single AppState ChangeNotifier, with GoRouter providing URL-based navigation. The middle tier is Firebase: Firestore for real-time data, Firebase Auth for identity, Cloud Functions v2 (deployed on Cloud Run) for server-side logic, and Firebase Hosting for static asset delivery. The integration tier consists of external APIs: the Shopify REST API for order data and an SMTP server for email notifications. The three tiers communicate over HTTPS; the client SDK talks directly to Firestore and Auth, while all Shopify and email communication is routed through Cloud Functions to keep credentials server-side.'),
    spacer(),
    ...imageBlock(D.architecture, 580, 360, 'Figure 5.2: System Architecture Diagram'),
    spacer(),
    pb(),

    // ── 3. ERD ─────────────────────────────────────────────────────────────
    h2('5.S.3 Entity Relationship Diagram'),
    body('The ERD in Figure 5.3 shows the data model underlying Ma5zony. All entities are scoped to a USERS root, reflecting the Firestore structure where each user\'s data lives under users/{uid}/. Products are at the centre of the model: they accumulate DEMAND_RECORDS over time, generate FORECAST_RESULTS and REPLENISHMENT_RECS, and can require raw materials via BOM_ITEMS. PURCHASE_ORDERS are placed with SUPPLIERS and contain ORDER_LINE_ITEMS referencing PRODUCTS. PRODUCTION_ORDERS are assigned to MANUFACTURERS and reference the finished product being produced.'),
    spacer(),
    ...imageBlock(D.erd, 580, 400, 'Figure 5.3: Entity Relationship Diagram'),
    spacer(),

    // ── 4. Component Diagram ───────────────────────────────────────────────
    h2('5.S.4 Component Diagram'),
    body('Figure 5.4 shows the main software components and their dependencies. AppState is the central hub: it instantiates and holds references to all service objects and exposes their data to the UI through ChangeNotifier. The service layer is strictly separated from the UI, meaning that any screen can access business logic only through AppState, never directly. The FirestoreInventoryRepository is the only component that talks to Firestore; all other services operate on in-memory data passed to them by AppState. This separation makes unit testing of the forecasting and replenishment logic straightforward, as those services have no Firestore dependency.'),
    spacer(),
    ...imageBlock(D.componentDiagram, 580, 420, 'Figure 5.4: Component Diagram'),
    spacer(),
    pb(),

    // ── 5. Login Sequence ──────────────────────────────────────────────────
    h2('5.S.5 Sequence Diagram: User Login'),
    body('Figure 5.5 shows the message sequence for user login. After the user submits credentials, the Flutter app calls Firebase Auth\'s signInWithEmailAndPassword(). On success, Firebase returns a JWT. AppState then fetches the AppUser document from Firestore (which contains the user\'s role and settings), attaches real-time listeners to all collections, and calls notifyListeners() to trigger a UI rebuild that navigates to the dashboard. The entire sequence from credential submission to dashboard display typically completes within 800-1200 milliseconds on a warm auth session.'),
    spacer(),
    ...imageBlock(D.loginSequence, 580, 340, 'Figure 5.5: Sequence Diagram - User Login'),
    spacer(),

    // ── 6. Shopify Sequence ────────────────────────────────────────────────
    h2('5.S.6 Sequence Diagram: Shopify Integration'),
    body('Figure 5.6 shows the Shopify OAuth connection flow. This is the most complex interaction in the system because it involves three parties: the Flutter client, a Cloud Function acting as the OAuth server, and Shopify\'s authorization server. The key security property is that the Shopify access token is never exposed to the client: it travels from Shopify to the Cloud Function, and from the Cloud Function directly to Firestore, without touching the browser. After connection, the import function paginates through the store\'s order history and writes demand records to Firestore.'),
    spacer(),
    ...imageBlock(D.shopifySequence, 580, 420, 'Figure 5.6: Sequence Diagram - Shopify OAuth and Import'),
    spacer(),
    pb(),

    // ── 7. State Machine ───────────────────────────────────────────────────
    h2('5.S.7 State Machine Diagram: Purchase Order Lifecycle'),
    body('Figure 5.7 models the lifecycle of a purchase order as a finite state machine. Orders begin as drafts, giving the owner time to adjust quantities and confirm the supplier before submitting. Once submitted, orders await approval (which may be instant in a solo-owner scenario) before being marked as Ordered when sent to the supplier. The two receiving states, PartiallyReceived and FullyReceived, handle the common case where a supplier delivers a shipment in multiple tranches. The Rejected state allows a submitted order to be revised rather than discarded.'),
    spacer(),
    ...imageBlock(D.orderStateMachine, 480, 360, 'Figure 5.7: State Machine - Purchase Order Lifecycle'),
    spacer(),

    // ── 8. Auth Flow ───────────────────────────────────────────────────────
    h2('5.S.8 Authentication and Authorisation Flow'),
    body('Figure 5.8 shows the complete authentication and role-based routing flow. The Firebase auth state listener fires on every app start and determines whether the user is presented with the login screen or the dashboard. Once authenticated, the user\'s role drives which view they see and which routes they can access. The owner-only routes (/cash-flow and /financial-analytics) are guarded by a redirect in GoRouter that checks AppState.currentUser.role; attempts to access these routes by non-owners are silently redirected to the dashboard.'),
    spacer(),
    ...imageBlock(D.authFlow, 520, 420, 'Figure 5.8: Authentication and Authorisation Flow'),
    spacer(),
    pb(),

    // ── 9. Replenishment Activity ──────────────────────────────────────────
    h2('5.S.9 Activity Diagram: Replenishment Recommendation Workflow'),
    body('Figure 5.9 models the replenishment recommendation workflow as an activity diagram. The process runs when the user opens the Forecasts page and evaluates every product in the catalogue. For each product with sufficient demand history, it runs the SES forecast, computes safety stock using the standard deviation of demand over the lead time, calculates the reorder point, and compares it to current stock. Products below their reorder point generate a ReplenishmentRecommendation document and an inbox notification. The EOQ formula determines the recommended order quantity to minimise the combined cost of ordering and holding.'),
    spacer(),
    ...imageBlock(D.replenishmentActivity, 520, 480, 'Figure 5.9: Activity Diagram - Replenishment Recommendation'),
    spacer(),

    // ── 10. Deployment ─────────────────────────────────────────────────────
    h2('5.S.10 Deployment Diagram'),
    body('Figure 5.10 shows the production deployment topology. The Flutter web bundle is served from Firebase Hosting\'s global CDN with automatic TLS. Firestore and Firebase Auth are managed services with no server configuration required. Cloud Functions are deployed as Cloud Run containers in the us-central1 region, with secrets stored in Google Cloud Secret Manager. The only outbound connections from Cloud Functions are to the Shopify REST API and the SMTP server; all other communication stays within Google Cloud.'),
    spacer(),
    ...imageBlock(D.deploymentDiagram, 580, 420, 'Figure 5.10: Deployment Diagram'),
    spacer(),
    pb(),

    // ── 11. Testing Flow ───────────────────────────────────────────────────
    h2('5.S.11 Testing Flow Diagram'),
    body('Figure 5.11 shows the testing process followed during development. The process begins with unit tests on the forecasting and replenishment service classes, which can be run without Firebase. Once those pass, the build is deployed to the Firebase staging project and manual smoke tests cover the core authentication and CRUD flows. Firestore security rules are tested using a separate test suite against the Firebase emulator. If all critical paths pass, think-aloud sessions are conducted with participants, followed by SUS questionnaires and performance benchmarking. Issues identified at any stage loop back to the deployment phase.'),
    spacer(),
    ...imageBlock(D.testingFlow, 520, 460, 'Figure 5.11: Testing Flow Diagram'),
    spacer(),

    // ── 12. Gantt ──────────────────────────────────────────────────────────
    h2('5.S.12 Project Timeline (Gantt Chart)'),
    body('Figure 5.12 shows the project timeline across the four development phases. The research phase covered requirements interviews and initial system design. The core development phase built the foundational modules: authentication, CRUD for products and suppliers, and the forecasting engine. The advanced features phase added the replenishment engine, manufacturing workflow, Shopify integration, and portal system. The finalisation phase covered usability testing, bug fixing, and dissertation writing. The total project duration from initial interviews to dissertation submission was approximately nine months.'),
    spacer(),
    ...imageBlock(D.gantt, 580, 320, 'Figure 5.12: Project Gantt Chart'),
    spacer(),
    pb(),

    // ── 13. Use Case Table ─────────────────────────────────────────────────
    h2('5.S.13 Use Case Descriptions'),
    body('The following table summarises the principal use cases of the Ma5zony system, covering actors, preconditions, main flow, and postconditions for the seven most critical workflows.'),
    spacer(),
    makeTable(
      ['Use Case', 'Actor', 'Precondition', 'Main Flow', 'Postcondition'],
      [
        ['UC01: Login', 'Any user', 'Account exists', '1. Enter email + password 2. Firebase Auth verifies 3. AppState loads profile 4. Redirect dashboard', 'User is authenticated and dashboard is shown'],
        ['UC02: Add product', 'Owner / Inv. Manager', 'Authenticated', '1. Navigate /products 2. Fill product form 3. Save to Firestore', 'Product appears in list with stock level'],
        ['UC03: Run forecast', 'Owner / Inv. Manager', 'Product + demand records exist', '1. Navigate /forecasts 2. System runs SES per product 3. Display results table', 'Replenishment recommendations generated'],
        ['UC04: Approve PO', 'SME Owner', 'PO in Submitted state', '1. Open PO detail 2. Review quantities 3. Approve 4. Email sent to supplier', 'PO moves to Approved state'],
        ['UC05: Connect Shopify', 'SME Owner', 'Shopify store exists', '1. Enter store URL 2. OAuth redirect 3. Approve 4. Orders imported', 'Demand records auto-populated from sales'],
        ['UC06: Production order', 'Manufacturer', 'Token-based portal access', '1. View assigned order 2. Update status 3. Notify completion', 'Production order marked complete, stock updated'],
        ['UC07: ABC-XYZ analysis', 'Owner / Inv. Manager', 'Demand records >= 3 periods', '1. Navigate /classification 2. System computes ABC + XYZ 3. Display matrix', 'Products segmented by value and variability'],
      ],
      [1400, 1400, 2000, 2600, 2000]
    ),
    caption('Table 5.S.1: Use case descriptions'),
    spacer(),
    pb(),
  ];
}

module.exports = { diagramsChapter };
