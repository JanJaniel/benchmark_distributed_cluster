CREATE TABLE nexmark_auction_source (
    id BIGINT,
    item_name TEXT,
    description TEXT,
    initial_bid BIGINT,
    reserve BIGINT,
    date_time TIMESTAMP NOT NULL,
    expires TIMESTAMP,
    seller BIGINT,
    category BIGINT,
    extra TEXT,
    WATERMARK FOR date_time AS date_time - INTERVAL '5 seconds'
) WITH (
    connector = 'kafka',
    topic = 'nexmark-auction',
    bootstrap_servers = 'localhost:9092',
    type = 'source',
    bad_data = 'fail',
    format = 'json'
);

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

CREATE TABLE nexmark_q4_output (
    category BIGINT,
    avg_price DOUBLE,
    max_date_time TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q4-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'debezium_json'
);

INSERT INTO nexmark_q4_output
WITH test AS (
    SELECT 
        MAX(B.price) AS final, 
        A.category,
        MAX(B.date_time) AS max_bid_time
    FROM nexmark_auction_source AS A
    JOIN nexmark_bid_source AS B ON A.id = B.auction
    WHERE B.date_time BETWEEN A.date_time AND A.expires
    GROUP BY A.id, A.category
)
SELECT
    test.category,
    AVG(test.final) as avg_price,
    MAX(test.max_bid_time) as max_date_time
FROM test
GROUP BY test.category;