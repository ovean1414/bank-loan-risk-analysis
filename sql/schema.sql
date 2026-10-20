-- ============================================================
-- PROJECT  : Hospital Emergency Room Analytics
-- FILE     : analysis.sql
-- PURPOSE  : Business analysis queries using professional
--            SQL techniques
-- ANALYST  : Ovean S
-- DATE     : October 2026
-- ============================================================

USE hospital_er;

-- ============================================================
-- QUERY 1 : EXECUTIVE KPI SUMMARY
-- Business Question: What are the overall ER performance metrics?
-- ============================================================
SELECT
    COUNT(*)                                    AS total_patients,
    ROUND(AVG(patient_wait_time), 2)            AS avg_wait_time_mins,
    ROUND(AVG(satisfaction_score), 2)           AS avg_satisfaction,
    ROUND(MIN(patient_wait_time), 2)            AS min_wait_time,
    ROUND(MAX(patient_wait_time), 2)            AS max_wait_time,
    SUM(CASE WHEN admission_flag = 1 
        THEN 1 ELSE 0 END)                      AS total_admitted,
    ROUND(SUM(CASE WHEN admission_flag = 1 
        THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*), 2)                          AS admission_rate_pct,
    SUM(CASE WHEN patient_wait_time > 45 
        THEN 1 ELSE 0 END)                      AS patients_over_45mins,
    ROUND(SUM(CASE WHEN patient_wait_time > 45 
        THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*), 2)                          AS pct_over_45mins
FROM er_visits;

-- ============================================================
-- QUERY 2 : PEAK HOURS ANALYSIS WITH RANKING
-- Business Question: Which hours have highest patient load?
-- Technique: Window Function — RANK()
-- ============================================================
SELECT
    hour,
    COUNT(*)                            AS patient_count,
    ROUND(AVG(patient_wait_time), 2)    AS avg_wait_time,
    ROUND(AVG(satisfaction_score), 2)   AS avg_satisfaction,
    RANK() OVER (
        ORDER BY COUNT(*) DESC
    )                                   AS busiest_hour_rank,
    CASE
        WHEN hour BETWEEN 8 AND 20 
            THEN 'Peak Hours'
        ELSE 'Off Peak'
    END                                 AS shift_type
FROM er_visits
GROUP BY hour
ORDER BY hour;

-- ============================================================
-- QUERY 3 : DEPARTMENT PERFORMANCE USING CTE
-- Business Question: Which departments need improvement?
-- Technique: CTE (Common Table Expression)
-- ============================================================
WITH department_metrics AS (
    SELECT
        department_referral,
        COUNT(*)                            AS patient_count,
        ROUND(AVG(patient_wait_time), 2)    AS avg_wait_time,
        ROUND(AVG(satisfaction_score), 2)   AS avg_satisfaction,
        ROUND(MIN(patient_wait_time), 2)    AS min_wait,
        ROUND(MAX(patient_wait_time), 2)    AS max_wait
    FROM er_visits
    WHERE department_referral != 'None'
    GROUP BY department_referral
),
department_ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY avg_wait_time DESC)    AS wait_time_rank,
        RANK() OVER (ORDER BY avg_satisfaction DESC) AS satisfaction_rank
    FROM department_metrics
)
SELECT *
FROM department_ranked
ORDER BY wait_time_rank;

-- ============================================================
-- QUERY 4 : MONTHLY TREND WITH MONTH-OVER-MONTH CHANGE
-- Business Question: Is performance improving over time?
-- Technique: LAG() Window Function
-- ============================================================
WITH monthly_stats AS (
    SELECT
        year,
        month,
        month_name,
        COUNT(*)                            AS patient_count,
        ROUND(AVG(patient_wait_time), 2)    AS avg_wait_time,
        ROUND(AVG(satisfaction_score), 2)   AS avg_satisfaction
    FROM er_visits
    GROUP BY year, month, month_name
    ORDER BY year, month
)
SELECT
    year,
    month_name,
    patient_count,
    avg_wait_time,
    avg_satisfaction,
    LAG(avg_wait_time) OVER (
        ORDER BY year, month
    )                                       AS prev_month_wait,
    ROUND(avg_wait_time - LAG(avg_wait_time) OVER (
        ORDER BY year, month
    ), 2)                                   AS wait_time_change,
    LAG(avg_satisfaction) OVER (
        ORDER BY year, month
    )                                       AS prev_month_satisfaction,
    ROUND(avg_satisfaction - LAG(avg_satisfaction) OVER (
        ORDER BY year, month
    ), 2)                                   AS satisfaction_change
FROM monthly_stats;

-- ============================================================
-- QUERY 5 : PATIENT RISK SEGMENTATION
-- Business Question: How can we categorize patients by
--                    experience quality?
-- Technique: CTE + CASE WHEN Segmentation
-- ============================================================
WITH patient_experience AS (
    SELECT
        patient_id,
        patient_age,
        age_group,
        department_referral,
        patient_wait_time,
        satisfaction_score,
        admission_flag,
        CASE
            WHEN patient_wait_time > 60 
                AND satisfaction_score < 4
                THEN 'Critical Experience'
            WHEN patient_wait_time > 45 
                AND satisfaction_score < 6
                THEN 'Poor Experience'
            WHEN patient_wait_time BETWEEN 30 AND 45
                AND satisfaction_score BETWEEN 5 AND 7
                THEN 'Average Experience'
            WHEN patient_wait_time < 30 
                AND satisfaction_score > 7
                THEN 'Good Experience'
            ELSE 'Mixed Experience'
        END AS experience_segment
    FROM er_visits
)
SELECT
    experience_segment,
    COUNT(*)                            AS patient_count,
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2)      AS percentage,
    ROUND(AVG(patient_wait_time), 2)    AS avg_wait_time,
    ROUND(AVG(satisfaction_score), 2)   AS avg_satisfaction
FROM patient_experience
GROUP BY experience_segment
ORDER BY patient_count DESC;

-- ============================================================
-- QUERY 6 : CREATE A VIEW FOR REPORTING
-- Purpose  : Save this analysis as a reusable view
-- Technique: CREATE VIEW
-- ============================================================
CREATE OR REPLACE VIEW hourly_performance AS
SELECT
    hour,
    CASE
        WHEN hour BETWEEN 8 AND 20
            THEN 'Peak Hours'
        ELSE 'Off Peak'
    END                                     AS shift_type,
    COUNT(*)                                AS patient_count,
    ROUND(AVG(patient_wait_time), 2)        AS avg_wait_time,
    ROUND(AVG(satisfaction_score), 2)       AS avg_satisfaction,
    SUM(CASE WHEN patient_wait_time > 45 
        THEN 1 ELSE 0 END)                  AS patients_over_threshold,
    ROUND(SUM(CASE WHEN patient_wait_time > 45 
        THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*), 2)                      AS pct_over_threshold
FROM er_visits
GROUP BY hour
ORDER BY hour;

-- Query the view
SELECT * FROM hourly_performance;


