package nexmark.queries;

import org.apache.flink.table.api.TableEnvironment;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

public class NexmarkTables {

    // Get Kafka broker from environment variable, default to localhost for local testing
    private static String getKafkaBroker() {
        String broker = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        if (broker == null || broker.isEmpty()) {
            broker = "localhost:9092";
        }
        System.out.println("Using Kafka broker: " + broker);
        return broker;
    }

    private static String getStartupMode() {
        String timestampFile = "benchmark_timestamp.txt";
        
        try (BufferedReader reader = new BufferedReader(new FileReader(timestampFile))) {
            String timestampStr = reader.readLine();
            if (timestampStr != null && !timestampStr.isEmpty()) {
                long timestamp = Long.parseLong(timestampStr.trim());
                System.out.println("Using timestamp-based scan mode: " + timestamp);
                return "'scan.startup.mode' = 'timestamp'," +
                       "'scan.startup.timestamp-millis' = '" + timestamp + "',";
            }
        } catch (IOException | NumberFormatException e) {
            // File doesn't exist or can't be read - use latest
        }
        
        System.out.println("No benchmark timestamp found, using latest-offset scan mode");
        return "'scan.startup.mode' = 'latest-offset',";
    }
    
    public static void createBidTable(TableEnvironment tEnv, String groupId) {
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS bids (" +
            "    auction BIGINT," +
            "    bidder BIGINT," +
            "    price BIGINT," +
            "    channel STRING," +
            "    url STRING," +
            "    date_time BIGINT," +  // Unix timestamp in milliseconds
            "    extra STRING," +
            "    event_time AS TO_TIMESTAMP(FROM_UNIXTIME(date_time / 1000))," +
            "    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'nexmark-bid'," +
            "    'properties.bootstrap.servers' = '" + getKafkaBroker() + "'," +
            "    'properties.group.id' = '" + groupId + "'," +
            getStartupMode() +
            "    'format' = 'json'" +
            ")"
        );
    }
    
    public static void createAuctionTable(TableEnvironment tEnv, String groupId) {
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS auctions (" +
            "    id BIGINT," +
            "    item_name STRING," +
            "    description STRING," +
            "    initial_bid BIGINT," +
            "    reserve BIGINT," +
            "    date_time BIGINT," +  // Unix timestamp in milliseconds
            "    expires BIGINT," +     // Unix timestamp in milliseconds  
            "    seller BIGINT," +
            "    category BIGINT," +
            "    extra STRING," +
            "    event_time AS TO_TIMESTAMP(FROM_UNIXTIME(date_time / 1000))," +
            "    expires_time AS TO_TIMESTAMP(FROM_UNIXTIME(expires / 1000))," +
            "    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'nexmark-auction'," +
            "    'properties.bootstrap.servers' = '" + getKafkaBroker() + "'," +
            "    'properties.group.id' = '" + groupId + "'," +
            getStartupMode() +
            "    'format' = 'json'" +
            ")"
        );
    }
    
    public static void createPersonTable(TableEnvironment tEnv, String groupId) {
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS persons (" +
            "    id BIGINT," +
            "    name STRING," +
            "    email_address STRING," +
            "    credit_card STRING," +
            "    city STRING," +
            "    state STRING," +
            "    date_time BIGINT," +  // Unix timestamp in milliseconds
            "    extra STRING," +
            "    event_time AS TO_TIMESTAMP(FROM_UNIXTIME(date_time / 1000))," +
            "    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'nexmark-person'," +
            "    'properties.bootstrap.servers' = '" + getKafkaBroker() + "'," +
            "    'properties.group.id' = '" + groupId + "'," +
            getStartupMode() +
            "    'format' = 'json'" +
            ")"
        );
    }
    
    public static void createKafkaSinkTable(TableEnvironment tEnv, String tableName, String topic, String columns) {
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
            columns +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = '" + topic + "'," +
            "    'properties.bootstrap.servers' = '" + getKafkaBroker() + "'," +
            "    'format' = 'json'" +
            ")"
        );
    }
    
    public static void createUpsertKafkaSinkTable(TableEnvironment tEnv, String tableName, String topic, String columns, String primaryKey) {
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
            columns +
            ", PRIMARY KEY (" + primaryKey + ") NOT ENFORCED" +
            ") WITH (" +
            "    'connector' = 'upsert-kafka'," +
            "    'topic' = '" + topic + "'," +
            "    'properties.bootstrap.servers' = '" + getKafkaBroker() + "'," +
            "    'key.format' = 'json'," +
            "    'value.format' = 'json'" +
            ")"
        );
    }
}