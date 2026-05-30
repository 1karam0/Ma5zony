
// Fetches Mermaid diagrams from mermaid.ink as PNG Buffers (cached locally)
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CACHE_DIR = path.join(__dirname, 'diagram_cache');
if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR);

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http;
    client.get(url, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetchBuffer(res.headers.location).then(resolve).catch(reject);
      }
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function fetchMermaid(key, mermaidCode, timeoutMs = 20000) {
  const cachePath = path.join(CACHE_DIR, key + '.png');
  if (fs.existsSync(cachePath)) {
    const cached = fs.readFileSync(cachePath);
    if (cached.length > 3000) {
      process.stdout.write('(cached) ');
      return cached;
    }
  }
  const b64 = Buffer.from(mermaidCode).toString('base64');
  const url = `https://mermaid.ink/img/${b64}?type=png&width=900`;
  const result = await Promise.race([
    fetchBuffer(url),
    new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), timeoutMs))
  ]);
  if (result.length < 3000) throw new Error('Image too small - likely render error');
  fs.writeFileSync(cachePath, result);
  return result;
}

// ─── Diagram definitions ───────────────────────────────────────────────────

const diagrams = {

  systemContext: `
graph LR
    A([SME Owner]) -->|manages inventory| M[Ma5zony System]
    B([Inventory Manager]) -->|updates stock| M
    C([Manufacturer]) -->|views & updates orders| M
    D([Supplier]) -->|views purchase orders| M
    M -->|imports sales orders| S[Shopify API]
    M -->|sends notifications| E[SMTP Email]
    M -->|stores data| F[(Cloud Firestore)]
    M -->|authenticates users| G[Firebase Auth]
    M -->|serves web app| H[Firebase Hosting CDN]
    style M fill:#4472C4,color:#fff,stroke:#44546A
    style F fill:#FFA500,color:#fff
    style G fill:#FFA500,color:#fff
    style H fill:#FFA500,color:#fff
`,

  architecture: `
graph TB
    subgraph Client ["Flutter Web Client (Browser)"]
        GR[GoRouter - URL Navigation]
        AS[AppState ChangeNotifier]
        SC[Feature Screens]
        WI[Shared Widgets]
    end
    subgraph Firebase ["Firebase / Google Cloud Platform"]
        FA[Firebase Auth]
        FS[(Cloud Firestore)]
        CF[Cloud Functions v2]
        FH[Firebase Hosting]
        SM[Secret Manager]
    end
    subgraph External ["External Services"]
        SH[Shopify REST API]
        SMTP[SMTP Email Server]
    end
    SC --> AS
    AS --> GR
    AS --> FA
    AS --> FS
    CF --> SH
    CF --> SMTP
    CF --> SM
    CF --> FS
    FH --> Client
    style Client fill:#EBF3FB,stroke:#4472C4
    style Firebase fill:#FFF3E0,stroke:#FFA500
    style External fill:#F3E5F5,stroke:#7B1FA2
`,

  erd: `
erDiagram
    USERS ||--o{ PRODUCTS : "owns"
    USERS ||--o{ SUPPLIERS : "manages"
    USERS ||--o{ WAREHOUSES : "owns"
    USERS ||--o{ DEMAND_RECORDS : "records"
    USERS ||--o{ PURCHASE_ORDERS : "creates"
    USERS ||--o{ SHOPIFY_CONNECTIONS : "links"
    PRODUCTS ||--o{ DEMAND_RECORDS : "has"
    PRODUCTS ||--o{ FORECAST_RESULTS : "generates"
    PRODUCTS ||--o{ REPLENISHMENT_RECS : "triggers"
    PRODUCTS ||--o{ BOM_ITEMS : "requires"
    BOM_ITEMS }o--|| RAW_MATERIALS : "references"
    RAW_MATERIALS ||--o{ RAW_MATERIAL_ORDERS : "ordered via"
    SUPPLIERS ||--o{ PURCHASE_ORDERS : "fulfils"
    PURCHASE_ORDERS ||--o{ ORDER_LINE_ITEMS : "contains"
    PRODUCTS ||--o{ ORDER_LINE_ITEMS : "included in"
    MANUFACTURERS ||--o{ PRODUCTION_ORDERS : "assigned"
    PRODUCTION_ORDERS }o--|| PRODUCTS : "produces"
`,

  loginSequence: `
sequenceDiagram
    actor User
    participant App as Flutter App
    participant Auth as Firebase Auth
    participant FS as Firestore
    participant State as AppState

    User->>App: Enter email + password
    App->>Auth: signInWithEmailAndPassword()
    Auth-->>App: UserCredential + JWT
    App->>State: setUser(uid)
    State->>FS: get users/{uid} document
    FS-->>State: AppUser (role, settings)
    State->>FS: attach collection listeners
    FS-->>State: real-time data streams
    State-->>App: notifyListeners()
    App->>User: Navigate to /dashboard
`,

  shopifySequence: `
sequenceDiagram
    actor Owner
    participant App as Flutter App
    participant CF as Cloud Functions
    participant SH as Shopify API
    participant FS as Firestore

    Owner->>App: Click "Connect Shopify"
    App->>App: Show store URL input
    Owner->>App: Enter store URL
    App->>CF: shopifyGetOAuthUrl(storeUrl)
    CF-->>App: Shopify OAuth URL
    App->>SH: Redirect browser to OAuth page
    Owner->>SH: Approve Ma5zony access
    SH->>CF: OAuth callback (code + shop)
    CF->>SH: Exchange code for access token
    SH-->>CF: Permanent access token
    CF->>FS: Store token in shopifyConnections/{uid}
    CF-->>App: Success response
    App->>CF: importShopifyOrders()
    CF->>SH: GET /orders.json (paginated)
    SH-->>CF: Order data
    CF->>FS: Write demand records
    App->>Owner: Show "Connected" status
`,

  orderStateMachine: `
stateDiagram-v2
    [*] --> Draft : Create PO
    Draft --> Submitted : submit()
    Draft --> [*] : delete()
    Submitted --> Approved : approve()
    Submitted --> Rejected : reject()
    Approved --> Ordered : markAsOrdered()
    Ordered --> PartiallyReceived : partialReceive()
    Ordered --> FullyReceived : fullReceive()
    PartiallyReceived --> FullyReceived : completeReceiving()
    FullyReceived --> [*]
    Rejected --> Draft : revise()
    Rejected --> [*] : discard()
`,

  componentDiagram: `
graph TB
    subgraph Routing
        GR[GoRouter - 25+ named routes]
        RG[RoleGuard - ownerOnlyRoutes]
    end
    subgraph State
        AS[AppState - Central ChangeNotifier]
    end
    subgraph Services
        FR[FirestoreInventoryRepository]
        FAS[FirebaseAuthService]
        FS[ForecastingService - SMA, SES, WMA]
        RS[ReplenishmentService - ROP, EOQ]
        MS[ManufacturingService]
        CS[CashFlowService]
        SS[FirebaseShopifyService]
        NS[NotificationService]
    end
    subgraph Data
        FSdb[(Firestore DB)]
        FAdb[(Firebase Auth)]
    end
    GR --> AS
    RG --> GR
    AS --> FR
    AS --> FAS
    AS --> FS
    AS --> RS
    AS --> MS
    AS --> CS
    AS --> SS
    AS --> NS
    FR --> FSdb
    FAS --> FAdb
    SS --> FSdb
`,

  authFlow: `
graph TD
    A[App Launch] --> B{Auth State}
    B -->|No session| C[Login Screen]
    B -->|Session exists| D[Load AppUser]
    D --> E{User Role}
    E -->|owner| F[Owner Dashboard]
    E -->|inventoryManager| G[Standard Dashboard]
    E -->|manufacturer| H[Manufacturing View]
    C --> I[Enter Credentials]
    I --> J[Firebase Auth]
    J -->|Invalid| K[Show Error]
    K --> I
    J -->|Valid| D
    F --> L{Route Guard}
    G --> L
    L -->|restricted route| M{isOwner}
    M -->|No| N[Redirect Dashboard]
    M -->|Yes| O[Allow Access]
`,

  replenishmentActivity: `
graph TD
    A[Open Forecasts Page] --> B[Load all products]
    B --> C[Evaluate product]
    C --> D{Has demand history?}
    D -->|No| E[Skip product]
    D -->|Yes| F[Run SES forecast]
    F --> G[Calculate ROP]
    G --> H{Stock below ROP?}
    H -->|No| I[Status: Adequate]
    H -->|Yes| J[Calculate EOQ]
    J --> K[Create Recommendation]
    K --> L[Send Inbox notification]
    I --> M{More products?}
    E --> M
    L --> M
    M -->|Yes| C
    M -->|No| N[Show Reorder Plan]
`,

  deploymentDiagram: `
graph TB
    Browser[Browser - Flutter Web App]
    Browser --> FH[Firebase Hosting CDN]
    Browser --> FA[Firebase Auth]
    Browser --> FS[Cloud Firestore]
    CF[Cloud Functions v2] --> SH[Shopify API]
    CF --> SMTP[SMTP Email]
    CF --> SM[Secret Manager]
    CF --> FS
    FS --> Rules[Security Rules]
    style Browser fill:#4472C4,color:#fff
    style CF fill:#FFA500,color:#000
    style FS fill:#34A853,color:#fff
    style FA fill:#EA4335,color:#fff
`,

  gantt: `
gantt
    title Ma5zony Development Timeline
    dateFormat YYYY-MM-DD
    section Research
    Requirements interviews :2024-09-01, 21d
    System design :2024-09-22, 14d
    section Core Dev
    Auth and data model :2024-10-06, 14d
    Product CRUD :2024-10-20, 21d
    Forecasting module :2024-11-10, 21d
    section Advanced
    Replenishment engine :2024-12-01, 21d
    Manufacturing workflow :2024-12-22, 28d
    Shopify integration :2025-01-19, 21d
    section Finalization
    Usability testing :2025-02-23, 14d
    Bug fixes :2025-03-09, 21d
    Dissertation :2025-03-30, 42d
`,

  testingFlow: `
graph TD
    A[Start Tests] --> B[Unit Tests Forecasting]
    B --> C[Unit Tests Replenishment]
    C --> D{Pass?}
    D -->|No| E[Fix tests]
    E --> B
    D -->|Yes| F[Deploy staging]
    F --> G[Smoke test auth]
    G --> H[Smoke test CRUD]
    H --> I[Security rules test]
    I --> J{Pass?}
    J -->|No| K[Fix issues]
    K --> F
    J -->|Yes| L[Think-aloud sessions]
    L --> M[SUS questionnaires]
    M --> N[Performance test]
    N --> O{Issues?}
    O -->|Yes| P[Fix and redeploy]
    P --> F
    O -->|No| Q[Production release]
`,

};

async function fetchAllDiagrams() {
  const results = {};
  const entries = Object.entries(diagrams);
  console.log('Fetching', entries.length, 'diagrams from mermaid.ink...');
  for (const [key, code] of entries) {
    try {
      process.stdout.write('  ' + key + '... ');
      results[key] = await fetchMermaid(key, code.trim());
      console.log('OK (' + Math.round(results[key].length/1024) + ' KB)');
      // Small delay to avoid rate limiting
      await new Promise(r => setTimeout(r, 300));
    } catch (err) {
      console.log('FAILED: ' + err.message);
      results[key] = null;
    }
  }
  return results;
}

module.exports = { fetchAllDiagrams };
