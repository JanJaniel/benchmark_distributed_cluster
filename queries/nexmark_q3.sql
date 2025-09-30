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

CREATE TABLE nexmark_person_source (
    id BIGINT,
    name TEXT,
    email_address TEXT,
    credit_card TEXT,
    city TEXT,
    state TEXT,
    date_time TIMESTAMP NOT NULL,
    extra TEXT,
    WATERMARK FOR date_time AS date_time - INTERVAL '5 seconds'
) WITH (
    connector = 'kafka',
    topic = 'nexmark-person',
    bootstrap_servers = 'localhost:9092',
    type = 'source',
    bad_data = 'fail',
    format = 'json'
);

CREATE TABLE nexmark_q3_output (
    name TEXT,
    city TEXT,
    state TEXT,
    id BIGINT,
    date_time TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q3-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q3_output
SELECT P.name, P.city, P.state, A.id, A.date_time
FROM nexmark_auction_source AS A 
INNER JOIN nexmark_person_source AS P ON A.seller = P.id
WHERE A.category = 10 AND (P.state = 'or' OR P.state = 'id' OR P.state = 'ca');