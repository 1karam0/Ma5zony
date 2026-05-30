/**
 * Cloud Functions for Ma5zony – Shopify Integration
 *
 * SETUP REQUIRED (one-time):
 *   firebase functions:secrets:set SHOPIFY_API_KEY
 *   firebase functions:secrets:set SHOPIFY_API_SECRET
 *
 * Deploy with:
 *   cd functions && npm install && cd ..
 *   firebase deploy --only functions
 */

const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const https = require("https");

admin.initializeApp();
const db = admin.firestore();

const SHOPIFY_API_KEY = defineSecret("SHOPIFY_API_KEY");
const SHOPIFY_API_SECRET = defineSecret("SHOPIFY_API_SECRET");

/** Shopify API version — override with SHOPIFY_API_VERSION env var. */
const SHOPIFY_API_VERSION = process.env.SHOPIFY_API_VERSION || "2025-04";

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Execute a Shopify GraphQL Admin API query. */
async function shopifyGraphQL(shopDomain, accessToken, query, variables = {}) {
  const postData = JSON.stringify({ query, variables });
  const result = await httpsRequest(
    {
      hostname: shopDomain,
      path: `/admin/api/${SHOPIFY_API_VERSION}/graphql.json`,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Access-Token": accessToken,
        "Content-Length": Buffer.byteLength(postData),
      },
    },
    postData
  );

  if (result.statusCode !== 200) {
    throw new Error(`Shopify GraphQL error: HTTP ${result.statusCode}`);
  }

  const parsed = JSON.parse(result.body);
  if (parsed.errors && parsed.errors.length > 0) {
    throw new Error(`Shopify GraphQL error: ${parsed.errors[0].message}`);
  }
  return parsed.data;
}

/** Promisified HTTPS request helper (no external deps). */
function httpsRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on("data", (d) => chunks.push(d));
      res.on("end", () => {
        const body = Buffer.concat(chunks).toString();
        resolve({ statusCode: res.statusCode, body, headers: res.headers });
      });
    });
    req.on("error", reject);
    if (postData) req.write(postData);
    req.end();
  });
}

/** Validate that a shop domain looks like *.myshopify.com */
function isValidShopDomain(shop) {
  return /^[a-zA-Z0-9][a-zA-Z0-9-]*\.myshopify\.com$/.test(shop);
}

/** Allowed origins for CORS.
 *  In production set the CORS_ALLOWED_ORIGINS env var (comma-separated).
 *  Localhost is only allowed when NODE_ENV !== 'production'.
 */
const _productionOrigins = [
  "https://ma5zony.web.app",
  "https://ma5zony.firebaseapp.com",
];
const _extraOrigins = process.env.CORS_ALLOWED_ORIGINS
  ? process.env.CORS_ALLOWED_ORIGINS.split(",").map((o) => o.trim())
  : [];
const ALLOWED_ORIGINS = [..._productionOrigins, ..._extraOrigins];

/** Set CORS headers and handle preflight. Returns true if preflight handled. */
function handleCors(req, res) {
  const origin = req.headers.origin || "";
  // Always allow localhost for local development (all ports).
  // All endpoints still require a valid Firebase Auth token, so this is safe.
  const isLocalhost = /^http:\/\/localhost(:\d+)?$/.test(origin);
  if (ALLOWED_ORIGINS.includes(origin) || isLocalhost) {
    res.set("Access-Control-Allow-Origin", origin);
  } else {
    res.set("Access-Control-Allow-Origin", ALLOWED_ORIGINS[0]);
  }
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

/** Verify Firebase ID token from Authorization header. Returns uid or null. */
async function verifyAuth(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const idToken = authHeader.split("Bearer ")[1];
  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded.uid;
  } catch {
    return null;
  }
}

// ── 1. shopifyGetOAuthUrl ────────────────────────────────────────────────────

exports.shopifyGetOAuthUrl = onRequest(
  { secrets: [SHOPIFY_API_KEY] },
  async (req, res) => {
    if (handleCors(req, res)) return;

    const uid = await verifyAuth(req);
    if (!uid) { res.status(401).json({ error: "Sign in required." }); return; }

    const shopDomain = req.body?.data?.shopDomain;
    if (!shopDomain || !isValidShopDomain(shopDomain)) {
      res.status(400).json({ error: "Provide a valid *.myshopify.com domain." });
      return;
    }

    const nonce = crypto.randomBytes(16).toString("hex");
    // Nonce expires in 10 minutes to prevent CSRF replay attacks.
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
    await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("pending_oauth")
      .set({ nonce, shopDomain, createdAt: admin.firestore.FieldValue.serverTimestamp(), expiresAt });

    const redirectUri = process.env.SHOPIFY_CALLBACK_URL ||
      `https://shopifyoauthcallback-rjv64oud6a-uc.a.run.app`;

    const scopes = "read_products,read_inventory,read_orders";
    const authUrl =
      `https://${shopDomain}/admin/oauth/authorize` +
      `?client_id=${SHOPIFY_API_KEY.value().trim()}` +
      `&scope=${scopes}` +
      `&redirect_uri=${encodeURIComponent(redirectUri)}` +
      `&state=${uid}:${nonce}`;

    res.json({ result: { authUrl } });
  }
);

// ── 2. shopifyOAuthCallback (HTTP) ───────────────────────────────────────────
// Shopify redirects here after the merchant approves the app.

exports.shopifyOAuthCallback = onRequest(
  { secrets: [SHOPIFY_API_KEY, SHOPIFY_API_SECRET] },
  async (req, res) => {
    const { code, shop, state, hmac } = req.query;

    // --- validate required params ---
    if (!code || !shop || !state || !hmac) {
      res.status(400).send("Missing required query parameters.");
      return;
    }

    if (!isValidShopDomain(shop)) {
      res.status(400).send("Invalid shop domain.");
      return;
    }

    // --- verify HMAC from Shopify ---
    const queryParams = { ...req.query };
    delete queryParams.hmac;
    const sorted = Object.keys(queryParams)
      .sort()
      .map((k) => `${k}=${queryParams[k]}`)
      .join("&");
    const digest = crypto
      .createHmac("sha256", SHOPIFY_API_SECRET.value().trim())
      .update(sorted)
      .digest("hex");
    if (
      !crypto.timingSafeEqual(Buffer.from(digest), Buffer.from(hmac))
    ) {
      res.status(403).send("HMAC verification failed.");
      return;
    }

    // --- verify nonce ---
    const parts = state.split(":");
    if (parts.length !== 2) {
      res.status(400).send("Invalid state parameter.");
      return;
    }
    const [uid, nonce] = parts;
    const pendingDoc = await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("pending_oauth")
      .get();

    if (!pendingDoc.exists || pendingDoc.data().nonce !== nonce) {
      res.status(403).send("Nonce mismatch – possible CSRF.");
      return;
    }
    // Validate nonce expiry (10 minutes)
    const oauthExpiresAt = pendingDoc.data().expiresAt;
    if (oauthExpiresAt && oauthExpiresAt.toDate && oauthExpiresAt.toDate() < new Date()) {
      res.status(403).send("OAuth nonce expired. Please start the connection process again.");
      return;
    }

    // --- exchange code for permanent access token ---
    const postData = JSON.stringify({
      client_id: SHOPIFY_API_KEY.value().trim(),
      client_secret: SHOPIFY_API_SECRET.value().trim(),
      code,
    });

    const tokenRes = await httpsRequest(
      {
        hostname: shop,
        path: "/admin/oauth/access_token",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(postData),
        },
      },
      postData
    );

    if (tokenRes.statusCode !== 200) {
      res.status(502).send("Failed to exchange code for token.");
      return;
    }

    const { access_token } = JSON.parse(tokenRes.body);

    // Store token server-side (never sent to the client).
    await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("connection")
      .set({
        shopDomain: shop,
        accessToken: access_token,
        isConnected: true,
        connectedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSyncAt: null,
      });

    // Clean up pending OAuth doc.
    await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("pending_oauth")
      .delete();

    // Best-effort: subscribe to orders/create so new sales auto-sync into
    // Firestore as demand records. Failure here is non-fatal — the user can
    // still trigger a manual sync from Integrations.
    try { await registerOrdersWebhook(uid, shop, access_token); }
    catch (e) { console.warn("OAuth: webhook registration failed:", e.message); }

    res.send(
      "<html><body><h2>Store connected!</h2><p>You can close this window and return to Ma5zony.</p></body></html>"
    );
  }
);

