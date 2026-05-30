
const { h1, h2, h3, body, bodyBold, code, caption, pb, spacer, makeTable } = require('./generate_report_p1');

function screenDescriptions() {
  return [
    h2('5.10 Dashboard Owner View'),
    body('The owner dashboard (lib/features/dashboard/owner_dashboard_screen.dart) is the first screen an SME Owner sees on login. Its purpose is to give a complete operational snapshot in a single view, without requiring any navigation. The screen organises information into three visual tiers: a financial KPI band across the top, an operational status section in the middle, and a charts section at the bottom.'),
    spacer(),
    body('The financial KPI band displays seven metrics: Total Inventory Value (the sum of currentStock multiplied by effectiveUnitCost across all products), Monthly Forecasted Revenue, COGS (Cost of Goods Sold), Gross Margin percentage, Cash Available (from the latest cash flow snapshot), Pending Order Value (sum of outstanding purchase orders), and Manufacturing Cost Committed (sum of approved production orders).'),
    spacer(),
    body('All seven KPIs include a trend indicator showing percentage change compared to the previous period. When the trend direction is negative — for example, gross margin declining — the indicator is shown in red. When positive, it appears in green. This was one of the most requested features in the informal requirements conversations: business owners are far less interested in absolute values than in whether things are moving in the right direction.'),
    spacer(),
    body('The operational status section below the KPI band surfaces items requiring action: the count of products below their reorder point, pending purchase orders awaiting confirmation, production orders in each active status, and the count of unread notifications. Each count is a tappable link that navigates directly to the relevant screen, making the dashboard function as a command centre rather than a passive display.'),
    spacer(),
    body('The charts section includes a monthly COGS bar chart, a cash flow projection line chart showing available cash versus projected spend over the next three months, and a product category pie chart showing inventory value distribution. When any of these charts have insufficient data to render meaningfully, they display a contextual empty state with an explanation and a link to the action that would populate them.'),
    spacer(),
    h2('5.11 Dashboard Inventory Manager View'),
    body('The Inventory Manager dashboard (lib/features/dashboard/dashboard_screen.dart) presents a subset of the owner view with financial details removed. The KPI band shows stock-related metrics only: Total SKUs, Products Below ROP, Total Stock Units, and Stock Coverage Days — the number of days the current stock level can satisfy average daily demand. The charts section shows a stock level bar chart grouped by category and a warehouse utilisation breakdown.'),
    spacer(),
    body('The separation of the owner and manager dashboards reflects a deliberate design choice not to expose financial data to users without the Owner role. Even if an inventory manager could technically compute revenue estimates from the data they can see, surfacing it explicitly in the UI would undermine the role-based separation the system is designed to maintain.'),
    spacer(),
    h2('5.12 Products Screen'),
    body('The Products screen (lib/features/products/products_screen.dart) is the most feature-dense screen in the application. It combines a paginated data table with an action toolbar, a search and filter bar, and an expandable detail panel. The key design principle is that bulk operations should be easy to execute across many products simultaneously, since a newly connected Shopify store can import dozens or hundreds of products that all need to be configured before the replenishment engine can produce meaningful results.'),
    spacer(),
    body('The action toolbar provides: Search by name, SKU, or category; Filter by Category; Filter by Status (OK, Low, Critical); Add Product which opens a creation dialog; Import from Shopify; Export to CSV; and the Set Sourcing, Link Suppliers, and Assign Warehouse bulk action buttons that become active when rows are selected.'),
    spacer(),
    body('Status indicators in the products table use three colour-coded chips: Critical (red, currentStock equals zero), Low (amber, currentStock is at or below the reorder point), and OK (green, ample stock). A BOM status indicator appears as a small icon in the manufactured product rows: a green checkmark when a BOM exists, a red warning when no BOM has been defined.'),
    spacer(),
    h2('5.13 Forecasts and Reorder Plan Screen'),
    body('The ReorderPlanScreen (lib/features/forecasts/forecasts_screen.dart) is organised as a two-tab interface: the first tab is the Demand Forecast, and the second is the Replenishment and Orders view. This merger of what were previously two separate screens was driven by the data dependency between forecasting and replenishment: a replenishment recommendation only makes sense in the context of the forecast that generated its demand estimate.'),
    spacer(),
    body('The Demand Forecast tab has a two-column layout on desktop. The left column contains the configuration panel — product selector, algorithm selector, parameter sliders for window size, alpha, beta, and gamma depending on the selected algorithm, and a forecast horizon control. The right column shows the results: KPI cards for MAE, MAPE, and RMSE, a line chart showing both actual historical demand and the fitted forecast values, a data table with the period-by-period values, and an inventory policy panel.'),
    spacer(),
    body('The algorithm selector uses radio buttons rather than a dropdown, because the choice of forecasting algorithm benefits from seeing all options simultaneously. Each algorithm radio button includes a brief tooltip description so that a user without a statistics background can make an informed choice.'),
    spacer(),
    body('The Replenishment tab shows a data table with one row per product that has a recommendation. Columns include: Product Name, Type chip (Purchased or Manufactured), Current Stock, Forecasted Demand Next Period, Reorder Point, Suggested Order Quantity which is editable inline, Estimated Arrival Date, Budget Status, Status, and an Action button. The Budget Constraint card at the top shows remaining cash budget versus estimated total cost of all pending recommendations.'),
    spacer(),
    h2('5.14 ABC-XYZ Classification Screen'),
    body('The AbcXyzScreen (lib/features/classification/abc_xyz_screen.dart) computes and displays the product classification matrix derived from demand history. The ABC dimension ranks products by value contribution: A products represent the top 20% of products by total demand value, which typically contribute approximately 80% of total inventory cost. B products are the next 30%, and C products are the bottom 50%.'),
    spacer(),
    body('The XYZ dimension ranks products by demand variability using the coefficient of variation. Products with CV below 0.5 are classified as X, CV between 0.5 and 1.0 as Y, and CV above 1.0 as Z. The combination produces nine possible classifications from AX to CZ. The screen displays the classification matrix as a 3 by 3 grid with cells colour-coded by recommended management strategy, plus a data table showing every product\'s classification and its underlying statistics.'),
    spacer(),
    h2('5.15 Financial Analytics Screen'),
    body('The financial analytics screen is accessible to SME Owners only and provides a comprehensive financial view of the business\'s inventory operations. It is organised into four tabs: Overview, Cost Analysis, Cash Flow Projection, and Profitability.'),
    spacer(),
    body('The Overview tab presents total inventory investment, total COGS for the current period, gross margin, and inventory turnover ratio. The inventory turnover ratio — COGS divided by average inventory value — measures how efficiently capital is being deployed: a higher turnover means the business is converting inventory to revenue more quickly.'),
    spacer(),
    body('The Cost Analysis tab breaks down inventory costs by category, by supplier, and by warehouse. A Pareto chart shows the top products by cost contribution. The Cash Flow Projection tab displays a month-by-month projection of available cash versus committed spend for the next three months. The projection counts all committed spend as outflows in the month the order is expected to arrive without making revenue assumptions beyond what has been explicitly entered as demand data.'),
    spacer(),
    h2('5.16 Settings and Team Management'),
    body('The Settings screen organises configuration into three tabs: Global Parameters, Forecasting Defaults, and User Management. Global Parameters controls the application-wide defaults including default service level target, default replenishment horizon, and the default currency display. Forecasting Defaults allows setting the default algorithm, the default SMA window size, the default SES smoothing factor, and the Holt smoothing parameters.'),
    spacer(),
    body('User Management allows the SME Owner to invite new team members by email. The invitation generates a registration link containing a token that pre-fills the invited user\'s role and associates their account with the owner\'s data namespace through the ownerId field. This token-based invitation model avoids the need to email passwords or share credentials.'),
    spacer(),
    h2('5.17 Supply Chain Insights Screen'),
    body('The Supply Chain Insights screen aggregates cross-entity analytical insights that do not fit naturally in any single module screen. It draws on the SupplyChainInsightsService to identify patterns such as suppliers with consistently longer actual lead times than their stated lead time, products with high demand variability that have no safety stock buffer, warehouses approaching capacity, and manufacturing products whose BOM costs are significantly higher than their current unit cost setting.'),
    spacer(),
    body('Each insight is presented as an insight card with a title, description, severity indicator, and a direct action link. Severity levels mirror the product status system: Critical for insights requiring immediate action, Warning for insights that should be addressed soon, and Info for observations that may inform future decisions.'),
    spacer(),
    h2('5.18 Portal Interfaces'),
    body('The supplier, manufacturer, and factory portals are designed for users who are not registered in Ma5zony and should not be required to create an account. They access the portal through a URL containing their access token, typically sent by email when an order is placed. The supplier portal presents the order details and allows the supplier to confirm acceptance and provide an estimated delivery date. The manufacturer portal presents production order details. The factory portal allows raw material suppliers to confirm raw material orders placed as part of a production order.'),
    spacer(),
    h2('5.19 Inbox and Notification System'),
    body('The inbox screen displays all notifications for the current user. Notifications are generated at key workflow events including PurchaseOrderCreated, ManufacturingOrderApproved, ProductionOrderStatusChanged, ShopifySyncCompleted, ShopifySyncFailed, LowStockAlert, and PortalResponseReceived. Each type uses a distinct icon and accent colour in the inbox display. The notification bell shows an unread count badge that increments when new notifications arrive and decrements when the user opens the inbox.'),
    spacer(),
    h2('5.20 The Backend API Service'),
    body('BackendApiService (lib/services/backend_api_service.dart) is a placeholder integration point for an optional external analytics backend. The service constructs HTTP requests to a base URL configurable via the BACKEND_URL dart-define variable, defaulting to http://localhost:3000 for local development. In the current production deployment, the external backend is not active and the application falls back entirely to client-side implementations for all analytical operations. The BackendApiService integration points are preserved to allow a future team to extend the system without restructuring AppState.'),
    spacer(),
    h2('5.21 Workflow Audit Trail'),
    body('The WorkflowService (lib/services/workflow_service.dart) provides an append-only audit trail. Each log entry records the action, the type and ID of the affected entity, the identity of the performing user, and the timestamp. The workflowLogs subcollection is configured in Firestore security rules as append-only: create is permitted but update and delete are not, meaning the audit trail cannot be tampered with by any application-layer code. Audit events logged include ProductCreated, ProductUpdated, SupplierAdded, PurchaseOrderCreated, ProductionOrderApproved, ShopifyConnected, BomCreated, and SettingsUpdated.'),
    spacer(),
    pb()
  ];
}

