CREATE TABLE nexmark_bid_source (
    auction BIGINT,
    bidder BIGINT,
    price BIGINT,
    channel TEXT,
    url TEXT,
    date_time TIMESTAMP NOT NULL,
    extra TEXT,
    WATERMARK FOR date_time AS date_time - INTERVAL '5 seconds'
) WITH (
    connector = 'kafka',
    topic = 'nexmark-bid',
    bootstrap_servers = 'localhost:9092',
    type = 'source',
    bad_data = 'fail',
    format = 'json'
);

CREATE TABLE nexmark_q7_output (
    auction BIGINT,
    bidder BIGINT,
    price BIGINT,
    window_start TIMESTAMP,
    window_end TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q7-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q7_output
-- Query 7: Highest bid per window - Flink compatible output
WITH MaxPricePerWindow AS (
    SELECT
        auction,
        bidder,
        price,
        TUMBLE(interval '10' second) AS window
    FROM nexmark_bid_source
    GROUP BY auction, bidder, price, window
)
SELECT
    auction,
    bidder,
    price,
    window.start AS window_start,
    window.end AS window_end
FROM (
    SELECT
        auction,
        bidder,
        price,
        window,
        RANK() OVER (PARTITION BY window ORDER BY price DESC) as rnk
    FROM MaxPricePerWindow
)
WHERE rnk = 1;