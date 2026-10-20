-- ============================================================
-- PROJECT  : Bank Loan Risk Analysis
-- FILE     : analysis.sql
-- PURPOSE  : Advanced SQL risk analysis queries
-- ANALYST  : Ovean S
-- DATE     : October 2026
-- ============================================================

USE bank_loan;

-- ============================================================
-- QUERY 1 : EXECUTIVE RISK SUMMARY
-- Business Question: What is the overall loan portfolio health?
-- ============================================================
SELECT
    COUNT(*)                                        AS total_loans,
    SUM(loan_amount)                                AS total_portfolio_value,
    ROUND(AVG(loan_amount), 2)                      AS avg_loan_amount,
    ROUND(AVG(interest_rate), 2)                    AS avg_interest_rate,
    SUM(CASE WHEN default_flag = 1 
        THEN 1 ELSE 0 END)                          AS total_defaults,
    ROUND(SUM(CASE WHEN default_flag = 1 
        THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*), 2)                              AS default_rate_pct,
    SUM(CASE WHEN default_flag = 1 
        THEN loan_amount ELSE 0 END)                AS total_defaulted_amount,
    ROUND(AVG(CASE WHEN default_flag = 1 
        THEN interest_rate END), 2)                 AS avg_defaulted_interest
FROM loans;


