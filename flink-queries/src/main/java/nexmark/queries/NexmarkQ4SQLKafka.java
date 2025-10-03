package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ4SQLKafka {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create source tables
        NexmarkTables.createAuctionTable(tEnv, "nexmark-flink-sql-q4-kafka");
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q4-kafka");
        
        // Create sink table for Kafka output with max timestamp
        tEnv.executeSql(
            "CREATE TABLE nexmark_q4_output (" +
            "    category BIGINT," +
            "    avg_price DOUBLE," +
            "    max_date_time BIGINT" +  // Latest bid timestamp in the category
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'nexmark-q4-results'," +
            "    'properties.bootstrap.servers' = 'localhost:9092'," +
            "    'format' = 'json'," +
            "    'sink.partitioner' = 'round-robin'" +
            ")"
        );
        
        // Query 4 with timestamp tracking
        tEnv.executeSql(
            "INSERT INTO nexmark_q4_output " +
            "WITH test AS (" +
            "    SELECT " +
            "        MAX(b.price) AS final, " +
            "        a.category, " +
            "        MAX(b.date_time) AS max_date_time " +
            "    FROM auctions a " +
            "    JOIN bids b ON a.id = b.auction " +
            "    WHERE b.event_time BETWEEN a.event_time AND a.expires_time " +
            "    GROUP BY a.id, a.category " +
            ") " +
            "SELECT " +
            "    category, " +
            "    AVG(final) AS avg_price, " +
            "    MAX(max_date_time) AS max_date_time " +
            "FROM test " +
            "GROUP BY category"
        );
    }
}