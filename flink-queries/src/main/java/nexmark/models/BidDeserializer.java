package nexmark.models;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import nexmark.models.Bid;

public class BidDeserializer implements DeserializationSchema<Bid> {
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public Bid deserialize(byte[] message) {
        try {
            return objectMapper.readValue(message, Bid.class);
        } catch (Exception e) {
            System.err.println("Failed to deserialize bid: " + e.getMessage());
            return null;
        }
    }

    @Override
    public boolean isEndOfStream(Bid nextElement) {
        return false;
    }

    @Override
    public TypeInformation<Bid> getProducedType() {
        return TypeInformation.of(Bid.class);
    }
}