// ── 3. shopifyImportProducts (GraphQL) ───────────────────────────────────────

exports.shopifyImportProducts = onRequest(
  { secrets: [SHOPIFY_API_KEY, SHOPIFY_API_SECRET] },
  async (req, res) => {
    if (handleCors(req, res)) return;

    const uid = await verifyAuth(req);
    if (!uid) { res.status(401).json({ error: "Sign in required." }); return; }

    const connDoc = await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("connection")
      .get();

    if (!connDoc.exists || !connDoc.data().isConnected) {
      res.status(400).json({ error: "No active Shopify connection." });
      return;
    }

    const { shopDomain, accessToken } = connDoc.data();

    // GraphQL query with cursor-based pagination.
    // `query: "status:active"` filters out archived/draft products so only
    // currently-sellable items are imported into Ma5zony.
    //
    // We pull Shopify's selling price (`variant.price`) and bundle
    // composition only. **Cost per item is intentionally NOT imported** —
    // cost is always derived inside Ma5zony from either:
    //   • the raw materials in the BOM + production fee (manufactured), or
    //   • the supplier price typed by the user (purchased).
    // This keeps the inventory cost on the dashboard accurate to what the
    // business actually pays.
    //
    // `productVariantComponents` is only available on stores running the
    // Shopify Bundles app + API 2024-01+. We try the full query first and
    // fall back to the no-bundles query if Shopify rejects the field.
    const PRODUCTS_QUERY_WITH_BUNDLES = `
      query FetchProducts($cursor: String) {
        products(first: 50, after: $cursor, query: "status:active") {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              title
              productType
              status
              featuredImage { url }
              variants(first: 20) {
                edges {
                  node {
                    id
                    title
                    sku
                    price
                    inventoryQuantity
                    productVariantComponents(first: 10) {
                      edges {
                        node {
                          quantity
                          productVariant {
                            id
                            sku
                            product { id title }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    `;

    const PRODUCTS_QUERY_NO_BUNDLES = `
      query FetchProducts($cursor: String) {
        products(first: 100, after: $cursor, query: "status:active") {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              title
              productType
              status
              featuredImage { url }
              variants(first: 50) {
                edges {
                  node {
                    id
                    title
                    sku
                    price
                    inventoryQuantity
                  }
                }
              }
            }
          }
        }
      }
    `;

    // Mutable: starts with bundle-aware query, downgrades on first failure.
    let PRODUCTS_QUERY = PRODUCTS_QUERY_WITH_BUNDLES;
    let bundleQuerySupported = true;

    // Auto-categorisation: keyword in the product title overrides whatever
    // Shopify productType says. Keeps "Figure 8 Strap", "Wrist Strap" etc. all
    // under one "Straps" category for the user's setup workflow.
    function autoCategory(title, fallback) {
      const t = String(title || "").toLowerCase();
      if (/\bstrap(s)?\b/.test(t)) return "Straps";
      if (/\bbelt(s)?\b/.test(t)) return "Belts";
      if (/\bcuff(s)?\b/.test(t)) return "Cuffs";
      return fallback || "Uncategorised";
    }

    try {
      // ── Pre-read existing Shopify-linked docs ─────────────────────────────
      // Used to (a) deactivation sweep and (b) preserve user-set fields (cost,
      // supplier, leadTime) that must NOT be overwritten on re-import.
      const existingSnap = await db
        .collection("users")
        .doc(uid)
        .collection("products")
        .where("shopifyProductId", "!=", null)
        .get();
      const existingDocMap = {};
      for (const doc of existingSnap.docs) {
        existingDocMap[doc.id] = doc.data();
      }

      const imported = [];
      const batch = db.batch();
      // bundleVariantMap[shopifyVariantId] = [{ shopifyVariantId, shopifyProductId, sku, quantity, name }, ...]
      // Persisted to Firestore so `shopifyImportOrders` can explode bundle
      // line items into demand against the underlying component SKUs instead
      // of double-counting the bundle as its own product.
      const bundleVariantMap = {};
      let cursor = null;
      let hasNextPage = true;

      while (hasNextPage) {
        let data;
        try {
          data = await shopifyGraphQL(
            shopDomain,
            accessToken,
            PRODUCTS_QUERY,
            { cursor }
          );
        } catch (err) {
          // Downgrade once if:
          //  (a) productVariantComponents field unsupported on this store, OR
          //  (b) the query cost exceeds Shopify's 1000-point single-query limit.
          // Both are recoverable by switching to the cheaper NO_BUNDLES query.
          const msg = String(err && err.message ? err.message : err);
          if (
            bundleQuerySupported &&
            /productVariantComponents|Field .* doesn't exist|Field .* not found|Query cost.*exceeds|exceeds.*cost.*limit|single query max cost/i
              .test(msg)
          ) {
            console.log(
              "[shopifyImport] falling back to no-bundles query. Reason: " + msg
            );
            bundleQuerySupported = false;
            PRODUCTS_QUERY = PRODUCTS_QUERY_NO_BUNDLES;
            continue; // retry same page with downgraded query
          }
          throw err;
        }

        const { edges, pageInfo } = data.products;
        hasNextPage = pageInfo.hasNextPage;
        cursor = pageInfo.endCursor;

        for (const { node: sp } of edges) {
          // Extract numeric ID from Shopify GID (e.g. "gid://shopify/Product/123" → "123")
          const shopifyId = sp.id.split("/").pop();
          const variants = sp.variants.edges.map((e) => e.node);
          if (variants.length === 0) continue;

          // ── Collapse all variants into ONE parent product ─────────────────
          // The user only needs to set up the general product once (cost,
          // supplier, etc.) — variants share those. Stock is summed across
          // variants so the parent reflects the real on-hand total.
          const totalStock = variants.reduce(
            (s, v) => s + (v.inventoryQuantity ?? 0),
            0
          );
          // Pick a representative SKU: first variant's SKU, or fall back.
          const firstSku = variants.find((v) => v.sku && v.sku.trim())?.sku;
          const sku = firstSku || `SHOP-${shopifyId}`;
          // Shopify selling price (first variant) — stored separately so it is
          // never confused with the user's cost price.
          const sellingPrice = parseFloat(
            variants.find((v) => v.price)?.price ?? "0"
          ) || null;

          // ── Bundle components (Shopify Bundles) ───────────────────────────
          // Flatten components across all variants of this product. Each
          // entry records which Shopify variant (and parent product) makes up
          // one unit of this bundle, plus the quantity. Cost is rolled up at
          // read time inside the Flutter app via AppState.effectiveUnitCost.
          const bundleComponents = [];
          for (const v of variants) {
            const compEdges =
              (v.productVariantComponents &&
                v.productVariantComponents.edges) ||
              [];
            for (const { node: comp } of compEdges) {
              const pv = comp && comp.productVariant;
              if (!pv) continue;
              const compVariantId = pv.id ? pv.id.split("/").pop() : null;
              const compProductId =
                pv.product && pv.product.id
                  ? pv.product.id.split("/").pop()
                  : null;
              bundleComponents.push({
                shopifyVariantId: compVariantId,
                shopifyProductId: compProductId,
                quantity: comp.quantity || 1,
                name: pv.product ? pv.product.title : pv.sku || null,
              });
            }
          }
          const isBundle = bundleComponents.length > 0;

          // ── Skip bundles entirely ─────────────────────────────────────────
          // Importing bundles as products causes double-counting in demand
          // and stock — the component SKUs are already imported as their own
          // Shopify products. Record the bundle→components mapping (keyed by
          // every bundle variant id) so `shopifyImportOrders` can explode
          // bundle line items into demand against the real component SKUs.
          if (isBundle) {
            for (const v of variants) {
              const vid = v.id.split("/").pop();
              const compEdges =
                (v.productVariantComponents &&
                  v.productVariantComponents.edges) ||
                [];
              if (compEdges.length === 0) continue;
              const comps = [];
              for (const { node: comp } of compEdges) {
                const pv = comp && comp.productVariant;
                if (!pv || !pv.id) continue;
                comps.push({
                  shopifyVariantId: pv.id.split("/").pop(),
                  shopifyProductId:
                    pv.product && pv.product.id
                      ? pv.product.id.split("/").pop()
                      : null,
                  sku: pv.sku || null,
                  quantity: comp.quantity || 1,
                  name:
                    (pv.product && pv.product.title) ||
                    pv.sku ||
                    null,
                });
              }
              if (comps.length > 0) bundleVariantMap[vid] = comps;
            }
            continue; // do not write the bundle as a product doc
          }

          const docId = `shopify_${shopifyId}`;
          const existing = existingDocMap[docId];

          // ── imageUrl: always sync from Shopify ────────────────────────────
          // The product's main image in Shopify is the source of truth. We
          // pull `featuredImage.url` and overwrite on every import so renames
          // / re-uploads on the Shopify side show up in Ma5zony's product
          // table next to the product name.
          const imageUrl =
            (sp.featuredImage && sp.featuredImage.url) || null;

          // ── unitCost: NEVER touched by Shopify import ─────────────────────
          // Cost is sourced from the BOM (manufactured) or typed by the user
          // (purchased). On first import we initialise to 0; on subsequent
          // imports we leave whatever the user has entered alone.
          const unitCostField = existing ? {} : { unitCost: 0 };

          const docData = {
            sku,
            name: sp.title,
            category: autoCategory(sp.title, sp.productType),
            // sellingPrice always comes from Shopify (source of truth).
            sellingPrice,
            // unitCost left untouched (managed inside Ma5zony, not Shopify).
            ...unitCostField,
            currentStock: totalStock,
            // Don't overwrite supplierId / manufacturerId / leadTimeDays that
            // the user may have linked — only set them on first import.
            ...(existing ? {} : { supplierId: null }),
            isActive: sp.status === "ACTIVE",
            shopifyProductId: shopifyId,
            imageUrl,
            // Comma-separated list of all variant IDs so order matching can
            // resolve any variant sale back to this single parent product.
            shopifyVariantId: variants
              .map((v) => v.id.split("/").pop())
              .join(","),
            variantCount: variants.length,
            // Bundle metadata. Always write so removed bundles are cleared.
            isBundle,
            bundleComponents,
          };

          const ref = db
            .collection("users")
            .doc(uid)
            .collection("products")
            .doc(docId);
          batch.set(ref, docData, { merge: true });
          imported.push({
            id: ref.id,
            ...docData,
            unitCost:
              unitCostField.unitCost ?? existing?.unitCost ?? 0,
          });
        }
      }

      await batch.commit();

      // ── Persist bundle → component-SKU map ──────────────────────────────────
      // Stored at users/{uid}/shopify/bundleMap so `shopifyImportOrders` can
      // explode bundle line items into demand against the underlying SKUs.
      // Always write (even if empty) to clear stale mappings from previous
      // imports when a bundle is deleted in Shopify.
      await db
        .collection("users")
        .doc(uid)
        .collection("shopify")
        .doc("bundleMap")
        .set({
          bundles: bundleVariantMap,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      // ── Deactivation sweep ──────────────────────────────────────────────────
      // Any product that was previously imported from Shopify but is NOT in the
      // current active-only result set has since been archived or deleted in
      // Shopify. Mark those Firestore docs as isActive: false so they are hidden
      // from forecasts, low-stock alerts, and replenishment recommendations.
      const importedDocIds = new Set(imported.map((p) => p.id));
      const deactivateBatch = db.batch();
      let deactivated = 0;
      for (const doc of existingSnap.docs) {
        if (!importedDocIds.has(doc.id)) {
          deactivateBatch.update(doc.ref, { isActive: false });
          deactivated++;
        }
      }
      if (deactivated > 0) await deactivateBatch.commit();

      res.json({ result: { count: imported.length, deactivated, products: imported } });
    } catch (err) {
      console.error("shopifyImportProducts error:", err);
      res.status(502).json({ error: err.message || "Shopify API error fetching products." });
    }
  }
);

// ── 4. shopifySyncInventory (GraphQL) ────────────────────────────────────────

exports.shopifySyncStock = onRequest(
  { secrets: [SHOPIFY_API_KEY, SHOPIFY_API_SECRET] },
  async (req, res) => {
    if (handleCors(req, res)) return;

    const uid = await verifyAuth(req);
    if (!uid) { res.status(401).json({ error: "Sign in required." }); return; }

    const connDoc = await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("connection")
      .get();

    if (!connDoc.exists || !connDoc.data().isConnected) {
      res.status(400).json({ error: "No active Shopify connection." });
      return;
    }

    const { shopDomain, accessToken } = connDoc.data();

    // `query: "status:active"` matches the product import filter so that
    // draft and archived products are never touched by inventory syncs.
    const SYNC_QUERY = `
      query SyncInventory($cursor: String) {
        products(first: 100, after: $cursor, query: "status:active") {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              variants(first: 50) {
                edges {
                  node {
                    id
                    inventoryQuantity
                  }
                }
              }
            }
          }
        }
      }
    `;

    try {
      const batch = db.batch();
      let synced = 0;
      let cursor = null;
      let hasNextPage = true;

      while (hasNextPage) {
        const data = await shopifyGraphQL(shopDomain, accessToken, SYNC_QUERY, { cursor });
        const { edges, pageInfo } = data.products;
        hasNextPage = pageInfo.hasNextPage;
        cursor = pageInfo.endCursor;

        for (const { node: sp } of edges) {
          const shopifyId = sp.id.split("/").pop();
          const variants = sp.variants.edges.map((e) => e.node);

          // Sum stock across all variants → write to the single parent doc.
          const totalStock = variants.reduce(
            (s, v) => s + (v.inventoryQuantity ?? 0),
            0
          );
          const ref = db
            .collection("users")
            .doc(uid)
            .collection("products")
            .doc(`shopify_${shopifyId}`);
          batch.set(ref, {
            currentStock: totalStock,
          }, { merge: true });
          synced++;
        }
      }

      await batch.commit();

      await db
        .collection("users")
        .doc(uid)
        .collection("shopify")
        .doc("connection")
        .update({ lastSyncAt: admin.firestore.FieldValue.serverTimestamp() });

      res.json({ result: { synced } });
    } catch (err) {
      console.error("shopifySyncStock error:", err);
      res.status(502).json({ error: err.message || "Shopify API error." });
    }
  }
);

// ── 5. shopifyDisconnect ─────────────────────────────────────────────────────

exports.shopifyDisconnectStore = onRequest(async (req, res) => {
  if (handleCors(req, res)) return;

  const uid = await verifyAuth(req);
  if (!uid) { res.status(401).json({ error: "Sign in required." }); return; }

  await db
    .collection("users")
    .doc(uid)
    .collection("shopify")
    .doc("connection")
    .delete();

  res.json({ result: { success: true } });
});

// ── 6. shopifyImportOrders (GraphQL) ─────────────────────────────────────────
// Fetches order history from Shopify using GraphQL and writes demand records
// to Firestore, aggregated into monthly buckets per product.
// Resolution order: shopifyVariantId → SKU (case-insensitive) → shopifyProductId
// This ensures variant-level products (e.g. same shirt, different size/color)
// each get their own demand bucket rather than being lumped under the parent.

exports.shopifyImportOrders = onRequest(
  { secrets: [SHOPIFY_API_KEY, SHOPIFY_API_SECRET] },
  async (req, res) => {
    if (handleCors(req, res)) return;

    const uid = await verifyAuth(req);
    if (!uid) { res.status(401).json({ error: "Sign in required." }); return; }

    const connDoc = await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("connection")
      .get();

    if (!connDoc.exists || !connDoc.data().isConnected) {
      res.status(400).json({ error: "No active Shopify connection." });
      return;
    }

    const { shopDomain, accessToken } = connDoc.data();

    // Fetch variant SKU + titles so we can match the correct Ma5zony product
    // even when it was added manually (no Shopify IDs, SKU possibly differs).
    const ORDERS_QUERY = `
      query FetchOrders($cursor: String) {
        orders(first: 100, after: $cursor) {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              createdAt
              lineItems(first: 50) {
                edges {
                  node {
                    quantity
                    title
                    name
                    sku
                    product { id title }
                    variant { id sku title }
                  }
                }
              }
            }
          }
        }
      }
    `;

    try {
      console.log(`shopifyImportOrders: starting for shop=${shopDomain}`);

      // ── Load bundle → component-SKU map (written by shopifyImportProducts) ──
      // Bundles are NOT imported as Ma5zony products to avoid double-counting
      // demand. Instead, when an order line item is a bundle variant we
      // explode it into demand against each underlying component SKU.
      const bundleMapDoc = await db
        .collection("users")
        .doc(uid)
        .collection("shopify")
        .doc("bundleMap")
        .get();
      const bundleMap = bundleMapDoc.exists
        ? (bundleMapDoc.data().bundles || {})
        : {};

      // ── Build product resolution maps from Firestore ──────────────────────
      // Priority: shopifyVariantId → sku exact → sku normalised → name → contains → shopifyProductId
      const productsSnap = await db
        .collection("users")
        .doc(uid)
        .collection("products")
        .get();

      const byVariantId = {};
      const bySku       = {};
      const bySkuNorm   = {};
      const byName      = {};
      const byProductId = {};

      const normalise = (s) =>
        String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "");

      for (const doc of productsSnap.docs) {
        const d = doc.data();
        // Skip inactive (archived) products so they're never matched against
        // incoming Shopify orders.
        if (d.isActive === false) continue;
        // shopifyVariantId may be a single ID OR a comma-separated list of
        // every variant under this parent product (collapsed variants).
        if (d.shopifyVariantId) {
          for (const vid of String(d.shopifyVariantId).split(",")) {
            const trimmed = vid.trim();
            if (trimmed) byVariantId[trimmed] = doc.id;
          }
        }
        if (d.sku) {
          const sku = String(d.sku);
          bySku[sku.toLowerCase()] = doc.id;
          const n = normalise(sku);
          if (n.length >= 3) bySkuNorm[n] = doc.id;
        }
        if (d.name) {
          const n = normalise(d.name);
          if (n.length >= 3) byName[n] = doc.id;
        }
        if (d.shopifyProductId) byProductId[String(d.shopifyProductId)] = doc.id;
      }

      const unmatchedSamples = new Map(); // key → diagnostic record

      function resolveProductId(line) {
        const { shopifyProductId, shopifyVariantId, variantSku, lineSku,
                productTitle, variantTitle, lineTitle } = line;

        // 1. Exact Shopify variant id
        if (shopifyVariantId && byVariantId[shopifyVariantId])
          return byVariantId[shopifyVariantId];

        // 2. Exact SKU (variant SKU, then line-item SKU)
        const skuCandidates = [variantSku, lineSku].filter(Boolean);
        for (const s of skuCandidates) {
          const lc = String(s).toLowerCase();
          if (bySku[lc]) return bySku[lc];
        }

        // 3. Normalised SKU (strip whitespace / punctuation)
        for (const s of skuCandidates) {
          const n = normalise(s);
          if (n.length >= 3 && bySkuNorm[n]) return bySkuNorm[n];
        }

        // 4. Normalised name — exact, then bidirectional "contains"
        const nameCandidates = [
          lineTitle,
          productTitle && variantTitle ? `${productTitle} ${variantTitle}` : null,
          productTitle,
        ].filter(Boolean);
        for (const t of nameCandidates) {
          const n = normalise(t);
          if (n.length >= 3 && byName[n]) return byName[n];
        }
        for (const t of nameCandidates) {
          const n = normalise(t);
          if (n.length < 4) continue;
          let bestKey = null;
          for (const key of Object.keys(byName)) {
            if (key.length < 4) continue;
            if (n.includes(key) || key.includes(n)) {
              if (!bestKey || key.length > bestKey.length) bestKey = key;
            }
          }
          if (bestKey) return byName[bestKey];
        }

        // 5. Parent Shopify product id (variant-level products will collide)
        if (shopifyProductId && byProductId[shopifyProductId])
          return byProductId[shopifyProductId];

        // Unmatched — record diagnostics so the UI can tell the user exactly
        // which Shopify SKUs / titles do not match any Ma5zony product.
        const key = shopifyVariantId || variantSku || lineSku || lineTitle || shopifyProductId || "unknown";
        const prev = unmatchedSamples.get(key);
        if (prev) prev.count += 1;
        else unmatchedSamples.set(key, {
          sku: variantSku || lineSku || null,
          title: lineTitle || null,
          productTitle: productTitle || null,
          shopifyProductId,
          shopifyVariantId,
          count: 1,
        });
        return `shopify_${shopifyProductId || "unknown"}`;
      }

      // ── Paginate through all orders ───────────────────────────────────────
      const monthlyMap = {};
      let cursor = null;
      let hasNextPage = true;
      let totalOrders = 0;
      let totalLineItems = 0;
      let matchedLineItems = 0;
      const MAX_PAGES = 50;
      let page = 0;

      while (hasNextPage && page < MAX_PAGES) {
        page++;
        const data = await shopifyGraphQL(shopDomain, accessToken, ORDERS_QUERY, { cursor });
        if (!data || !data.orders) {
          console.error("shopifyImportOrders: unexpected response structure", JSON.stringify(data));
          throw new Error("Unexpected response from Shopify orders API");
        }
        const { edges, pageInfo } = data.orders;
        hasNextPage = pageInfo.hasNextPage;
        cursor = pageInfo.endCursor;

        for (const { node: order } of edges) {
          totalOrders++;
          const orderDate = order.createdAt || new Date().toISOString();
          const d = new Date(orderDate);
          const year  = d.getUTCFullYear();
          const month = String(d.getUTCMonth() + 1).padStart(2, "0");

          for (const { node: item } of order.lineItems.edges) {
            totalLineItems++;
            const shopifyProductId = item.product && item.product.id ? item.product.id.split("/").pop() : null;
            const shopifyVariantId = item.variant && item.variant.id ? item.variant.id.split("/").pop() : null;

            // ── Bundle explosion ────────────────────────────────────────────
            // If this variant is a known bundle, split it into per-component
            // demand records (qty × componentQty) and skip the bundle itself.
            const components = shopifyVariantId && bundleMap[shopifyVariantId];
            if (components && components.length > 0) {
              for (const comp of components) {
                const compLine = {
                  shopifyProductId: comp.shopifyProductId,
                  shopifyVariantId: comp.shopifyVariantId,
                  variantSku: comp.sku,
                  lineSku: comp.sku,
                  productTitle: comp.name,
                  variantTitle: null,
                  lineTitle: comp.name,
                };
                const compFirestoreId = resolveProductId(compLine);
                if (compFirestoreId && !compFirestoreId.startsWith("shopify_")) matchedLineItems++;
                const qty = (item.quantity || 0) * (comp.quantity || 1);
                const key = `${compFirestoreId}||${year}-${month}`;
                if (!monthlyMap[key]) {
                  monthlyMap[key] = {
                    productId: compFirestoreId,
                    periodStart: new Date(Date.UTC(year, d.getUTCMonth(), 1)).toISOString(),
                    quantity: 0,
                  };
                }
                monthlyMap[key].quantity += qty;
              }
              continue; // do not also credit the bundle
            }

            const line = {
              shopifyProductId,
              shopifyVariantId,
              variantSku:   item.variant ? (item.variant.sku || null) : null,
              lineSku:      item.sku || null,
              productTitle: item.product ? (item.product.title || null) : null,
              variantTitle: item.variant ? (item.variant.title || null) : null,
              lineTitle:    item.title || item.name || null,
            };

            const firestoreId = resolveProductId(line);
            if (firestoreId && !firestoreId.startsWith("shopify_")) matchedLineItems++;

            const key = `${firestoreId}||${year}-${month}`;
            if (!monthlyMap[key]) {
              monthlyMap[key] = {
                productId: firestoreId,
                periodStart: new Date(Date.UTC(year, d.getUTCMonth(), 1)).toISOString(),
                quantity: 0,
              };
            }
            monthlyMap[key].quantity += item.quantity || 0;
          }
        }
      }

      // ── Write to Firestore ────────────────────────────────────────────────
      // Use deterministic doc IDs derived from (productId, year-month) so that
      // re-imports overwrite cleanly without creating duplicates.
      const batch = db.batch();
      let imported = 0;

      for (const [key, record] of Object.entries(monthlyMap)) {
        if (record.quantity <= 0) continue;

        // Build a stable doc ID: "shopify_<safeProductId>_YYYY-MM"
        const safeId = record.productId.replace(/[^a-zA-Z0-9_-]/g, "_");
        const yearMonth = key.split("||")[1];
        const docId = `shopify_${safeId}_${yearMonth}`;

        const ref = db
          .collection("users")
          .doc(uid)
          .collection("demandRecords")
          .doc(docId);

        batch.set(ref, {
          productId: record.productId,
          periodStart: record.periodStart,
          quantity: record.quantity,
          source: "shopify",
          updatedAt: new Date().toISOString(),
        });

        imported++;
      }

      if (imported > 0) {
        await batch.commit();
      }

      // Build top-20 list of unmatched SKUs/titles for diagnostics.
      const unmatched = Array.from(unmatchedSamples.values())
        .sort((a, b) => b.count - a.count)
        .slice(0, 20);

      console.log(
        `shopifyImportOrders: done. totalOrders=${totalOrders}, lineItems=${totalLineItems}, ` +
        `matched=${matchedLineItems}, unmatchedSkus=${unmatchedSamples.size}, monthlyBuckets=${imported}`
      );
      res.json({
        result: {
          totalOrders,
          totalLineItems,
          matchedLineItems,
          unmatchedLineItems: totalLineItems - matchedLineItems,
          newRecordsImported: imported,
          monthlyBuckets: imported,
          unmatchedSamples: unmatched,
        },
      });
    } catch (err) {
      console.error("shopifyImportOrders error:", err.message, err.stack);
      res.status(502).json({ error: err.message || "Shopify API error fetching orders." });
    }
  }
);

// ── Email Secrets ────────────────────────────────────────────────────────────
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

/** Create a nodemailer transporter using SMTP secrets. */
function createMailTransporter() {
  const nodemailer = require("nodemailer");
  const host = SMTP_HOST.value().trim();
  const port = parseInt(SMTP_PORT.value().trim()) || 587;
  const user = SMTP_USER.value().trim();
  const pass = SMTP_PASS.value().trim();
  return {
    transporter: nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user, pass },
    }),
    fromAddress: `"Ma5zony Orders" <${user}>`,
  };
}

