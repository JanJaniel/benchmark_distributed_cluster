package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ2SQL {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create bid table
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q2");
        
        // Create output sink table
        NexmarkTables.createKafkaSinkTable(tEnv, "q2_results", "nexmark-q2-results",
            "auction BIGINT," +
            "price BIGINT," +
            "date_time BIGINT"
        );
        
        // Query 2: Selection - find bids with auction = 1007 or 1020 or 2001 or 2019 or 2087
        tEnv.executeSql(
            "INSERT INTO q2_results " +
            "SELECT auction, price, date_time " +
            "FROM bids " +
            "WHERE auction IN (1007, 1020, 2001, 2019, 2087)"
        );
    }
}