-- ============================================================
-- QUERY 2 : DEFAULT RATE BY CREDIT SCORE BAND
-- Business Question: Which credit score range defaults most?
-- Technique: CTE + CASE WHEN segmentation
-- ============================================================
WITH credit_segments AS (
    SELECT
        loan_id,
        loan_amount,
        default_flag,
        interest_rate,
        CASE
            WHEN c.credit_score >= 750 THEN 'Excellent (750+)'
            WHEN c.credit_score >= 700 THEN 'Good (700-749)'
            WHEN c.credit_score >= 650 THEN 'Fair (650-699)'
            WHEN c.credit_score >= 600 THEN 'Poor (600-649)'
            ELSE                             'Very Poor (<600)'
        END AS credit_band
    FROM loans l
    JOIN customers c 
        ON l.customer_id = c.customer_id
)
SELECT
    credit_band,
    COUNT(*)                                    AS total_loans,
    SUM(default_flag)                           AS defaults,
    ROUND(SUM(default_flag) * 100.0 
        / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(AVG(loan_amount), 2)                  AS avg_loan_amount,
    ROUND(AVG(interest_rate), 2)                AS avg_interest_rate,
    ROUND(SUM(CASE WHEN default_flag = 1 
        THEN loan_amount ELSE 0 END), 2)        AS defaulted_amount
FROM credit_segments
GROUP BY credit_band
ORDER BY default_rate_pct DESC;

-- ============================================================
-- QUERY 3 : RISK ANALYSIS BY EMPLOYMENT TYPE
-- Business Question: Which employment type is highest risk?
-- Technique: Window Function — RANK() + RATIO_TO_REPORT
-- ============================================================
WITH employment_risk AS (
    SELECT
        c.employment_type,
        COUNT(l.loan_id)                        AS total_loans,
        SUM(l.default_flag)                     AS total_defaults,
        ROUND(SUM(l.default_flag) * 100.0 
            / COUNT(l.loan_id), 2)              AS default_rate,
        ROUND(AVG(l.loan_amount), 2)            AS avg_loan_amount,
        ROUND(AVG(c.annual_income), 2)          AS avg_income,
        ROUND(AVG(l.interest_rate), 2)          AS avg_interest
    FROM loans l
    JOIN customers c 
        ON l.customer_id = c.customer_id
    GROUP BY c.employment_type
)
SELECT
    employment_type,
    total_loans,
    total_defaults,
    default_rate,
    avg_loan_amount,
    avg_income,
    avg_interest,
    RANK() OVER (
        ORDER BY default_rate DESC
    )                                           AS risk_rank
FROM employment_risk
ORDER BY risk_rank;

-- ============================================================
-- QUERY 4 : DEFAULT RATE BY LOAN PURPOSE
-- Business Question: Which loan purpose is riskiest?
-- Technique: Multiple JOINs + Aggregation
-- ============================================================
SELECT
    l.loan_purpose,
    COUNT(*)                                    AS total_loans,
    SUM(l.default_flag)                         AS defaults,
    ROUND(SUM(l.default_flag) * 100.0 
        / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(AVG(l.loan_amount), 2)                AS avg_loan_amount,
    ROUND(AVG(l.interest_rate), 2)              AS avg_interest_rate,
    ROUND(SUM(CASE WHEN l.default_flag = 1 
        THEN l.loan_amount ELSE 0 END), 2)      AS total_defaulted_amt,
    RANK() OVER (
        ORDER BY SUM(l.default_flag) * 100.0 
        / COUNT(*) DESC
    )                                           AS risk_rank
FROM loans l
JOIN customers c 
    ON l.customer_id = c.customer_id
GROUP BY l.loan_purpose
ORDER BY default_rate_pct DESC;

-- ============================================================
-- QUERY 5 : CUSTOMER RISK SCORE MODEL
-- Business Question: Score each customer by risk level
-- Technique: Multi-CTE + Composite Risk Score
-- ============================================================
WITH payment_behavior AS (
    SELECT
        l.customer_id,
        COUNT(p.payment_id)                     AS total_payments,
        SUM(CASE WHEN p.payment_status = 'Missed'
            THEN 1 ELSE 0 END)                  AS missed_payments,
        SUM(CASE WHEN p.payment_status = 'Late'
            THEN 1 ELSE 0 END)                  AS late_payments,
        ROUND(AVG(p.days_late), 2)              AS avg_days_late
    FROM loans l
    JOIN payments p ON l.loan_id = p.loan_id
    GROUP BY l.customer_id
),
customer_risk AS (
    SELECT
        c.customer_id,
        c.age,
        c.employment_type,
        c.annual_income,
        c.credit_score,
        COUNT(l.loan_id)                        AS total_loans,
        SUM(l.default_flag)                     AS total_defaults,
        ROUND(AVG(l.loan_amount), 2)            AS avg_loan_amount,
        pb.missed_payments,
        pb.late_payments,
        pb.avg_days_late,
        -- Composite risk score (lower = safer)
        ROUND(
            (CASE
                WHEN c.credit_score >= 750 THEN 10
                WHEN c.credit_score >= 700 THEN 25
                WHEN c.credit_score >= 650 THEN 40
                WHEN c.credit_score >= 600 THEN 60
                ELSE 80
            END) * 0.40 +
            (CASE c.employment_type
                WHEN 'Salaried'       THEN 10
                WHEN 'Business Owner' THEN 25
                WHEN 'Self-Employed'  THEN 40
                WHEN 'Unemployed'     THEN 80
            END) * 0.30 +
            (CASE
                WHEN c.annual_income >= 1000000 THEN 10
                WHEN c.annual_income >= 500000  THEN 25
                WHEN c.annual_income >= 200000  THEN 40
                ELSE 70
            END) * 0.30
        , 2)                                    AS risk_score
    FROM customers c
    JOIN loans l ON c.customer_id = l.customer_id
    JOIN payment_behavior pb ON c.customer_id = pb.customer_id
    GROUP BY 
        c.customer_id, c.age, c.employment_type,
        c.annual_income, c.credit_score,
        pb.missed_payments, pb.late_payments,
        pb.avg_days_late
),
risk_segmented AS (
    SELECT
        *,
        CASE
            WHEN risk_score >= 60 THEN 'High Risk'
            WHEN risk_score >= 35 THEN 'Medium Risk'
            ELSE                       'Low Risk'
        END AS risk_category
    FROM customer_risk
)
SELECT
    risk_category,
    COUNT(*)                                    AS customer_count,
    ROUND(COUNT(*) * 100.0 / 
        SUM(COUNT(*)) OVER(), 2)                AS percentage,
    ROUND(AVG(risk_score), 2)                   AS avg_risk_score,
    ROUND(AVG(annual_income), 2)                AS avg_income,
    ROUND(AVG(credit_score), 2)                 AS avg_credit_score,
    ROUND(AVG(avg_loan_amount), 2)              AS avg_loan_amount,
    SUM(total_defaults)                         AS total_defaults
FROM risk_segmented
GROUP BY risk_category
ORDER BY avg_risk_score DESC;

-- ============================================================
-- QUERY 6 : PAYMENT TREND ANALYSIS
-- Business Question: How does payment behavior change over time?
-- Technique: LAG() Window Function
-- ============================================================
WITH monthly_payments AS (
    SELECT
        DATE_FORMAT(payment_date, '%Y-%m')      AS payment_month,
        COUNT(*)                                AS total_payments,
        SUM(CASE WHEN payment_status = 'On Time'
            THEN 1 ELSE 0 END)                  AS on_time,
        SUM(CASE WHEN payment_status = 'Late'
            THEN 1 ELSE 0 END)                  AS late,
        SUM(CASE WHEN payment_status = 'Missed'
            THEN 1 ELSE 0 END)                  AS missed,
        ROUND(SUM(CASE WHEN payment_status = 'Missed'
            THEN 1 ELSE 0 END) * 100.0 
            / COUNT(*), 2)                      AS missed_rate
    FROM payments
    GROUP BY DATE_FORMAT(payment_date, '%Y-%m')
)
SELECT
    payment_month,
    total_payments,
    on_time,
    late,
    missed,
    missed_rate,
    LAG(missed_rate) OVER (
        ORDER BY payment_month
    )                                           AS prev_month_missed_rate,
    ROUND(missed_rate - LAG(missed_rate) OVER (
        ORDER BY payment_month
    ), 2)                                       AS missed_rate_change
FROM monthly_payments
ORDER BY payment_month;

-- ============================================================
-- VIEWS : Created for Power BI direct connection
-- Purpose: Pre-aggregate data for faster dashboard loading
-- ============================================================

-- View 1: Customer Risk Overview
CREATE OR REPLACE VIEW vw_customer_risk AS
SELECT
    c.customer_id,
    c.age,
    c.gender,
    c.employment_type,
    c.annual_income,
    c.credit_score,
    c.state,
    COUNT(l.loan_id)                            AS total_loans,
    SUM(l.default_flag)                         AS total_defaults,
    ROUND(AVG(l.loan_amount), 2)                AS avg_loan_amount,
    ROUND(AVG(l.interest_rate), 2)              AS avg_interest_rate,
    CASE
        WHEN c.credit_score >= 750 THEN 'Excellent'
        WHEN c.credit_score >= 700 THEN 'Good'
        WHEN c.credit_score >= 650 THEN 'Fair'
        WHEN c.credit_score >= 600 THEN 'Poor'
        ELSE                            'Very Poor'
    END                                         AS credit_band,
    CASE
        WHEN c.annual_income >= 1000000 THEN 'High Income'
        WHEN c.annual_income >= 500000  THEN 'Mid Income'
        WHEN c.annual_income >= 200000  THEN 'Low Income'
        ELSE                                 'Very Low Income'
    END                                         AS income_band
FROM customers c
JOIN loans l ON c.customer_id = l.customer_id
GROUP BY
    c.customer_id, c.age, c.gender,
    c.employment_type, c.annual_income,
    c.credit_score, c.state;

-- View 2: Loan Portfolio Overview
CREATE OR REPLACE VIEW vw_loan_portfolio AS
SELECT
    l.loan_id,
    l.loan_amount,
    l.loan_purpose,
    l.interest_rate,
    l.loan_term,
    l.issue_date,
    l.loan_status,
    l.default_flag,
    c.age,
    c.gender,
    c.employment_type,
    c.annual_income,
    c.credit_score,
    c.state,
    CASE
        WHEN c.credit_score >= 750 THEN 'Excellent'
        WHEN c.credit_score >= 700 THEN 'Good'
        WHEN c.credit_score >= 650 THEN 'Fair'
        WHEN c.credit_score >= 600 THEN 'Poor'
        ELSE                            'Very Poor'
    END                                         AS credit_band
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id;

-- View 3: Payment Summary
CREATE OR REPLACE VIEW vw_payment_summary AS
SELECT
    p.loan_id,
    l.customer_id,
    l.loan_amount,
    l.default_flag,
    COUNT(p.payment_id)                         AS total_payments,
    SUM(CASE WHEN p.payment_status = 'On Time'
        THEN 1 ELSE 0 END)                      AS on_time_count,
    SUM(CASE WHEN p.payment_status = 'Late'
        THEN 1 ELSE 0 END)                      AS late_count,
    SUM(CASE WHEN p.payment_status = 'Missed'
        THEN 1 ELSE 0 END)                      AS missed_count,
    ROUND(AVG(p.days_late), 2)                  AS avg_days_late,
    SUM(p.amount_paid)                          AS total_paid,
    SUM(p.amount_due)                           AS total_due,
    ROUND(SUM(p.amount_paid) * 100.0 
        / SUM(p.amount_due), 2)                 AS payment_rate_pct
FROM payments p
JOIN loans l ON p.loan_id = l.loan_id
GROUP BY p.loan_id, l.customer_id,
         l.loan_amount, l.default_flag;

-- Verify views
SELECT COUNT(*) AS customer_risk_rows 
FROM vw_customer_risk;
SELECT COUNT(*) AS loan_portfolio_rows 
FROM vw_loan_portfolio;
SELECT COUNT(*) AS payment_summary_rows 
FROM vw_payment_summary;

-- Age group coloumn --
CREATE OR REPLACE VIEW vw_customer_risk AS
SELECT
    c.customer_id,
    c.age,
    c.gender,
    c.employment_type,
    c.annual_income,
    c.credit_score,
    c.state,
    COUNT(l.loan_id)                AS total_loans,
    SUM(l.default_flag)             AS total_defaults,
    ROUND(AVG(l.loan_amount), 2)    AS avg_loan_amount,
    ROUND(AVG(l.interest_rate), 2)  AS avg_interest_rate,
    CASE
        WHEN c.credit_score >= 750 THEN 'Excellent'
        WHEN c.credit_score >= 700 THEN 'Good'
        WHEN c.credit_score >= 650 THEN 'Fair'
        WHEN c.credit_score >= 600 THEN 'Poor'
        ELSE 'Very Poor'
    END                             AS credit_band,
    CASE
        WHEN c.annual_income >= 1000000 THEN 'High (10L+)'
        WHEN c.annual_income >= 500000  THEN 'Mid (5-10L)'
        WHEN c.annual_income >= 200000  THEN 'Low (2-5L)'
        ELSE 'Very Low (<2L)'
    END                             AS income_band,
    CASE
        WHEN c.age < 30 THEN '20-29'
        WHEN c.age < 40 THEN '30-39'
        WHEN c.age < 50 THEN '40-49'
        WHEN c.age < 60 THEN '50-59'
        ELSE '60+'
    END                             AS age_group
FROM customers c
JOIN loans l ON c.customer_id = l.customer_id
GROUP BY
    c.customer_id, c.age, c.gender,
    c.employment_type, c.annual_income,
    c.credit_score, c.state;