// ── Send Order Emails to Suppliers ───────────────────────────────────────────

/**
 * Called when a purchase order status changes to "sent".
 * Looks up all supplier orders for this purchase order and sends
 * an email to each supplier with their order details and a portal link.
 *
 * POST /sendSupplierEmails
 * Body: { uid, purchaseOrderId, appUrl }
 *
 * SETUP:
 *   firebase functions:secrets:set SMTP_HOST   (e.g. smtp.gmail.com)
 *   firebase functions:secrets:set SMTP_PORT   (e.g. 587)
 *   firebase functions:secrets:set SMTP_USER   (e.g. your@gmail.com)
 *   firebase functions:secrets:set SMTP_PASS   (e.g. app password)
 */
exports.sendSupplierEmails = onRequest(
  {
    cors: true,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    const callerUid = await verifyAuth(req);
    const { uid, purchaseOrderId, appUrl } = req.body;
    if (!callerUid || callerUid !== uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    if (!uid || !purchaseOrderId) {
      res.status(400).json({ error: "uid and purchaseOrderId required" });
      return;
    }

    const siteUrl = appUrl || "https://ma5zony.web.app";

    try {
      // Fetch supplier orders for this purchase order
      const supplierSnap = await db
        .collection("supplierOrders")
        .where("purchaseOrderId", "==", purchaseOrderId)
        .where("ownerUid", "==", uid)
        .get();

      if (supplierSnap.empty) {
        res.status(404).json({ error: "No supplier orders found" });
        return;
      }

      // Set up email transport
      const { transporter, fromAddress } = createMailTransporter();

      const results = [];
      for (const doc of supplierSnap.docs) {
        const order = doc.data();
        const portalUrl = `${siteUrl}/#/supplier-portal?token=${order.accessToken}`;

        // Build items table HTML
        const itemsHtml = order.items
          .map(
            (item) => `
          <tr>
            <td style="padding:8px;border:1px solid #ddd">${item.productName}</td>
            <td style="padding:8px;border:1px solid #ddd">${item.sku}</td>
            <td style="padding:8px;border:1px solid #ddd;text-align:center">${item.quantity}</td>
            <td style="padding:8px;border:1px solid #ddd;text-align:right">$${(item.unitCost * item.quantity).toFixed(2)}</td>
          </tr>`
          )
          .join("");

        const totalCost = order.items
          .reduce((sum, i) => sum + i.unitCost * i.quantity, 0)
          .toFixed(2);

        const html = `
          <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
            <div style="background:#1a73e8;color:white;padding:20px;border-radius:8px 8px 0 0">
              <h2 style="margin:0">Ma5zony — New Purchase Order</h2>
            </div>
            <div style="padding:20px;border:1px solid #ddd;border-top:none;border-radius:0 0 8px 8px">
              <p>Hello <strong>${order.supplierName}</strong>,</p>
              <p>You have received a new purchase order. Please review the items below:</p>
              
              <table style="width:100%;border-collapse:collapse;margin:16px 0">
                <tr style="background:#f5f5f5">
                  <th style="padding:8px;border:1px solid #ddd;text-align:left">Product</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:left">SKU</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:center">Quantity</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:right">Est. Cost</th>
                </tr>
                ${itemsHtml}
                <tr style="background:#f5f5f5;font-weight:bold">
                  <td colspan="3" style="padding:8px;border:1px solid #ddd;text-align:right">Total:</td>
                  <td style="padding:8px;border:1px solid #ddd;text-align:right">$${totalCost}</td>
                </tr>
              </table>

              <p><strong>Next Steps:</strong></p>
              <ol>
                <li>Click the button below to open your supplier portal</li>
                <li>Enter your estimated delivery time</li>
                <li>Provide your final cost quote</li>
                <li>Add any notes or constraints</li>
              </ol>

              <div style="text-align:center;margin:24px 0">
                <a href="${portalUrl}" 
                   style="background:#1a73e8;color:white;padding:12px 32px;text-decoration:none;border-radius:6px;font-weight:bold;display:inline-block">
                  Open Supplier Portal
                </a>
              </div>

              <p style="color:#666;font-size:12px">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <a href="${portalUrl}">${portalUrl}</a>
              </p>
            </div>
          </div>`;

        try {
          await transporter.sendMail({
            from: fromAddress,
            to: order.supplierEmail,
            subject: `New Purchase Order — ${order.items.length} item(s)`,
            html: html,
          });
          results.push({
            supplier: order.supplierName,
            email: order.supplierEmail,
            status: "sent",
          });
        } catch (emailErr) {
          results.push({
            supplier: order.supplierName,
            email: order.supplierEmail,
            status: "failed",
            error: emailErr.message,
          });
        }
      }

      res.json({ results });
    } catch (err) {
      console.error("sendSupplierEmails error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

// ── Send Emails to Factories (Raw Material Orders) ──────────────────────────

/**
 * Called when raw material orders are created for a production order.
 * Sends an email to each factory/supplier with their material order details
 * and a portal link.
 *
 * POST /sendFactoryEmails
 * Body: { uid, productionOrderId, appUrl }
 */
exports.sendFactoryEmails = onRequest(
  {
    cors: true,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    const callerUid = await verifyAuth(req);
    const { uid, productionOrderId, appUrl } = req.body;
    if (!callerUid || callerUid !== uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    if (!uid || !productionOrderId) {
      res.status(400).json({ error: "uid and productionOrderId required" });
      return;
    }

    const siteUrl = appUrl || "https://ma5zony.web.app";

    try {
      // Fetch factory orders for this production order
      const orderSnap = await db
        .collection("factoryOrders")
        .where("productionOrderId", "==", productionOrderId)
        .where("ownerUid", "==", uid)
        .get();

      if (orderSnap.empty) {
        res.status(404).json({ error: "No factory orders found" });
        return;
      }

      const { transporter, fromAddress } = createMailTransporter();

      const results = [];
      for (const doc of orderSnap.docs) {
        const order = doc.data();
        const portalUrl = `${siteUrl}/#/factory-portal?token=${order.accessToken}`;

        // Support new grouped schema (order.materials array) and legacy single-material docs.
        const materials =
          Array.isArray(order.materials) && order.materials.length > 0
            ? order.materials
            : [
                {
                  materialName: order.materialName || "—",
                  quantity: order.quantity || 0,
                  unit: order.unit || "pcs",
                },
              ];

        const itemCount = materials.length;
        const materialRows = materials
          .map(
            (m) => `
            <tr>
              <td style="padding:8px;border:1px solid #ddd">${m.materialName || "—"}</td>
              <td style="padding:8px;border:1px solid #ddd;text-align:center">${m.quantity || 0}</td>
              <td style="padding:8px;border:1px solid #ddd">${m.unit || "pcs"}</td>
            </tr>`
          )
          .join("");

        const html = `
          <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
            <div style="background:#1a73e8;color:white;padding:20px;border-radius:8px 8px 0 0">
              <h2 style="margin:0">Ma5zony — Raw Material Order</h2>
            </div>
            <div style="padding:20px;border:1px solid #ddd;border-top:none;border-radius:0 0 8px 8px">
              <p>Hello <strong>${order.supplierName || "Supplier"}</strong>,</p>
              <p>You have received a new raw material order containing <strong>${itemCount} item${itemCount === 1 ? "" : "s"}</strong>:</p>

              <table style="width:100%;border-collapse:collapse;margin:16px 0">
                <tr style="background:#f5f5f5">
                  <th style="padding:8px;border:1px solid #ddd;text-align:left">Material</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:center">Quantity</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:left">Unit</th>
                </tr>
                ${materialRows}
              </table>

              <p><strong>Next Steps:</strong></p>
              <ol>
                <li>Click the button below to open your factory portal</li>
                <li>Accept the order</li>
                <li>Provide estimated delivery time</li>
                <li>Mark as completed when shipped</li>
              </ol>

              <div style="text-align:center;margin:24px 0">
                <a href="${portalUrl}"
                   style="background:#1a73e8;color:white;padding:12px 32px;text-decoration:none;border-radius:6px;font-weight:bold;display:inline-block">
                  Open Factory Portal
                </a>
              </div>

              <p style="color:#666;font-size:12px">
                If the button doesn't work, copy and paste this link:<br>
                <a href="${portalUrl}">${portalUrl}</a>
              </p>
            </div>
          </div>`;

        try {
          await transporter.sendMail({
            from: fromAddress,
            to: order.supplierEmail || order.factoryEmail,
            subject: `Raw Material Order — ${itemCount} item${itemCount === 1 ? "" : "s"} (${order.supplierName || "Supplier"})`,
            html: html,
          });
          results.push({
            supplier: order.supplierName,
            email: order.supplierEmail || order.factoryEmail,
            status: "sent",
          });
        } catch (emailErr) {
          results.push({
            supplier: order.supplierName,
            email: order.supplierEmail || order.factoryEmail,
            status: "failed",
            error: emailErr.message,
          });
        }
      }

      res.json({ results });
    } catch (err) {
      console.error("sendFactoryEmails error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

// ── Send Emails to Manufacturers (Production Orders) ─────────────────────────

/**
 * Called when a production order transitions to materials_ready.
 * Sends an email to the assigned manufacturer with production order details
 * and a portal link.
 *
 * POST /sendManufacturerEmails
 * Body: { uid, productionOrderId, appUrl }
 */
exports.sendManufacturerEmails = onRequest(
  {
    cors: true,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    const callerUid = await verifyAuth(req);
    const { uid, productionOrderId, appUrl } = req.body;
    if (!callerUid || callerUid !== uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    if (!uid || !productionOrderId) {
      res.status(400).json({ error: "uid and productionOrderId required" });
      return;
    }

    const siteUrl = appUrl || "https://ma5zony.web.app";

    try {
      // Fetch the manufacturer order for this production order
      const orderSnap = await db
        .collection("manufacturerOrders")
        .where("productionOrderId", "==", productionOrderId)
        .where("ownerUid", "==", uid)
        .limit(1)
        .get();

      if (orderSnap.empty) {
        res.status(404).json({ error: "No manufacturer order found" });
        return;
      }

      const { transporter, fromAddress } = createMailTransporter();

      const results = [];
      for (const doc of orderSnap.docs) {
        const order = doc.data();
        const portalUrl = `${siteUrl}/#/manufacturer-portal?token=${order.accessToken}`;

        // Build materials table if available, including supplier column.
        let materialsHtml = "";
        const incomingSuppliers =
          Array.isArray(order.incomingSuppliers) && order.incomingSuppliers.length > 0
            ? order.incomingSuppliers
            : null;

        if (order.rawMaterialOrders && order.rawMaterialOrders.length > 0) {
          const rows = order.rawMaterialOrders
            .map(
              (rm) => `
            <tr>
              <td style="padding:8px;border:1px solid #ddd">${rm.materialName || "—"}</td>
              <td style="padding:8px;border:1px solid #ddd;text-align:center">${rm.quantity || 0}</td>
              <td style="padding:8px;border:1px solid #ddd">${rm.unit || "pcs"}</td>
              <td style="padding:8px;border:1px solid #ddd">${rm.supplierName || "—"}</td>
            </tr>`
            )
            .join("");

          const supplierNote = incomingSuppliers
            ? `<p>Materials are being ordered from: <strong>${incomingSuppliers.join(", ")}</strong>. They will be delivered to you shortly.</p>`
            : "";

          materialsHtml = `
            ${supplierNote}
            <h3 style="margin:16px 0 8px">Materials Ordered</h3>
            <table style="width:100%;border-collapse:collapse;margin:0 0 16px">
              <tr style="background:#f5f5f5">
                <th style="padding:8px;border:1px solid #ddd;text-align:left">Material</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:center">Quantity</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:left">Unit</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:left">Supplier</th>
              </tr>
              ${rows}
            </table>`;
        }

        const html = `
          <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
            <div style="background:#1a73e8;color:white;padding:20px;border-radius:8px 8px 0 0">
              <h2 style="margin:0">Ma5zony — Production Order Approved</h2>
            </div>
            <div style="padding:20px;border:1px solid #ddd;border-top:none;border-radius:0 0 8px 8px">
              <p>Hello <strong>${order.manufacturerName || "Manufacturer"}</strong>,</p>
              <p>A production order has been approved and material sourcing is underway. Please expect the raw materials to arrive shortly.</p>

              <table style="width:100%;border-collapse:collapse;margin:16px 0">
                <tr style="background:#f5f5f5">
                  <th style="padding:8px;border:1px solid #ddd;text-align:left">Product</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:center">Quantity</th>
                  <th style="padding:8px;border:1px solid #ddd;text-align:right">Est. Cost</th>
                </tr>
                <tr>
                  <td style="padding:8px;border:1px solid #ddd">${order.productName || "—"}</td>
                  <td style="padding:8px;border:1px solid #ddd;text-align:center">${order.quantity || 0}</td>
                  <td style="padding:8px;border:1px solid #ddd;text-align:right">$${(order.estimatedCost || 0).toFixed(2)}</td>
                </tr>
              </table>

              ${materialsHtml}

              <p><strong>Next Steps:</strong></p>
              <ol>
                <li>Click the button below to open your manufacturer portal</li>
                <li>Start production once all materials have arrived</li>
                <li>Mark as completed when finished</li>
              </ol>

              <div style="text-align:center;margin:24px 0">
                <a href="${portalUrl}"
                   style="background:#1a73e8;color:white;padding:12px 32px;text-decoration:none;border-radius:6px;font-weight:bold;display:inline-block">
                  Open Manufacturer Portal
                </a>
              </div>

              <p style="color:#666;font-size:12px">
                If the button doesn't work, copy and paste this link:<br>
                <a href="${portalUrl}">${portalUrl}</a>
              </p>
            </div>
          </div>`;

        try {
          await transporter.sendMail({
            from: fromAddress,
            to: order.manufacturerEmail,
            subject: `Production Order Approved — ${order.productName || "Product"}`,
            html: html,
          });
          results.push({
            manufacturer: order.manufacturerName,
            email: order.manufacturerEmail,
            status: "sent",
          });
        } catch (emailErr) {
          results.push({
            manufacturer: order.manufacturerName,
            email: order.manufacturerEmail,
            status: "failed",
            error: emailErr.message,
          });
        }
      }

      res.json({ results });
    } catch (err) {
      console.error("sendManufacturerEmails error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

// ── Send Email to Supplier for Raw Material Purchase Order ───────────────────

/**
 * Called when a rawMaterialPurchaseOrder status changes to "sent".
 * Reads the multi-item PO from users/{uid}/rawMaterialPurchaseOrders/{id},
 * fetches the supplier email, and sends an HTML email with a line-items table.
 *
 * POST /sendRawMaterialSupplierEmail
 * Body: { uid, rawMaterialPurchaseOrderId, appUrl }
 */
exports.sendRawMaterialSupplierEmail = onRequest(
  {
    cors: true,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    const callerUid = await verifyAuth(req);
    const { uid, rawMaterialPurchaseOrderId, appUrl } = req.body;
    if (!callerUid || callerUid !== uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    if (!uid || !rawMaterialPurchaseOrderId) {
      res.status(400).json({ error: "uid and rawMaterialPurchaseOrderId required" });
      return;
    }

    const siteUrl = appUrl || "https://ma5zony.web.app";

    try {
      // Fetch the purchase order
      const poRef = db
        .collection("users")
        .doc(uid)
        .collection("rawMaterialPurchaseOrders")
        .doc(rawMaterialPurchaseOrderId);
      const poSnap = await poRef.get();

      if (!poSnap.exists) {
        res.status(404).json({ error: "Purchase order not found" });
        return;
      }

      const po = poSnap.data();

      // Fetch the supplier to get their email
      const supplierSnap = await db
        .collection("users")
        .doc(uid)
        .collection("suppliers")
        .doc(po.supplierId)
        .get();

      if (!supplierSnap.exists) {
        res.status(404).json({ error: "Supplier not found" });
        return;
      }

      const supplier = supplierSnap.data();
      const supplierEmail = supplier.contactEmail || supplier.email;
      if (!supplierEmail) {
        res.status(400).json({ error: "Supplier has no email address" });
        return;
      }

      const items = Array.isArray(po.items) ? po.items : [];
      const grandTotal = items.reduce(
        (sum, item) => sum + (item.unitCost || 0) * (item.quantityOrdered || 0),
        0
      );

      const itemsHtml = items
        .map(
          (item) => `
          <tr>
            <td style="padding:8px;border:1px solid #ddd">${item.rawMaterialName || "—"}</td>
            <td style="padding:8px;border:1px solid #ddd;text-align:center">${item.quantityOrdered || 0}</td>
            <td style="padding:8px;border:1px solid #ddd">${item.unitOfMeasure || "pcs"}</td>
            <td style="padding:8px;border:1px solid #ddd;text-align:right">EGP ${(item.unitCost || 0).toFixed(2)}</td>
            <td style="padding:8px;border:1px solid #ddd;text-align:right">EGP ${((item.unitCost || 0) * (item.quantityOrdered || 0)).toFixed(2)}</td>
          </tr>`
        )
        .join("");

      const html = `
        <div style="font-family:Arial,sans-serif;max-width:620px;margin:0 auto">
          <div style="background:#1a73e8;color:white;padding:20px;border-radius:8px 8px 0 0">
            <h2 style="margin:0">Ma5zony — Raw Material Purchase Order</h2>
          </div>
          <div style="padding:20px;border:1px solid #ddd;border-top:none;border-radius:0 0 8px 8px">
            <p>Hello <strong>${po.supplierName || supplier.name || "Supplier"}</strong>,</p>
            <p>You have received a new raw material purchase order. Please review the details below and confirm availability.</p>

            <table style="width:100%;border-collapse:collapse;margin:16px 0">
              <tr style="background:#f5f5f5">
                <th style="padding:8px;border:1px solid #ddd;text-align:left">Material</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:center">Qty</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:left">Unit</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:right">Unit Cost</th>
                <th style="padding:8px;border:1px solid #ddd;text-align:right">Total</th>
              </tr>
              ${itemsHtml}
              <tr style="background:#f5f5f5;font-weight:bold">
                <td colspan="4" style="padding:8px;border:1px solid #ddd;text-align:right">Grand Total:</td>
                <td style="padding:8px;border:1px solid #ddd;text-align:right">EGP ${grandTotal.toFixed(2)}</td>
              </tr>
            </table>

            <p><strong>Next Steps:</strong></p>
            <ol>
              <li>Review the materials and quantities listed above</li>
              <li>Confirm availability and estimated delivery date</li>
              <li>Reply to this email or contact us directly</li>
            </ol>

            <p style="color:#666;font-size:12px;margin-top:24px">
              This order was generated by Ma5zony — <a href="${siteUrl}">${siteUrl}</a>
            </p>
          </div>
        </div>`;

      const { transporter, fromAddress } = createMailTransporter();

      await transporter.sendMail({
        from: fromAddress,
        to: supplierEmail,
        subject: `Raw Material Order — ${items.length} item${items.length === 1 ? "" : "s"} (EGP ${grandTotal.toFixed(2)})`,
        html,
      });

      // Mark the PO status as "sent" if it was "draft"
      if (po.status === "draft") {
        await poRef.update({ status: "sent", sentAt: admin.firestore.FieldValue.serverTimestamp() });
      }

      res.json({
        result: {
          supplier: po.supplierName,
          email: supplierEmail,
          itemCount: items.length,
          grandTotal,
          status: "sent",
        },
      });
    } catch (err) {
      console.error("sendRawMaterialSupplierEmail error:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

// ══════════════════════════════════════════════════════════════════════════════
// Phase 5: Portal Response Notification Triggers
// ══════════════════════════════════════════════════════════════════════════════

/**
 * When a supplier responds via the portal (updates response fields),
 * create an in-app notification for the order owner.
 */
exports.onSupplierOrderUpdate = onDocumentUpdated(
  "supplierOrders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after.ownerUid) return;

    // Only notify if response changed
    const responseBefore = before.response || {};
    const responseAfter = after.response || {};
    if (
      responseBefore.deliveryDays === responseAfter.deliveryDays &&
      responseBefore.quotedCost === responseAfter.quotedCost &&
      responseBefore.notes === responseAfter.notes
    ) {
      return;
    }

    await db
      .collection("users")
      .doc(after.ownerUid)
      .collection("notifications")
      .add({
        type: "supplier_response",
        title: `Supplier ${after.supplierName || "Unknown"} responded`,
        message: `${after.supplierName} provided a quote of $${responseAfter.quotedCost || "—"} with ${responseAfter.deliveryDays || "—"} day delivery.`,
        entityType: "supplierOrder",
        entityId: event.params.orderId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  }
);

/**
 * When a factory order status changes (accepted, completed),
 * notify the order owner.
 */
exports.onFactoryOrderUpdate = onDocumentUpdated(
  "factoryOrders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after.ownerUid || before.status === after.status) return;

    const statusLabel = (after.status || "").replace(/_/g, " ");
    await db
      .collection("users")
      .doc(after.ownerUid)
      .collection("notifications")
      .add({
        type: "factory_status",
        title: `Factory order ${statusLabel}`,
        message: `${after.supplierName || "Factory"} marked material "${after.materialName || ""}" as ${statusLabel}.`,
        entityType: "factoryOrder",
        entityId: event.params.orderId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    // If factory completed → check if all materials for this PO are done
    if (after.status === "completed" && after.productionOrderId) {
      const allFactory = await db
        .collection("factoryOrders")
        .where("productionOrderId", "==", after.productionOrderId)
        .where("ownerUid", "==", after.ownerUid)
        .get();

      const allDone = allFactory.docs.every(
        (d) => d.data().status === "completed"
      );

      if (allDone) {
        // Auto-transition production order to materials_ready
        const poRef = db
          .collection("users")
          .doc(after.ownerUid)
          .collection("productionOrders")
          .doc(after.productionOrderId);
        const poSnap = await poRef.get();
        if (poSnap.exists && poSnap.data().status === "materials_ordered") {
          await poRef.update({ status: "materials_ready" });

          await db
            .collection("users")
            .doc(after.ownerUid)
            .collection("notifications")
            .add({
              type: "materials_ready",
              title: "All materials ready!",
              message: `All raw materials for production order are complete. Ready for manufacturing.`,
              entityType: "productionOrder",
              entityId: after.productionOrderId,
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
      }
    }
  }
);

/**
 * When a manufacturer order status changes,
 * notify the order owner. If completed → increase stock.
 */
exports.onManufacturerOrderUpdate = onDocumentUpdated(
  "manufacturerOrders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after.ownerUid || before.status === after.status) return;

    const statusLabel = (after.status || "").replace(/_/g, " ");
    await db
      .collection("users")
      .doc(after.ownerUid)
      .collection("notifications")
      .add({
        type: "manufacturer_status",
        title: `Production ${statusLabel}`,
        message: `${after.manufacturerName || "Manufacturer"} marked "${after.productName || ""}" as ${statusLabel}.`,
        entityType: "manufacturerOrder",
        entityId: event.params.orderId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    // If manufacturer completed production → update production order + increase stock
    if (after.status === "completed" && after.productionOrderId) {
      const poRef = db
        .collection("users")
        .doc(after.ownerUid)
        .collection("productionOrders")
        .doc(after.productionOrderId);
      const poSnap = await poRef.get();
      if (poSnap.exists) {
        await poRef.update({ status: "completed" });

        // Increase product stock
        const prodId = poSnap.data().finalProductId;
        const qty = poSnap.data().quantity || 0;
        if (prodId && qty > 0) {
          const prodRef = db
            .collection("users")
            .doc(after.ownerUid)
            .collection("products")
            .doc(prodId);
          const prodSnap = await prodRef.get();
          if (prodSnap.exists) {
            const currentStock = prodSnap.data().currentStock || 0;
            await prodRef.update({ currentStock: currentStock + qty });
          }
        }
      }
    }
  }
);

// ── Shopify Orders Webhook (auto-sync) ───────────────────────────────────────
//
// Receives `orders/create` events from Shopify and writes a demand record
// (monthly bucket) for each matching product into the owning user's
// Firestore. Eliminates the need to click "Sync Order History" after each
// sale.
//
// Deployment:
//   1. Set `SHOPIFY_WEBHOOK_BASE_URL` env var to the deployed URL prefix
//      (e.g. https://us-central1-ma5zony.cloudfunctions.net) OR leave unset
//      and the OAuth callback will skip registration with a console warning.
//   2. firebase deploy --only functions
//   3. Reconnect existing Shopify stores (or call shopifyRegisterWebhooks
//      once per user) so the webhook subscription gets created.

/** Build the resolveProductId function for a single user. */
async function buildProductResolver(uid) {
  const productsSnap = await db
    .collection("users").doc(uid).collection("products").get();

  const byVariantId = {};
  const bySku = {};
  const bySkuNorm = {};
  const byName = {};
  const byProductId = {};
  const normalise = (s) =>
    String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "");

  for (const doc of productsSnap.docs) {
    const d = doc.data();
    if (d.shopifyVariantId) byVariantId[String(d.shopifyVariantId)] = doc.id;
    if (d.sku) {
      const sku = String(d.sku);
      bySku[sku.toLowerCase()] = doc.id;
      const n = normalise(sku);
      if (n.length >= 3) bySkuNorm[n] = doc.id;
    }
    if (d.name) {
      const n = normalise(d.name);
      if (n.length >= 3) byName[n] = doc.id;
    }
    if (d.shopifyProductId) byProductId[String(d.shopifyProductId)] = doc.id;
  }

  return function resolve(line) {
    const { shopifyProductId, shopifyVariantId, variantSku, lineSku,
            productTitle, variantTitle, lineTitle } = line;
    if (shopifyVariantId && byVariantId[shopifyVariantId])
      return byVariantId[shopifyVariantId];
    const skuCandidates = [variantSku, lineSku].filter(Boolean);
    for (const s of skuCandidates) {
      const lc = String(s).toLowerCase();
      if (bySku[lc]) return bySku[lc];
    }
    for (const s of skuCandidates) {
      const n = normalise(s);
      if (n.length >= 3 && bySkuNorm[n]) return bySkuNorm[n];
    }
    const nameCandidates = [
      lineTitle,
      productTitle && variantTitle ? `${productTitle} ${variantTitle}` : null,
      productTitle,
    ].filter(Boolean);
    for (const t of nameCandidates) {
      const n = normalise(t);
      if (n.length >= 3 && byName[n]) return byName[n];
    }
    if (shopifyProductId && byProductId[shopifyProductId])
      return byProductId[shopifyProductId];
    return `shopify_${shopifyProductId || "unknown"}`;
  };
}

/** Register the orders/create webhook for the given user's Shopify store. */
async function registerOrdersWebhook(uid, shopDomain, accessToken) {
  const base = process.env.SHOPIFY_WEBHOOK_BASE_URL;
  if (!base) {
    console.warn(
      "registerOrdersWebhook: SHOPIFY_WEBHOOK_BASE_URL not set; " +
      "auto-sync via webhook is disabled. Set this env var and redeploy."
    );
    return;
  }
  const callbackUrl = `${base.replace(/\/$/, "")}/shopifyOrdersWebhook`;
  const mutation = `
    mutation webhookSubscriptionCreate(
      $topic: WebhookSubscriptionTopic!,
      $webhookSubscription: WebhookSubscriptionInput!
    ) {
      webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
        webhookSubscription { id }
        userErrors { field message }
      }
    }`;
  try {
    const data = await shopifyGraphQL(shopDomain, accessToken, mutation, {
      topic: "ORDERS_CREATE",
      webhookSubscription: { callbackUrl, format: "JSON" },
    });
    const errors = data.webhookSubscriptionCreate.userErrors;
    if (errors && errors.length > 0) {
      // "already exists" is acceptable
      const msg = errors[0].message || "";
      if (!/already/i.test(msg)) {
        console.warn(`registerOrdersWebhook: ${msg} for ${shopDomain}`);
      }
    } else {
      console.log(`registerOrdersWebhook: subscribed ${shopDomain} → ${callbackUrl}`);
    }
    await db.collection("users").doc(uid).collection("shopify")
      .doc("connection").set(
        { webhookCallbackUrl: callbackUrl, webhookRegisteredAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
  } catch (err) {
    console.error("registerOrdersWebhook failed:", err.message);
  }
}

/**
 * HTTPS webhook endpoint hit by Shopify for orders/create events.
 * Shopify signs the raw body with SHOPIFY_API_SECRET; we verify HMAC
 * before trusting any data.
 */
exports.shopifyOrdersWebhook = onRequest(
  { secrets: [SHOPIFY_API_SECRET] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("POST only"); return; }

    // Firebase Functions v2 exposes the raw body for HMAC verification.
    const rawBody = req.rawBody;
    const hmacHeader = req.get("X-Shopify-Hmac-Sha256");
    const shopDomain = req.get("X-Shopify-Shop-Domain");
    if (!rawBody || !hmacHeader || !shopDomain) {
      res.status(400).send("Missing required headers");
      return;
    }

    const computed = crypto
      .createHmac("sha256", SHOPIFY_API_SECRET.value())
      .update(rawBody)
      .digest("base64");
    if (
      computed.length !== hmacHeader.length ||
      !crypto.timingSafeEqual(Buffer.from(computed), Buffer.from(hmacHeader))
    ) {
      res.status(401).send("HMAC verification failed");
      return;
    }

    // Find the user that owns this shop. We use a collectionGroup query
    // because shopify connections are nested under each user.
    const connSnap = await db
      .collectionGroup("shopify")
      .where("shopDomain", "==", shopDomain)
      .where("isConnected", "==", true)
      .limit(1)
      .get();
    if (connSnap.empty) {
      // Acknowledge so Shopify doesn't retry forever, but log it.
      console.warn(`shopifyOrdersWebhook: no user for shop ${shopDomain}`);
      res.status(200).send("no-op");
      return;
    }
    const connDoc = connSnap.docs[0];
    // Path is users/{uid}/shopify/connection
    const uid = connDoc.ref.parent.parent.id;

    let order;
    try { order = JSON.parse(rawBody.toString("utf8")); }
    catch (e) { res.status(400).send("Invalid JSON"); return; }

    const lineItems = Array.isArray(order.line_items) ? order.line_items : [];
    if (lineItems.length === 0) { res.status(200).send("no-lines"); return; }

    const orderDate = order.created_at ? new Date(order.created_at) : new Date();
    const year = orderDate.getUTCFullYear();
    const month = String(orderDate.getUTCMonth() + 1).padStart(2, "0");
    const yearMonth = `${year}-${month}`;
    const periodStart = new Date(Date.UTC(year, orderDate.getUTCMonth(), 1)).toISOString();

    const resolve = await buildProductResolver(uid);

    // Aggregate quantities per product within this single order.
    const perProduct = {};
    for (const item of lineItems) {
      const line = {
        shopifyProductId: item.product_id ? String(item.product_id) : null,
        shopifyVariantId: item.variant_id ? String(item.variant_id) : null,
        variantSku: item.sku || null,
        lineSku: item.sku || null,
        productTitle: item.title || item.name || null,
        variantTitle: item.variant_title || null,
        lineTitle: item.name || item.title || null,
      };
      const pid = resolve(line);
      perProduct[pid] = (perProduct[pid] || 0) + (item.quantity || 0);
    }

    // Atomically increment the monthly demand bucket per product.
    const writes = [];
    for (const [productId, qty] of Object.entries(perProduct)) {
      if (qty <= 0) continue;
      const safeId = productId.replace(/[^a-zA-Z0-9_-]/g, "_");
      const docId = `shopify_${safeId}_${yearMonth}`;
      const ref = db.collection("users").doc(uid)
        .collection("demandRecords").doc(docId);
      writes.push(ref.set({
        productId,
        periodStart,
        quantity: admin.firestore.FieldValue.increment(qty),
        source: "shopify",
        updatedAt: new Date().toISOString(),
      }, { merge: true }));
    }
    await Promise.all(writes);
    res.status(200).send("ok");
  }
);

