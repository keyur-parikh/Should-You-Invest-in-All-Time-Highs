-- Data should be imported and all good to go, but let us look at it
SELECT *
FROM sp500_data.sp500.sp500_data
ORDER BY date DESC;

-- So far, everything looks good and clean, now we need to worry about all time highs, we need to having like a running max going
DROP TABLE IF EXISTS with_running_max;
CREATE TEMP TABLE with_running_max AS (
SELECT date, close, MAX(close) OVER (ORDER BY date) AS running_max
FROM sp500.sp500_data
ORDER BY date);

SELECT * FROM with_running_max;

-- Okay, now that we have the running_max, we need to have another table that sees if the current close value is the same as running_max,
-- if it is then adds a new high flag

DROP TABLE IF EXISTS with_all_time_flag;
CREATE TEMP TABLE with_all_time_flag AS (
    SELECT date
           ,close
           ,CASE WHEN close = running_max THEN 'Y' ELSE 'N' END AS all_time_flag
    FROM with_running_max
);

SELECT f.date, f.close, running_max, f.all_time_flag
FROM with_all_time_flag f INNER JOIN
    with_running_max m
    ON f.date = m.date
ORDER BY f.date DESC;

-- Okay, everything looks great so far, we have a flag that lets us know if it is all-time high or not, and a basic sanity check ensures everything in place

-- Now we need to check 1-year returns, 3-year returns, and 5 year returns had we bought stock on that date

-- First, we will start with one year

SELECT
        f1.date
        ,f1.close
        ,f1.all_time_flag
        ,f2.date as one_year_from_now
        ,f2.close
FROM with_all_time_flag f1
LEFT JOIN with_all_time_flag f2
ON f1.date + INTERVAL '1 year' = f2.date;

-- Okay, the current problem is that sometimes 1 year from now doesn't exist, due to it being a weekend,
-- I need to add some logic where if in the case there is null, it should take it form the day before and keep going back days until it gets a non null value

-- One way I want to do this is by using a Lateral Join, I want to see if it is fast or not

SELECT
    f1.date                AS original_date
    ,f1.close               AS original_close
    ,f1.all_time_flag
    ,f2.date                AS one_year_from_now
    ,f2.close               AS one_year_close
FROM with_all_time_flag f1
LEFT JOIN LATERAL (
    SELECT waf.date, waf.close
    FROM with_all_time_flag waf
    WHERE waf.date <= f1.date + INTERVAL '1 year'
    ORDER BY waf.date DESC
    LIMIT 1
) AS f2 ON TRUE
ORDER BY f1.date;

-- It took about 13 seconds, but I want to see if it would take longer with 3 and 5 years, if it does then we need to optimize it

SELECT
    f1.date AS original_date,
    f1.close AS original_close,
    f1.all_time_flag,

    -- 1-year
    f2.date AS one_year_from_now,
    f2.close AS one_year_close,

    -- 3-year
    f3.date AS three_year_from_now,
    f3.close AS three_year_close,

    -- 5-year
    f5.date AS five_year_from_now,
    f5.close AS five_year_close

FROM with_all_time_flag f1

-- 1-year lateral
LEFT JOIN LATERAL (
    SELECT waf.date, waf.close
    FROM with_all_time_flag waf
    WHERE waf.date <= f1.date + INTERVAL '1 year'
    ORDER BY waf.date DESC
    LIMIT 1
) AS f2 ON TRUE

-- 3-year lateral
LEFT JOIN LATERAL (
    SELECT waf.date, waf.close
    FROM with_all_time_flag waf
    WHERE waf.date <= f1.date + INTERVAL '3 year'
    ORDER BY waf.date DESC
    LIMIT 1
) AS f3 ON TRUE

-- 5-year lateral
LEFT JOIN LATERAL (
    SELECT waf.date, waf.close
    FROM with_all_time_flag waf
    WHERE waf.date <= f1.date + INTERVAL '5 year'
    ORDER BY waf.date DESC
    LIMIT 1
) AS f5 ON TRUE

ORDER BY f1.date;

-- It took about 40 seconds, which isn't bad

