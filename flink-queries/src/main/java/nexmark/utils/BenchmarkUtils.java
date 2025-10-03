package nexmark.utils;

import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

public class BenchmarkUtils {

    /**
     * Get Kafka broker address from environment variable or use default.
     * This allows running queries with different Kafka broker addresses without code changes.
     */
    public static String getKafkaBroker() {
        String broker = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        if (broker == null || broker.isEmpty()) {
            broker = "localhost:9092";
        }
        System.out.println("Using Kafka broker: " + broker);
        return broker;
    }

    /**
     * Get the appropriate Kafka offset initializer based on whether a benchmark timestamp file exists.
     * If the file exists, use timestamp-based initialization to avoid reading old events.
     * Otherwise, use latest offset.
     */
    public static OffsetsInitializer getOffsetsInitializer() {
        String timestampFile = "benchmark_timestamp.txt";
        
        try (BufferedReader reader = new BufferedReader(new FileReader(timestampFile))) {
            String timestampStr = reader.readLine();
            if (timestampStr != null && !timestampStr.isEmpty()) {
                long timestamp = Long.parseLong(timestampStr.trim());
                System.out.println("Using timestamp-based offset initialization: " + timestamp);
                return OffsetsInitializer.timestamp(timestamp);
            }
        } catch (IOException | NumberFormatException e) {
            // File doesn't exist or can't be read - use latest
            System.out.println("No benchmark timestamp found, using latest offset");
        }
        
        return OffsetsInitializer.latest();
    }
}