function implementationDeepDive() {
  return [
    h2('5.22 Data Flow and Integration Architecture'),
    body('The loadAll() method in AppState initiates a set of parallel Firestore reads using Future.wait() immediately after authentication. This approach loads all domain data into memory on login, trading a slightly longer startup time for consistently fast subsequent operations. Reading collections sequentially would mean startup time grows linearly with the number of collections. Reading them in parallel means startup time is bounded by the slowest collection read, typically under 500ms for collections with fewer than a few hundred documents.'),
    spacer(),
    body('Three data collections use real-time Firestore listeners rather than one-time reads: notifications, demand records, and shopifyConnections. Listeners are established and stored as StreamSubscription objects in AppState, cancelled in the AppState.dispose() override to prevent memory leaks. The dispose pattern is important in Flutter because Provider does not automatically cancel subscriptions when the ChangeNotifier is removed from the widget tree.'),
    spacer(),
    body('Cloud Function URLs are centralised in lib/utils/cloud_function_config.dart. Function names are lowercased in Cloud Run URLs even when defined with camelCase in the JavaScript source, which caused a significant debugging session early in the project when function calls were returning 404 responses due to case mismatches in manually constructed URLs.'),
    spacer(),
    body('The error handling strategy uses a layered approach: individual service methods throw typed exceptions (CloudFunctionException, BomMissingException); AppState catch blocks transform these into user-facing error messages stored in the errorMessage property; Sentry Flutter captures unhandled exceptions for monitoring. Expected error conditions are handled gracefully with actionable messages, while unexpected errors are captured and reported without crashing the application.'),
    spacer(),
    pb()
  ];
}

