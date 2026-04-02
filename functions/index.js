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
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
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

    const scopes = "read_products,read_inventory,read_orders";
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

// ── 6. shopifyImportOrders ───────────────────────────────────────────────────
// Fetches order history from Shopify and writes demand records to Firestore.

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

    // Paginate through all orders
    let allOrders = [];
    let nextPageUrl = `/admin/api/2024-01/orders.json?limit=250&status=any`;

    while (nextPageUrl) {
      const orderRes = await httpsRequest({
        hostname: shopDomain,
        path: nextPageUrl,
        method: "GET",
        headers: { "X-Shopify-Access-Token": accessToken },
      });

      if (orderRes.statusCode !== 200) {
        res.status(502).json({ error: "Shopify API error fetching orders." });
        return;
      }

      const parsed = JSON.parse(orderRes.body);
      allOrders = allOrders.concat(parsed.orders || []);

      // Check for pagination via Link header (simplified: look for "next" in body)
      // Shopify REST pagination: if fewer than limit returned, we're done.
      if (!parsed.orders || parsed.orders.length < 250) {
        nextPageUrl = null;
      } else {
        // For simplicity, stop after first page (250 orders).
        // Full cursor-based pagination can be added later.
        nextPageUrl = null;
      }
    }

    // Deduplicate: check which Shopify order IDs already exist
    const existingSnap = await db
      .collection("users")
      .doc(uid)
      .collection("demandRecords")
      .where("source", "==", "shopify")
      .get();

    const existingOrderIds = new Set(
      existingSnap.docs
        .map((d) => d.data().shopifyOrderId)
        .filter(Boolean)
    );

    // Map line items to demand records
    const batch = db.batch();
    let imported = 0;

    for (const order of allOrders) {
      const orderId = String(order.id);
      if (existingOrderIds.has(orderId)) continue;

      const orderDate = order.created_at
        ? new Date(order.created_at).toISOString()
        : new Date().toISOString();

      for (const item of order.line_items || []) {
        const shopifyProductId = String(item.product_id || "");
        if (!shopifyProductId || shopifyProductId === "null") continue;

        // Look up internal product by shopifyProductId
        const productRef = db
          .collection("users")
          .doc(uid)
          .collection("products")
          .doc(`shopify_${shopifyProductId}`);

        const ref = db
          .collection("users")
          .doc(uid)
          .collection("demandRecords")
          .doc(); // auto-ID

        batch.set(ref, {
          productId: `shopify_${shopifyProductId}`,
          periodStart: orderDate,
          quantity: item.quantity || 0,
          source: "shopify",
          shopifyOrderId: orderId,
        });

        imported++;
      }
    }

    if (imported > 0) {
      await batch.commit();
    }

    res.json({
      result: {
        totalOrders: allOrders.length,
        newRecordsImported: imported,
        skippedDuplicates: allOrders.length > 0
          ? existingOrderIds.size
          : 0,
      },
    });
  }
);

// ── Email Secrets ────────────────────────────────────────────────────────────
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

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

    const { uid, purchaseOrderId, appUrl } = req.body;
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
      const nodemailer = require("nodemailer");
      const transporter = nodemailer.createTransport({
        host: SMTP_HOST.value(),
        port: parseInt(SMTP_PORT.value()) || 587,
        secure: parseInt(SMTP_PORT.value()) === 465,
        auth: {
          user: SMTP_USER.value(),
          pass: SMTP_PASS.value(),
        },
      });

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
            from: `"Ma5zony Orders" <${SMTP_USER.value()}>`,
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
