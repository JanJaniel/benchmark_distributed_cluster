package nexmark.queries;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;

public class NexmarkQ6SQL {
    public static void main(String[] args) throws Exception {
        TableEnvironment tEnv = TableEnvironment.create(EnvironmentSettings.inStreamingMode());
        
        // Create tables using NexmarkTables helper
        NexmarkTables.createBidTable(tEnv, "nexmark-flink-sql-q6");
        
        // Query 6: Average Selling Price by Seller
        // What is the average selling price per seller for their last 10 closed auctions
        // Simplified: Average bid price per bidder for their last 10 bids
        tEnv.executeSql(
            "SELECT " +
            "    bidder, " +
            "    AVG(price) AS avg_price " +
            "FROM (" +
            "    SELECT " +
            "        bidder, " +
            "        price, " +
            "        ROW_NUMBER() OVER (PARTITION BY bidder ORDER BY event_time DESC) AS row_num " +
            "    FROM bids" +
            ") " +
            "WHERE row_num <= 10 " +
            "GROUP BY bidder"
        ).print();
    }
}