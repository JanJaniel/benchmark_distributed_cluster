package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ1SQLMetrics {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q1-metrics");
        
        // Execute without print() - job will run continuously for metrics monitoring
        tEnv.executeSql(
            "SELECT " +
            "    auction," +
            "    bidder," +
            "    price  * 0.89 AS price_euros," +
            "    date_time " +
            "FROM bids"
        );
        
        // Keep the job running
        Thread.sleep(Long.MAX_VALUE);
    }
}