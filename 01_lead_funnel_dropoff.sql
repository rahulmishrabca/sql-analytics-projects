-- ============================================================
-- Lead Funnel Stage-wise Drop-off Analysis
-- Platform : Trino (Hive)
-- Table    : team_postpaid_business.lead_history_snapshot_v3
-- Purpose  : Track how many leads progress through each stage
--            of the BNPL postpaid funnel and where drop-offs occur
-- ============================================================

WITH funnel_base AS (
    SELECT
        lead_id,
        product_variant,                          -- Delite / Lite / Mini
        current_stage,
        previous_stage,
        DATE_FORMAT(created_at, '%Y-%m')          AS month_year,
        DATE_FORMAT(updated_at, '%Y-%m-%d')       AS last_updated_date,
        status                                    -- active / dropped / converted
    FROM
        team_postpaid_business.lead_history_snapshot_v3
    WHERE
        dl_last_updated = '2026-04-30'            -- partition filter (always required)
        AND DATE_FORMAT(created_at, '%Y-%m') IN ('2026-03', '2026-04')
),

stage_counts AS (
    SELECT
        month_year,
        product_variant,
        current_stage,
        COUNT(DISTINCT lead_id)                   AS leads_at_stage
    FROM
        funnel_base
    GROUP BY
        month_year,
        product_variant,
        current_stage
),

stage_with_next AS (
    SELECT
        month_year,
        product_variant,
        current_stage,
        leads_at_stage,
        LAG(leads_at_stage) OVER (
            PARTITION BY month_year, product_variant
            ORDER BY current_stage
        )                                         AS leads_prev_stage
    FROM
        stage_counts
)

SELECT
    month_year,
    product_variant,
    current_stage,
    leads_at_stage,
    leads_prev_stage,
    ROUND(
        100.0 * (leads_prev_stage - leads_at_stage) / NULLIF(leads_prev_stage, 0),
        2
    )                                             AS drop_off_pct
FROM
    stage_with_next
ORDER BY
    month_year,
    product_variant,
    current_stage
;
