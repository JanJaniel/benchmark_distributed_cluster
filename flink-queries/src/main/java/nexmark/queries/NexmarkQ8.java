package nexmark.queries;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.java.tuple.Tuple3;
import org.apache.flink.api.java.tuple.Tuple4;
import java.util.HashMap;
import java.util.Map;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import nexmark.utils.BenchmarkUtils;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.co.ProcessJoinFunction;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;
import nexmark.models.*;

/**
 * Nexmark Query 8: Windowed Join of Person and Auction
 * Implements the following SQL query using Flink streaming:
 * 
 * WITH PersonWindow AS (
 *   SELECT P.id as pid, P.name as pname, TUMBLE(interval '10 second') as window
 *   FROM Person as P
 *   GROUP BY P.id, P.name, window
 * ), AuctionWindow AS (
 *   SELECT A.seller as aseller, TUMBLE(interval '10 second') as window
 *   FROM Auction as A
 *   GROUP BY A.seller, window
 * )
 * SELECT PersonWindow.pid, PersonWindow.pname, AuctionWindow.aseller 
 * FROM PersonWindow
 * JOIN AuctionWindow 
 * ON PersonWindow.pid = AuctionWindow.aseller AND PersonWindow.window = AuctionWindow.window;
 */
public class NexmarkQ8 {
    
    // Process function for PersonWindow: outputs (pid, pname, window_end) with GROUP BY semantics
    public static class PersonWindowProcessFunction 
            extends ProcessWindowFunction<Person, Tuple3<Long, String, Long>, Long, TimeWindow> {
        @Override
        public void process(Long key, Context context, Iterable<Person> elements, 
                          Collector<Tuple3<Long, String, Long>> out) throws Exception {
            // GROUP BY logic: emit only one record per person ID per window
            // Since we're already keyed by person.getId(), any person in this window will do
            Person person = elements.iterator().next();
            if (person != null) {
                // Emit with window end time for consistent joining
                out.collect(new Tuple3<>(person.getId(), person.getName(), context.window().getEnd()));
            }
        }
    }
    
    // Process function for AuctionWindow: outputs (aseller, aseller, window_end) with GROUP BY semantics
    public static class AuctionWindowProcessFunction 
            extends ProcessWindowFunction<Auction, Tuple3<Long, Long, Long>, Long, TimeWindow> {
        @Override
        public void process(Long key, Context context, Iterable<Auction> elements,
                          Collector<Tuple3<Long, Long, Long>> out) throws Exception {
            // GROUP BY logic: emit only one record per seller ID per window
            // Since we're already keyed by auction.getSeller(), just check if we have any auctions
            if (elements.iterator().hasNext()) {
                // key is the seller ID from keyBy, emit with window end time
                out.collect(new Tuple3<>(key, key, context.window().getEnd()));
            }
        }
    }
    
    public static void main(String[] args) throws Exception {
      

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);
        

        KafkaSource<Person> personSource = KafkaSource.<Person>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setTopics("nexmark-person")
                .setGroupId("nexmark-flink-java-q8-person-" + System.currentTimeMillis())
                .setStartingOffsets(BenchmarkUtils.getOffsetsInitializer())
                .setValueOnlyDeserializer(new PersonDeserializerFlink())
                .build();
        

        KafkaSource<Auction> auctionSource = KafkaSource.<Auction>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setTopics("nexmark-auction")
                .setGroupId("nexmark-flink-java-q8-auction-" + System.currentTimeMillis())
                .setStartingOffsets(BenchmarkUtils.getOffsetsInitializer())
                .setValueOnlyDeserializer(new AuctionDeserializerFlink())
                .build();
        

        DataStream<Person> persons = env.fromSource(personSource,
                WatermarkStrategy.<Person>forBoundedOutOfOrderness(java.time.Duration.ofSeconds(5))
                        .withTimestampAssigner((person, recordTimestamp) -> person.getDateTime()),
                "Kafka Person Source");
        
        DataStream<Auction> auctions = env.fromSource(auctionSource,
                WatermarkStrategy.<Auction>forBoundedOutOfOrderness(java.time.Duration.ofSeconds(5))
                        .withTimestampAssigner((auction, recordTimestamp) -> auction.getDateTime()),
                "Kafka Auction Source");
        
        // PersonWindow: Group persons by id, name with 10-second tumbling windows
        DataStream<Tuple3<Long, String, Long>> personWindows = persons
            .filter(person -> person != null)
            .keyBy(person -> person.getId())
            .window(TumblingEventTimeWindows.of(Time.seconds(10)))
            .process(new PersonWindowProcessFunction());
            
        // AuctionWindow: Group auctions by seller with 10-second tumbling windows  
        DataStream<Tuple3<Long, Long, Long>> auctionWindows = auctions
            .filter(auction -> auction != null)
            .keyBy(auction -> auction.getSeller())
            .window(TumblingEventTimeWindows.of(Time.seconds(10)))
            .process(new AuctionWindowProcessFunction());
            
        // Join PersonWindow and AuctionWindow on pid = aseller AND same window
        DataStream<Tuple4<Long, String, Long, Long>> results = personWindows
            .keyBy(tuple -> tuple.f0) // key by person id
            .intervalJoin(auctionWindows.keyBy(tuple -> tuple.f0)) // key by seller id
            .between(Time.milliseconds(0), Time.milliseconds(0)) // exact time match
            .process(new ProcessJoinFunction<Tuple3<Long, String, Long>, Tuple3<Long, Long, Long>, Tuple4<Long, String, Long, Long>>() {
                @Override
                public void processElement(
                    Tuple3<Long, String, Long> personWindow,
                    Tuple3<Long, Long, Long> auctionWindow,
                    Context context,
                    Collector<Tuple4<Long, String, Long, Long>> out) throws Exception {
                    
                    // Check if windows match (same window end time)
                    if (personWindow.f2.equals(auctionWindow.f2)) {
                        // Output: pid, pname, aseller, window_end
                        out.collect(new Tuple4<>(personWindow.f0, personWindow.f1, auctionWindow.f1, personWindow.f2));
                    }
                }
            });

        // Convert to JSON format and write to Kafka
        DataStream<String> jsonResults = results.map(new MapFunction<Tuple4<Long, String, Long, Long>, String>() {
            @Override
            public String map(Tuple4<Long, String, Long, Long> tuple) throws Exception {
                // Use window_end timestamp for latency measurement
                return String.format("{\"person_id\":%d,\"name\":\"%s\",\"seller_id\":%d,\"window_end\":%d}", 
                                   tuple.f0, tuple.f1, tuple.f2, tuple.f3);
            }
        });
        
        // Write to Kafka
        jsonResults.sinkTo(
            org.apache.flink.connector.kafka.sink.KafkaSink.<String>builder()
                .setBootstrapServers(BenchmarkUtils.getKafkaBroker())
                .setRecordSerializer(org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema.builder()
                    .setTopic("nexmark-q8-results")
                    .setValueSerializationSchema(new org.apache.flink.api.common.serialization.SimpleStringSchema())
                    .build()
                )
                .build()
        );

        env.execute("Windowed Join Person-Auction Q8");
    }
}