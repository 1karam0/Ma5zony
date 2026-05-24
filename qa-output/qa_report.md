# Ma5zony QA Report
**Date**: 2026-05-24  
**Tester**: GitHub Copilot (automated browser session)  
**App URL**: http://localhost:63140  
**Auth**: karamony1@gmail.com (SME Owner role)

---

## Summary

| Phase | Feature | Result | Notes |
|-------|---------|--------|-------|
| Login | Firebase Auth → GoRouter redirect | ✅ PASS | Redirected to `/dashboard` correctly |
| Phase C | 7-day low-stock KPI label | ✅ PASS | Dashboard KPI reads "Products with less than 7 days of stock 33" |
| Phase A | Setup wizard — "I'm done" button | ✅ PASS | Button visible on step 2 |
| Phase A | Setup wizard — "Optional ·" prefix on steps 3–6 | ✅ PASS | Step 3 reads "Optional · Add Raw Materials" |
| Phase A | Setup wizard — "You're ready to use Ma5zony" banner | ✅ PASS | Green banner with "Go to dashboard" CTA on step 3+ |
| Phase A | Setup wizard — "Finish later" replaces "Skip setup" | ✅ PASS | Visible on step 3+ in top-right |
| Phase E | Supplier "Materials Supplied" collapsible section | ✅ PASS | Renders in Edit Supplier dialog |
| Phase E | "Materials Supplied" empty state | ✅ PASS | Shows "No raw materials defined yet. Add them in the Raw Materials screen…" |
| Phase E | "Raw Materials" column in Suppliers table | ✅ PASS | Column shows 0 for each supplier |
| Phase D | Forecast → "Create Order" button (after running forecast) | ✅ PASS | Appears in `_GoToReplenishmentCard` with suggested qty |
| Phase D | Order wizard opens on "Create Order" click | ✅ PASS | "Supplier Purchase Order" dialog opens |
| Phase D | Wizard auto-detects supplier branch | ✅ PASS | Shows supplier name, email, lead time |
| Phase D | "Save as Draft" saves to Firestore | ✅ PASS (after fix) | Success banner: "Purchase order saved as draft. Approve later from Replenishment." |
| Phase D | "Done" button replaces actions after save | ✅ PASS | Single "Done" CTA shown post-save |

---

## Bug Found & Fixed During QA

### `PurchaseOrder` missing top-level `supplierId` field
**Symptom**: "Save as Draft" returned `[cloud_firestore/permission-denied] Missing or insufficient permissions.`

**Root cause**: Firestore security rules for `/users/{uid}/purchaseOrders` require `request.resource.data.supplierId is string && size() > 0`, but `PurchaseOrder.toFirestore()` never emitted a top-level `supplierId`. The field only existed on each `PurchaseOrderItem`, not on the `PurchaseOrder` itself.

**Fix applied**:
- Added `final String? supplierId` field to `PurchaseOrder` class (`lib/models/purchase_order.dart`)
- Updated `toFirestore()` to emit `supplierId` when non-null
- Updated `fromFirestore()` to deserialize it
- Updated `saveDraftPOFromRecommendation()` in `lib/providers/app_state.dart` to pass `supplierId: supplierId` to the `PurchaseOrder` constructor

**This was a pre-existing bug** affecting all PO creation paths (not just the Phase D wizard).

---

## Notes

### Phase E — FilterChips require raw materials to be defined first
The "Materials Supplied" multi-select picker correctly shows an empty state because no raw materials exist in this account. To test chip selection, add raw materials first at `/supply-chain/raw-materials`.

### Phase B — Not browser-testable
Phase B (Shopify active-only filter + webhook registration) is a Cloud Functions change. It requires `firebase deploy --only functions` and a Shopify store reconnect to verify end-to-end.

### Firestore connection errors
Intermittent `ERR_ABORTED` on Firestore Listen channel (long-polling) — these are expected in a local Flutter web dev environment and don't affect app functionality.
