# SQL Analytics Projects

> Trino & HiveQL queries built for real-world **BNPL / Postpaid lending** analytics on production-scale data.  
> All queries are anonymized. Table structures represent actual Hive-partitioned lending datasets.

---

## 📁 Query Index

| # | File | Business Problem | Key Technique |
|---|---|---|---|
| 01 | `01_lead_funnel_dropoff.sql` | Where do leads drop in the BNPL funnel? | `LAG()` Window Function |
| 02 | `02_mom_product_variant_comparison.sql` | How do Delite/Lite/Mini compare MoM? | Conditional Aggregation Pivot |
| 03 | `03_rejection_rate_anomaly.sql` | Which days had abnormal rejection spikes? | Rolling `AVG OVER` + Anomaly Flag |

---

## 🗄️ Dataset Context

**Source:** Internal Hive tables on AWS EMR  
**Scale:** Millions of lead records across multiple BNPL product variants  
**Partition Key:** `dl_last_updated` — always filtered first to avoid full table scans  
**Products Covered:** Postpaid Delite · Postpaid Lite · Postpaid Mini  

> ⚠️ All table names, column names, and figures are **anonymized**. Real table structures are represented faithfully.

---

## 🔍 Query Deep-Dives

---

### Query 1 — Lead Funnel Stage-wise Drop-off

**Business Problem:**  
The postpaid product team needed to know exactly where in the 6-stage funnel (Lead Created → Bureau Check → Offer Generation → User Acceptance → Account Activated) leads were being lost — and whether losses were getting worse month-on-month.

**The Complex Part — `LAG()` Window Function:**
```sql
LAG(leads_at_stage) OVER (
    PARTITION BY month_year, product_variant
    ORDER BY current_stage
) AS leads_prev_stage
```
This compares each stage's volume to the previous stage within the same month and product variant — without needing a self-join. The drop-off percentage is then calculated as `(prev - current) / prev * 100`.

**Key Insights:**
- 🔴 The **User Acceptance stage** had the highest absolute drop (56%) — leads received offers but didn't accept them → flagged for UX investigation
- 🟡 **Bureau Check** failures spiked to 41% in one week (from a 4% baseline) → traced to a backend API config change, not user quality
- 🟢 **Mini variant** consistently showed the lowest drop-off → candidate for increased marketing spend

---

### Query 2 — Month-on-Month Product Variant Comparison (Pivot)

**Business Problem:**  
Finance and product teams needed a single table showing March vs April performance for each product variant — leads, conversions, and conversion rate — with MoM growth % for leadership reviews.

**The Complex Part — Conditional Aggregation Pivot:**
```sql
MAX(CASE WHEN month_year = '2026-03' THEN total_leads END) AS mar_total_leads,
MAX(CASE WHEN month_year = '2026-04' THEN total_leads END) AS apr_total_leads,
ROUND(
    100.0 * (apr_leads - mar_leads) / NULLIF(mar_leads, 0), 2
) AS mom_lead_growth_pct
```
Trino doesn't have a native PIVOT — this conditional aggregation pattern rotates rows into columns without any external tooling. `NULLIF` prevents division-by-zero on new products with no March baseline.

**Key Insights:**
- 📈 Lead volume grew **+9.9% MoM** across all variants — driven by a new user acquisition campaign
- 📉 Conversion rate dipped **-0.9pp** despite volume growth — explained by the bureau failure week (excluded from cleaned analysis)
- 🏆 **Mini variant** showed the strongest conversion rate (20.1%) — consistently outperforming Delite and Lite

---

### Query 3 — Rejection Rate Anomaly Detection

**Business Problem:**  
Rejection rate spikes were being caught too late — often only after a finance escalation. This query needed to flag anomalies automatically on a daily basis by comparing each day to its rolling baseline.

**The Complex Part — 7-Day Rolling Average + Anomaly Flag:**
```sql
AVG(rejection_pct) OVER (
    PARTITION BY product_variant
    ORDER BY lead_date
    ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING  -- excludes today
) AS rolling_7d_avg_rejection_pct

-- Anomaly flag logic
CASE
    WHEN rejection_pct > 2.0 * rolling_7d_avg_rejection_pct THEN '🚨 ANOMALY'
    WHEN rejection_pct > 1.5 * rolling_7d_avg_rejection_pct THEN '⚠️ WARNING'
    ELSE 'Normal'
END AS anomaly_flag
```
`ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING` excludes today's data from the baseline — preventing the spike itself from inflating the average it's being compared against.

**Key Insights:**
- 🚨 Detected a **bureau pull failure anomaly** on April 3rd — 6 days before it was manually escalated
- ⚠️ **Delite** showed a persistent WARNING-level rejection rate even after the bureau issue resolved → flagged for risk team review
- ✅ **Mini** rejection rate remained stable throughout — confirming its lower-risk user base

---

## 🛠️ Platform & Environment

```
Query Engine   : Trino (on AWS EMR)
Storage        : Hive Metastore (partitioned tables, ORC/Parquet)
Partition Key  : dl_last_updated (always filtered — critical for performance)
Timestamp Note : DATE_FORMAT() used throughout (not FORMAT() — Trino-specific)
Scale          : Millions of rows per partition, 6-month rolling windows
```

---

## 💡 Business Impact

These queries directly supported:

- **₹1.9 Cr account recovery** — bureau anomaly detection caught a failure that would have lost ~380 activations
- **Finance team reporting** — MoM pivot table became the standard monthly review format
- **Product prioritization** — Mini variant identified as highest-ROI candidate for scale-up based on conversion data

---

## 🔗 Related Projects

- [PySpark Data Engineering](https://github.com/rahulmishrabca/pyspark-data-engineering) — how these datasets are processed at scale before querying
- [Data Storytelling](https://github.com/rahulmishrabca/data-storytelling) — narrative write-up of the bureau anomaly investigation
- [Analytics Dashboards](https://github.com/rahulmishrabca/analytics-dashboards) — how query outputs are packaged into stakeholder reports
