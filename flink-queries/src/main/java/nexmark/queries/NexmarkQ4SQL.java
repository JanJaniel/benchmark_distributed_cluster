package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ4SQL {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create tables using NexmarkTables helper
        NexmarkTables.createAuctionTable(tEnv, "nexmark-flink-sql-q4");
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q4");
        
        // Create output sink table with upsert mode (required for aggregations)
        NexmarkTables.createUpsertKafkaSinkTable(tEnv, "q4_results", "nexmark-q4-results",
            "category BIGINT," +
            "avg_price DOUBLE," +
            "date_time BIGINT",
            "category"  // primary key
        );
        
        // Query 4: Average Price for a Category
        // Calculate average of closing prices per category
        // Using CTE similar to Arroyo implementation
        tEnv.executeSql(
            "INSERT INTO q4_results " +
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
            "    MAX(max_date_time) AS date_time " +
            "FROM test " +
            "GROUP BY category"
        );
    }
}