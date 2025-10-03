package nexmark.queries;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import nexmark.utils.BenchmarkUtils;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import nexmark.models.Bid;
import nexmark.models.BidDeserializer;

/**
 * Nexmark Query 7: Highest Bid
 * Monitors and returns the highest bid price in fixed time windows.
 */
public class NexmarkQ7 {
    
    public static void main(String[] args) throws Exception {
       

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);
        

        KafkaSource<Bid> source = KafkaSource.<Bid>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setTopics("nexmark-bid")
                .setGroupId("nexmark-flink-java-q7-" + System.currentTimeMillis())
                .setStartingOffsets(BenchmarkUtils.getOffsetsInitializer())
                .setValueOnlyDeserializer(new BidDeserializer())
                .build();
        
  
        DataStream<Bid> bids = env.fromSource(source,
                WatermarkStrategy.<Bid>forBoundedOutOfOrderness(java.time.Duration.ofSeconds(5))
                        .withTimestampAssigner((bid, recordTimestamp) -> bid.dateTime),
                "Kafka Bid Source");
        
     
        DataStream<String> results = bids
                .filter(bid -> bid != null)
                .windowAll(TumblingEventTimeWindows.of(Time.seconds(10)))
                .apply(new org.apache.flink.streaming.api.functions.windowing.AllWindowFunction<Bid, String, TimeWindow>() {
                    @Override
                    public void apply(TimeWindow window, Iterable<Bid> values, org.apache.flink.util.Collector<String> out) throws Exception {
                        Bid highestBid = null;
                        for (Bid bid : values) {
                            if (highestBid == null || bid.price > highestBid.price) {
                                highestBid = bid;
                            }
                        }
                        
                        if (highestBid != null) {
                            // Use window_end for latency measurement, similar to Q5
                            String result = String.format("{\"auction\":%d,\"bidder\":%d,\"price\":%d,\"window_end\":%d}",
                                               highestBid.auction, highestBid.bidder, 
                                               highestBid.price, window.getEnd());
                            out.collect(result);
                        }
                    }
                });
    
        // Write to Kafka instead of printing
        results.sinkTo(
            org.apache.flink.connector.kafka.sink.KafkaSink.<String>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setRecordSerializer(org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema.builder()
                    .setTopic("nexmark-q7-results")
                    .setValueSerializationSchema(new org.apache.flink.api.common.serialization.SimpleStringSchema())
                    .build()
                )
                .build()
        );
        

        env.execute("Nexmark Query 7 - Highest Bid");
    }
}