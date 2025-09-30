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

CREATE TABLE nexmark_q2_output (
    auction BIGINT,
    price BIGINT,
    date_time TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q2-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q2_output
SELECT auction, price, date_time
FROM nexmark_bid_source
WHERE auction = 1007 OR auction = 1020 OR auction = 2001 OR auction = 2019 OR auction = 2087;