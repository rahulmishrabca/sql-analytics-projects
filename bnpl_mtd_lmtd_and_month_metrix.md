--MTD - Month till date vs LMTD - Last month till date comparision query
WITH
  account_regs AS (
    SELECT 
        loan_account_number,
        account_limit
    FROM workflow_nexus_po.account_registry_snapshot_v3
    WHERE dl_last_updated >=date'2025-07-01' --date_trunc('month', current_date - interval '1' month)
),

  
  account_data AS 
  
  (select aa.*,bb.account_limit as loan_amount from (
    SELECT
      *
    FROM
      (
        SELECT
          loan_account_number,
          product_id,
          lender_id,
          lead_id,
          loan_account_status,
          loan_account_sub_status,
          activation_date,
          base_id,
          convenience_fee,
          processing_fee,
          lender_mid,
          loan_amount as loan_amount2,
          customer_id,
          current_date + interval '-1' day AS yday,
          ROW_NUMBER() OVER (
            PARTITION BY
              customer_id
            ORDER BY
              activation_date DESC
          ) rn
        FROM
          hive.lms_postpaid.loan_account_snapshot_v3
        WHERE
          date(dl_last_updated) >= date '2025-07-01'
      )
    WHERE
      rn = 1
  )aa left join account_regs bb on aa.loan_account_number=bb.loan_account_number),
  
  txns AS (
    SELECT
      aa.*,
      -- bb.status,
      -- cc.loan_amount,
      -- cc.convenience_fee,
      current_date + interval '-1' day AS yday
    FROM
      team_postpaid_business.clou_txns_data_olap aa
      
    WHERE
      aa.status = 'SUCCESS'
  ),
  /* ------------------------------------------------------- EXISTING TIME PERIOD WINDOWS ------------------------------------------------------- */ 
  
  
  bounds_static AS (
    SELECT
      *
    FROM
      (
        VALUES
          (
            'A. FTD',
            current_date + interval '-1' day,
            current_date + interval '-1' day
          ),
          (
            'B. LMSD',
            (current_date + interval '-1' day) + interval '-1' month,
            (current_date + interval '-1' day) + interval '-1' month
          ),
          (
            'C. MTD',
            date_trunc('month', current_date - interval '1' day),
            current_date + interval '-1' day
          ),
          (
            'D. LMTD',
            date_trunc('month', current_date + interval '-1' month),
            (
              (current_date + interval '-1' MONTH) + interval '-1' DAY
            )
          ),
          (
            'E. LTD',
            date '2025-07-01',
            current_date + interval '-1' day
          )
      ) AS t (flag, start_dt, end_dt)
  ),
  /* ------------------------------------------------------- 🔥 NEW: MONTH ON MONTH WINDOWS Generates: 'M. 2025-07', 'M. 2025-08', ..., 'M. current' ------------------------------------------------------- */ month_bounds AS (
    SELECT
      'M. ' || date_format(month_start, '%Y-%m') AS flag,
      month_start AS start_dt,
      date_add('day', -1, date_add('month', 1, month_start)) AS end_dt
    FROM
      UNNEST (
        SEQUENCE(
          DATE '2025-07-01',
          date_trunc('month', current_date),
          INTERVAL '1' MONTH
        )
      ) AS t (month_start)
  ),
  /* Combine both static and MoM windows */ bounds AS (
    SELECT
      *
    FROM
      bounds_static
    UNION ALL
    SELECT
      *
    FROM
      month_bounds
  ),
  /* ------------------------------------------------------- NORMAL METRIC AGGREGATION (unchanged) ------------------------------------------------------- */ 
  
  txn_base AS (
    SELECT
      b.flag AS time_flag,
      NULL AS signup,
      SUM(CAST(amount AS DOUBLE)) AS gmv,
      NULL AS AIF,
      COUNT(DISTINCT cust_id) AS txning_users,
      SUM(CAST(amount AS DOUBLE)) / COUNT(DISTINCT cust_id) AS spac,
      NULL AS limit_sanctioned,
      NULL AS avg_cl,
      NULL AS avg_cf_onboarded,
      AVG(CAST(convenience_fee AS DOUBLE)) AS avg_cf_txning_user,
      count(distinct txn_id) as no_of_txns
    FROM
      txns t
      LEFT JOIN bounds b ON date(t.created_on_date) BETWEEN date(b.start_dt) AND date(b.end_dt)
    WHERE
      date(t.created_on_date) >= date '2025-07-01'
    GROUP BY
      1
  ),
  
    acct_base AS (
    -- cross-join bounds so we can evaluate AIF windows independently of signup window
    SELECT
        b.flag AS time_flag,

        -- signup: unchanged semantics (only count customers activated inside the flag window)
        COUNT(DISTINCT CASE WHEN date(a.activation_date) BETWEEN date(b.start_dt) AND date(b.end_dt)
                            THEN customer_id END) AS signup,

        NULL AS gmv,

        /* FIXED AIF: count distinct customer_id ONLY if loan_account_status = 1
           and activation_date falls into the AIF window required for this flag.
           - For FTD, MTD, LTD: activation_date between 2025-07-01 and yesterday
           - For LMTD, LMSD: activation_date between 2025-07-01 and end_of_last_month
        */
        COUNT(DISTINCT CASE
    WHEN loan_account_status = 1
     AND (
          /* FTD / MTD / LTD */
          (b.flag IN ('A. FTD','C. MTD','E. LTD')
           AND date(a.activation_date)
               BETWEEN date '2025-07-01'
                   AND (current_date - INTERVAL '1' DAY)
          )

          OR

          /* LMTD / LMSD */
          (b.flag IN ('D. LMTD','B. LMSD')
           AND date(a.activation_date)
               BETWEEN date '2025-07-01'
                   AND (date_trunc('day', current_date - interval '1' day) - INTERVAL '1' month)
          )

          OR

          /* ✅ MONTH-ON-MONTH */
          (b.flag LIKE 'M. %'
           AND date(a.activation_date)
               BETWEEN date(b.start_dt) AND date(b.end_dt)
          )
     )
    THEN customer_id
END) AS AIF,

        NULL AS txning_users,
        NULL AS spac,

        -- remaining metrics unchanged
        --SUM(CASE WHEN loan_account_status = 1 THEN CAST(loan_amount AS DOUBLE) END) AS limit_sanctioned,
        --AVG(CAST(loan_amount AS DOUBLE)) AS avg_cl,
        --AVG(CAST(convenience_fee AS DOUBLE)) AS avg_cf_onboarded,
		
		SUM(
    CASE
        WHEN loan_account_status = 1
         AND date(a.activation_date) BETWEEN date(b.start_dt) AND date(b.end_dt)
        THEN CAST(loan_amount AS DOUBLE)
    END
) AS limit_sanctioned,

AVG(
    CASE
        WHEN date(a.activation_date) BETWEEN date(b.start_dt) AND date(b.end_dt)
        THEN CAST(loan_amount AS DOUBLE)
    END
) AS avg_cl,

AVG(
    CASE
        WHEN date(a.activation_date) BETWEEN date(b.start_dt) AND date(b.end_dt)
        THEN CAST(convenience_fee AS DOUBLE)
    END
) AS avg_cf_onboarded,

        NULL AS avg_cf_txning_user,
        NULL AS no_of_txns

    FROM account_data a
    CROSS JOIN bounds b
    WHERE date(a.activation_date) >= date '2025-07-01'  -- preserve your lower bound
    GROUP BY 1
),
  


  
  base AS (
    SELECT
      *
    FROM
      txn_base
    UNION ALL
    SELECT
      *
    FROM
      acct_base
  )
SELECT
  time_flag,
  MAX(signup) AS signup,
  MAX(gmv) AS gmv,
  MAX(AIF) AS AIF,
  MAX(txning_users) AS txning_users,
  MAX(spac) AS spac,
  MAX(limit_sanctioned) AS limit_sanctioned,
  MAX(avg_cl) AS avg_cl,
  MAX(avg_cf_onboarded) AS avg_cf_onboarded,
  MAX(avg_cf_txning_user) AS avg_cf_txning_user,
  max(no_of_txns) as no_of_txns
FROM
  base
GROUP BY
  1
ORDER BY
  time_flag;
