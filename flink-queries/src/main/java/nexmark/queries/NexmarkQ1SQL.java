package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ1SQL {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q1");
        
        // Create output sink table
        NexmarkTables.createKafkaSinkTable(tEnv, "q1_results", "nexmark-q1-results",
            "auction BIGINT," +
            "bidder BIGINT," +
            "price_euros DOUBLE," +
            "date_time BIGINT"
        );
        
        // Execute query and write to Kafka
        tEnv.executeSql(
            "INSERT INTO q1_results " +
            "SELECT " +
            "    auction," +
            "    bidder," +
            "    price  * 0.89 AS price_euros," +
            "    date_time " +
            "FROM bids"
        );
    }
}