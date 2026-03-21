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
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const https = require("https");

admin.initializeApp();
const db = admin.firestore();

const SHOPIFY_API_KEY = defineSecret("SHOPIFY_API_KEY");
const SHOPIFY_API_SECRET = defineSecret("SHOPIFY_API_SECRET");

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Promisified HTTPS request helper (no external deps). */
function httpsRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on("data", (d) => chunks.push(d));
      res.on("end", () => {
        const body = Buffer.concat(chunks).toString();
        resolve({ statusCode: res.statusCode, body });
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

/** Set CORS headers and handle preflight. Returns true if preflight handled. */
function handleCors(req, res) {
  res.set("Access-Control-Allow-Origin", "*");
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
    await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("pending_oauth")
      .set({ nonce, shopDomain, createdAt: admin.firestore.FieldValue.serverTimestamp() });

    const redirectUri = `https://shopifyoauthcallback-rjv64oud6a-uc.a.run.app`;

    const scopes = "read_products,read_inventory";
    const authUrl =
      `https://${shopDomain}/admin/oauth/authorize` +
      `?client_id=${SHOPIFY_API_KEY.value()}` +
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
      .createHmac("sha256", SHOPIFY_API_SECRET.value())
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

    // --- exchange code for permanent access token ---
    const postData = JSON.stringify({
      client_id: SHOPIFY_API_KEY.value(),
      client_secret: SHOPIFY_API_SECRET.value(),
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

    res.send(
      "<html><body><h2>Store connected!</h2><p>You can close this window and return to Ma5zony.</p></body></html>"
    );
  }
);

// ── 3. shopifyImportProducts ─────────────────────────────────────────────────

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

    const prodRes = await httpsRequest({
      hostname: shopDomain,
      path: "/admin/api/2024-01/products.json?limit=250",
      method: "GET",
      headers: { "X-Shopify-Access-Token": accessToken },
    });

    if (prodRes.statusCode !== 200) {
      res.status(502).json({ error: "Shopify API error fetching products." });
      return;
    }

    const { products } = JSON.parse(prodRes.body);
    const imported = [];

    const batch = db.batch();
    for (const sp of products) {
      const variant = sp.variants?.[0] || {};
      const docData = {
        sku: variant.sku || `SHOP-${sp.id}`,
        name: sp.title,
        category: sp.product_type || "Uncategorised",
        unitCost: parseFloat(variant.price) || 0,
        currentStock: variant.inventory_quantity ?? 0,
        supplierId: null,
        isActive: sp.status === "active",
        shopifyProductId: String(sp.id),
      };

      const ref = db
        .collection("users")
        .doc(uid)
        .collection("products")
        .doc(`shopify_${sp.id}`);
      batch.set(ref, docData, { merge: true });
      imported.push({ id: ref.id, ...docData });
    }
    await batch.commit();

    res.json({ result: { count: imported.length, products: imported } });
  }
);

// ── 4. shopifySyncInventory ──────────────────────────────────────────────────

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

    const prodRes = await httpsRequest({
      hostname: shopDomain,
      path: "/admin/api/2024-01/products.json?limit=250&fields=id,variants",
      method: "GET",
      headers: { "X-Shopify-Access-Token": accessToken },
    });

    if (prodRes.statusCode !== 200) {
      res.status(502).json({ error: "Shopify API error." });
      return;
    }

    const { products } = JSON.parse(prodRes.body);
    const batch = db.batch();
    let synced = 0;

    for (const sp of products) {
      const variant = sp.variants?.[0];
      if (!variant) continue;

      const ref = db
        .collection("users")
        .doc(uid)
        .collection("products")
        .doc(`shopify_${sp.id}`);
      batch.update(ref, {
        currentStock: variant.inventory_quantity ?? 0,
      });
      synced++;
    }
    await batch.commit();

    await db
      .collection("users")
      .doc(uid)
      .collection("shopify")
      .doc("connection")
      .update({ lastSyncAt: admin.firestore.FieldValue.serverTimestamp() });

    res.json({ result: { synced } });
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
