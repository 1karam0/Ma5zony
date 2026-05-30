
// Professional PlantUML diagrams via Kroki.io — high-resolution PNG output
const https = require('https');
const fs = require('fs');
const path = require('path');

const CACHE_DIR = path.join(__dirname, 'diagram_cache');
if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR);

// ── Shared skinparam header for all diagrams ──────────────────────────────────
const SKIN = `
skinparam backgroundColor #FFFFFF
skinparam DefaultFontName Arial
skinparam DefaultFontSize 11
skinparam DefaultFontColor #2C3E50
skinparam ArrowColor #44546A
skinparam ArrowFontColor #44546A
skinparam ArrowFontSize 10
skinparam dpi 180
skinparam shadowing false
skinparam roundCorner 6
skinparam Padding 5
skinparam Handwritten false
`;

const CLASS_SKIN = `
skinparam class {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  HeaderBackgroundColor #44546A
  FontColor #2C3E50
  AttributeFontColor #2C3E50
  StereotypeFontColor #7F8C8D
  BorderThickness 1.5
}
skinparam classHeader {
  FontColor White
  FontStyle Bold
  FontSize 12
}
`;

const SEQ_SKIN = `
skinparam sequence {
  ArrowColor #44546A
  ActorBorderColor #44546A
  ActorBackgroundColor #EBF3FB
  ParticipantBorderColor #44546A
  ParticipantBackgroundColor #EBF3FB
  ParticipantFontStyle Bold
  LifeLineBorderColor #7F8C8D
  LifeLineBackgroundColor #F8F9FA
  BoxBackgroundColor #F0F4F8
  BoxBorderColor #BDC3C7
  DividerBackgroundColor #E8EAF6
  DividerBorderColor #7986CB
  GroupBorderColor #7986CB
  GroupBackgroundColor #E8EAF6
  GroupHeaderFontStyle Bold
}
skinparam note {
  BackgroundColor #FFF9C4
  BorderColor #F0C040
  FontColor #5D4037
}
`;

const ACTIVITY_SKIN = `
skinparam activity {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  DiamondBackgroundColor #FFF3E0
  DiamondBorderColor #E65100
  FontColor #2C3E50
  FontStyle Bold
  ArrowColor #44546A
  StartColor #44546A
  EndColor #C0392B
}
`;

const STATE_SKIN = `
skinparam state {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
  StartColor #44546A
  EndColor #C0392B
  ArrowColor #44546A
}
`;

const COMPONENT_SKIN = `
skinparam component {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
  FontStyle Bold
}
skinparam package {
  BackgroundColor #F0F4F8
  BorderColor #7986CB
  FontColor #2C3E50
  FontStyle Bold
}
skinparam interface {
  BackgroundColor #FFF3E0
  BorderColor #E65100
}
`;

// ── Fetch from Kroki.io ───────────────────────────────────────────────────────
function fetchKroki(diagramType, format, code, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    const body = Buffer.from(code.trim(), 'utf8');
    const options = {
      hostname: 'kroki.io',
      path: `/${diagramType}/${format}`,
      method: 'POST',
      headers: {
        'Content-Type': 'text/plain',
        'Content-Length': body.length,
        'Accept': `image/${format}`
      }
    };
    const timer = setTimeout(() => reject(new Error('timeout')), timeoutMs);
    const req = https.request(options, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        clearTimeout(timer);
        const result = Buffer.concat(chunks);
        // Check for valid PNG or valid content
        const isPNG = result[0] === 0x89 && result[1] === 0x50;
        const isSmall = result.length < 4000;
        if (isSmall && !isPNG) reject(new Error('Render error: ' + result.toString().slice(0, 80)));
        else resolve(result);
      });
      res.on('error', e => { clearTimeout(timer); reject(e); });
    });
    req.on('error', e => { clearTimeout(timer); reject(e); });
    req.write(body);
    req.end();
  });
}

async function fetchDiagram(key, diagramType, format, code) {
  const cachePath = path.join(CACHE_DIR, key + '.' + format);
  if (fs.existsSync(cachePath)) {
    const cached = fs.readFileSync(cachePath);
    if (cached.length > 4000) {
      process.stdout.write('(cached) ');
      return cached;
    }
  }
  const result = await fetchKroki(diagramType, format, code);
  fs.writeFileSync(cachePath, result);
  return result;
}

