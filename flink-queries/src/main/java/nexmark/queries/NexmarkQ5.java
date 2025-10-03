package nexmark.queries;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.java.tuple.Tuple4;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import nexmark.utils.BenchmarkUtils;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.windowing.ProcessAllWindowFunction;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.assigners.SlidingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;
import nexmark.models.Bid;
import nexmark.models.BidDeserializer;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * Nexmark Query 5: Hot Items
 * Returns ONLY the auction(s) with the most bids in hopping windows (10 second window, 2 second slide).
 * Exactly matches Arroyo implementation - outputs only hot items per window.
 */
public class NexmarkQ5 {
    
    public static void main(String[] args) throws Exception {
        
        // Create execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);
        
        // Create Kafka source
        KafkaSource<Bid> source = KafkaSource.<Bid>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setTopics("nexmark-bid")
                .setGroupId("nexmark-flink-java-q5-" + System.currentTimeMillis())
                .setStartingOffsets(BenchmarkUtils.getOffsetsInitializer())
                .setValueOnlyDeserializer(new BidDeserializer())
                .build();
        
        // Read from Kafka
        DataStream<Bid> bids = env.fromSource(source,
                WatermarkStrategy.<Bid>forBoundedOutOfOrderness(java.time.Duration.ofSeconds(5))
                        .withTimestampAssigner((bid, recordTimestamp) -> bid.dateTime),
                "Kafka Bid Source");
        
        // Step 1: Count bids per auction in each window
        DataStream<Tuple4<Long, Long, Long, Long>> auctionCounts = bids
                .filter(bid -> bid != null)
                .keyBy(bid -> bid.auction)
                .window(SlidingEventTimeWindows.of(Time.seconds(10), Time.seconds(2)))
                .aggregate(new AggregateFunction<Bid, Long, Long>() {
                    @Override
                    public Long createAccumulator() {
                        return 0L;
                    }
                    
                    @Override
                    public Long add(Bid value, Long accumulator) {
                        return accumulator + 1;
                    }
                    
                    @Override
                    public Long getResult(Long accumulator) {
                        return accumulator;
                    }
                    
                    @Override
                    public Long merge(Long a, Long b) {
                        return a + b;
                    }
                }, new ProcessWindowFunction<Long, Tuple4<Long, Long, Long, Long>, Long, TimeWindow>() {
                    @Override
                    public void process(Long auctionId, Context context, Iterable<Long> counts, 
                                      Collector<Tuple4<Long, Long, Long, Long>> out) {
                        Long count = counts.iterator().next();
                        TimeWindow window = context.window();
                        // Output: (auction, count, windowStart, windowEnd)
                        out.collect(new Tuple4<>(auctionId, count, window.getStart(), window.getEnd()));
                    }
                });
        
        // Step 2: For each window, find the auction(s) with the most bids (hot items)
        DataStream<String> hotItems = auctionCounts
                .windowAll(SlidingEventTimeWindows.of(Time.seconds(10), Time.seconds(2)))
                .process(new ProcessAllWindowFunction<Tuple4<Long, Long, Long, Long>, String, TimeWindow>() {
                    @Override
                    public void process(Context context, Iterable<Tuple4<Long, Long, Long, Long>> values, 
                                      Collector<String> out) {
                        List<Tuple4<Long, Long, Long, Long>> windowAuctions = new ArrayList<>();
                        long maxCount = 0;
                        TimeWindow window = context.window();
                        
                        // Collect all auctions in this window and find max count
                        for (Tuple4<Long, Long, Long, Long> auction : values) {
                            // Only include auctions from the current window
                            if (auction.f2.equals(window.getStart()) && auction.f3.equals(window.getEnd())) {
                                windowAuctions.add(auction);
                                if (auction.f1 > maxCount) {
                                    maxCount = auction.f1;
                                }
                            }
                        }
                        
                        // Output ONLY auctions with max count (hot items)
                        if (maxCount > 0) {
                            DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");
                            String windowStart = Instant.ofEpochMilli(window.getStart())
                                .atZone(ZoneOffset.UTC)
                                .format(formatter);
                            String windowEnd = Instant.ofEpochMilli(window.getEnd())
                                .atZone(ZoneOffset.UTC)
                                .format(formatter);
                            
                            for (Tuple4<Long, Long, Long, Long> auction : windowAuctions) {
                                if (auction.f1.equals(maxCount)) {
                                    // Output JSON format matching Arroyo exactly
                                    String json = String.format(
                                        "{\"auction\":%d,\"bid_count\":%d,\"window_start\":\"%s\",\"window_end\":\"%s\"}", 
                                        auction.f0, auction.f1, windowStart, windowEnd);
                                    out.collect(json);
                                }
                            }
                        }
                    }
                });
        
        // Write to Kafka instead of printing
        hotItems.sinkTo(
            org.apache.flink.connector.kafka.sink.KafkaSink.<String>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setRecordSerializer(org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema.builder()
                    .setTopic("nexmark-q5-results")
                    .setValueSerializationSchema(new org.apache.flink.api.common.serialization.SimpleStringSchema())
                    .build()
                )
                .build()
        );
        
        // Execute
        env.execute("Nexmark Query 5 - Hot Items");
    }
}