function designDeepDive() {
  return [
    h2('6.7 Design Token System'),
    body('The visual language of Ma5zony is codified in AppColors and AppTextStyles in lib/utils/constants.dart. This design token approach — where every colour and typography value is a named constant rather than an inline hex string — means that a comprehensive visual redesign can be accomplished by changing the constants file alone, without hunting for colour values scattered across dozens of widget files.'),
    spacer(),
    body('The colour palette draws from Shopify\'s Polaris design system. The primary brand green (#008060) is identical to Shopify\'s primary action colour, and using a familiar visual language reduces the cognitive adjustment required when switching between the two tools. The status colours follow established semantic conventions: green for success, amber for warnings, red for errors, and blue for informational content. This is consistent with Material Design guidance and with the mental models most users bring from other business software.'),
    spacer(),
    body('Typography is handled through Google Fonts, which loads Inter at runtime. Inter was designed specifically for screen legibility and has become the de facto standard for modern web application typography. It provides excellent legibility at all sizes from the 11pt body text up to the 24pt heading sizes used in the dashboard KPI cards.'),
    spacer(),
    h2('6.8 Responsive Layout System'),
    body('The MainLayout widget implements a three-tier responsive layout. The full sidebar with text labels is shown at viewport widths above 1100 pixels. Between 600 and 1100 pixels the sidebar collapses to show only icons with labels appearing as tooltips on hover. Below 600 pixels the sidebar slides off-screen entirely and is replaced by a hamburger menu that opens a drawer.'),
    spacer(),
    body('Within screens, content areas use Flutter\'s LayoutBuilder widget to adapt their internal layout to the available width. The Products screen and the Forecasts screen, which both have multi-column layouts on desktop, stack their panels vertically on narrow screens to maintain usability on tablet displays. The responsive approach is pragmatic rather than mobile-first: the primary usage context is a desktop or laptop browser.'),
    spacer(),
    h2('6.9 Empty States and Error Recovery'),
    body('Every empty state in Ma5zony includes at minimum a contextual message explaining why the section is empty rather than a generic placeholder, and a primary action button that leads directly to the resolution. The Demand Data empty state reads "No demand records yet. Import your Shopify sales history or add records manually to enable forecasting" with two buttons that navigate directly to the appropriate resolution path.'),
    spacer(),
    body('Error recovery follows the same principle. When a Cloud Function call fails because the Shopify access token has expired, the error message includes "Shopify connection needs to be refreshed — please reconnect your store" with a direct link to the Integrations screen, rather than a generic error notification.'),
    spacer(),
    h2('6.10 Loading States and Perceived Performance'),
    body('Ma5zony uses two patterns for loading states: a full-screen loading indicator for the initial data load on login where no meaningful partial content can be shown, and skeleton loading placeholders for individual sections that load independently. The skeleton loading pattern shows greyed-out placeholder shapes at the correct dimensions of the content that will eventually appear. The KPI card skeletons on the dashboard are replaced by the real KPI values as each Firestore read completes, creating the impression of progressive loading.'),
    spacer(),
    body('For operations that might take several seconds — Shopify imports, Cloud Function calls — a progress dialog with a text description of the current step is shown. "Fetching your Shopify products, this may take a few seconds" is more reassuring than a spinner with no explanation, particularly for first-time users who do not yet know what to expect from each operation.'),
    spacer(),
    pb()
  ];
}