-- I am going to put into a temp table
DROP TABLE IF EXISTS all_returns;
CREATE TEMP TABLE all_returns AS
    (SELECT f1.date AS original_date,
             f1.close AS original_close,
             f1.all_time_flag,

             -- 1-year
             f2.date  AS one_year_from_now,
             f2.close AS one_year_close,

             -- 3-year
             f3.date  AS three_year_from_now,
             f3.close AS three_year_close,

             -- 5-year
             f5.date  AS five_year_from_now,
             f5.close AS five_year_close

      FROM with_all_time_flag f1

    -- 1-year lateral
               LEFT JOIN LATERAL (
          SELECT waf.date, waf.close
          FROM with_all_time_flag waf
          WHERE waf.date >= f1.date + INTERVAL '1 year'
          ORDER BY waf.date
          LIMIT 1
          ) AS f2 ON TRUE

    -- 3-year lateral
               LEFT JOIN LATERAL (
          SELECT waf.date, waf.close
          FROM with_all_time_flag waf
          WHERE waf.date >= f1.date + INTERVAL '3 year'
          ORDER BY waf.date
          LIMIT 1
          ) AS f3 ON TRUE

    -- 5-year lateral
               LEFT JOIN LATERAL (
          SELECT waf.date, waf.close
          FROM with_all_time_flag waf
          WHERE waf.date >= f1.date + INTERVAL '5 year'
          ORDER BY waf.date
          LIMIT 1
          ) AS f5 ON TRUE

      ORDER BY f1.date);

-- Time to do a quick sanity check

SELECT *
FROM all_returns
WHERE five_year_from_now IS NOT NULL
ORDER BY original_date DESC;


-- Everything looks good, now that we have the table, we can conduct our analysis and see if JPMorgan got it right

-- ANALYSIS --

SELECT
    'All Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE all_time_flag = 'Y';


-- From first glance, it looks like the JP-Morgan data was correct, however this is just the total data
-- One thing I want to do is group by Year to ensure that this would still be the case

SELECT
    'All Trades' AS Sector
    ,EXTRACT(YEAR FROM original_date) AS year
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
GROUP BY year

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,EXTRACT(YEAR FROM original_date) AS year
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE all_time_flag = 'Y'
GROUP BY year

ORDER BY year,sector;


-- Now we can see that it is not exactly what it seems

-- In fact, lets do the aggregate but only from 2001
SELECT
    'All Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE EXTRACT(year FROM original_date) >= 2001

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE
    TRUE
    AND all_time_flag = 'Y'
    AND EXTRACT(year FROM original_date) >= 2001;


-- Now the all-time high trades only effect from five years, lets do this again, but this time only since the financial crisis of 2008

SELECT
    'All Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE EXTRACT(year FROM original_date) >= 2008

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE
    TRUE
    AND all_time_flag = 'Y'
    AND EXTRACT(year FROM original_date) >= 2008;

-- Now we can see that if you only but at all-time highs then it isn't necessarily more beneficial


-- For the last one, let us try from 2020
SELECT
    'All Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE EXTRACT(year FROM original_date) >= 2020

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,ROUND(AVG((one_year_close - original_close)/original_close)::numeric,2) AS one_year_average_return
    ,ROUND(AVG((three_year_close - original_close)/original_close)::numeric,2) AS three_year_average_return
    ,ROUND(AVG((five_year_close - original_close)/original_close)::numeric,2) AS five_year_average_return
FROM all_returns
WHERE
    TRUE
    AND all_time_flag = 'Y'
    AND EXTRACT(year FROM original_date) >= 2020;


-- Count the number of Highs each year
SELECT
    EXTRACT(YEAR FROM original_date) AS year
    ,COUNT(number_of_all_times) AS number_of_all_time_highs
FROM
    (SELECT
         CASE WHEN all_time_flag = 'Y' THEN 1 END AS number_of_all_times
        ,original_date
    FROM all_returns) AS subquery
GROUP BY year
ORDER BY year;

-- For sake of completeness, lets take the median

SELECT
    'All Trades' AS Sector
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (one_year_close - original_close)/original_close) AS one_year_median_return
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (three_year_close - original_close)/original_close) AS three_year_median_return
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (five_year_close - original_close)/original_close) AS five_year_median_return
FROM all_returns

UNION ALL

SELECT
    'All-Time-High-Trades' AS Sector
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (one_year_close - original_close)/original_close) AS one_year_median_return
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (three_year_close - original_close)/original_close) AS three_year_median_return
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (five_year_close - original_close)/original_close) AS five_year_median_return
FROM all_returns
WHERE all_time_flag = 'Y';
