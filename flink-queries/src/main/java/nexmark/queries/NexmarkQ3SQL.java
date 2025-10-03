package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ3SQL {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create tables using NexmarkTables helper
        NexmarkTables.createAuctionTable(tEnv, "nexmark-flink-sql-q3");
        NexmarkTables.createPersonTable(tEnv, "nexmark-flink-sql-q3");
        
        // Create output sink table
        NexmarkTables.createKafkaSinkTable(tEnv, "q3_results", "nexmark-q3-results",
            "name STRING," +
            "city STRING," +
            "state STRING," +
            "id BIGINT," +
            "date_time BIGINT"
        );
        
        // Query 3: Local Item Suggestion
        // Find auctions by sellers in OR, ID, CA with category 10
        tEnv.executeSql(
            "INSERT INTO q3_results " +
            "SELECT " +
            "    p.name, " +
            "    p.city, " +
            "    p.state, " +
            "    a.id, " +
            "    a.date_time " +
            "FROM auctions a " +
            "INNER JOIN persons p ON a.seller = p.id " +
            "WHERE a.category = 10 " +
            "AND p.state IN ('or', 'id', 'ca')"
        );
    }
}