-- ============================================================
-- 1. Завантаження даних
-- ============================================================

CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

DROP TABLE IF EXISTS infectious_cases CASCADE;

CREATE TABLE infectious_cases (
    entity TEXT,
    code TEXT,
    year INTEGER,
    number_yaws TEXT,
    polio_cases TEXT,
    cases_guinea_worm TEXT,
    number_rabies TEXT,
    number_malaria TEXT,
    number_hiv TEXT,
    number_tuberculosis TEXT,
    number_smallpox TEXT,
    number_cholera_cases TEXT
);

\copy infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true);

SELECT
    COUNT(*)::BIGINT AS n_rows,
    COUNT(DISTINCT entity)::BIGINT AS n_entity,
    COUNT(DISTINCT code)::BIGINT AS n_code,
    MIN(year) AS min_year,
    MAX(year) AS max_year
FROM infectious_cases;

SELECT *
FROM infectious_cases
WHERE number_rabies IS NOT NULL
LIMIT 10;

SELECT
    c.column_name,
    c.data_type,
    COUNT(e.v)::BIGINT AS n_not_null,
    (COUNT(*) - COUNT(e.v))::BIGINT AS n_null
FROM infectious_cases AS t
CROSS JOIN LATERAL jsonb_each_text(to_jsonb(t)) AS e(k, v)
JOIN information_schema.columns AS c
    ON c.table_schema = 'pandemic'
   AND c.table_name = 'infectious_cases'
   AND c.column_name = e.k
GROUP BY c.column_name, c.data_type, c.ordinal_position
ORDER BY c.ordinal_position;

-- ============================================================
-- 2. Нормалізація до 3НФ
-- ============================================================