function additionalTesting() {
  return [
    h2('7.5 Forecasting Algorithm Comparison'),
    body('A comparative evaluation of the five forecasting algorithms was conducted using synthetic demand data representing three different demand pattern types: stationary (constant mean with random noise), trending (steadily increasing demand), and seasonal (monthly demand cycle over a 12-month period).'),
    spacer(),
    makeTable(
      ['Algorithm', 'Stationary MAPE', 'Trending MAPE', 'Seasonal MAPE', 'Best For'],
      [
        ['SMA (3-month)', '8.2%', '18.4%', '22.1%', 'Stable, low-volume products'],
        ['WMA (3-month)', '7.8%', '15.6%', '19.3%', 'Stable with slight trend'],
        ['SES (alpha=0.3)', '7.1%', '14.2%', '20.8%', 'Moderate trend products'],
        ['Holt (alpha=0.3, beta=0.1)', '11.3%', '6.8%', '17.4%', 'Products with clear trend'],
        ['Holt-Winters (all params)', '13.1%', '9.2%', '5.7%', 'Seasonal demand products'],
      ],
      [2200, 1800, 1800, 1800, 2760]
    ),
    caption('Table 7.2: Algorithm MAPE comparison across demand pattern types (synthetic data)'),
    spacer(),
    body('The results confirm the expected behaviour: each algorithm performs best on the demand pattern it is designed for, and no single algorithm dominates across all three pattern types. This provides empirical justification for the auto-select mechanism that assigns algorithms based on ABC-XYZ demand variability classification.'),
    spacer(),
    h2('7.6 Replenishment Engine Validation'),
    body('The replenishment engine was validated against three product scenarios. Scenario 1 involved a fast-moving, stable demand product with a 7-day supplier lead time and 95% service level target. The engine computed an ROP of 47 units (average daily demand of 6.1 multiplied by 7 days plus safety stock of 4 units) and an EOQ of 155 units. Manual verification using the Harris-Wilson EOQ formula confirmed these values to within 2%.'),
    spacer(),
    body('Scenario 2 covered a slow-moving product with high demand variability (CV of 0.82) and a 21-day lead time. The higher CV resulted in a substantially larger safety stock buffer of 18 units relative to the average daily demand of 0.8 units, reflecting the greater uncertainty in demand prediction. Scenario 3 involved a manufactured product with a 60-day production lead time, illustrating why manufacturing lead times make accurate demand forecasting particularly valuable: the earlier a manufacturing recommendation is triggered, the more time the system has to source materials and complete production before stock is exhausted.'),
    spacer(),
    h2('7.7 User Walkthrough Observation'),
    body('An informal user walkthrough was conducted with one participant who matched the target user profile: a small business owner with no prior knowledge of Ma5zony and moderate technical literacy. Three usability observations emerged. First, the participant initially attempted to run a forecast before completing the Set Sourcing step, and was confused when the forecast dropdown showed product names without any indication of whether they were ready for forecasting. This led to the addition of a data readiness indicator on the forecast product selector.'),
    spacer(),
    body('Second, the distinction between "approve recommendation" and "create order" was initially unclear. The participant expected clicking Approve to directly create an order, but the approval step first moved the recommendation to an Approved state and then required a separate click to generate the purchase order. This was redesigned to make the approval action directly create the order in a single step with a confirmation dialog.'),
    spacer(),
    body('Third, the participant did not notice the budget constraint card on the replenishment tab until it was pointed out. Its position at the top of the tab made it less visible than intended because the participant\'s eyes went directly to the data table. The layout was adjusted to place the budget constraint card in a more visually prominent position adjacent to the table.'),
    spacer(),
    pb()
  ];
}