// ── Diagram definitions ───────────────────────────────────────────────────────

const diagrams = {

  // 1. System Context (C4-style using PlantUML)
  systemContext: { type: 'plantuml', format: 'png', code: `
@startuml systemContext
${SKIN}
skinparam actor {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
  FontStyle Bold
}
skinparam rectangle {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  RoundCorner 10
}
skinparam database {
  BackgroundColor #FFF3E0
  BorderColor #E65100
}
skinparam cloud {
  BackgroundColor #E8F5E9
  BorderColor #2E7D32
}

title System Context Diagram - Ma5zony

actor "SME Owner" as OWNER #EBF3FB
actor "Inventory\\nManager" as INV #EBF3FB
actor "Manufacturer" as MAN #EBF3FB
actor "Supplier" as SUP #EBF3FB

rectangle "**Ma5zony**\\nInventory Management System\\n(Flutter Web + Firebase)" as SYS #DDEEFF

cloud "Shopify\\nPlatform" as SHOP #E8F5E9
database "Cloud\\nFirestore" as FS #FFF3E0
cloud "SMTP\\nEmail Server" as EMAIL #E8F5E9
database "Firebase\\nAuthentication" as AUTH #FFF3E0

OWNER -right-> SYS : Manages inventory,\\nreviews forecasts,\\napproves orders
INV -right-> SYS : Updates stock,\\nrecords demand data
MAN --> SYS : Views & updates\\nproduction orders
SUP --> SYS : Views purchase\\norders (portal)

SYS -right-> SHOP : Imports sales\\norders via OAuth
SYS -right-> EMAIL : Sends supplier &\\nmanufacturer emails
SYS -down-> FS : Persists all\\nbusiness data
SYS -down-> AUTH : User identity\\n& JWT tokens

note right of SYS
  Flutter Web frontend
  Firebase Hosting CDN
  Cloud Functions v2
  Firestore real-time DB
end note
@enduml
` },

  // 2. Use Case Diagram
  useCaseDiagram: { type: 'plantuml', format: 'png', code: `
@startuml useCases
${SKIN}
skinparam usecase {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
}
skinparam actor {
  BackgroundColor #FDEBD0
  BorderColor #E67E22
  FontColor #2C3E50
  FontStyle Bold
}

title Use Case Diagram - Ma5zony System

left to right direction

actor "SME Owner" as OWNER
actor "Inventory Manager" as INV
actor "Manufacturer" as MAN
actor "Supplier" as SUP

OWNER --|> INV : <<extends>>

rectangle "Ma5zony System" {
  usecase "UC01: Login / Register" as UC1
  usecase "UC02: Manage Products" as UC2
  usecase "UC03: Manage Suppliers" as UC3
  usecase "UC04: Manage Warehouses" as UC4
  usecase "UC05: Record Demand Data" as UC5
  usecase "UC06: Run Demand Forecast" as UC6
  usecase "UC07: View Replenishment Plan" as UC7
  usecase "UC08: Create Purchase Order" as UC8
  usecase "UC09: Approve Purchase Order" as UC9
  usecase "UC10: Connect Shopify Store" as UC10
  usecase "UC11: Import Shopify Orders" as UC11
  usecase "UC12: View ABC-XYZ Matrix" as UC12
  usecase "UC13: Manage Raw Materials" as UC13
  usecase "UC14: Manage Bill of Materials" as UC14
  usecase "UC15: Create Production Order" as UC15
  usecase "UC16: Update Production Status" as UC16
  usecase "UC17: View Financial Analytics" as UC17
  usecase "UC18: View Cash Flow" as UC18
  usecase "UC19: Configure Settings" as UC19
  usecase "UC20: Respond via Portal" as UC20
}

INV --> UC1
INV --> UC2
INV --> UC3
INV --> UC4
INV --> UC5
INV --> UC6
INV --> UC7
INV --> UC8
INV --> UC12
INV --> UC13
INV --> UC14
INV --> UC15

OWNER --> UC9
OWNER --> UC10
OWNER --> UC11
OWNER --> UC17
OWNER --> UC18
OWNER --> UC19

MAN --> UC1
MAN --> UC16
MAN --> UC20

SUP --> UC20

UC11 .> UC10 : <<include>>
UC7 .> UC6 : <<include>>
UC8 .> UC3 : <<include>>
UC15 .> UC14 : <<include>>
@enduml
` },

  // 3. Class Diagram
  classDiagram: { type: 'plantuml', format: 'png', code: `
@startuml classDiagram
${SKIN}
${CLASS_SKIN}

title Class Diagram - Ma5zony Domain Model

class AppUser {
  +String uid
  +String email
  +String displayName
  +String role
  +bool tourCompleted
  +fromMap(Map): AppUser
  +toMap(): Map
}

class Product {
  +String id
  +String name
  +String sku
  +String sourcingType
  +double currentStock
  +double unitCost
  +double sellingPrice
  +String supplierId
  +String warehouseId
  +String manufacturerId
  +int leadTimeDays
  +double safetyStock
  +double reorderPoint
  +computeReorderStatus(): String
  +daysOfStock(): double
}

class Supplier {
  +String id
  +String name
  +String email
  +String phone
  +String address
  +String portalToken
}

class Warehouse {
  +String id
  +String name
  +String location
  +double capacity
}

class DemandRecord {
  +String id
  +String productId
  +double quantity
  +DateTime periodStart
  +DateTime periodEnd
  +String source
}

class ForecastResult {
  +String id
  +String productId
  +String algorithm
  +double forecastedDemand
  +double alpha
  +List~double~ historicalValues
  +DateTime generatedAt
}

class ReplenishmentRecommendation {
  +String id
  +String productId
  +double currentStock
  +double reorderPoint
  +double recommendedQty
  +double eoqQty
  +String status
  +DateTime generatedAt
}

class PurchaseOrder {
  +String id
  +String supplierId
  +String status
  +DateTime orderedAt
  +DateTime expectedDelivery
  +double totalCost
  +List~OrderLineItem~ lineItems
  +submit()
  +approve()
  +markOrdered()
  +confirmReceipt()
}

class OrderLineItem {
  +String productId
  +double quantity
  +double unitCost
  +double lineTotal()
}

class RawMaterial {
  +String id
  +String name
  +String unit
  +double currentStock
  +double unitCost
  +int leadTimeDays
}

class BillOfMaterials {
  +String id
  +String productId
  +List~BomItem~ items
  +computeCost(): double
}

class BomItem {
  +String rawMaterialId
  +double quantityRequired
}

class ProductionOrder {
  +String id
  +String productId
  +String manufacturerId
  +double quantityOrdered
  +String status
  +DateTime targetDate
  +updateStatus(String)
}

class ForecastingService {
  +computeSMA(List~double~, int): double
  +computeWMA(List~double~, List~double~): double
  +computeSES(List~double~, double): double
  +computeHolt(List~double~, double, double): List~double~
  +computeHoltWinters(List~double~, int): List~double~
}

class ReplenishmentService {
  +computeROP(double, int, double): double
  +computeSafetyStock(double, double, int): double
  +computeEOQ(double, double, double): double
  +generateRecommendations(List~Product~, List~DemandRecord~): List
}

AppUser "1" --> "many" Product : owns
AppUser "1" --> "many" Supplier : manages
AppUser "1" --> "many" Warehouse : owns
Product "1" --> "many" DemandRecord : has
Product "1" --> "many" ForecastResult : generates
Product "1" --> "1" BillOfMaterials : defined by
BillOfMaterials "1" *-- "many" BomItem : contains
BomItem "many" --> "1" RawMaterial : references
Supplier "1" --> "many" PurchaseOrder : fulfils
PurchaseOrder "1" *-- "many" OrderLineItem : contains
OrderLineItem "many" --> "1" Product : references
ProductionOrder "many" --> "1" Product : produces
ForecastingService ..> DemandRecord : reads
ForecastingService ..> ForecastResult : writes
ReplenishmentService ..> ForecastResult : reads
ReplenishmentService ..> ReplenishmentRecommendation : writes
@enduml
` },

  // 4. ER Diagram
  erd: { type: 'plantuml', format: 'png', code: `
@startuml erd
${SKIN}
skinparam entity {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
}

title Entity-Relationship Diagram - Ma5zony Firestore Schema

entity "**USERS**" as U {
  * uid : String <<PK>>
  --
  email : String
  displayName : String
  role : String
  tourCompleted : Boolean
}

entity "**PRODUCTS**" as P {
  * id : String <<PK>>
  --
  name : String
  sku : String
  sourcingType : String
  currentStock : Number
  unitCost : Number
  supplierId : String <<FK>>
  warehouseId : String <<FK>>
  leadTimeDays : Number
  reorderPoint : Number
}

entity "**SUPPLIERS**" as S {
  * id : String <<PK>>
  --
  name : String
  email : String
  phone : String
  portalToken : String
}

entity "**WAREHOUSES**" as W {
  * id : String <<PK>>
  --
  name : String
  location : String
}

entity "**DEMAND_RECORDS**" as DR {
  * id : String <<PK>>
  --
  productId : String <<FK>>
  quantity : Number
  periodStart : Timestamp
  source : String
}

entity "**FORECAST_RESULTS**" as FR {
  * id : String <<PK>>
  --
  productId : String <<FK>>
  algorithm : String
  forecastedDemand : Number
  historicalValues : Array
  generatedAt : Timestamp
}

entity "**PURCHASE_ORDERS**" as PO {
  * id : String <<PK>>
  --
  supplierId : String <<FK>>
  status : String
  orderedAt : Timestamp
  totalCost : Number
}

entity "**ORDER_LINE_ITEMS**" as OLI {
  * id : String <<PK>>
  --
  productId : String <<FK>>
  quantity : Number
  unitCost : Number
}

entity "**RAW_MATERIALS**" as RM {
  * id : String <<PK>>
  --
  name : String
  unit : String
  currentStock : Number
  unitCost : Number
}

entity "**BILL_OF_MATERIALS**" as BOM {
  * id : String <<PK>>
  --
  productId : String <<FK>>
}

entity "**BOM_ITEMS**" as BI {
  * id : String <<PK>>
  --
  rawMaterialId : String <<FK>>
  quantityRequired : Number
}

entity "**PRODUCTION_ORDERS**" as PRO {
  * id : String <<PK>>
  --
  productId : String <<FK>>
  manufacturerId : String
  status : String
  targetDate : Timestamp
}

entity "**SHOPIFY_CONNECTIONS**" as SC {
  * id : String <<PK>>
  --
  shop : String
  accessToken : String (encrypted)
  connectedAt : Timestamp
}

U ||--o{ P : "owns"
U ||--o{ S : "manages"
U ||--o{ W : "owns"
U ||--o{ PO : "creates"
U ||--o{ SC : "links"
P ||--o{ DR : "recorded in"
P ||--o{ FR : "forecast"
P ||--|{ BOM : "requires"
BOM ||--o{ BI : "contains"
BI }o--|| RM : "references"
S ||--o{ PO : "fulfils"
PO ||--o{ OLI : "contains"
OLI }o--|| P : "for product"
P ||--o{ PRO : "produced by"
@enduml
` },

  // 5. Login Sequence
  loginSequence: { type: 'plantuml', format: 'png', code: `
@startuml loginSequence
${SKIN}
${SEQ_SKIN}
skinparam maxMessageSize 180

title Sequence Diagram: User Authentication Flow

actor "User" as USER
box "Flutter Web Client" #F0F4F8
  participant "LoginScreen" as LS
  participant "AppState" as AS
  participant "FirebaseAuthService" as FAS
end box
box "Firebase / Google Cloud" #FFF3E0
  participant "Firebase Auth" as FA
  database "Cloud Firestore" as FS
end box

USER -> LS : Enter email + password
activate LS
LS -> AS : signIn(email, password)
activate AS
AS -> FAS : signInWithEmailAndPassword()
activate FAS
FAS -> FA : REST call (Firebase Auth API)
activate FA

alt Credentials invalid
  FA -->> FAS : AuthException (wrong-password)
  FAS -->> AS : throw FirebaseAuthException
  AS -->> LS : notifyListeners() [error state]
  LS -->> USER : Show error banner
else Credentials valid
  FA -->> FAS : UserCredential + JWT token
  deactivate FA
  FAS -->> AS : UserCredential
  deactivate FAS

  AS -> FS : get users/{uid} document
  activate FS
  FS -->> AS : AppUser { role, settings }
  deactivate FS

  AS -> FS : attach 15 collection listeners
  activate FS
  note right of FS
    Listeners for: products,
    suppliers, warehouses,
    demandRecords, forecasts,
    orders, rawMaterials, bom,
    manufacturers, productionOrders,
    replenishmentRecs, notifications,
    cashFlow, shopifyConnections,
    workflowLogs
  end note
  FS -->> AS : real-time data streams
  deactivate FS

  AS -> AS : setUser(appUser)
  AS -> AS : notifyListeners()
  deactivate AS
  LS -> LS : GoRouter.go('/dashboard')
  deactivate LS
  LS -->> USER : Dashboard rendered
end
@enduml
` },

  // 6. Shopify OAuth Sequence
  shopifySequence: { type: 'plantuml', format: 'png', code: `
@startuml shopifySequence
${SKIN}
${SEQ_SKIN}
skinparam maxMessageSize 160

title Sequence Diagram: Shopify OAuth Integration & Order Import

actor "SME Owner" as OWNER
box "Flutter Web" #F0F4F8
  participant "IntegrationsScreen" as IS
  participant "AppState" as AS
end box
box "Cloud Functions v2" #E8F5E9
  participant "shopifyGetOAuthUrl" as CF1
  participant "shopifyOAuthCallback" as CF2
  participant "importShopifyOrders" as CF3
end box
box "Shopify" #FFF3E0
  participant "Shopify OAuth" as SO
  participant "Shopify API" as SA
end box
database "Firestore" as FS

OWNER -> IS : Enter store URL, click Connect
IS -> CF1 : POST shopifyGetOAuthUrl\\n{storeUrl, redirectUri}
activate CF1
CF1 -> CF1 : Build OAuth URL with scopes:\\nread_orders, read_products
CF1 -->> IS : {oauthUrl}
deactivate CF1

IS -> SO : Redirect browser to Shopify OAuth page
SO -->> OWNER : Display permission grant screen
OWNER -> SO : Click "Install App"
SO -> CF2 : GET callback?code=xxx&shop=yyy
activate CF2
CF2 -> SO : POST /oauth/access_token\\n{client_id, client_secret, code}
SO -->> CF2 : {access_token, scope}
note right of CF2
  Token NEVER sent to client.
  Stored server-side only.
end note
CF2 -> FS : set shopifyConnections/{uid}\\n{shop, accessToken, scope}
CF2 -->> IS : 200 OK - redirect to app
deactivate CF2

IS -> AS : onShopifyConnected()
AS -> CF3 : call importShopifyOrders()
activate CF3
CF3 -> FS : get shopifyConnections/{uid}
FS -->> CF3 : access_token
loop Paginate orders (cursor-based)
  CF3 -> SA : GET /admin/orders.json\\n?status=any&limit=250&page_info=...
  SA -->> CF3 : Order batch (line items, dates)
  CF3 -> FS : batch write demand records
end
CF3 -->> IS : {imported: N orders}
deactivate CF3
IS -->> OWNER : "Connected - N orders imported"
@enduml
` },

  // 7. Purchase Order State Machine
  orderStateMachine: { type: 'plantuml', format: 'png', code: `
@startuml orderStateMachine
${SKIN}
${STATE_SKIN}

title State Machine Diagram: Purchase Order Lifecycle

[*] --> Draft : Owner creates\\nPurchase Order

Draft : Entry / Set status = "draft"
Draft : Do / Allow quantity editing
Draft : Do / Allow supplier change

state "Draft" as Draft
state "Submitted" as Submitted
state "Approved" as Approved
state "Ordered" as Ordered
state "PartiallyReceived" as PartiallyReceived {
  state "Awaiting\\nremainder" as Await
}
state "FullyReceived" as FullyReceived
state "Rejected" as Rejected

Draft --> Submitted : submit()\\n[all line items complete]
Draft --> [*] : delete()

Submitted : Entry / Notify owner for approval
Submitted : Do / Lock editing
Submitted --> Approved : approve()\\n[Owner role required]
Submitted --> Rejected : reject(reason)

Approved : Entry / Send email to supplier\\nvia Cloud Functions
Approved --> Ordered : markAsOrdered()\\n[confirmation sent to supplier]

Ordered : Entry / Track expected delivery date
Ordered --> PartiallyReceived : receivePartial(qty)\\n[received < ordered]
Ordered --> FullyReceived : receiveAll()\\n[received = ordered]

PartiallyReceived --> FullyReceived : completeReceiving()

FullyReceived : Entry / Update product stock\\nEntry / Record stock movement
FullyReceived --> [*]

Rejected : Entry / Notify reason to submitter
Rejected --> Draft : revise()
Rejected --> [*] : discard()

note right of Approved
  Email sent automatically
  via Cloud Function:
  sendSupplierEmail()
end note

note right of FullyReceived
  Firestore stock level updated.
  WorkflowLog entry created.
end note
@enduml
` },

  // 8. Component Diagram
  componentDiagram: { type: 'plantuml', format: 'png', code: `
@startuml componentDiagram
${SKIN}
${COMPONENT_SKIN}

title Component Diagram - Ma5zony Architecture

package "Flutter Web Application" {
  package "Routing Layer" {
    [GoRouter] as GR
    [RoleGuard] as RG
  }
  package "State Management" {
    [AppState\\n(ChangeNotifier)] as AS
  }
  package "Service Layer" {
    [FirestoreInventory\\nRepository] as FIR
    [FirebaseAuth\\nService] as FAS
    [ForecastingService\\n(SMA, WMA, SES, Holt)] as FS
    [ReplenishmentService\\n(ROP, EOQ, SafetyStock)] as RS
    [ManufacturingService] as MS
    [CashFlowService] as CS
    [FirebaseShopify\\nService] as SS
    [NotificationService] as NS
    [WorkflowService] as WS
  }
  package "UI Layer" {
    [Dashboard Screen] as DS
    [Products Screen] as PS
    [Forecasts Screen] as FC
    [Orders Screen] as OS
    [Manufacturing\\nScreens] as MfS
    [Financial Screens] as FinS
  }
}

package "Firebase Backend" {
  database "Cloud Firestore" as CF
  database "Firebase Auth" as FA
  [Cloud Functions v2] as CFn
}

package "External APIs" {
  [Shopify REST API] as SHOP
  [SMTP Server] as SMTP
}

GR --> AS : reads auth state
RG --> GR : enforces\\nowner-only routes
DS --> AS : context.watch()
PS --> AS : context.watch()
FC --> AS : context.watch()
OS --> AS : context.watch()
MfS --> AS : context.watch()
FinS --> AS : context.watch()

AS --> FIR : CRUD operations
AS --> FAS : auth operations
AS --> FS : compute forecasts
AS --> RS : compute replenishment
AS --> MS : production workflow
AS --> CS : financial aggregation
AS --> SS : Shopify connection
AS --> NS : notifications
AS --> WS : audit trail

FIR --> CF : Firestore SDK
FAS --> FA : Firebase Auth SDK
SS --> CFn : HTTP calls
CFn --> SHOP : REST API
CFn --> SMTP : Nodemailer
CFn --> CF : Admin SDK
@enduml
` },

  // 9. Authentication Flow (Activity)
  authFlow: { type: 'plantuml', format: 'png', code: `
@startuml authFlow
${SKIN}
${ACTIVITY_SKIN}
skinparam swimlane {
  BorderColor #44546A
  TitleFontColor #44546A
}

title Activity Diagram: Authentication and Role-Based Access Control

|Flutter App|
start
:App Launch - main.dart;
:Initialize Firebase;
:Subscribe to Auth State stream;

|Firebase Auth|
:Evaluate persistent session;

|Flutter App|
if (Session token valid?) then (yes)
  :Resolve current User;
  |Firestore|
  :Fetch AppUser document\\n(role, settings, tourCompleted);
  |Flutter App|
  :Populate AppState with user profile;
  :Attach real-time collection listeners;

  switch (User Role?)
  case ( owner )
    :Navigate to Owner Dashboard\\n(all modules visible);
  case ( inventoryManager )
    :Navigate to Standard Dashboard\\n(Finance hidden);
  case ( manufacturer )
    :Navigate to Manufacturing View\\n(only mfg screens);
  case ( rawMaterialFactory )
    :Navigate to Factory View\\n(only RM screens);
  endswitch

  if (Accessing owner-only route?) then (yes)
    if (isOwner?) then (yes)
      :Allow access;
    else (no)
      :Redirect to /dashboard;
    endif
  else (no)
    :Allow access;
  endif

else (no)
  :Navigate to /login;
  :User enters credentials;

  |Firebase Auth|
  :Verify email + password;

  if (Valid credentials?) then (yes)
    :Issue JWT token;
    |Flutter App|
    :Return to auth state check;
  else (no)
    |Flutter App|
    :Display error banner;
    :Return to login form;
  endif
endif

stop
@enduml
` },

  // 10. Replenishment Activity
  replenishmentActivity: { type: 'plantuml', format: 'png', code: `
@startuml replenishmentActivity
${SKIN}
${ACTIVITY_SKIN}

title Activity Diagram: Demand Forecasting and Replenishment Workflow

start
:User navigates to /forecasts;
:AppState triggers ReplenishmentService;
:Load all active products with\\ncurrent stock levels;
:Load all demand records;

while (More products to evaluate?) is (yes)
  :Select next product;

  if (Has demand records >= 3 periods?) then (no)
    #FFE0B2:Mark as INSUFFICIENT DATA;
    note right: Cannot compute forecast\\nwithout minimum data
  else (yes)
    :Compute SES forecast\\nalpha = 0.3 (configurable);
    :Retrieve product lead time (days);
    :Compute average demand rate;

    :Calculate Safety Stock\\nSS = Z * sigma_demand * sqrt(lead_time)\\nZ = 1.645 for 95% service level;

    :Calculate Reorder Point\\nROP = avg_demand_per_day * lead_time + SS;

    if (Current stock <= ROP?) then (yes)
      #FFCDD2:Status: REORDER REQUIRED;
      :Calculate EOQ\\nEOQ = sqrt(2 * annual_demand * ordering_cost / holding_cost);
      :Create ReplenishmentRecommendation\\n{productId, currentStock, ROP, EOQ, recommendedQty};
      :Write recommendation to Firestore;
      :Create inbox notification for owner;
    else (no)
      #C8E6C9:Status: ADEQUATE;
      note right
        Stock level is above
        reorder point. No action
        required this period.
      end note
    endif
  endif
endwhile (no)

:Sort recommendations by urgency\\n(days of stock remaining ASC);
:Render Reorder Plan table to user;
:Display ABC-XYZ classification overlay;

stop
@enduml
` },

  // 11. Deployment Diagram
  deploymentDiagram: { type: 'plantuml', format: 'png', code: `
@startuml deploymentDiagram
${SKIN}
skinparam node {
  BackgroundColor #EBF3FB
  BorderColor #44546A
  FontColor #2C3E50
  FontStyle Bold
}
skinparam artifact {
  BackgroundColor #FFF3E0
  BorderColor #E65100
}
skinparam database {
  BackgroundColor #E8F5E9
  BorderColor #2E7D32
}
skinparam cloud {
  BackgroundColor #E3F2FD
  BorderColor #1565C0
}

title Deployment Diagram - Ma5zony Production Infrastructure

node "User Browser" as BROWSER {
  artifact "Flutter Web Bundle\\n(WASM + JS, ~1.8 MB compressed)" as FW
}

cloud "Google Cloud Platform\\nus-central1 region" as GCP {

  node "Firebase Hosting\\n(Global CDN)" as FH {
    artifact "Static Web Assets\\nbuild/web/**" as ASSETS
    artifact "Auto TLS Certificate\\n(Google-managed)" as TLS
  }

  node "Firebase Authentication\\n(Google Identity Platform)" as FA {
    artifact "JWT Token Service" as JWT
    artifact "User Identity Store" as UIS
  }

  node "Cloud Firestore\\n(NoSQL Document DB)" as FS {
    database "users/{uid}/..." as USERD
    artifact "Security Rules Engine\\nfirestore.rules" as RULES
    artifact "Real-time Listener\\nPush Updates" as RTDB
  }

  node "Cloud Functions v2\\n(Cloud Run containers)" as CF {
    artifact "shopifyGetOAuthUrl" as CF1
    artifact "shopifyOAuthCallback" as CF2
    artifact "importShopifyOrders" as CF3
    artifact "sendSupplierEmail" as CF4
    artifact "shopifyWebhook" as CF5
  }

  node "Secret Manager" as SM {
    artifact "SHOPIFY_API_KEY\\nSHOPIFY_API_SECRET\\nSMTP_HOST / SMTP_PASS" as SECRETS
  }
}

node "Shopify Platform" as SHOP {
  artifact "Shopify REST API\\n/admin/orders, /admin/products" as SHOPAPI
}

node "Email Infrastructure" as EMAIL {
  artifact "SMTP Server\\n(Gmail / SendGrid)" as SMTP
}

FW --> FH : HTTPS\\n(CDN edge)
FW --> FA : Firebase SDK\\n(JWT auth)
FW --> FS : Firestore SDK\\n(real-time WebSocket)
CF --> SECRETS : Secret Manager API
CF --> SHOPAPI : REST API\\n(server-to-server)
CF --> SMTP : STARTTLS\\n(Nodemailer)
CF --> USERD : Admin SDK\\n(privileged write)
BROWSER -[hidden]right- GCP
@enduml
` },

  // 12. Gantt Chart
  gantt: { type: 'plantuml', format: 'png', code: `
@startgantt
${SKIN}
skinparam gantt {
  FontName Arial
  FontSize 11
  BarColor #4472C4
  BarBackgroundColor #EBF3FB
  MilestoneColor #C0392B
  ArrowColor #44546A
}

title Ma5zony - Project Development Gantt Chart
printscale monthly zoom 2

Project starts 2024-09-01

-- Phase 1: Research and Planning --
[Requirements interviews] lasts 21 days
[System architecture design] lasts 14 days
[System architecture design] starts at [Requirements interviews]'s end

-- Phase 2: Core Development --
[Firebase project setup] lasts 7 days
[Firebase project setup] starts at [System architecture design]'s end

[Authentication module] lasts 14 days
[Authentication module] starts at [Firebase project setup]'s end

[Firestore data model] lasts 10 days
[Firestore data model] starts at [Firebase project setup]'s end

[Product and Supplier CRUD] lasts 21 days
[Product and Supplier CRUD] starts at [Authentication module]'s end

[Demand data recording] lasts 14 days
[Demand data recording] starts at [Product and Supplier CRUD]'s end

-- Phase 3: Intelligence Features --
[Forecasting module SMA+SES] lasts 21 days
[Forecasting module SMA+SES] starts at [Demand data recording]'s end

[Replenishment engine ROP+EOQ] lasts 21 days
[Replenishment engine ROP+EOQ] starts at [Forecasting module SMA+SES]'s end

[ABC-XYZ classification matrix] lasts 10 days
[ABC-XYZ classification matrix] starts at [Replenishment engine ROP+EOQ]'s end

-- Phase 4: Advanced Modules --
[Manufacturing workflow] lasts 28 days
[Manufacturing workflow] starts at [ABC-XYZ classification matrix]'s end

[Shopify OAuth integration] lasts 21 days
[Shopify OAuth integration] starts at [Manufacturing workflow]'s end

[Portal system Supplier+Mfg] lasts 14 days
[Portal system Supplier+Mfg] starts at [Shopify OAuth integration]'s end

[Financial analytics module] lasts 14 days
[Financial analytics module] starts at [Portal system Supplier+Mfg]'s end

-- Phase 5: Quality and Documentation --
[Think-aloud usability testing] lasts 14 days
[Think-aloud usability testing] starts at [Financial analytics module]'s end

[Bug fixes and QA] lasts 21 days
[Bug fixes and QA] starts at [Think-aloud usability testing]'s end

[Dissertation writing] lasts 42 days
[Dissertation writing] starts at [Bug fixes and QA]'s end

[Ma5zony v1.0 Release] happens at [Bug fixes and QA]'s end
[Dissertation Submission] happens at [Dissertation writing]'s end
@endgantt
` },

};

// ── Fetch all diagrams ────────────────────────────────────────────────────────
async function fetchAllDiagrams() {
  const results = {};
  const entries = Object.entries(diagrams);
  console.log('Rendering', entries.length, 'professional diagrams via Kroki.io...');

  for (const [key, { type, format, code }] of entries) {
    try {
      process.stdout.write('  ' + key + '... ');
      results[key] = await fetchDiagram(key, type, format, code);
      console.log('OK (' + Math.round(results[key].length / 1024) + ' KB)');
      await new Promise(r => setTimeout(r, 400));
    } catch (err) {
      console.log('FAILED: ' + err.message);
      results[key] = null;
    }
  }
  return results;
}

module.exports = { fetchAllDiagrams };
