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

CREATE TABLE nexmark_q5_output (
    auction BIGINT,
    bid_count BIGINT,
    window_start TIMESTAMP,
    window_end TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q5-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q5_output
WITH AuctionCounts AS (
    SELECT
        auction,
        COUNT(*) AS bid_count,
        hop(INTERVAL '2' second, INTERVAL '10' second) AS window
    FROM nexmark_bid_source
    GROUP BY auction, window
)
SELECT
    auction,
    bid_count,
    window.start AS window_start,
    window.end AS window_end
FROM (
    SELECT
        auction,
        bid_count,
        window,
        RANK() OVER (PARTITION BY window ORDER BY bid_count DESC) as rnk
    FROM
        AuctionCounts
)
WHERE rnk = 1;
