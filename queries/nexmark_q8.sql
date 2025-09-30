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

CREATE TABLE nexmark_q8_output (
    person_id BIGINT,
    person_name TEXT,
    seller_id BIGINT,
    window_start TIMESTAMP,
    window_end TIMESTAMP
) WITH (
    connector = 'kafka',
    topic = 'nexmark-q8-results',
    bootstrap_servers = 'localhost:9092',
    type = 'sink',
    format = 'json'
);

INSERT INTO nexmark_q8_output
WITH PersonWindow AS (
    SELECT P.id as pid, P.name as pname,
        TUMBLE(interval '10 second') as window
    FROM nexmark_person_source as P
    GROUP BY P.id, P.name, window
),
AuctionWindow AS (
    SELECT A.seller as aseller,
        TUMBLE(interval '10 second') as window
    FROM nexmark_auction_source as A
    GROUP BY A.seller, window
)
SELECT 
    PersonWindow.pid as person_id, 
    PersonWindow.pname as person_name, 
    AuctionWindow.aseller as seller_id,
    PersonWindow.window.start as window_start,
    PersonWindow.window.end as window_end
FROM PersonWindow
JOIN AuctionWindow 
ON PersonWindow.pid = AuctionWindow.aseller AND PersonWindow.window = AuctionWindow.window;