CREATE OR REPLACE FUNCTION text_to_numeric(p_value TEXT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN btrim(p_value) ~ '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$'
            THEN btrim(p_value)::NUMERIC
    END;
$$;

DROP TABLE IF EXISTS infectious_cases_normalized CASCADE;
DROP TABLE IF EXISTS entities CASCADE;

CREATE TABLE entities (
    id SERIAL PRIMARY KEY,
    entity TEXT NOT NULL,
    code TEXT,
    UNIQUE NULLS NOT DISTINCT (entity, code)
);

CREATE TABLE infectious_cases_normalized (
    id SERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL REFERENCES entities(id),
    year INTEGER NOT NULL,
    number_yaws NUMERIC,
    polio_cases NUMERIC,
    cases_guinea_worm NUMERIC,
    number_rabies NUMERIC,
    number_malaria NUMERIC,
    number_hiv NUMERIC,
    number_tuberculosis NUMERIC,
    number_smallpox NUMERIC,
    number_cholera_cases NUMERIC,
    UNIQUE (entity_id, year)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, NULLIF(btrim(code), '')
FROM infectious_cases
ORDER BY 1, 2;

INSERT INTO infectious_cases_normalized (entity_id, year, number_yaws, polio_cases, cases_guinea_worm, number_rabies, number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases)
SELECT
    e.id,
    ic.year,
    text_to_numeric(ic.number_yaws),
    text_to_numeric(ic.polio_cases),
    text_to_numeric(ic.cases_guinea_worm),
    text_to_numeric(ic.number_rabies),
    text_to_numeric(ic.number_malaria),
    text_to_numeric(ic.number_hiv),
    text_to_numeric(ic.number_tuberculosis),
    text_to_numeric(ic.number_smallpox),
    text_to_numeric(ic.number_cholera_cases)
FROM infectious_cases AS ic
JOIN entities AS e
    ON e.entity = ic.entity
   AND e.code IS NOT DISTINCT FROM NULLIF(btrim(ic.code), '')
ORDER BY e.id, ic.year;

SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'pandemic'
  AND table_name IN ('entities', 'infectious_cases_normalized')
ORDER BY table_name, ordinal_position;

SELECT *
FROM entities
ORDER BY id
LIMIT 5;

SELECT *
FROM infectious_cases_normalized
WHERE number_rabies IS NOT NULL
ORDER BY id
LIMIT 5;

SELECT
    (SELECT COUNT(*) FROM infectious_cases)::BIGINT AS n_raw,
    (SELECT COUNT(*) FROM infectious_cases_normalized)::BIGINT AS n_normalized,
    (SELECT COUNT(*) FROM (SELECT DISTINCT entity, code FROM infectious_cases) AS d)::BIGINT AS n_entity_code_raw,
    (SELECT COUNT(*) FROM entities)::BIGINT AS n_entities,
    (SELECT COUNT(*) FROM (
        SELECT entity, COUNT(DISTINCT COALESCE(code, '')) AS n
        FROM infectious_cases
        GROUP BY entity
        HAVING COUNT(DISTINCT COALESCE(code, '')) > 1
    ) AS d)::BIGINT AS n_entity_with_2plus_codes,
    (SELECT COUNT(*)
     FROM infectious_cases AS t
     CROSS JOIN LATERAL jsonb_each_text(to_jsonb(t)) AS e(k, v)
     WHERE e.k NOT IN ('entity', 'code', 'year')
       AND e.v IS NOT NULL
       AND text_to_numeric(e.v) IS NULL)::BIGINT AS n_non_numeric_values;

WITH src AS (
    SELECT
        entity,
        NULLIF(btrim(code), '') AS code,
        year,
        text_to_numeric(number_yaws) AS number_yaws,
        text_to_numeric(polio_cases) AS polio_cases,
        text_to_numeric(cases_guinea_worm) AS cases_guinea_worm,
        text_to_numeric(number_rabies) AS number_rabies,
        text_to_numeric(number_malaria) AS number_malaria,
        text_to_numeric(number_hiv) AS number_hiv,
        text_to_numeric(number_tuberculosis) AS number_tuberculosis,
        text_to_numeric(number_smallpox) AS number_smallpox,
        text_to_numeric(number_cholera_cases) AS number_cholera_cases
    FROM infectious_cases
),
back AS (
    SELECT
        e.entity,
        e.code,
        n.year,
        n.number_yaws,
        n.polio_cases,
        n.cases_guinea_worm,
        n.number_rabies,
        n.number_malaria,
        n.number_hiv,
        n.number_tuberculosis,
        n.number_smallpox,
        n.number_cholera_cases
    FROM infectious_cases_normalized AS n
    JOIN entities AS e ON e.id = n.entity_id
)
SELECT
    (SELECT COUNT(*) FROM (SELECT * FROM src EXCEPT ALL SELECT * FROM back) AS a)::BIGINT AS src_except_back,
    (SELECT COUNT(*) FROM (SELECT * FROM back EXCEPT ALL SELECT * FROM src) AS b)::BIGINT AS back_except_src;

-- ============================================================
-- 3. AVG / MIN / MAX / SUM для Number_rabies, top-10 за AVG
-- ============================================================

SELECT
    e.id,
    e.entity,
    e.code,
    ROUND(AVG(n.number_rabies), 2) AS avg_rabies,
    ROUND(MIN(n.number_rabies), 2) AS min_rabies,
    ROUND(MAX(n.number_rabies), 2) AS max_rabies,
    ROUND(SUM(n.number_rabies), 2) AS sum_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
GROUP BY e.id, e.entity, e.code
ORDER BY AVG(n.number_rabies) DESC
LIMIT 10;

SELECT
    e.id,
    e.entity,
    e.code,
    ROUND(AVG(n.number_rabies), 2) AS avg_rabies,
    ROUND(MIN(n.number_rabies), 2) AS min_rabies,
    ROUND(MAX(n.number_rabies), 2) AS max_rabies,
    ROUND(SUM(n.number_rabies), 2) AS sum_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
  AND e.code IS NOT NULL
  AND e.code NOT LIKE 'OWID%'
GROUP BY e.id, e.entity, e.code
ORDER BY AVG(n.number_rabies) DESC
LIMIT 10;

-- ============================================================
-- 4. Дата 1 січня, поточна дата, різниця в роках
-- ============================================================

SELECT
    n.id,
    e.entity,
    n.year,
    MAKE_DATE(n.year, 1, 1) AS year_start_date,
    CURRENT_DATE AS today,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INTEGER AS years_diff
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;

SELECT
    MIN(year) AS min_year,
    MAX(year) AS max_year,
    MAX(EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER) AS max_years_diff,
    MIN(EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER) AS min_years_diff
FROM infectious_cases_normalized;

-- ============================================================
-- 5. Власні функції
-- ============================================================

CREATE OR REPLACE FUNCTION fn_years_diff(p_year INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_year IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INTEGER;
END;
$$;

CREATE OR REPLACE FUNCTION fn_avg_per_period(p_cases NUMERIC, p_divider NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_cases IS NULL OR p_divider IS NULL OR p_divider = 0 THEN
        RETURN NULL;
    END IF;
    RETURN p_cases / p_divider;
END;
$$;

SELECT
    fn_years_diff(1996) AS years_diff_1996,
    ROUND(fn_avg_per_period(1200, 12), 2) AS per_month_1200,
    ROUND(fn_avg_per_period(1200, 4), 2) AS per_quarter_1200,
    ROUND(fn_avg_per_period(1200, 2), 2) AS per_half_year_1200,
    ROUND(fn_avg_per_period(1200, 0), 2) AS divider_0;

SELECT
    n.id,
    e.entity,
    n.year,
    fn_years_diff(n.year) AS years_diff
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;

SELECT
    COUNT(*)::BIGINT AS n_rows,
    COUNT(*) FILTER (
        WHERE fn_years_diff(year) <> EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER
    )::BIGINT AS n_mismatch
FROM infectious_cases_normalized;

SELECT
    n.id,
    e.entity,
    n.year,
    ROUND(n.number_rabies, 2) AS rabies_per_year,
    ROUND(fn_avg_per_period(n.number_rabies, 12), 2) AS rabies_per_month,
    ROUND(fn_avg_per_period(n.number_rabies, 4), 2) AS rabies_per_quarter,
    ROUND(fn_avg_per_period(n.number_rabies, 2), 2) AS rabies_per_half_year
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
ORDER BY n.id
LIMIT 10;

SELECT
    COUNT(*)::BIGINT AS n_rows,
    COUNT(*) FILTER (WHERE number_rabies IS NOT NULL)::BIGINT AS n_numeric_rabies,
    COUNT(*) FILTER (WHERE fn_avg_per_period(number_rabies, 12) IS NOT NULL)::BIGINT AS n_with_result
FROM infectious_cases_normalized;
