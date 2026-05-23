-- ============================================================
-- Rejection Rate Anomaly Detection
-- Platform : Trino (Hive)
-- Table    : team_postpaid_business.lead_history_snapshot_v3
-- Purpose  : Detect unusual spikes in rejection rates by day
--            and product variant — flags days where rejection
--            rate exceeds 2x the 7-day rolling average
-- ============================================================

WITH daily_stats AS (
    SELECT
        DATE_FORMAT(created_at, '%Y-%m-%d')       AS lead_date,
        CASE
            WHEN product_code = 'PP_DELITE' THEN 'Delite'
            WHEN product_code = 'PP_LITE'   THEN 'Lite'
            WHEN product_code = 'PP_MINI'   THEN 'Mini'
            ELSE 'Other'
        END                                       AS product_variant,
        COUNT(DISTINCT lead_id)                   AS total_leads,
        COUNT(DISTINCT CASE
            WHEN status = 'REJECTED' THEN lead_id
        END)                                      AS rejected_leads
    FROM
        team_postpaid_business.lead_history_snapshot_v3
    WHERE
        dl_last_updated     = '2026-04-30'
        AND created_at     >= TIMESTAMP '2026-03-01 00:00:00'
        AND created_at      < TIMESTAMP '2026-05-01 00:00:00'
    GROUP BY
        DATE_FORMAT(created_at, '%Y-%m-%d'),
        product_code
),

with_rejection_rate AS (
    SELECT
        lead_date,
        product_variant,
        total_leads,
        rejected_leads,
        ROUND(
            100.0 * rejected_leads / NULLIF(total_leads, 0),
            2
        )                                         AS rejection_pct
    FROM
        daily_stats
),

with_rolling_avg AS (
    SELECT
        lead_date,
        product_variant,
        total_leads,
        rejected_leads,
        rejection_pct,
        ROUND(
            AVG(rejection_pct) OVER (
                PARTITION BY product_variant
                ORDER BY lead_date
                ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING   -- 7-day rolling avg (excludes today)
            ),
            2
        )                                         AS rolling_7d_avg_rejection_pct
    FROM
        with_rejection_rate
)

SELECT
    lead_date,
    product_variant,
    total_leads,
    rejected_leads,
    rejection_pct,
    rolling_7d_avg_rejection_pct,

    --Flag anomaly: today's rate > 2x rolling average
    CASE
        WHEN rolling_7d_avg_rejection_pct IS NULL         THEN 'Insufficient history'
        WHEN rejection_pct > 2 * rolling_7d_avg_rejection_pct THEN '🚨 ANOMALY'
        WHEN rejection_pct > 1.5 * rolling_7d_avg_rejection_pct THEN '⚠️  WARNING'
        ELSE 'Normal'
    END                                           AS anomaly_flag

FROM
    with_rolling_avg
ORDER BY
    lead_date DESC,
    product_variant
;
