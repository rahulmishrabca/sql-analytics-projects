-- ============================================================
-- Month-on-Month Product Variant Comparison (Pivot Layout)
-- Platform : Trino (Hive)
-- Tables   : lead_history_snapshot_v3
--            team_postpaid_business.old_pp_accounts_data
-- Purpose  : Compare March vs April lead volumes and conversion
--            across product variants: Delite, Lite, Mini
-- Note     : Use DATE_FORMAT() not FORMAT() in Trino for timestamps
-- ============================================================

WITH leads AS (
    SELECT
        lead_id,
        user_id,
        DATE_FORMAT(created_at, '%Y-%m')          AS month_year,
        CASE
            WHEN product_code = 'PP_DELITE' THEN 'Delite'
            WHEN product_code = 'PP_LITE'   THEN 'Lite'
            WHEN product_code = 'PP_MINI'   THEN 'Mini'
            ELSE 'Other'
        END                                       AS product_variant,
        status
    FROM
        team_postpaid_business.lead_history_snapshot_v3
    WHERE
        dl_last_updated = '2026-04-30'
        AND DATE_FORMAT(created_at, '%Y-%m') IN ('2026-03', '2026-04')
),

accounts AS (
    SELECT
        user_id,
        account_id,
        DATE_FORMAT(activation_date, '%Y-%m')     AS activation_month
    FROM
        team_postpaid_business.old_pp_accounts_data
    WHERE
        dl_last_updated = '2026-04-30'
        AND DATE_FORMAT(activation_date, '%Y-%m') IN ('2026-03', '2026-04')
),

joined AS (
    SELECT
        l.month_year,
        l.product_variant,
        l.lead_id,
        l.user_id,
        CASE WHEN a.account_id IS NOT NULL THEN 1 ELSE 0 END  AS is_converted
    FROM
        leads l
    LEFT JOIN
        accounts a
        ON  l.user_id        = a.user_id
        AND l.month_year     = a.activation_month
),

summary AS (
    SELECT
        product_variant,
        month_year,
        COUNT(DISTINCT lead_id)                   AS total_leads,
        SUM(is_converted)                         AS converted_leads,
        ROUND(
            100.0 * SUM(is_converted) / NULLIF(COUNT(DISTINCT lead_id), 0),
            2
        )                                         AS conversion_pct
    FROM
        joined
    GROUP BY
        product_variant,
        month_year
)

-- Pivot: one row per product variant, columns for March vs April
SELECT
    product_variant,

    MAX(CASE WHEN month_year = '2026-03' THEN total_leads      END) AS mar_total_leads,
    MAX(CASE WHEN month_year = '2026-04' THEN total_leads      END) AS apr_total_leads,

    MAX(CASE WHEN month_year = '2026-03' THEN converted_leads  END) AS mar_conversions,
    MAX(CASE WHEN month_year = '2026-04' THEN converted_leads  END) AS apr_conversions,

    MAX(CASE WHEN month_year = '2026-03' THEN conversion_pct   END) AS mar_conversion_pct,
    MAX(CASE WHEN month_year = '2026-04' THEN conversion_pct   END) AS apr_conversion_pct,

    -- MoM change in leads
    MAX(CASE WHEN month_year = '2026-04' THEN total_leads END)
    - MAX(CASE WHEN month_year = '2026-03' THEN total_leads END)     AS mom_lead_delta,

    ROUND(
        100.0 * (
            MAX(CASE WHEN month_year = '2026-04' THEN total_leads END)
            - MAX(CASE WHEN month_year = '2026-03' THEN total_leads END)
        ) / NULLIF(MAX(CASE WHEN month_year = '2026-03' THEN total_leads END), 0),
        2
    )                                                                AS mom_lead_growth_pct

FROM
    summary
GROUP BY
    product_variant
ORDER BY
    product_variant
;
