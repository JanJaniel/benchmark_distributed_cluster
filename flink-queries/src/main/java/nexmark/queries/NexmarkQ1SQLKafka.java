package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ1SQLKafka {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create source table
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q1-kafka");
        
        // Create sink table for Kafka output with timestamp
        tEnv.executeSql(
            "CREATE TABLE nexmark_q1_output (" +
            "    auction BIGINT," +
            "    bidder BIGINT," +
            "    price_euros DOUBLE," +
            "    date_time BIGINT" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'nexmark-q1-results'," +
            "    'properties.bootstrap.servers' = 'localhost:9092'," +
            "    'format' = 'json'," +
            "    'sink.partitioner' = 'round-robin'" +
            ")"
        );
        
        // Insert query results into Kafka
        tEnv.executeSql(
            "INSERT INTO nexmark_q1_output " +
            "SELECT " +
            "    auction," +
            "    bidder," +
            "    price * 0.89 AS price_euros," +
            "    date_time " +
            "FROM bids"
        );
    }
}