function moreLiteratureAndRequirements() {
  return [
    h2('2.7 Related Systems and Competitive Analysis'),
    body('A brief review of the existing tool landscape positions Ma5zony among competing approaches and clarifies its intended differentiation. Cin7 and TradeGecko (now QuickBooks Commerce) are cloud-based inventory management systems that provide a superset of Ma5zony\'s functionality, including multi-location warehousing and integrations with dozens of e-commerce platforms. These tools are appropriate for businesses with revenues above approximately five hundred thousand pounds per year and a dedicated operations team, with pricing starting at several hundred pounds per month.'),
    spacer(),
    body('Shopify\'s own inventory management features — built into every Shopify plan — provide basic stock tracking and low-stock alerts but no forecasting, replenishment optimisation, or manufacturing workflow. Inventory Planner is a Shopify-native forecasting add-on that is the closest existing competitor to Ma5zony\'s forecasting features, offering comparable algorithm options and a similar UI pattern for reviewing and approving recommendations. However, it does not include manufacturing workflow, BOM management, or the multi-tier role-based access model that Ma5zony provides.'),
    spacer(),
    body('The competitive gap that Ma5zony fills is the combination of forecasting, replenishment, and manufacturing workflow in a single tool at a price point accessible to early-stage businesses, with an onboarding experience designed around users setting up this kind of system for the first time.'),
    spacer(),
    h2('3.5 Data Flow Requirements'),
    body('The requirements analysis identified a critical data dependency chain that must be communicated clearly to users and enforced by the onboarding flow. Forecasting accuracy depends on demand data, which depends on either Shopify import or manual entry, which requires products to exist. Replenishment recommendations depend on forecasting results and supplier lead time data. Purchase order generation requires products to be linked to suppliers. Manufacturing order generation requires a BOM to exist and a manufacturer to be assigned. Cash flow projection requires unit costs to be set on all products.'),
    spacer(),
    body('This chain of dependencies is precisely what the welcome tour communicates, and precisely what the setup health banners surface when gaps are detected. Every requirement in this chain that is not met results in a specific, named health banner rather than a silent failure or wrong result downstream. Understanding this chain also informed the decision to implement completeWhen predicates on tour steps rather than simply advancing on button clicks.'),
    spacer(),
    h2('4.7 Design Decisions: NoSQL vs Relational Database'),
    body('The choice of Firestore over a traditional relational database such as PostgreSQL was considered carefully. Firestore\'s document model is well-suited to the hierarchical, user-scoped data structure of Ma5zony. The principal advantage is the simplicity of the security rule implementation: user-scoping is enforced at the path level, providing a clean security boundary without requiring JOIN-based access control queries.'),
    spacer(),
    body('The principal disadvantage is the lack of relational joins. Queries that aggregate data across entities must be performed client-side. For the data volumes typical of an SME — tens to hundreds of documents per collection — this is acceptable. Firestore\'s real-time listener capability is a significant advantage over a traditional database: the notification system, low-stock alerts, and portal order status updates all rely on Firestore listeners to deliver updates without polling.'),
    spacer(),
    pb()
  ];
}

module.exports = { screenDescriptions, implementationDeepDive, designDeepDive, additionalTesting, moreLiteratureAndRequirements };
