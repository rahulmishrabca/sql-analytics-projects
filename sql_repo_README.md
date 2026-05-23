# SQL Analytics Projects

Trino & HiveQL queries built for real-world **BNPL / Postpaid lending** analytics.  
All queries are anonymized and use representative table/column structures.

---

## 📁 Queries

### 1. `01_lead_funnel_dropoff.sql`
**Lead Funnel Stage-wise Drop-off Analysis**

Tracks how many leads progress through each stage of the postpaid funnel and calculates the percentage drop-off between stages — month-wise and product-variant-wise.

Key techniques: CTEs, `COUNT DISTINCT`, `LAG()` window function, `NULLIF` for safe division

---

### 2. `02_mom_product_variant_comparison.sql`
**Month-on-Month Product Variant Comparison (Pivot)**

Compares March vs April lead volumes and conversion rates across product variants (Delite, Lite, Mini) using a pivot layout with conditional aggregation.

Key techniques: LEFT JOIN across two tables, CASE-based product mapping, conditional `MAX(CASE WHEN ...)` pivot, MoM delta and growth % calculation

---

### 3. `03_rejection_rate_anomaly.sql`
**Rejection Rate Anomaly Detection**

Detects unusual spikes in daily rejection rates by comparing each day's rate against a 7-day rolling average. Flags days that exceed 1.5x or 2x the rolling baseline.

Key techniques: Rolling window with `ROWS BETWEEN`, anomaly flagging with CASE, timestamp filtering in Trino

---

## 🛠️ Platform & Environment

- **Query Engine:** Trino (on AWS EMR)
- **Storage:** Hive Metastore (partitioned tables)
- **Partition Filter:** `dl_last_updated` — always applied to avoid full scans
- **Timestamp Formatting:** `DATE_FORMAT()` used throughout (Trino-compatible; not `FORMAT()`)

---

## 💡 Business Context

These queries support:
- **Funnel optimization** — identifying stages where leads get stuck
- **Finance reporting** — month-wise product performance for stakeholder review
- **Anomaly alerting** — catching rejection spikes before they affect SLAs

---

## 📌 Notes

- All table and column names are anonymized
- Data represents a postpaid credit product with multiple variants (Delite / Lite / Mini)
- Queries are production-style with partition filters, safe division, and window functions
