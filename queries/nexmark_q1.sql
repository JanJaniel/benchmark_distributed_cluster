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

CREATE TABLE nexmark_q1_output (
    auction BIGINT,
    bidder BIGINT,
    price_euros DOUBLE,
    date_time TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q1-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q1_output
SELECT 
    auction, 
    bidder, 
    0.89 * price as price_euros, 
    date_time
FROM nexmark_bid_source;